#include <Storages/TimeSeries/PrometheusQueryToSQL/applyFusedAggregationBinaryOperator.h>

#include <Parsers/ASTFunction.h>
#include <Parsers/ASTIdentifier.h>
#include <Parsers/ASTLiteral.h>
#include <Parsers/makeASTForLogicalFunction.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/ConverterContext.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/SelectQueryBuilder.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/applyFunctionOverRange.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/applyFunctionPredictLinear.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/applyFunctionQuantileOverTime.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/applyMathBinaryOperator.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/applyOneArgumentAggregationOperator.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/toVectorGrid.h>
#include <Storages/TimeSeries/PrometheusQueryToSQL/transformGroupASTForAggregationOperator.h>
#include <Storages/TimeSeries/timeSeriesLabelMatcherToAST.h>
#include <algorithm>


namespace DB::ErrorCodes
{
    extern const int CANNOT_EXECUTE_PROMQL_QUERY;
}


namespace DB::PrometheusQueryToSQL
{

namespace
{
    using AggregationOperatorNode = PrometheusQueryTree::AggregationOperator;
    using InstantSelectorNode = PrometheusQueryTree::InstantSelector;
    using Matcher = PrometheusQueryTree::Matcher;
    using MatcherList = PrometheusQueryTree::MatcherList;

    /// The column of the aggregation which tells whether a group has a series satisfying the extra matchers of a side.
    constexpr const char * HasSeriesWithExtraMatchers = "has_series_with_extra_matchers";

    const AggregationOperatorNode * tryGetFusableAggregation(const Node * node)
    {
        if (node->node_type != NodeType::AggregationOperator)
            return nullptr;

        const auto * aggregation = static_cast<const AggregationOperatorNode *>(node);

        if (!isOneArgumentAggregationOperator(aggregation->operator_name) || (aggregation->getArguments().size() != 1))
            return nullptr;

        /// `by (__name__)` keeps the metric name; the operator then drops it and must detect duplicate series.
        const auto & labels = aggregation->labels;
        if (aggregation->by && (std::find(labels.begin(), labels.end(), kMetricName) != labels.end()))
            return nullptr;

        return aggregation;
    }

    bool haveSameGrouping(const AggregationOperatorNode * left, const AggregationOperatorNode * right)
    {
        if ((left->by != right->by) || (left->without != right->without))
            return false;

        auto sorted_labels = [](const Strings & labels)
        {
            std::vector<std::string_view> res{labels.begin(), labels.end()};
            std::sort(res.begin(), res.end());
            res.erase(std::unique(res.begin(), res.end()), res.end());
            return res;
        };

        return sorted_labels(left->labels) == sorted_labels(right->labels);
    }

    bool haveSameRange(const Node * left, const Node * right, const ConverterContext & context)
    {
        const auto & left_range = context.node_range_getter.get(left);
        const auto & right_range = context.node_range_getter.get(right);

        return (left_range.start_time == right_range.start_time) && (left_range.end_time == right_range.end_time)
            && (left_range.step == right_range.step) && (left_range.window == right_range.window);
    }

    /// Returns the selector of an expression if each series of the expression is calculated from the samples of one series
    /// of the selector and has the same labels, except maybe the metric name, e.g. `rate(m{job="api"}[5m] offset 1m)`.
    /// A matcher of the selector on a label other than `__name__` then holds for exactly the series of the expression
    /// calculated from the series it holds for. Returns nullptr for other expressions.
    const InstantSelectorNode * getSeriesPreservingSelector(const Node * node)
    {
        switch (node->node_type)
        {
            case NodeType::InstantSelector:
                return static_cast<const InstantSelectorNode *>(node);

            case NodeType::RangeSelector:
            case NodeType::Subquery:
            case NodeType::Offset:
                return getSeriesPreservingSelector(node->children.at(0));

            case NodeType::Function:
            {
                const auto & function_name = static_cast<const PrometheusQueryTree::Function *>(node)->function_name;
                if (!isFunctionOverRange(function_name) && !isFunctionQuantileOverTime(function_name)
                    && !isFunctionPredictLinear(function_name))
                    return nullptr;

                /// The other arguments are scalars.
                const Node * range_argument = nullptr;
                for (const auto * argument : node->children)
                {
                    if (argument->result_type != ResultType::RANGE_VECTOR)
                        continue;
                    if (range_argument)
                        return nullptr;
                    range_argument = argument;
                }
                return range_argument ? getSeriesPreservingSelector(range_argument) : nullptr;
            }

            default:
                return nullptr;
        }
    }

    bool containsMatcher(const MatcherList & matchers, const Matcher & matcher)
    {
        return std::ranges::any_of(matchers, [&](const Matcher & other)
        {
            return (other.label_name == matcher.label_name) && (other.label_value == matcher.label_value)
                && (other.matcher_type == matcher.matcher_type);
        });
    }

    /// Returns the matchers from `matchers` which `other_matchers` doesn't have.
    MatcherList getExtraMatchers(const MatcherList & matchers, const MatcherList & other_matchers)
    {
        MatcherList res;
        for (const auto & matcher : matchers)
        {
            if (!containsMatcher(other_matchers, matcher) && !containsMatcher(res, matcher))
                res.push_back(matcher);
        }
        return res;
    }

    /// Replaces `what` with `replacement` in `text` if `what` occurs in `text` exactly once.
    bool tryReplaceSingleOccurrence(String & text, const String & what, const String & replacement)
    {
        size_t pos = text.find(what);
        if ((pos == String::npos) || (text.find(what, pos + 1) != String::npos))
            return false;
        text.replace(pos, what.size(), replacement);
        return true;
    }

    /// Whether two expressions are the same, except the matchers of their selectors `left_selector` and `right_selector`.
    bool areSameExceptSelectors(
        const Node * left,
        const InstantSelectorNode * left_selector,
        const Node * right,
        const InstantSelectorNode * right_selector,
        const PrometheusQueryTree & tree)
    {
        /// The text of an expression contains the text of each of its subexpressions. If the text of `left_selector` occurs in
        /// the text of `left` only once, replacing it with the text of `right_selector` gives the text of `left` with its selector
        /// replaced by `right_selector`, which is the text of `right` only if the rest of the expressions is the same.
        /// If the text of a selector occurs more than once (e.g. `m` in `rate(m[5m])`), it's unknown which occurrence is
        /// the selector, then the other direction is tried.
        String left_text = left->toString(tree);
        String right_text = right->toString(tree);
        String left_selector_text = left_selector->toString(tree);
        String right_selector_text = right_selector->toString(tree);

        String replaced = left_text;
        if (tryReplaceSingleOccurrence(replaced, left_selector_text, right_selector_text))
            return replaced == right_text;

        replaced = right_text;
        if (tryReplaceSingleOccurrence(replaced, right_selector_text, left_selector_text))
            return replaced == left_text;

        return false;
    }

    /// Makes the condition which a series of the argument must satisfy to be aggregated by a side with extra matchers:
    /// the same condition `timeSeriesSelector` filters series by, checked on the labels of the series (the metric name isn't
    /// among the extra matchers, so it doesn't matter that it can be dropped). An absent label is the empty string for both.
    ASTPtr makeExtraMatchersCondition(const MatcherList & extra_matchers)
    {
        ASTs conditions;
        for (const auto & matcher : extra_matchers)
        {
            /// ifNull(timeSeriesExtractTag(group, '<label_name>'), '')
            ASTPtr label_value = makeASTFunction(
                "ifNull",
                makeASTFunction(
                    "timeSeriesExtractTag",
                    make_intrusive<ASTIdentifier>(ColumnNames::Group),
                    make_intrusive<ASTLiteral>(matcher.label_name)),
                make_intrusive<ASTLiteral>(String{}));
            conditions.push_back(timeSeriesLabelMatcherToAST(matcher, std::move(label_value)));
        }
        return makeASTForLogicalAnd(std::move(conditions));
    }

    /// Makes the values which the aggregate function of a side aggregates: `values` if the side aggregates all the series,
    /// otherwise `if(<condition>, values, arrayWithConstant(length(values), NULL))`. The aggregate functions skip NULLs,
    /// so the other series don't change the result at any step. The arrays keep their length for a group without
    /// such series, unlike the `-If` combinator, whose `-ForEach` result for that group would be an empty array.
    ASTPtr makeValuesToAggregate(const MatcherList & extra_matchers)
    {
        if (extra_matchers.empty())
            return make_intrusive<ASTIdentifier>(ColumnNames::Values);

        return makeASTFunction(
            "if",
            makeExtraMatchersCondition(extra_matchers),
            make_intrusive<ASTIdentifier>(ColumnNames::Values),
            makeASTFunction(
                "arrayWithConstant",
                makeASTFunction("length", make_intrusive<ASTIdentifier>(ColumnNames::Values)),
                make_intrusive<ASTLiteral>(Field{} /* NULL */)));
    }
}


std::optional<AggregationBinaryOperatorFusion> tryFuseAggregationBinaryOperator(
    const PrometheusQueryTree::BinaryOperator * operator_node, const ConverterContext & context)
{
    if (!isMathBinaryOperator(operator_node->operator_name))
        return std::nullopt;

    if (operator_node->bool_modifier || operator_node->on || operator_node->ignoring
        || operator_node->group_left || operator_node->group_right)
        return std::nullopt;

    const auto * left_aggregation = tryGetFusableAggregation(operator_node->getLeftArgument());
    const auto * right_aggregation = tryGetFusableAggregation(operator_node->getRightArgument());

    if (!left_aggregation || !right_aggregation || !haveSameGrouping(left_aggregation, right_aggregation))
        return std::nullopt;

    const auto * left_argument = left_aggregation->getArguments().at(0);
    const auto * right_argument = right_aggregation->getArguments().at(0);

    if (!haveSameRange(left_argument, right_argument, context))
        return std::nullopt;

    const auto & tree = *context.promql_tree;
    AggregationBinaryOperatorFusion fusion;

    if (left_argument->toString(tree) == right_argument->toString(tree))
    {
        fusion.argument = left_argument;
        return fusion;
    }

    /// The expressions can differ only in the matchers of their selectors.
    const auto * left_selector = getSeriesPreservingSelector(left_argument);
    const auto * right_selector = getSeriesPreservingSelector(right_argument);
    if (!left_selector || !right_selector || !areSameExceptSelectors(left_argument, left_selector, right_argument, right_selector, tree))
        return std::nullopt;

    /// A side whose selector has all the matchers of the other selector and some extra ones aggregates a subset of the series
    /// of the other side: the series satisfying the extra matchers.
    fusion.left_extra_matchers = getExtraMatchers(left_selector->matchers, right_selector->matchers);
    fusion.right_extra_matchers = getExtraMatchers(right_selector->matchers, left_selector->matchers);
    if (!fusion.left_extra_matchers.empty() && !fusion.right_extra_matchers.empty())
        return std::nullopt;

    /// The metric name can't be checked on the series of the argument: a function drops it.
    auto is_metric_name_matcher = [](const Matcher & matcher) { return matcher.label_name == kMetricName; };
    if (std::ranges::any_of(fusion.left_extra_matchers, is_metric_name_matcher)
        || std::ranges::any_of(fusion.right_extra_matchers, is_metric_name_matcher))
        return std::nullopt;

    /// The side without extra matchers reads all the series both sides need.
    fusion.argument = fusion.left_extra_matchers.empty() ? left_argument : right_argument;
    return fusion;
}


SQLQueryPiece applyFusedAggregationBinaryOperator(
    const PrometheusQueryTree::BinaryOperator * operator_node,
    const AggregationBinaryOperatorFusion & fusion,
    SQLQueryPiece && argument,
    ConverterContext & context)
{
    const auto * left_aggregation = static_cast<const AggregationOperatorNode *>(operator_node->getLeftArgument());
    const auto * right_aggregation = static_cast<const AggregationOperatorNode *>(operator_node->getRightArgument());

    auto left_transform = getOneArgumentAggregationTransform(left_aggregation->operator_name);
    auto right_transform = getOneArgumentAggregationTransform(right_aggregation->operator_name);
    chassert(left_transform && right_transform);

    if (argument.type != ResultType::INSTANT_VECTOR)
    {
        throw Exception(ErrorCodes::CANNOT_EXECUTE_PROMQL_QUERY,
                        "Aggregation operator '{}' expects an argument of type {}, but expression {} has type {}",
                        left_aggregation->operator_name, ResultType::INSTANT_VECTOR,
                        getPromQLText(argument, context), argument.type);
    }

    if (argument.store_method == StoreMethod::EMPTY)
        return SQLQueryPiece{operator_node, operator_node->result_type, StoreMethod::EMPTY};

    argument = toVectorGrid(std::move(argument), context);

    auto res = argument;
    res.node = operator_node;
    res.type = operator_node->result_type;

    /// At most one side has extra matchers.
    const auto & extra_matchers = fusion.left_extra_matchers.empty() ? fusion.right_extra_matchers : fusion.left_extra_matchers;

    /// Step 1:
    /// SELECT <group> AS new_group,
    ///        arrayMap((x, y) -> f(x, y), <left_aggregate>(<left_values>), <right_aggregate>(<right_values>)) AS values
    ///        [, max(<extra_matchers_condition>) AS has_series_with_extra_matchers]
    /// FROM argument
    /// [GROUP BY new_group]
    /// where <side_values> is `values` for a side without extra matchers,
    /// or `if(<extra_matchers_condition>, values, arrayWithConstant(length(values), NULL))` for a side with them.
    ASTPtr aggregation_query;
    {
        SelectQueryBuilder builder;

        context.subqueries.emplace_back(SQLSubquery{context.subqueries.size(), std::move(argument.select_query), SQLSubqueryType::TABLE});
        builder.from_table = context.subqueries.back().name;

        ASTPtr new_group = transformGroupASTForAggregationOperator(
            left_aggregation, make_intrusive<ASTIdentifier>(ColumnNames::Group), /*drop_metric_name=*/true, res.metric_name_dropped);

        builder.select_list.push_back(std::move(new_group));
        builder.select_list.back()->setAlias(ColumnNames::NewGroup);

        builder.select_list.push_back(makeASTFunction(
            "arrayMap",
            makeASTFunction(
                "lambda",
                makeASTFunction("tuple", make_intrusive<ASTIdentifier>("x"), make_intrusive<ASTIdentifier>("y")),
                applyMathBinaryOperatorToAST(
                    operator_node->operator_name, make_intrusive<ASTIdentifier>("x"), make_intrusive<ASTIdentifier>("y"))),
            left_transform(makeValuesToAggregate(fusion.left_extra_matchers)),
            right_transform(makeValuesToAggregate(fusion.right_extra_matchers))));
        builder.select_list.back()->setAlias(ColumnNames::Values);

        if (!extra_matchers.empty())
        {
            builder.select_list.push_back(makeASTFunction("max", makeExtraMatchersCondition(extra_matchers)));
            builder.select_list.back()->setAlias(HasSeriesWithExtraMatchers);
        }

        if (left_aggregation->by || left_aggregation->without)
            builder.group_by.push_back(make_intrusive<ASTIdentifier>(ColumnNames::NewGroup));

        aggregation_query = builder.getSelectQuery();
    }

    /// Step 2: rename `new_group` back to `group` and drop empty grids (a WHERE, so `values` cannot bind to the input column
    /// under prefer_column_name_to_alias).
    /// A group without series satisfying the extra matchers is dropped too: the side with them has no such group,
    /// so the operator has no result for it.
    {
        context.subqueries.emplace_back(SQLSubquery{context.subqueries.size(), std::move(aggregation_query), SQLSubqueryType::TABLE});

        SelectQueryBuilder builder;
        builder.from_table = context.subqueries.back().name;
        builder.select_list.push_back(make_intrusive<ASTIdentifier>(ColumnNames::NewGroup));
        builder.select_list.back()->setAlias(ColumnNames::Group);
        builder.select_list.push_back(make_intrusive<ASTIdentifier>(ColumnNames::Values));
        builder.where = makeASTFunction("notEmpty", make_intrusive<ASTIdentifier>(ColumnNames::Values));
        if (!extra_matchers.empty())
            builder.where = makeASTFunction("and", builder.where, make_intrusive<ASTIdentifier>(HasSeriesWithExtraMatchers));

        res.select_query = builder.getSelectQuery();
    }

    return res;
}

}

#include <Storages/TimeSeries/timeSeriesLabelMatcherToAST.h>

#include <Parsers/ASTFunction.h>
#include <Parsers/ASTLiteral.h>
#include <Storages/TimeSeries/tryGetLiteralAlternatives.h>


namespace DB
{

ASTPtr timeSeriesLabelMatcherToAST(const PrometheusQueryTree::Matcher & matcher, ASTPtr label_value)
{
    std::string_view function_name;
    bool add_anchors = false;
    bool add_not = false;

    auto matcher_type = matcher.matcher_type;
    switch (matcher_type)
    {
        case PrometheusQueryTree::MatcherType::EQ:  function_name = "equals"; break;
        case PrometheusQueryTree::MatcherType::NE:  function_name = "notEquals"; break;
        case PrometheusQueryTree::MatcherType::RE:  function_name = "match"; add_anchors = true; break;
        case PrometheusQueryTree::MatcherType::NRE: function_name = "match"; add_anchors = true; add_not = true; break;
    }

    String value = matcher.label_value;
    if (add_anchors)
    {
        /// `IN` matches exactly what the fully anchored regex matches, and the primary key can filter by it.
        if (auto terms = tryGetLiteralAlternatives(value))
        {
            /// A single term is an equality, which the text index on tags can serve too.
            if (terms->size() == 1)
                return makeASTFunction(add_not ? "notEquals" : "equals",
                    std::move(label_value), make_intrusive<ASTLiteral>(std::move(terms->front())));

            ASTs literals;
            for (auto & term : *terms)
                literals.push_back(make_intrusive<ASTLiteral>(std::move(term)));
            return makeASTFunction(add_not ? "notIn" : "in", std::move(label_value), makeASTFunction("tuple", std::move(literals)));
        }

        if (!value.starts_with('^'))
            value = '^' + value;
        if (!value.ends_with('$'))
            value += '$';
    }
    ASTPtr res = makeASTFunction(function_name, std::move(label_value), make_intrusive<ASTLiteral>(value));
    if (add_not)
        res = makeASTFunction("not", res);
    return res;
}

}

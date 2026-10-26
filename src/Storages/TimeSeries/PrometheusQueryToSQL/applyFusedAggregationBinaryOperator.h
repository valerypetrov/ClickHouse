#pragma once

#include <Storages/TimeSeries/PrometheusQueryToSQL/SQLQueryPiece.h>

#include <optional>


namespace DB::PrometheusQueryToSQL
{

struct ConverterContext;

/// Describes how both sides of a binary operator between two aggregations are calculated in one aggregation over one expression.
struct AggregationBinaryOperatorFusion
{
    /// The expression which is converted and aggregated once for both sides.
    const Node * argument = nullptr;

    /// The label matchers which a series of `argument` must also satisfy to be aggregated by the left or the right side,
    /// e.g. `status="500"` for the left side of `sum(rate(m{status="500"}[5m])) / sum(rate(m[5m]))`.
    /// Empty if the side aggregates all the series of `argument`. At most one side has them.
    PrometheusQueryTree::MatcherList left_extra_matchers;
    PrometheusQueryTree::MatcherList right_extra_matchers;
};

/// Returns how to calculate both sides in one aggregation if both sides are one-argument aggregations with the same grouping
/// of the same expression, e.g. `sum(x) - max(x)`, or of two expressions which differ only in that the selector of one of them
/// has extra matchers on labels other than `__name__` and the tags stored in separate columns (see `tags_to_columns`),
/// e.g. `sum(rate(m{status="500"}[5m])) / sum(rate(m[5m]))`.
/// Returns `std::nullopt` if the sides must be calculated separately.
std::optional<AggregationBinaryOperatorFusion> tryFuseAggregationBinaryOperator(
    const PrometheusQueryTree::BinaryOperator * operator_node, const ConverterContext & context);

/// Calculates both aggregations and the operator in one aggregation over `argument`, the converted `fusion.argument`.
SQLQueryPiece applyFusedAggregationBinaryOperator(
    const PrometheusQueryTree::BinaryOperator * operator_node,
    const AggregationBinaryOperatorFusion & fusion,
    SQLQueryPiece && argument,
    ConverterContext & context);

}

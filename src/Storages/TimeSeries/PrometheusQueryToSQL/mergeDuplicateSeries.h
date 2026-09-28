#pragma once

#include <Parsers/IAST_fwd.h>


namespace DB::PrometheusQueryToSQL
{

/// Returns an aggregate expression which merges `values` of the rows in a group, taking the non-NULL value at each step.
/// Prometheus merges series with the same tags like that if they never have values at the same step.
ASTPtr makeMergedValues(const ASTPtr & values);

/// Returns a HAVING condition which throws if two rows of a group have values at the same step.
ASTPtr makeDuplicateSeriesCheck(const ASTPtr & values, ASTPtr group);

}

#pragma once

#include <Parsers/IAST_fwd.h>
#include <Parsers/Prometheus/PrometheusQueryTree.h>


namespace DB
{

/// Makes an AST checking that a label satisfies a matcher of a prometheus selector, for example `equals(<label_value>, 'api')`
/// for the matcher `job="api"`. `label_value` is a String expression, which must be the empty string for an absent label.
/// A regular expression must match the whole value, so the matchers `=~` and `!~` are anchored.
/// It's the condition `timeSeriesSelector` filters series by, so other filters by the same matchers select the same series.
ASTPtr timeSeriesLabelMatcherToAST(const PrometheusQueryTree::Matcher & matcher, ASTPtr label_value);

}

#!/usr/bin/env bash
# Tags: no-fasttest
# Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

# PromQL `quantile` takes at most `aggregate_function_group_array_max_element_size` series in one group at one step,
# and fails with a clear error above that limit, whatever groupArray does at its limit.

SETUP="
CREATE TABLE prometheus ENGINE = TimeSeries;
INSERT INTO prometheus (metric_name, tags, samples) VALUES
    ('three', map('s', 'a'), [(toDateTime64(60, 3), 1)]),
    ('three', map('s', 'b'), [(toDateTime64(60, 3), 2)]),
    ('three', map('s', 'c'), [(toDateTime64(60, 3), 4)]),
    ('four', map('s', 'a', 'g', 'x'), [(toDateTime64(60, 3), 1)]),
    ('four', map('s', 'b', 'g', 'x'), [(toDateTime64(60, 3), 2)]),
    ('four', map('s', 'c', 'g', 'y'), [(toDateTime64(60, 3), 4)]),
    ('four', map('s', 'd', 'g', 'y'), [(toDateTime64(60, 3), 8)]),
    ('spread', map('s', 'a'), [(toDateTime64(60, 3), 1)]),
    ('spread', map('s', 'b'), [(toDateTime64(60, 3), 2)]),
    ('spread', map('s', 'c'), [(toDateTime64(60, 3), 4)]),
    ('spread', map('s', 'd'), [(toDateTime64(1000, 3), 8)]);
"

function run()
{
    local action=$1
    local query=$2
    echo "-- $query"
    ${CLICKHOUSE_LOCAL} --session_timezone UTC --allow_experimental_time_series_table 1 -q "$SETUP $query" \
        -- --aggregate_function_group_array_max_element_size=3 --aggregate_function_group_array_action_when_limit_is_reached="$action" 2>&1 \
        | sed -E 's/^Code: ([0-9]+)\. DB::Exception: (PromQL [^:]*).*/error \1: \2/'
}

for action in throw discard; do
    echo "---- $action"
    run "$action" "SELECT value FROM prometheusQuery('prometheus', 'quantile(0.5, three)', 60)"
    run "$action" "SELECT value FROM prometheusQuery('prometheus', 'quantile(0.5, four)', 60)"
    run "$action" "SELECT value FROM prometheusQuery('prometheus', 'quantile(scalar(vector(0.5)), four)', 60)"
    run "$action" "SELECT tags, value FROM prometheusQuery('prometheus', 'quantile by (g) (0.5, four)', 60) ORDER BY tags"
    # Four series in the group, but at most three at one step.
    run "$action" "SELECT samples FROM prometheusQueryRange('prometheus', 'quantile(0.5, spread)', 60, 1000, 940)"
done

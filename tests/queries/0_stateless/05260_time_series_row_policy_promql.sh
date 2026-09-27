#!/usr/bin/env bash
# Tags: no-fasttest, no-replicated-database
# no-fasttest: PromQL needs ANTLR4; no-replicated-database: `TimeSeries` inner tables are not dropped synchronously there.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

user="u_ts_policy_${CLICKHOUSE_DATABASE}"
policy="p_ts_policy_${CLICKHOUSE_DATABASE}"

${CLICKHOUSE_CLIENT} --query "DROP USER IF EXISTS ${user}"
${CLICKHOUSE_CLIENT} --multiquery --query "
SET allow_experimental_time_series_table = 1;
CREATE TABLE ts ENGINE = TimeSeries SETTINGS tags_to_columns = {'region': 'region'};
INSERT INTO ts (metric_name, tags, samples) VALUES
    ('up', {'job': 'api', 'region': 'eu'}, [(toDateTime64(1000, 3), 1)]),
    ('up', {'job': 'db', 'region': 'us'}, [(toDateTime64(1000, 3), 2)]);
CREATE USER ${user} NOT IDENTIFIED;
GRANT SELECT ON ${CLICKHOUSE_DATABASE}.* TO ${user};
GRANT CREATE TEMPORARY TABLE ON *.* TO ${user};
CREATE ROW POLICY ${policy} ON ts FOR SELECT USING tags['job'] = 'api' TO ${user};
"

function query()
{
    local out
    out=$(${CLICKHOUSE_CLIENT} "$@" 2>&1)
    if [[ $out == *"Cannot read time series from table"*"(ACCESS_DENIED)"* ]]; then echo "ACCESS_DENIED"; else echo "$out"; fi
}

function check()
{
    echo "-- $1"
    query --user "${user}" --query "SELECT arraySort(groupArrayArray(samples.2)) FROM ts"
    query --user "${user}" --query "SELECT groupArray(value) FROM (SELECT value FROM prometheusQuery(ts, 'up', 1000) ORDER BY value)"
    query --user "${user}" --query "SELECT groupArray(value) FROM (SELECT value FROM prometheusQuery(ts, 'sum(up)', 1000))"
    query --user "${user}" --query "SELECT groupArray(value) FROM (SELECT value FROM timeSeriesSelector(ts, 'up', 0, 2000) ORDER BY value)"
}

check "a policy on a tag"

${CLICKHOUSE_CLIENT} --query "ALTER ROW POLICY ${policy} ON ts USING tags['region'] = 'us' AND metric_name = 'up'"
check "a policy on a tag with its own column and on the metric name"

${CLICKHOUSE_CLIENT} --query "ALTER ROW POLICY ${policy} ON ts USING NOT mapContains(tags, 'job') OR tags['job'] != 'db'"
check "a policy on the whole tags map"

${CLICKHOUSE_CLIENT} --query "ALTER ROW POLICY ${policy} ON ts USING type = 'gauge'"
check "a policy on another column is refused"

${CLICKHOUSE_CLIENT} --query "DROP ROW POLICY ${policy} ON ts"

echo "-- additional_table_filters"
query --query "SELECT groupArray(value) FROM (SELECT value FROM prometheusQuery(ts, 'up', 1000) ORDER BY value) SETTINGS additional_table_filters = {'ts': 'tags[\\'job\\'] = \\'db\\''}"
query --query "SELECT groupArray(value) FROM (SELECT value FROM prometheusQuery(ts, 'up', 1000) ORDER BY value) SETTINGS additional_table_filters = {'${CLICKHOUSE_DATABASE}.ts': 'tags[\\'job\\'] = \\'api\\''}"
query --query "SELECT groupArray(value) FROM (SELECT value FROM prometheusQuery(ts, 'up', 1000) ORDER BY value) SETTINGS additional_table_filters = {'ts': 'length(samples) > 0'}"

${CLICKHOUSE_CLIENT} --query "DROP USER ${user}"

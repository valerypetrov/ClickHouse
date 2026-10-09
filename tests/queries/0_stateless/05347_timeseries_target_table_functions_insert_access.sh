#!/usr/bin/env bash

# Writing through a target table function of a TimeSeries table writes into that table,
# so it needs the INSERT grant on it, the same as `INSERT INTO` the table.

CLICKHOUSE_CLIENT_SERVER_LOGS_LEVEL=none

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

user="user_${CLICKHOUSE_DATABASE}"
db="${CLICKHOUSE_DATABASE}"

${CLICKHOUSE_CLIENT} --allow_experimental_time_series_table 1 -q "
    DROP USER IF EXISTS ${user};
    CREATE USER ${user};
    CREATE TABLE ${db}.ts ENGINE = TimeSeries;
    GRANT SELECT ON ${db}.ts TO ${user};
    GRANT CREATE TEMPORARY TABLE ON *.* TO ${user};
"

function try_inserts()
{
    echo "-- with ${1}:"
    for insert in \
        "timeSeriesSamples(${db}.ts) (timestamp, value) VALUES (1000, 1)" \
        "timeSeriesTags(${db}.ts) (metric_name, tags) VALUES ('m', {'job': 'api'})" \
        "timeSeriesTagsMinMax(${db}.ts) (metric_name, min_time, max_time) VALUES ('m', 1000, 2000)" \
        "timeSeriesMetricFamilies(${db}.ts) (metric_family, type) VALUES ('m', 'gauge')"
    do
        error=$(${CLICKHOUSE_CLIENT} --user "${user}" --async_insert 0 -q "INSERT INTO FUNCTION ${insert}" 2>&1 \
            | grep -m1 -oE "grant INSERT ON ${db}\.ts|\([A-Z_]+\)" | sed "s/${db}/db/" | paste -sd ' ' -)
        echo "${insert%%(*}: ${error:-OK}"
    done
    ${CLICKHOUSE_CLIENT} -q "
        SELECT (SELECT count() FROM timeSeriesSamples(${db}.ts)), (SELECT count() FROM timeSeriesTags(${db}.ts)),
               (SELECT count() FROM timeSeriesTagsMinMax(${db}.ts)), (SELECT count() FROM timeSeriesMetricFamilies(${db}.ts))
    "
}

try_inserts "SELECT only"

${CLICKHOUSE_CLIENT} -q "GRANT INSERT ON ${db}.ts TO ${user}"
try_inserts "INSERT"

${CLICKHOUSE_CLIENT} -q "
    DROP TABLE ${db}.ts;
    DROP USER ${user};
"

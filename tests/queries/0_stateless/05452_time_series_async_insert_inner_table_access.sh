#!/usr/bin/env bash

# An insert into a `TimeSeries` table writes to its inner tables, so it requires the INSERT privilege on them.
# With `async_insert = 1` and `wait_for_async_insert = 0` the data is inserted in a background flush after the query
# has returned, so the privilege must be checked when the query is executed, though nothing is written to the inner
# tables then. Otherwise the query would succeed and its data would be lost in the flush.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

user="user_${CLICKHOUSE_DATABASE}"
db="${CLICKHOUSE_DATABASE}"

${CLICKHOUSE_CLIENT} --allow_experimental_time_series_table 1 -q "
    DROP USER IF EXISTS ${user};
    CREATE TABLE ${db}.ts ENGINE = TimeSeries;
    CREATE USER ${user};
    GRANT INSERT ON ${db}.ts TO ${user};
"

# The user can insert into all the inner tables except the samples table.
samples_table=$(${CLICKHOUSE_CLIENT} -q "SELECT name FROM system.tables WHERE database = '${db}' AND name LIKE '.inner%.samples.%'")
for table in $(${CLICKHOUSE_CLIENT} -q "SELECT name FROM system.tables WHERE database = '${db}' AND name LIKE '.inner%' AND name != '${samples_table}'"); do
    ${CLICKHOUSE_CLIENT} -q "GRANT INSERT ON ${db}.\`${table}\` TO ${user}"
done

# Prints the missing privilege from the error, if any. The error is repeated in the server logs sent to the client.
function print_access_denied()
{
    grep -oE "grant INSERT ON [^ ]+ \(ACCESS_DENIED\)" | head -n 1 | sed -e "s/${db}/db/" -e "s/${samples_table}/samples_table/"
}

# The client sends the data separately from the query, so the server executes the query before putting the data
# into the asynchronous insert queue (unlike `INSERT ... VALUES` with the data inlined in the query).
function async_insert()
{
    ${CLICKHOUSE_CLIENT} --user "${user}" --async_insert 1 --wait_for_async_insert 0 \
        -q "INSERT INTO ${db}.ts ${1} FORMAT Values" 2>&1 | print_access_denied
}

function empty_insert_select()
{
    ${CLICKHOUSE_CLIENT} --user "${user}" --async_insert 1 \
        -q "INSERT INTO ${db}.ts (metric_name, tags, samples) SELECT 'm', map(), [] WHERE 0" 2>&1 | print_access_denied
}

echo "--- without INSERT on the samples table the inserts writing samples are denied, even without rows ---"
echo "('m1', {'tag': 'a'}, [('2026-01-01 00:00:00', 1)])" | async_insert "(metric_name, tags, samples)"
empty_insert_select

echo "--- an insert writing only metric families doesn't need it ---"
echo "('family', 'gauge', '', '')" | async_insert "(metric_family, type, unit, help)"

echo "--- with INSERT on the samples table ---"
${CLICKHOUSE_CLIENT} -q "GRANT INSERT ON ${db}.\`${samples_table}\` TO ${user}"
echo "('m2', {'tag': 'b'}, [('2026-01-01 00:00:00', 2), ('2026-01-01 00:00:10', 3)])" | async_insert "(metric_name, tags, samples)"
empty_insert_select

# With parallel replicas every replica reads all the rows of the inner tables behind these table functions,
# see https://github.com/ClickHouse/ClickHouse/issues/118130.
${CLICKHOUSE_CLIENT} --enable_parallel_replicas 0 -q "
    SYSTEM FLUSH ASYNC INSERT QUEUE ${db}.ts;
    SELECT 'tags', metric_name, tags FROM timeSeriesTags(${db}.ts) ORDER BY ALL;
    SELECT 'time ranges', min_time, max_time FROM timeSeriesTimeRanges(${db}.ts) ORDER BY ALL;
    SELECT 'samples', timestamp, value FROM timeSeriesSamples(${db}.ts) ORDER BY ALL;
    SELECT 'metric families', metric_family, type FROM timeSeriesMetricFamilies(${db}.ts) ORDER BY ALL;
"

${CLICKHOUSE_CLIENT} -q "
    DROP TABLE ${db}.ts;
    DROP USER ${user};
"

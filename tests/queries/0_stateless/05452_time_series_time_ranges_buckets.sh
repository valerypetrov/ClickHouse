#!/usr/bin/env bash
# Tags: no-fasttest
# Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.
#
# With the `time_ranges_bucket_seconds` setting a TimeSeries table widens the time range of a time series to whole buckets
# counted from the Unix epoch (`min_time` is rounded down to the start of its bucket, `max_time` up to the end of its bucket),
# and its deduplication cache skips a time range written before for the same time series. So the inserts of a time series
# within one bucket write one row to the "time ranges" table instead of one row per insert.
# The merges of the inner time ranges tables are stopped, so their rows are counted as the inserts wrote them.
# A wider time range only makes a time series a candidate for a query, so the selector still returns exactly the samples in its range.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

CLIENT="$CLICKHOUSE_CLIENT --allow_experimental_time_series_table=1"

$CLIENT -q "
    CREATE TABLE ts ENGINE = TimeSeries SETTINGS time_ranges_bucket_seconds = 3600;
    CREATE TABLE ts_datetime (samples Array(Tuple(DateTime('UTC'), Float64))) ENGINE = TimeSeries SETTINGS time_ranges_bucket_seconds = 60;
    CREATE TABLE ts_datetime64_6 (samples Array(Tuple(DateTime64(6, 'UTC'), Float64))) ENGINE = TimeSeries SETTINGS time_ranges_bucket_seconds = 60;
    CREATE TABLE ts_exact ENGINE = TimeSeries;
"

# The names of the inner time ranges tables, their merges are stopped before the inserts.
declare -A time_ranges
for table in ts ts_datetime ts_datetime64_6 ts_exact; do
    time_ranges[$table]=$($CLIENT -q "SELECT '.inner_id.timeranges.' || toString(uuid) FROM system.tables WHERE database = currentDatabase() AND name = '$table'")
    $CLIENT -q "SYSTEM STOP MERGES \`${time_ranges[$table]}\`"
done

# Prints the number of rows in the inner time ranges table of a TimeSeries table, then the rows.
function print_time_ranges()
{
    $CLIENT -q "
        SET session_timezone = 'UTC';
        SELECT count() FROM \`${time_ranges[$1]}\`;
        SELECT min_time, max_time FROM \`${time_ranges[$1]}\` ORDER BY min_time, max_time;
    "
}

echo "-- one row per time series and bucket of one hour, a block spanning two buckets writes a time range covering both"
$CLIENT -q "
    SET session_timezone = 'UTC';
    INSERT INTO ts (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 00:00:15', 3), 1), (toDateTime64('2026-01-01 00:00:30', 3), 2)]);
    INSERT INTO ts (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 00:15:00', 3), 3)]), ('m', {'job': 'b'}, [(toDateTime64('2026-01-01 00:20:00', 3), 11)]);
    INSERT INTO ts (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 00:59:59.999', 3), 4)]), ('m', {'job': 'b'}, [(toDateTime64('2026-01-01 00:40:00', 3), 12)]);
    INSERT INTO ts (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 01:00:00', 3), 5)]);
    INSERT INTO ts (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 01:30:00', 3), 6)]);
    INSERT INTO ts (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 01:59:45', 3), 7), (toDateTime64('2026-01-01 02:00:15', 3), 8)]);
    INSERT INTO ts (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 02:30:00', 3), 9)]);
    INSERT INTO ts (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 02:45:00', 3), 10)]);
"
print_time_ranges ts

echo "-- the selector returns every sample in its time range, inside the buckets and at their edges"
$CLIENT -q "
    SET session_timezone = 'UTC';
    SELECT count() FROM timeSeriesSelector(ts, 'm', toDateTime64('2026-01-01 00:00:00', 3), toDateTime64('2026-01-01 03:00:00', 3));
    SELECT count() FROM timeSeriesSelector(ts, 'm', toDateTime64('2026-01-01 00:00:00', 3), toDateTime64('2026-01-01 00:30:00', 3));
    SELECT count() FROM timeSeriesSelector(ts, 'm{job=\"a\"}', toDateTime64('2026-01-01 00:10:00', 3), toDateTime64('2026-01-01 00:20:00', 3));
    SELECT count() FROM timeSeriesSelector(ts, 'm{job=\"a\"}', toDateTime64('2026-01-01 00:00:00', 3), toDateTime64('2026-01-01 00:00:15', 3));
    SELECT count() FROM timeSeriesSelector(ts, 'm{job=\"a\"}', toDateTime64('2026-01-01 00:59:59.999', 3), toDateTime64('2026-01-01 01:00:00', 3));
    SELECT count() FROM timeSeriesSelector(ts, 'm{job=\"a\"}', toDateTime64('2026-01-01 02:00:00', 3), toDateTime64('2026-01-01 02:00:15', 3));
    SELECT count() FROM timeSeriesSelector(ts, 'm{job=\"a\"}', toDateTime64('2026-01-01 02:45:00', 3), toDateTime64('2026-01-01 03:00:00', 3));
    SELECT count() FROM timeSeriesSelector(ts, 'm{job=\"b\"}', toDateTime64('2026-01-01 00:20:00.001', 3), toDateTime64('2026-01-01 00:39:59.999', 3));
    SELECT count() FROM timeSeriesSelector(ts, 'm', toDateTime64('2026-01-01 03:00:00', 3), toDateTime64('2026-01-01 04:00:00', 3));
"

echo "-- DateTime timestamps"
$CLIENT -q "
    SET session_timezone = 'UTC';
    INSERT INTO ts_datetime (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime('2026-01-01 00:00:10'), 1)]);
    INSERT INTO ts_datetime (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime('2026-01-01 00:00:50'), 2)]);
    INSERT INTO ts_datetime (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime('2026-01-01 00:01:00'), 3)]);
"
print_time_ranges ts_datetime
$CLIENT -q "
    SET session_timezone = 'UTC';
    SELECT count() FROM timeSeriesSelector(ts_datetime, 'm', toDateTime('2026-01-01 00:00:00'), toDateTime('2026-01-01 00:02:00'));
    SELECT count() FROM timeSeriesSelector(ts_datetime, 'm', toDateTime('2026-01-01 00:00:50'), toDateTime('2026-01-01 00:01:00'));
"

echo "-- DateTime64(6) timestamps around the Unix epoch"
$CLIENT -q "
    SET session_timezone = 'UTC';
    INSERT INTO ts_datetime64_6 (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('1969-12-31 23:59:30.000001', 6), 1)]);
    INSERT INTO ts_datetime64_6 (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('1969-12-31 23:59:59.999999', 6), 2)]);
    INSERT INTO ts_datetime64_6 (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('1970-01-01 00:00:00', 6), 3)]);
"
print_time_ranges ts_datetime64_6
$CLIENT -q "
    SET session_timezone = 'UTC';
    SELECT count() FROM timeSeriesSelector(ts_datetime64_6, 'm', toDateTime64('1969-12-31 23:59:00', 6), toDateTime64('1970-01-01 00:01:00', 6));
    SELECT count() FROM timeSeriesSelector(ts_datetime64_6, 'm', toDateTime64('1969-12-31 23:59:59.999999', 6), toDateTime64('1970-01-01 00:00:00', 6));
"

echo "-- the time ranges are exact by default, and rounded after the setting is changed"
$CLIENT -q "
    SET session_timezone = 'UTC';
    INSERT INTO ts_exact (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 00:00:10', 3), 1)]);
    INSERT INTO ts_exact (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 00:00:20', 3), 2)]);
    ALTER TABLE ts_exact MODIFY SETTING time_ranges_bucket_seconds = 60;
    INSERT INTO ts_exact (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 00:00:30', 3), 3)]);
    INSERT INTO ts_exact (metric_name, tags, samples) VALUES ('m', {'job': 'a'}, [(toDateTime64('2026-01-01 00:00:40', 3), 4)]);
"
print_time_ranges ts_exact

$CLIENT -q "DROP TABLE ts, ts_datetime, ts_datetime64_6, ts_exact"

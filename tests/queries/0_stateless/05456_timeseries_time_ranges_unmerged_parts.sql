-- Tags: no-fasttest, no-parallel-replicas
-- Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.
-- Tag no-parallel-replicas: every parallel replica reads all rows of the table behind `timeSeriesTimeRanges`, so each row
-- is returned once per replica until https://github.com/ClickHouse/ClickHouse/pull/119350 is merged.
--
-- The time ranges table has a row per insert of a time series until its parts are merged.
-- The selectors return the same samples whether those rows are merged or not.

SET allow_experimental_time_series_table = 1;
SET session_timezone = 'UTC';

DROP TABLE IF EXISTS ts;

-- The time ranges table doesn't merge its parts by itself, so every insert keeps its own row of each time series.
CREATE TABLE ts ENGINE = TimeSeries
TIME RANGES INNER ENGINE = AggregatingMergeTree ORDER BY id SETTINGS max_bytes_to_merge_at_max_space_in_pool = 1;

INSERT INTO ts (metric_name, tags, samples) SELECT 'm', map('host', 'h' || toString(number)), [(toDateTime64(1000, 3), number)] FROM numbers(4);
INSERT INTO ts (metric_name, tags, samples) VALUES ('m2', map('host', 'h0'), [(toDateTime64(1000, 3), 10.)]);
INSERT INTO ts (metric_name, tags, samples) SELECT 'm', map('host', 'h' || toString(number)), [(toDateTime64(1100, 3), number + 1)] FROM numbers(4);
INSERT INTO ts (metric_name, tags, samples) SELECT 'm', map('host', 'h' || toString(number)), [(toDateTime64(1200, 3), number + 2)] FROM numbers(2);

SELECT '-- unmerged';
SELECT count(), uniqExact(id) FROM timeSeriesTimeRanges(ts);

SELECT count(), sum(value) FROM timeSeriesSelector(ts, 'm', 0, 2000);
SELECT count(), sum(value) FROM timeSeriesSelector(ts, 'm{host="h1"}', 0, 2000);
SELECT count(), sum(value) FROM timeSeriesSelector(ts, 'm', 1150, 2000);
SELECT count(), sum(value) FROM timeSeriesSelector(ts, '{__name__=~"m.*"}', 0, 2000);
SELECT count(), sum(value) FROM timeSeriesSelector(ts, 'm', 0, 2000) SETTINGS any_join_distinct_right_table_keys = 1;
SELECT count(), sum(value) FROM timeSeriesSelector(ts, '{__name__=~"m.*"}', 0, 2000) SETTINGS join_use_nulls = 1;
SELECT tags, value FROM prometheusQuery(ts, 'm', 1200) ORDER BY tags;
SELECT tags, value FROM prometheusQuery(ts, 'count({__name__=~"m.*"})', 1100);

SELECT '-- merged';
OPTIMIZE TABLE ts FINAL;
SELECT count(), uniqExact(id) FROM timeSeriesTimeRanges(ts);

SELECT count(), sum(value) FROM timeSeriesSelector(ts, 'm', 0, 2000);
SELECT count(), sum(value) FROM timeSeriesSelector(ts, 'm{host="h1"}', 0, 2000);
SELECT count(), sum(value) FROM timeSeriesSelector(ts, 'm', 1150, 2000);
SELECT count(), sum(value) FROM timeSeriesSelector(ts, '{__name__=~"m.*"}', 0, 2000);
SELECT count(), sum(value) FROM timeSeriesSelector(ts, 'm', 0, 2000) SETTINGS any_join_distinct_right_table_keys = 1;
SELECT count(), sum(value) FROM timeSeriesSelector(ts, '{__name__=~"m.*"}', 0, 2000) SETTINGS join_use_nulls = 1;
SELECT tags, value FROM prometheusQuery(ts, 'm', 1200) ORDER BY tags;
SELECT tags, value FROM prometheusQuery(ts, 'count({__name__=~"m.*"})', 1100);

DROP TABLE ts;

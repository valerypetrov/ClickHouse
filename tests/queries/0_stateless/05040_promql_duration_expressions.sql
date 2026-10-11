-- Tags: no-fasttest
-- Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.

-- Duration expressions in range selectors, subqueries and offsets, like in Prometheus 3.5 with --enable-feature=promql-duration-expr.

SET allow_experimental_time_series_table = 1;

DROP TABLE IF EXISTS ts;
CREATE TABLE ts ENGINE = TimeSeries;

-- metric1_total has value i at i * 10 seconds.
INSERT INTO ts (metric_name, tags, samples)
    SELECT 'metric1_total', map(), arrayMap(i -> (toDateTime64(i * 10, 3), toFloat64(i)), range(201));

SELECT '--- range selectors ---';
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[60s])', 1000);
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[50s+10s])', 1000);
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[2m/2])', 1000);
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[2 ^ 6 - 4])', 1000);
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[1m30s % 1m + 30s])', 1000);
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[-1m + 2m])', 1000);
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[(1m)])', 1000);
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[2 * (10s + 20s)])', 1000);

SELECT '--- subqueries ---';
SELECT value FROM prometheusQuery(ts, 'sum_over_time(metric1_total[29s+1s:5s+5s])', 1000);
SELECT value FROM prometheusQuery(ts, 'sum_over_time(metric1_total[29s+1s:((((8 - 2) / 3) * 7s) % 4) + 8000ms])', 1000);
SELECT value FROM prometheusQuery(ts, 'sum_over_time(metric1_total[29s+1s:20*500ms] offset (20*(((((8 - 2) / 3) * 7s) % 4) + 8000ms)))', 1200);
SELECT value FROM prometheusQuery(ts, 'sum_over_time(metric1_total[29s+1s:20*500ms] offset -(20*(((((8 - 2) / 3) * 7s) % 4) + 8000ms)))', 800);

SELECT '--- offsets ---';
SELECT value FROM prometheusQuery(ts, 'metric1_total offset (100 + 2)', 1000);
SELECT value FROM prometheusQuery(ts, 'metric1_total offset 100 + 2', 1000);
SELECT value FROM prometheusQuery(ts, 'metric1_total offset 2 ^ 2', 1002);
SELECT value FROM prometheusQuery(ts, 'metric1_total offset -2 ^ 2', 998);
SELECT value FROM prometheusQuery(ts, 'metric1_total offset (2 ^ 2)', 1000);
SELECT value FROM prometheusQuery(ts, 'metric1_total offset -2 * 2', 1000);
SELECT value FROM prometheusQuery(ts, 'metric1_total offset (-2 * 2)', 1000);
SELECT value FROM prometheusQuery(ts, 'metric1_total offset (-2 ^ 2)', 1000);

SELECT '--- errors ---';
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[1m - 1m])', 1000); -- { serverError CANNOT_PARSE_PROMQL_QUERY }
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[-1m])', 1000); -- { serverError CANNOT_PARSE_PROMQL_QUERY }
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[1m / 0])', 1000); -- { serverError CANNOT_PARSE_PROMQL_QUERY }
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[1m % 0])', 1000); -- { serverError CANNOT_PARSE_PROMQL_QUERY }
SELECT value FROM prometheusQuery(ts, 'sum_over_time(metric1_total[1m:0 * 1s])', 1000); -- { serverError CANNOT_PARSE_PROMQL_QUERY }
SELECT value FROM prometheusQuery(ts, 'count_over_time(metric1_total[1e30 * 1])', 1000); -- { serverError CANNOT_PARSE_PROMQL_QUERY }
SELECT value FROM prometheusQuery(ts, 'metric1_total offset (1 / 0)', 1000); -- { serverError CANNOT_PARSE_PROMQL_QUERY }

DROP TABLE ts;

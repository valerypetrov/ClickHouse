-- Tags: no-fasttest
-- Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.
DROP TABLE IF EXISTS t_promql_dfp;

SET session_timezone = 'UTC';
SET allow_experimental_time_series_table = 1;

CREATE TABLE t_promql_dfp ENGINE = TimeSeries;

-- Left-side metric `requests` with dc=a (hosts h1, h2)
-- Right-side metric `target_info` with dc=a, dc=b and dc=c
INSERT INTO t_promql_dfp (metric_name, tags, samples) VALUES
    ('requests', map('host', 'h1', 'dc', 'a'), [(toDateTime64(100, 3), 10), (toDateTime64(110, 3), 20)]),
    ('requests', map('host', 'h2', 'dc', 'a'), [(toDateTime64(100, 3), 30), (toDateTime64(110, 3), 40)]),
    ('target_info', map('dc', 'a', 'env', 'prod'), [(toDateTime64(100, 3), 1), (toDateTime64(110, 3), 1)]),
    ('target_info', map('dc', 'b', 'env', 'staging'), [(toDateTime64(100, 3), 1), (toDateTime64(110, 3), 1)]),
    ('target_info', map('dc', 'c', 'env', 'dev'), [(toDateTime64(100, 3), 1), (toDateTime64(110, 3), 1)]);

SELECT '-- group_left prunes dc=b and dc=c';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) target_info', 110) ORDER BY tags;

SELECT '-- explain plan verifies join_group filter pushdown';
SELECT countIf(explain LIKE '%Filter%' AND (explain LIKE '%timeSeriesRemoveAllTagsExcept%' OR explain LIKE '%join_group%')) >= 2
FROM (EXPLAIN PLAN actions = 1 SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) target_info', 110));

SELECT '-- group_left with subquery on right side';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) last_over_time(target_info[5m:10s])', 110) ORDER BY tags;

SELECT '-- explain plan verifies join_group filter pushdown with subquery on right side';
SELECT countIf(explain LIKE '%Filter%' AND (explain LIKE '%timeSeriesRemoveAllTagsExcept%' OR explain LIKE '%join_group%')) >= 2
FROM (EXPLAIN PLAN actions = 1 SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) last_over_time(target_info[5m:10s])', 110));

SELECT '-- group_left with offset on right side';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) (target_info offset 10s)', 110) ORDER BY tags;

SELECT '-- explain plan verifies join_group filter pushdown with offset on right side';
SELECT countIf(explain LIKE '%Filter%' AND (explain LIKE '%timeSeriesRemoveAllTagsExcept%' OR explain LIKE '%join_group%')) >= 2
FROM (EXPLAIN PLAN actions = 1 SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) (target_info offset 10s)', 110));

SELECT '-- group_left with fixed at modifier on right side';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) (target_info @ 110)', 110) ORDER BY tags;

SELECT '-- explain plan verifies join_group filter pushdown with fixed at modifier on right side';
SELECT countIf(explain LIKE '%Filter%' AND (explain LIKE '%timeSeriesRemoveAllTagsExcept%' OR explain LIKE '%join_group%')) >= 2
FROM (EXPLAIN PLAN actions = 1 SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) (target_info @ 110)', 110));

SELECT '-- group_left with label_replace on right side';
SELECT * FROM prometheusQuery('t_promql_dfp', 'label_replace(requests, "dc2", "$1", "dc", "(.*)") * on (dc2) group_left (env) label_replace(target_info, "dc2", "$1", "dc", "(.*)")', 110) ORDER BY tags;

SELECT '-- group_left with vector(scalar(...)) on right side';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on () group_left vector(scalar(sum(requests)))', 110) ORDER BY tags;

SELECT '-- group_left with on () is not pushed down, its join group is always the zero group';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on () group_left target_info{dc="a"}', 110) ORDER BY tags;

SELECT '-- explain plan verifies that on () skips the extra read of the right selector';
SELECT
    (SELECT countIf(explain LIKE '%ReadFrom%') FROM (EXPLAIN PLAN SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on () group_left target_info{dc="a"}', 110)))
    < (SELECT countIf(explain LIKE '%ReadFrom%') FROM (EXPLAIN PLAN SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left target_info{dc="a"}', 110)));

SELECT '-- group_left with on(__name__) and rate';
INSERT INTO t_promql_dfp (metric_name, tags, samples) VALUES
    ('rate_target', map('dc', 'a', 'env', 'prod'), [(toDateTime64(100, 3), 2), (toDateTime64(110, 3), 4)]);
SELECT * FROM prometheusQuery('t_promql_dfp', 'rate(requests{host="h1"}[50s]) * on (__name__) group_left rate(rate_target[50s])', 110) ORDER BY tags;

SELECT '-- group_left with absent on right side';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left absent(nonexistent_metric{dc="a"})', 110) ORDER BY tags;

SELECT '-- group_left with absent returning empty';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left absent(target_info{dc="a"})', 110) ORDER BY tags;

SELECT '-- a duplicate on a join group the left side does not have is reported too, as in Prometheus';
INSERT INTO t_promql_dfp (metric_name, tags, samples) VALUES
    ('target_info', map('dc', 'b', 'env', 'staging_dup'), [(toDateTime64(100, 3), 1), (toDateTime64(110, 3), 1)]);
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) target_info', 110); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) (target_info offset 10s)', 110); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) last_over_time(target_info[5m:10s])', 110); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQuery('t_promql_dfp', 'label_replace(requests, "dc2", "$1", "dc", "(.*)") * on (dc2) group_left (env) label_replace(target_info, "dc2", "$1", "dc", "(.*)")', 110); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }

SELECT '-- with an empty left side the duplicate is not reported, as in Prometheus';
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests{dc="nonexistent"} * on (dc) group_left (env) target_info', 110) ORDER BY tags;
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests{dc="nonexistent"} * on (dc) group_left (env) (target_info offset 10s)', 110) ORDER BY tags;

SELECT '-- a duplicate on a matched join group is still reported';
INSERT INTO t_promql_dfp (metric_name, tags, samples) VALUES
    ('target_info', map('dc', 'a', 'env', 'prod_dup'), [(toDateTime64(100, 3), 1), (toDateTime64(110, 3), 1)]);
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) target_info', 110); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQuery('t_promql_dfp', 'requests * on (dc) group_left (env) (target_info offset 10s)', 110); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }

DROP TABLE t_promql_dfp;

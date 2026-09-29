-- Tags: no-fasttest
-- Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.

-- Series which get the same tags are merged if they never have values at the same step, like in Prometheus.
-- They are still an error if they have values at the same step.

DROP TABLE IF EXISTS prometheus;

SET session_timezone = 'UTC';
SET allow_experimental_time_series_table = 1;
SET enable_time_series_aggregate_functions = 1;

CREATE TABLE prometheus ENGINE = TimeSeries;

-- a_total and b_total never overlap, c_total and d_total overlap,
-- f_total has a single sample, so its rate has no value.
INSERT INTO prometheus (metric_name, tags, samples) VALUES
    ('a_total', map('job', 'j'), arrayMap(i -> (toDateTime64(100 + i * 10, 3), i + 1), range(7))),
    ('b_total', map('job', 'j'), arrayMap(i -> (toDateTime64(1000 + i * 10, 3), (i + 1) * 10), range(7))),
    ('c_total', map('job', 'k'), arrayMap(i -> (toDateTime64(100 + i * 10, 3), i + 1), range(7))),
    ('d_total', map('job', 'k'), arrayMap(i -> (toDateTime64(130 + i * 10, 3), (i + 1) * 10), range(7))),
    ('e_total', map('job', 'm'), arrayMap(i -> (toDateTime64(100 + i * 10, 3), i + 1), range(7))),
    ('f_total', map('job', 'm'), [(toDateTime64(150, 3), 5)]),
    ('thr', map('job', 'j'), arrayMap(i -> (toDateTime64(100 + i * 100, 3), 0.5), range(11))),
    ('n', map('job', 'j'), arrayMap(i -> (toDateTime64(100 + i * 10, 3), nan), range(7))),
    ('s1', map('job', 's'), [(toDateTime64(140, 3), 1), (toDateTime64(150, 3), 1), (toDateTime64(160, 3), reinterpretAsFloat64(0x7FF0000000000002))]),
    ('s2', map('job', 's'), arrayMap(i -> (toDateTime64(170 + i * 10, 3), 2), range(4))),
    ('x', map('job', 'g', 't', '1'), arrayMap(i -> (toDateTime64(100 + i * 10, 3), 1), range(7))),
    ('x', map('job', 'g', 't', '2'), arrayMap(i -> (toDateTime64(100 + i * 10, 3), 10), range(7))),
    ('x', map('job', 'g', 't', '3'), arrayMap(i -> (toDateTime64(1000 + i * 10, 3), 20), range(7))),
    ('thr3', map('job', 'g', 't', 'z'), arrayMap(i -> (toDateTime64(100 + i * 100, 3), 5), range(11)));

SELECT '-- rate over series which never overlap';
SELECT * FROM prometheusQueryRange('prometheus', 'rate({__name__=~\'a_total|b_total\'}[60s])', 160, 1060, 100);

SELECT '-- unary minus over series which never overlap';
SELECT * FROM prometheusQueryRange('prometheus', '-{__name__=~\'a_total|b_total\'}', 160, 1060, 100);

SELECT '-- label_replace over series which never overlap';
SELECT * FROM prometheusQueryRange('prometheus', 'label_replace({__name__=~\'a_total|b_total\'}, \'__name__\', \'x\', \'\', \'\')', 160, 1060, 100);

SELECT '-- instant query, one of the series has no value at this step';
SELECT * FROM prometheusQuery('prometheus', 'rate({__name__=~\'e_total|f_total\'}[60s])', 160);

SELECT '-- binary operator, the side "one" has series which never overlap';
SELECT * FROM prometheusQueryRange('prometheus', 'thr + on(job) {__name__=~\'a_total|b_total\'}', 160, 1060, 100);

SELECT '-- binary operator, the result has series which never overlap';
SELECT * FROM prometheusQueryRange('prometheus', '{__name__=~\'a_total|b_total\'} + on(job) group_left thr', 160, 1060, 100);

SELECT '-- group_left, the side "one" has series which never overlap';
SELECT * FROM prometheusQueryRange('prometheus', 'thr + on(job) group_left {__name__=~\'a_total|b_total\'}', 160, 1060, 100);

SELECT '-- group_right, the side "one" has series which never overlap';
SELECT * FROM prometheusQueryRange('prometheus', '{__name__=~\'a_total|b_total\'} + on(job) group_right thr', 160, 1060, 100);

SELECT '-- NaN is a value';
SELECT * FROM prometheusQueryRange('prometheus', '-{__name__=~\'n|b_total\'}', 160, 1060, 100);
SELECT * FROM prometheusQuery('prometheus', '-{__name__=~\'n|a_total\'}', 160); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }

SELECT '-- a stale marker ends the series';
SELECT * FROM prometheusQueryRange('prometheus', '-{__name__=~\'s1|s2\'}', 140, 200, 10);

SELECT '-- group_left(t) with a comparison: a match which the comparison drops is still a duplicate';
SELECT * FROM prometheusQuery('prometheus', 'x > on(job) group_left(t) thr3', 160); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQuery('prometheus', 'x > bool on(job) group_left(t) thr3', 160); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQueryRange('prometheus', 'x{t!="2"} > on(job) group_left(t) thr3', 160, 1060, 100);

SELECT '-- series which overlap';
SELECT * FROM prometheusQueryRange('prometheus', 'rate({__name__=~\'c_total|d_total\'}[60s])', 160, 260, 100); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQuery('prometheus', '-{__name__=~\'c_total|d_total\'}', 160); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQuery('prometheus', 'label_replace({__name__=~\'c_total|d_total\'}, \'__name__\', \'x\', \'\', \'\')', 160); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQuery('prometheus', 'thr + ignoring(job) {__name__=~\'c_total|d_total\'}', 160); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }

SELECT '-- still an error: the result takes the tags of each series on the side "one", so they are not merged';
SELECT * FROM prometheusQueryRange('prometheus', '{__name__=~\'a_total|b_total\'} > on(job) thr', 160, 1060, 100); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }

TRUNCATE TABLE prometheus;

-- From promqltest operators.test: the side "one" of `group_left` is an `or` with a row that has no values.
INSERT INTO prometheus (metric_name, tags, samples) VALUES
    ('node_cpu', map('instance', 'abc', 'job', 'node', 'mode', 'idle'), [(toDateTime64(0, 3), 3)]),
    ('node_cpu', map('instance', 'abc', 'job', 'node', 'mode', 'user'), [(toDateTime64(0, 3), 1)]),
    ('node_cpu', map('instance', 'def', 'job', 'node', 'mode', 'idle'), [(toDateTime64(0, 3), 8)]),
    ('node_cpu', map('instance', 'def', 'job', 'node', 'mode', 'user'), [(toDateTime64(0, 3), 2)]),
    ('threshold', map('instance', 'abc', 'job', 'node', 'target', 'a@b.com'), [(toDateTime64(0, 3), 0)]);

SELECT '-- group_left with `or on` on the side "one"';
SELECT * FROM prometheusQuery('prometheus', 'node_cpu > on(job, instance) group_left(target) (threshold or on (job, instance) (sum by (job, instance)(node_cpu) * 0 + 1))', 60) ORDER BY tags;

DROP TABLE prometheus;

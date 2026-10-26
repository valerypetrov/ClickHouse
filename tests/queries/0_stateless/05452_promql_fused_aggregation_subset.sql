-- Tags: no-fasttest
-- Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.

-- Tests binary operators applied to two aggregations of expressions which differ only in that the selector of one side
-- has extra label matchers, e.g. `sum by (job) (rate(req{status="500"}[30s])) / sum by (job) (rate(req[30s]))`.
-- They are calculated in a single aggregation over the series of the other side: a series which doesn't satisfy
-- the extra matchers is aggregated only by the other side.
-- Each query is compared with the query which wraps both sides in a `label_replace` of a label nobody has: it changes nothing
-- but turns the fusion off, so the sides are calculated separately and joined.
-- The values are rounded because a sum of three or more series can differ in the last bit.

DROP TABLE IF EXISTS prometheus;
DROP TABLE IF EXISTS prometheus_empty;

SET session_timezone = 'UTC';
SET allow_experimental_time_series_table = 1;

CREATE TABLE prometheus ENGINE = TimeSeries;

-- The metric `req` has series of the jobs `api`, `db`, `web` with different statuses: the job `web` has no series
-- with status="500", and the series of the job `db` with status="500" ends at timestamp 100. The job `batch` has a series
-- without the label `status` and a series where it's empty, and one series has no label `job`.
-- The metric `lim` is selected together with `req` by a regex, and `m1`, `m2` have the same labels after dropping the metric name.
INSERT INTO prometheus (metric_name, tags, samples) VALUES
    ('req', map('job', 'api', 'instance', 'i1', 'status', '200'), [(toDateTime64(70, 3), 1), (toDateTime64(80, 3), 3), (toDateTime64(90, 3), 6), (toDateTime64(100, 3), 10), (toDateTime64(110, 3), 15), (toDateTime64(120, 3), 21), (toDateTime64(130, 3), 28)]),
    ('req', map('job', 'api', 'instance', 'i1', 'status', '500'), [(toDateTime64(70, 3), 0), (toDateTime64(80, 3), 1), (toDateTime64(90, 3), 1), (toDateTime64(100, 3), 2), (toDateTime64(110, 3), 3), (toDateTime64(120, 3), 3), (toDateTime64(130, 3), 4)]),
    ('req', map('job', 'api', 'instance', 'i2', 'status', '200'), [(toDateTime64(70, 3), 2), (toDateTime64(80, 3), 4), (toDateTime64(90, 3), 8), (toDateTime64(100, 3), 16), (toDateTime64(110, 3), 32), (toDateTime64(120, 3), 64), (toDateTime64(130, 3), 128)]),
    ('req', map('job', 'api', 'instance', 'i2', 'status', '503'), [(toDateTime64(70, 3), 0), (toDateTime64(80, 3), 0), (toDateTime64(90, 3), 1), (toDateTime64(100, 3), 1), (toDateTime64(110, 3), 2), (toDateTime64(120, 3), 2), (toDateTime64(130, 3), 3)]),
    ('req', map('job', 'db', 'instance', 'i3', 'status', '200'), [(toDateTime64(70, 3), 5), (toDateTime64(80, 3), 10), (toDateTime64(90, 3), 15), (toDateTime64(100, 3), 20), (toDateTime64(110, 3), 25), (toDateTime64(120, 3), 30), (toDateTime64(130, 3), 35)]),
    ('req', map('job', 'db', 'instance', 'i3', 'status', '500'), [(toDateTime64(70, 3), 1), (toDateTime64(80, 3), 2), (toDateTime64(90, 3), 4), (toDateTime64(100, 3), 7)]),
    ('req', map('job', 'web', 'instance', 'i4', 'status', '200'), [(toDateTime64(70, 3), 3), (toDateTime64(80, 3), 6), (toDateTime64(90, 3), 9), (toDateTime64(100, 3), 12), (toDateTime64(110, 3), 15), (toDateTime64(120, 3), 18), (toDateTime64(130, 3), 21)]),
    ('req', map('job', 'web', 'instance', 'i4', 'status', '404'), [(toDateTime64(70, 3), 0), (toDateTime64(80, 3), 1), (toDateTime64(90, 3), 2), (toDateTime64(100, 3), 3), (toDateTime64(110, 3), 4), (toDateTime64(120, 3), 5), (toDateTime64(130, 3), 6)]),
    ('req', map('job', 'batch', 'instance', 'i5'), [(toDateTime64(70, 3), 1), (toDateTime64(80, 3), 2), (toDateTime64(90, 3), 3), (toDateTime64(100, 3), 4), (toDateTime64(110, 3), 5), (toDateTime64(120, 3), 6), (toDateTime64(130, 3), 7)]),
    ('req', map('job', 'batch', 'instance', 'i6', 'status', ''), [(toDateTime64(70, 3), 2), (toDateTime64(80, 3), 3), (toDateTime64(90, 3), 5), (toDateTime64(100, 3), 8), (toDateTime64(110, 3), 13), (toDateTime64(120, 3), 21), (toDateTime64(130, 3), 34)]),
    ('req', map('instance', 'i7', 'status', '500'), [(toDateTime64(70, 3), 1), (toDateTime64(80, 3), 3), (toDateTime64(90, 3), 5), (toDateTime64(100, 3), 7), (toDateTime64(110, 3), 9), (toDateTime64(120, 3), 11), (toDateTime64(130, 3), 13)]),
    ('lim', map('job', 'api', 'instance', 'i8', 'status', '500'), [(toDateTime64(70, 3), 1), (toDateTime64(80, 3), 2), (toDateTime64(90, 3), 4), (toDateTime64(100, 3), 5), (toDateTime64(110, 3), 7), (toDateTime64(120, 3), 8), (toDateTime64(130, 3), 10)]),
    ('m1', map('a', '1'), [(toDateTime64(70, 3), 1), (toDateTime64(80, 3), 3), (toDateTime64(90, 3), 5), (toDateTime64(100, 3), 7), (toDateTime64(110, 3), 9), (toDateTime64(120, 3), 11), (toDateTime64(130, 3), 13)]),
    ('m1', map('a', '2'), [(toDateTime64(70, 3), 2), (toDateTime64(80, 3), 5), (toDateTime64(90, 3), 8), (toDateTime64(100, 3), 11), (toDateTime64(110, 3), 14), (toDateTime64(120, 3), 17), (toDateTime64(130, 3), 20)]),
    ('m2', map('a', '2'), [(toDateTime64(70, 3), 3), (toDateTime64(80, 3), 4), (toDateTime64(90, 3), 5), (toDateTime64(100, 3), 6), (toDateTime64(110, 3), 7), (toDateTime64(120, 3), 8), (toDateTime64(130, 3), 9)]);

SELECT '-- one aggregation, the same result as with a join';
SELECT 'eq', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status="500"}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status="500"}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'eq_on_the_right_side', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req[30s])) - sum by (job) (rate(req{status="500"}[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "") - label_replace(sum by (job) (rate(req{status="500"}[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'regex', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status=~"5.."}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status=~"5.."}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'regex_matching_empty', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status=~"500|"}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status=~"500|"}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'not_equal', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status!="200"}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status!="200"}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'not_regex', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status!~"2.*|4.*"}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status!~"2.*|4.*"}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'empty', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status=""}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status=""}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'two_extra_matchers', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status="500", instance="i1"}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status="500", instance="i1"}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
-- The sides select the same series.
SELECT 'reordered_matchers', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{instance=~"i1|i3", status="500"}[30s])) - sum by (job) (rate(req{status="500", instance=~"i1|i3"}[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{instance=~"i1|i3", status="500"}[30s])), "nx", "", "nx", "") - label_replace(sum by (job) (rate(req{status="500", instance=~"i1|i3"}[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'without', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum without (instance, status) (rate(req{status="500"}[30s])) / sum without (instance, status) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum without (instance, status) (rate(req{status="500"}[30s])), "nx", "", "nx", "") / label_replace(sum without (instance, status) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'no_grouping', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum(rate(req{status="500"}[30s])) / sum(rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum(rate(req{status="500"}[30s])), "nx", "", "nx", "") / label_replace(sum(rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'no_matching_series', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status="418"}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status="418"}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'no_matching_series_no_grouping', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum(rate(req{status="418"}[30s])) / sum(rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum(rate(req{status="418"}[30s])), "nx", "", "nx", "") / label_replace(sum(rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'count', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'count by (job) (req{status=~"5.."}) / count by (job) (req)',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(count by (job) (req{status=~"5.."}), "nx", "", "nx", "") / label_replace(count by (job) (req), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'max_min', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'max by (job) (req{status!="200"}) - min by (job) (req)',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(max by (job) (req{status!="200"}), "nx", "", "nx", "") - label_replace(min by (job) (req), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'stddev_stdvar', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'stddev by (job) (req{status=~"200|500"}) + stdvar by (job) (req)',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(stddev by (job) (req{status=~"200|500"}), "nx", "", "nx", "") + label_replace(stdvar by (job) (req), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'avg_group', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'avg by (job) (req) * group by (job) (req{status="500"})',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(avg by (job) (req), "nx", "", "nx", "") * label_replace(group by (job) (req{status="500"}), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'instant_selector', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (req{status="500"}) / sum by (job) (req)',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (req{status="500"}), "nx", "", "nx", "") / label_replace(sum by (job) (req), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'offset', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{status="500"}[30s] offset 10s)) / sum by (job) (rate(req[30s] offset 10s))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{status="500"}[30s] offset 10s)), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s] offset 10s)), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'subquery', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (max_over_time(rate(req{status="500"}[20s])[30s:10s])) / sum by (job) (max_over_time(rate(req[20s])[30s:10s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (max_over_time(rate(req{status="500"}[20s])[30s:10s])), "nx", "", "nx", "") / label_replace(sum by (job) (max_over_time(rate(req[20s])[30s:10s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SELECT 'quantile_over_time', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (quantile_over_time(0.5, req{status="500"}[30s])) / sum by (job) (quantile_over_time(0.5, req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (quantile_over_time(0.5, req{status="500"}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (quantile_over_time(0.5, req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
-- The text of the selector `m1` occurs twice in `rate(m1[1m1s])`, but the text of the other selector occurs once.
SELECT 'selector_text_repeated', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum(rate(m1[61s])) - sum(rate(m1{a="1"}[61s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum(rate(m1[61s])), "nx", "", "nx", "") - label_replace(sum(rate(m1{a="1"}[61s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SET promql_push_down_label_matchers = 0;
-- Without the pushdown, the sides differ in a matcher on a grouping label.
SELECT 'grouping_label', a = b, a FROM
(
    SELECT
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'sum by (job) (rate(req{job="api"}[30s])) / sum by (job) (rate(req[30s]))',
            100, 130, 10) ORDER BY tags)) AS a,
        (SELECT groupArray((tags, arrayMap(s -> (toUInt32(s.1), round(s.2, 9)), samples))) FROM (SELECT * FROM prometheusQueryRange('prometheus',
            'label_replace(sum by (job) (rate(req{job="api"}[30s])), "nx", "", "nx", "") / label_replace(sum by (job) (rate(req[30s])), "nx", "", "nx", "")',
            100, 130, 10) ORDER BY tags)) AS b
);
SET promql_push_down_label_matchers = 1;

SELECT '-- an instant query';
SELECT tags, timestamp, round(value, 9) FROM prometheusQuery('prometheus', 'sum by (job) (rate(req{status="500"}[30s])) / sum by (job) (rate(req[30s]))', 120) ORDER BY tags;

SELECT '-- a duplicate series after dropping the metric name is still an error';
SELECT * FROM prometheusQueryRange('prometheus', 'sum by (a) (rate({__name__=~"m1|m2", a="1"}[30s])) / sum by (a) (rate({__name__=~"m1|m2"}[30s]))', 100, 130, 10); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }
SELECT * FROM prometheusQueryRange('prometheus', 'sum by (a) (rate({__name__=~"m1|m2"}[30s])) / sum by (a) (rate({__name__=~"m1|m2", a="1"}[30s]))', 100, 130, 10); -- { serverError CANNOT_EXECUTE_PROMQL_QUERY }

-- Prints how many selectors the query reads and how many joins it makes, as in 05271_promql_label_matcher_pushdown.
-- EXPLAIN keeps the selector filters in the plan only for an empty table. Only the hash joins are counted: the PromQL operators
-- are executed with a hash join, while each selector joins the time ranges table with a merge join.
CREATE TABLE prometheus_empty ENGINE = TimeSeries;

SELECT '-- the fused queries read one selector and make no join';
SELECT 'eq', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum by (job) (rate(req{status="500"}[30s])) / sum by (job) (rate(req[30s]))', 100, 130, 10));
SELECT 'eq_on_the_right_side', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum by (job) (rate(req[30s])) - sum by (job) (rate(req{status="500"}[30s]))', 100, 130, 10));
SELECT 'not_equal', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum by (job) (rate(req{status!="200"}[30s])) / sum by (job) (rate(req[30s]))', 100, 130, 10));
SELECT 'no_grouping', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum(rate(req{status="500"}[30s])) / sum(rate(req[30s]))', 100, 130, 10));
SELECT 'selector_text_repeated', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum(rate(m1[61s])) - sum(rate(m1{a="1"}[61s]))', 100, 130, 10));
SELECT '-- the queries which are not fused read two selectors and join them';
-- A matcher on `__name__` can't be checked on the series of `rate`, which drops the metric name.
SELECT 'different_ranges', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum by (job) (rate(req{status="500"}[30s])) / sum by (job) (rate(req[1m]))', 100, 130, 10));
SELECT 'different_functions', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum by (job) (irate(req{status="500"}[30s])) / sum by (job) (rate(req[30s]))', 100, 130, 10));
SELECT 'extra_matchers_on_both_sides', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum by (job) (rate(req{status="500"}[30s])) / sum by (job) (rate(req{instance="i1"}[30s]))', 100, 130, 10));
SELECT 'extra_metric_name_matcher', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum by (job) (rate({__name__=~"req|lim", __name__!="lim"}[30s])) / sum by (job) (rate({__name__=~"req|lim"}[30s]))', 100, 130, 10));
SELECT '-- without the pushdown, the sides differ in a matcher on a grouping label and are fused too';
SET promql_push_down_label_matchers = 0;
SELECT 'grouping_label', countIf(explain LIKE '%Filter column:%metric_name%'), countIf(explain LIKE '%Join (JOIN FillRightFirst)%')
FROM (EXPLAIN SELECT * FROM prometheusQueryRange('prometheus_empty', 'sum by (job) (rate(req{job="api"}[30s])) / sum by (job) (rate(req[30s]))', 100, 130, 10));
SET promql_push_down_label_matchers = 1;

DROP TABLE prometheus_empty;
DROP TABLE prometheus;

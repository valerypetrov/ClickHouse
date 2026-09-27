-- Tags: no-fasttest
-- Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.

-- PromQL stddev and stdvar return NaN for a group holding NaN or Inf, even a lone one, like Prometheus.

DROP TABLE IF EXISTS prometheus;

SET session_timezone = 'UTC';
SET allow_experimental_time_series_table = 1;

CREATE TABLE prometheus ENGINE = TimeSeries;

INSERT INTO prometheus (metric_name, tags, samples) VALUES
    ('m', map('grp', 'finite', 'i', '1'), [(toDateTime64(100, 3), 1)]),
    ('m', map('grp', 'finite', 'i', '2'), [(toDateTime64(100, 3), 5)]),
    ('m', map('grp', 'lone_nan'), [(toDateTime64(100, 3), nan)]),
    ('m', map('grp', 'nan_and_finite', 'i', '1'), [(toDateTime64(100, 3), 1)]),
    ('m', map('grp', 'nan_and_finite', 'i', '2'), [(toDateTime64(100, 3), nan)]),
    ('m', map('grp', 'lone_inf'), [(toDateTime64(100, 3), inf)]),
    ('m', map('grp', 'inf_and_finite', 'i', '1'), [(toDateTime64(100, 3), 1)]),
    ('m', map('grp', 'inf_and_finite', 'i', '2'), [(toDateTime64(100, 3), inf)]),
    ('m', map('grp', 'lone_neg_inf'), [(toDateTime64(100, 3), -inf)]),
    ('r', map('i', '1'), [(toDateTime64(100, 3), 1), (toDateTime64(110, 3), nan), (toDateTime64(120, 3), 3)]),
    ('r', map('i', '2'), [(toDateTime64(100, 3), 2), (toDateTime64(110, 3), 2), (toDateTime64(120, 3), 2)]);

SELECT '-- stddev by (grp) (m)';
SELECT * FROM prometheusQuery('prometheus', 'stddev by (grp) (m)', 100) ORDER BY tags;
SELECT '-- stdvar by (grp) (m)';
SELECT * FROM prometheusQuery('prometheus', 'stdvar by (grp) (m)', 100) ORDER BY tags;
SELECT '-- stddev(m)';
SELECT * FROM prometheusQuery('prometheus', 'stddev(m)', 100);
SELECT '-- stddev by (grp) (m) + stdvar by (grp) (m)';
SELECT * FROM prometheusQuery('prometheus', 'stddev by (grp) (m) + stdvar by (grp) (m)', 100) ORDER BY tags;

SELECT '-- stddev(r) and stdvar(r), range: only the step with NaN is NaN';
SELECT * FROM prometheusQueryRange('prometheus', 'stddev(r)', 100, 120, 10);
SELECT * FROM prometheusQueryRange('prometheus', 'stdvar(r)', 100, 120, 10);
SELECT '-- stddev by (i) (r), range: steps without samples stay empty';
SELECT * FROM prometheusQueryRange('prometheus', 'stddev by (i) (r)', 110, 710, 300) ORDER BY tags;

DROP TABLE prometheus;

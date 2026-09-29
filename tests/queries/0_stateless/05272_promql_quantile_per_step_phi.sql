-- Tags: no-fasttest
-- Tag no-fasttest: PromQL needs ANTLR4, which is disabled in the fast-test build.

-- The PromQL `quantile` aggregation with a phi that changes from step to step.

SET session_timezone = 'UTC';
SET allow_experimental_time_series_table = 1;

DROP TABLE IF EXISTS prometheus;
CREATE TABLE prometheus ENGINE = TimeSeries;

INSERT INTO prometheus (metric_name, tags, samples) VALUES
    ('m', map('host', 'h1', 'dc', 'a'), [(toDateTime64(100, 3), 1), (toDateTime64(110, 3), 10), (toDateTime64(120, 3), 4), (toDateTime64(130, 3), 1), (toDateTime64(140, 3), nan), (toDateTime64(150, 3), 5), (toDateTime64(160, 3), -inf), (toDateTime64(170, 3), 2)]),
    ('m', map('host', 'h2', 'dc', 'a'), [(toDateTime64(100, 3), 2), (toDateTime64(110, 3), 20), (toDateTime64(120, 3), 3), (toDateTime64(130, 3), 2), (toDateTime64(140, 3), 7), (toDateTime64(150, 3), inf), (toDateTime64(160, 3), 6), (toDateTime64(170, 3), 2)]),
    ('m', map('host', 'h3', 'dc', 'b'), [(toDateTime64(100, 3), 3), (toDateTime64(110, 3), 5), (toDateTime64(120, 3), 2), (toDateTime64(130, 3), 3), (toDateTime64(140, 3), 8), (toDateTime64(150, 3), 1), (toDateTime64(160, 3), 6), (toDateTime64(170, 3), 9)]),
    ('m', map('host', 'h4', 'dc', 'b'), [(toDateTime64(100, 3), 4), (toDateTime64(110, 3), 0.1), (toDateTime64(120, 3), 0.7), (toDateTime64(130, 3), 4), (toDateTime64(140, 3), 9), (toDateTime64(150, 3), 3), (toDateTime64(160, 3), 3), (toDateTime64(170, 3), 1)]),
    ('m', map('host', 'h5', 'dc', 'c'), [(toDateTime64(150, 3), nan), (toDateTime64(160, 3), 1)]),
    ('phi', map(), [(toDateTime64(100, 3), 0), (toDateTime64(110, 3), 0.25), (toDateTime64(120, 3), 0.5), (toDateTime64(130, 3), 0.3), (toDateTime64(140, 3), 0.9), (toDateTime64(150, 3), 1), (toDateTime64(160, 3), 0.75), (toDateTime64(170, 3), 0.6)]),
    ('phi_edge', map(), [(toDateTime64(100, 3), -0.5), (toDateTime64(110, 3), 1.5), (toDateTime64(120, 3), nan), (toDateTime64(130, 3), 0.5)]),
    ('bar', map('shape', 'circle', 'size', 'l'), [(toDateTime64(110, 3), 10), (toDateTime64(120, 3), 16), (toDateTime64(130, 3), 50), (toDateTime64(150, 3), 1000)]),
    ('bar', map('shape', 'square', 'size', 's'), [(toDateTime64(110, 3), 3), (toDateTime64(120, 3), 40), (toDateTime64(140, 3), 700)]),
    ('bar', map('shape', 'triangle', 'size', 'xl'), [(toDateTime64(110, 3), 8), (toDateTime64(150, 3), 30)]),
    ('bar', map('shape', 'rectangle', 'size', 'l'), [(toDateTime64(110, 3), 9), (toDateTime64(130, 3), 90)]);

SELECT '-- quantile(scalar(phi), m), range';
SELECT * FROM prometheusQueryRange('prometheus', 'quantile(scalar(phi), m)', 100, 170, 10);

SELECT '-- the same with the constant phi of each step';
SELECT timestamp, value FROM
(
    SELECT * FROM prometheusQuery('prometheus', 'quantile(0, m)', 100)
    UNION ALL SELECT * FROM prometheusQuery('prometheus', 'quantile(0.25, m)', 110)
    UNION ALL SELECT * FROM prometheusQuery('prometheus', 'quantile(0.5, m)', 120)
    UNION ALL SELECT * FROM prometheusQuery('prometheus', 'quantile(0.3, m)', 130)
    UNION ALL SELECT * FROM prometheusQuery('prometheus', 'quantile(0.9, m)', 140)
    UNION ALL SELECT * FROM prometheusQuery('prometheus', 'quantile(1, m)', 150)
    UNION ALL SELECT * FROM prometheusQuery('prometheus', 'quantile(0.75, m)', 160)
    UNION ALL SELECT * FROM prometheusQuery('prometheus', 'quantile(0.6, m)', 170)
)
ORDER BY timestamp;

SELECT '-- quantile by (dc) (scalar(phi), m), range';
SELECT * FROM prometheusQueryRange('prometheus', 'quantile by (dc) (scalar(phi), m)', 100, 170, 10) ORDER BY tags;

SELECT '-- quantile without (host) (scalar(phi), m), range';
SELECT * FROM prometheusQueryRange('prometheus', 'quantile without (host) (scalar(phi), m)', 100, 170, 10) ORDER BY tags;

SELECT '-- quantile(scalar(phi_edge), m), range: phi < 0, phi > 1, NaN, 0.5';
SELECT * FROM prometheusQueryRange('prometheus', 'quantile(scalar(phi_edge), m)', 100, 130, 10);

SELECT '-- quantile(time() / 200, m), range';
SELECT * FROM prometheusQueryRange('prometheus', 'quantile(time() / 200, m)', 100, 170, 10);

SELECT '-- quantile(time() / 200, last_over_time(bar[10]))[50:10]';
SELECT * FROM prometheusQuery('prometheus', 'quantile(time() / 200, last_over_time(bar[10]))[50:10]', 150);

SELECT '-- quantile(scalar(phi), nonexistent), range';
SELECT * FROM prometheusQueryRange('prometheus', 'quantile(scalar(phi), nonexistent)', 100, 170, 10);

SELECT '-- the same without short-circuit evaluation';
SET short_circuit_function_evaluation = 'disable';
SELECT * FROM prometheusQueryRange('prometheus', 'quantile(scalar(phi_edge), m)', 100, 130, 10);
SELECT * FROM prometheusQueryRange('prometheus', 'quantile(scalar(phi), nonexistent)', 100, 170, 10);

DROP TABLE prometheus;

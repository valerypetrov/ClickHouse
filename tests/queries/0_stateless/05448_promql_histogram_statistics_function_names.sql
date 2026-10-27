-- Tags: no-fasttest
-- PromQL needs ANTLR4, which is disabled in the fast-test build.

SET enable_time_series_table = 1;
SET enable_time_series_aggregate_functions = 1;
SET session_timezone = 'UTC';

DROP TABLE IF EXISTS ts;
CREATE TABLE ts ENGINE = TimeSeries;

-- These Prometheus functions are parsed, and the conversion reports that they are not implemented.
SELECT * FROM prometheusQuery(ts, 'histogram_avg(up)', 100); -- { serverError NOT_IMPLEMENTED }
SELECT * FROM prometheusQuery(ts, 'histogram_stddev(up)', 100); -- { serverError NOT_IMPLEMENTED }
SELECT * FROM prometheusQuery(ts, 'histogram_stdvar(up)', 100); -- { serverError NOT_IMPLEMENTED }

-- Without '(' after them, they are metric names.
SELECT count() FROM prometheusQuery(ts, 'histogram_avg{job="x"}', 100);
SELECT count() FROM prometheusQuery(ts, 'histogram_stddev + histogram_stdvar', 100);

DROP TABLE ts;

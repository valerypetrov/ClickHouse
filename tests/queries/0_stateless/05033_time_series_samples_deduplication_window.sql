-- The generated MergeTree samples tables keep a deduplication window, so a retried insert of the same data doesn't duplicate samples.

SET allow_experimental_time_series_table = 1;
SET session_timezone = 'UTC';

DROP TABLE IF EXISTS ts_retry;
DROP TABLE IF EXISTS ts_no_window;

-- The TTL is 10 years: the fixed timestamps below must stay inside the TTL window of the recent samples table.
CREATE TABLE ts_retry ENGINE = TimeSeries SETTINGS recent_samples_ttl_seconds = 315360000;

SELECT '-- the samples and recent samples tables get the deduplication window';
SELECT extract(engine_full, 'non_replicated_deduplication_window = \\d+')
FROM system.tables
WHERE database = currentDatabase() AND (name LIKE '.inner\_id.samples.%' OR name LIKE '.inner\_id.recentsamples.%');

SELECT '-- the same data inserted three times is written once';
INSERT INTO ts_retry (metric_name, tags, samples) VALUES ('m', map('env', 'prod'), [(toDateTime64('2026-01-01 00:00:00', 3), 1.), (toDateTime64('2026-01-01 00:00:15', 3), 2.)]);
INSERT INTO ts_retry (metric_name, tags, samples) VALUES ('m', map('env', 'prod'), [(toDateTime64('2026-01-01 00:00:00', 3), 1.), (toDateTime64('2026-01-01 00:00:15', 3), 2.)]);
INSERT INTO ts_retry (metric_name, tags, samples) VALUES ('m', map('env', 'prod'), [(toDateTime64('2026-01-01 00:00:00', 3), 1.), (toDateTime64('2026-01-01 00:00:15', 3), 2.)]);
SELECT
    (SELECT sum(total_rows) FROM system.tables WHERE database = currentDatabase() AND name LIKE '.inner\_id.samples.%'),
    (SELECT sum(total_rows) FROM system.tables WHERE database = currentDatabase() AND name LIKE '.inner\_id.recentsamples.%');

SELECT '-- different data is written';
INSERT INTO ts_retry (metric_name, tags, samples) VALUES ('m', map('env', 'prod'), [(toDateTime64('2026-01-01 00:00:30', 3), 3.)]);
SELECT
    (SELECT sum(total_rows) FROM system.tables WHERE database = currentDatabase() AND name LIKE '.inner\_id.samples.%'),
    (SELECT sum(total_rows) FROM system.tables WHERE database = currentDatabase() AND name LIKE '.inner\_id.recentsamples.%');

SELECT '-- a window specified in the engine declaration is kept';
CREATE TABLE ts_no_window ENGINE = TimeSeries
SETTINGS recent_samples_ttl_seconds = 0
SAMPLES INNER ENGINE = MergeTree SETTINGS non_replicated_deduplication_window = 0;

INSERT INTO ts_no_window (metric_name, tags, samples) VALUES ('m', map('env', 'prod'), [(toDateTime64('2026-01-01 00:00:00', 3), 1.)]);
INSERT INTO ts_no_window (metric_name, tags, samples) VALUES ('m', map('env', 'prod'), [(toDateTime64('2026-01-01 00:00:00', 3), 1.)]);
SELECT count() FROM timeSeriesSamples(ts_no_window);

DROP TABLE ts_retry;
DROP TABLE ts_no_window;

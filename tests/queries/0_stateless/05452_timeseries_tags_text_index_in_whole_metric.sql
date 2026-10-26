-- Tags: no-fasttest
-- PromQL requires ANTLR4, which is disabled in the fast-test build.

-- `m['key'] IN (...)` reads the postings of a `keyValuePairs` text index. `timeSeriesSelector` makes such a condition
-- from a regex of literal alternatives, e.g. `job=~"api-server|api-x"`. When the selector matches the whole metric,
-- the id set of the tags subquery is excluded from index analysis, and that must not exclude the literal set of the
-- matcher in the tags subquery too.

SET allow_experimental_time_series_table = 1;
SET use_skip_indexes = 1;
SET query_plan_direct_read_from_text_index = 1;
-- The assertions below count posting lists read by one query, so keep them independent of what earlier queries have
-- already put into the server-wide postings cache, and of the query condition cache, which can skip granules first.
SET use_text_index_postings_cache = 0;
SET use_query_condition_cache = 0;
SET log_queries = 1;
SET log_profile_events = 1;
-- Direct reads from text indexes require a single replica.
SET max_parallel_replicas = 1;

SELECT 'Map column';
CREATE TABLE tab (id UInt64, m Map(String, String), INDEX idx m TYPE text(tokenizer = 'keyValuePairs')) ENGINE = MergeTree ORDER BY id;
INSERT INTO tab SELECT number, map('job', ['api-server', 'api-x', 'worker'][number % 3 + 1], 'zone', 'west') FROM numbers(30);

SELECT count(), sum(id) FROM tab WHERE m['job'] IN ('api-server', 'api-x') SETTINGS log_comment = 'text_index_in_map';
SELECT count(), sum(id) FROM tab WHERE m['job'] IN ('api-server', 'api-x') SETTINGS use_skip_indexes = 0;

SELECT 'timeSeriesSelector';
CREATE TABLE ts ENGINE = TimeSeries SETTINGS recent_samples_ttl_seconds = 0, tags_index_granularity = 1;

-- Every series of `a_total` has `job` either 'api-server' or 'api-x'.
INSERT INTO ts (metric_name, tags, samples) VALUES
    ('a_total', {'job':'api-server', 'zone':'west'}, [(1000, 1.)]),
    ('a_total', {'job':'api-x', 'zone':'west'}, [(1000, 2.)]),
    ('a_total', {'job':'api-server', 'zone':'east'}, [(1000, 3.)]),
    ('b_total', {'job':'worker', 'zone':'west'}, [(1000, 4.)]);

-- The selector matches the whole metric: the samples table is read with the id range of the metric,
-- and the id set is kept out of the primary-key index analysis.
SELECT
    countIf(explain LIKE '%ffffffff-ffff-ffff-ffff-ffffffffffff%') > 0 AS whole_metric_id_range,
    countIf(explain ILIKE '%Condition:%' AND explain ILIKE '%element set%') = 0 AS id_set_not_in_index_analysis
FROM (EXPLAIN indexes = 1 SELECT sum(value) FROM timeSeriesSelector(ts, 'a_total{job=~"api-server|api-x"}', 0, 2000));

SELECT value FROM timeSeriesSelector(ts, 'a_total{job=~"api-server|api-x"}', 0, 2000) ORDER BY value
SETTINGS log_comment = 'text_index_in_selector_whole_metric';
SELECT value FROM timeSeriesSelector(ts, 'a_total{job=~"api-server|api-x"}', 0, 2000) ORDER BY value
SETTINGS use_skip_indexes = 0;

-- The selector matches only some series of the metric.
SELECT value FROM timeSeriesSelector(ts, 'a_total{job=~"api-x|worker"}', 0, 2000) ORDER BY value
SETTINGS log_comment = 'text_index_in_selector_partial';
SELECT value FROM timeSeriesSelector(ts, 'a_total{job=~"api-x|worker"}', 0, 2000) ORDER BY value
SETTINGS use_skip_indexes = 0;

SELECT 'postings read';
SYSTEM FLUSH LOGS query_log;
SELECT log_comment, ProfileEvents['TextIndexUsedEmbeddedPostings'] + ProfileEvents['TextIndexReadPostings'] > 0
FROM system.query_log
WHERE type = 'QueryFinish' AND current_database = currentDatabase()
    AND log_comment IN ('text_index_in_map', 'text_index_in_selector_whole_metric', 'text_index_in_selector_partial')
ORDER BY log_comment;

DROP TABLE ts;
DROP TABLE tab;

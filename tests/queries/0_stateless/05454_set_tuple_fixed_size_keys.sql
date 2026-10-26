-- The set of `IN` with a single key column of a `Tuple` type keys the elements of the tuple as separate
-- columns of its table when they have fixed-size values without `NULL`, and hashes other tuples as a whole.
-- The results must not depend on that.

SET enable_nullable_tuple_type = 1;

-- `Tuple(UInt64, LowCardinality(UUID))`, the type of the identifiers of the series of a `TimeSeries` table.
WITH rhs AS (SELECT (number * 3, toLowCardinality(reinterpretAsUUID(MD5(toString(number % 7))))) FROM numbers(1000))
SELECT 'UInt64 LowCardinality(UUID)', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (number, toLowCardinality(reinterpretAsUUID(MD5(toString(number % 7))))) AS t FROM numbers(5000));

-- The left side is cast to the type of the set, with and without `LowCardinality`.
WITH rhs AS (SELECT (number * 3, toLowCardinality(reinterpretAsUUID(MD5(toString(number % 7))))) FROM numbers(1000))
SELECT 'UInt64 UUID to LowCardinality', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (number, reinterpretAsUUID(MD5(toString(number % 7)))) AS t FROM numbers(5000));
WITH rhs AS (SELECT (number * 3, reinterpretAsUUID(MD5(toString(number % 7)))) FROM numbers(1000))
SELECT 'LowCardinality to UInt64 UUID', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (number, toLowCardinality(reinterpretAsUUID(MD5(toString(number % 7))))) AS t FROM numbers(5000));

-- `Tuple(UInt32, UInt8)`, also with a left side of other types.
WITH rhs AS (SELECT (toUInt32(number * 3), toUInt8(number % 7)) FROM numbers(1000))
SELECT 'UInt32 UInt8', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (toUInt32(number), toUInt8(number % 7)) AS t FROM numbers(5000));
WITH rhs AS (SELECT (toUInt32(number * 3), toUInt8(number % 7)) FROM numbers(1000))
SELECT 'UInt16 UInt8 to UInt32 UInt8', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (toUInt16(number), toUInt8(number % 7)) AS t FROM numbers(5000));
SELECT 'constant', (3, 1) IN (SELECT (toUInt32(number * 3), toUInt8(number % 7)) FROM numbers(10)),
    (3, 4) IN (SELECT (toUInt32(number * 3), toUInt8(number % 7)) FROM numbers(10)),
    (3, 1) NOT IN (SELECT (toUInt32(number * 3), toUInt8(number % 7)) FROM numbers(10));

-- One element; signed numbers, a date, a decimal and a `FixedString`; 32 bytes.
WITH rhs AS (SELECT tuple(number * 3) FROM numbers(1000))
SELECT 'Tuple(UInt64)', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, tuple(number) AS t FROM numbers(5000));
WITH rhs AS (SELECT (toInt16(number * 3) - 1000, toDate('2026-01-01') + number % 10, toDecimal32(number % 5, 2) - 2, toFixedString(toString(number % 3), 2)) FROM numbers(1000))
SELECT 'Int16 Date Decimal32 FixedString(2)', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (toInt16(number) - 1000, toDate('2026-01-01') + number % 10, toDecimal32(number % 5, 2) - 2, toFixedString(toString(number % 3), 2)) AS t FROM numbers(5000));
WITH rhs AS (SELECT (number * 3, toUInt64(number % 7), reinterpretAsUUID(MD5(toString(number % 5)))) FROM numbers(1000))
SELECT 'UInt64 UInt64 UUID', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (number, toUInt64(number % 7), reinterpretAsUUID(MD5(toString(number % 5)))) AS t FROM numbers(5000));

-- Special floating-point values compare by their binary representation.
SELECT 'floats', groupArray((x, 1) IN (SELECT (arrayJoin([0., nan, inf, 1.5]), 1))), groupArray((x, 1) NOT IN (SELECT (arrayJoin([0., nan, inf, 1.5]), 1)))
FROM (SELECT arrayJoin([0., -0., nan, -nan, inf, -inf, 1.5, 2.5]) AS x);

-- Tuples that are hashed as a whole: more than 32 bytes, a `String` element, a nested tuple.
WITH rhs AS (SELECT (number * 3, reinterpretAsUUID(MD5(toString(number % 7))), toUInt128(number % 5)) FROM numbers(1000))
SELECT 'UInt64 UUID UInt128', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (number, reinterpretAsUUID(MD5(toString(number % 7))), toUInt128(number % 5)) AS t FROM numbers(5000));
WITH rhs AS (SELECT (toString(number * 3), toUInt8(number % 7)) FROM numbers(1000))
SELECT 'String UInt8', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (toString(number), toUInt8(number % 7)) AS t FROM numbers(5000));
WITH rhs AS (SELECT ((toUInt32(number * 3), toUInt8(number % 5)), toUInt8(number % 7)) FROM numbers(1000))
SELECT 'nested tuple', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, ((toUInt32(number), toUInt8(number % 5)), toUInt8(number % 7)) AS t FROM numbers(5000));

-- A `Nullable` element: the tuple is hashed as a whole.
WITH rhs AS (SELECT (if(number % 5 = 0, NULL, toUInt32(number * 3)), toUInt8(number % 3)) FROM numbers(1000))
SELECT 'Nullable element', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (if(number % 7 = 0, NULL, toUInt32(number)), toUInt8(number % 3)) AS t FROM numbers(5000));
WITH rhs AS (SELECT (if(number % 5 = 0, NULL, toUInt32(number * 3)), toUInt8(number % 3)) FROM numbers(1000))
SELECT 'Nullable element transform_null_in', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (if(number % 7 = 0, NULL, toUInt32(number)), toUInt8(number % 3)) AS t FROM numbers(5000))
SETTINGS transform_null_in = 1;

-- A `Nullable` tuple: without `transform_null_in`, the set skips `NULL` and keys the elements of the other
-- tuples; with it, `NULL` is a key, and the tuple is hashed as a whole.
WITH rhs AS (SELECT if(number % 5 = 0, NULL, (toUInt32(number * 3), toUInt8(number % 3)))::Nullable(Tuple(UInt32, UInt8)) FROM numbers(1000))
SELECT 'Nullable tuple', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, if(number % 7 = 0, NULL, (toUInt32(number), toUInt8(number % 3)))::Nullable(Tuple(UInt32, UInt8)) AS t FROM numbers(5000));
WITH rhs AS (SELECT if(number % 5 = 0, NULL, (toUInt32(number * 3), toUInt8(number % 3)))::Nullable(Tuple(UInt32, UInt8)) FROM numbers(1000))
SELECT 'Nullable tuple transform_null_in', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, if(number % 7 = 0, NULL, (toUInt32(number), toUInt8(number % 3)))::Nullable(Tuple(UInt32, UInt8)) AS t FROM numbers(5000))
SETTINGS transform_null_in = 1;
WITH rhs AS (SELECT (toUInt32(number * 3), toUInt8(number % 3)) FROM numbers(1000))
SELECT 'Nullable left side transform_null_in', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, if(number % 7 = 0, NULL, (toUInt32(number), toUInt8(number % 3)))::Nullable(Tuple(UInt32, UInt8)) AS t FROM numbers(5000))
SETTINGS transform_null_in = 1;

-- An empty set.
SELECT 'empty', countIf(t IN (SELECT (number, toUInt8(1)) FROM numbers(0))), countIf(t NOT IN (SELECT (number, toUInt8(1)) FROM numbers(0)))
FROM (SELECT (number, toUInt8(number % 2)) AS t FROM numbers(10));

-- The set spills to disk, or stays in memory.
WITH rhs AS (SELECT (number * 3, toLowCardinality(reinterpretAsUUID(MD5(toString(number % 7))))) FROM numbers(3000))
SELECT 'spilled', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (number, toLowCardinality(reinterpretAsUUID(MD5(toString(number % 7))))) AS t FROM numbers(10000))
SETTINGS max_bytes_before_external_set = 1, max_block_size = 1000;
WITH rhs AS (SELECT (number * 3, toLowCardinality(reinterpretAsUUID(MD5(toString(number % 7))))) FROM numbers(3000))
SELECT 'in memory', countIf(t IN rhs), countIf(t NOT IN rhs), sum(cityHash64(number) * (t IN rhs))
FROM (SELECT number, (number, toLowCardinality(reinterpretAsUUID(MD5(toString(number % 7))))) AS t FROM numbers(10000))
SETTINGS max_bytes_before_external_set = 0, max_bytes_ratio_before_external_set = 0, max_block_size = 1000;

-- Tables: `GLOBAL IN` sends the keys of the set to the shards, and a `Set` table keeps them.
DROP TABLE IF EXISTS tuple_lhs;
DROP TABLE IF EXISTS tuple_rhs;
DROP TABLE IF EXISTS tuple_set;
CREATE TABLE tuple_lhs (number UInt64, t Tuple(UInt64, LowCardinality(UUID))) ENGINE = MergeTree ORDER BY number;
INSERT INTO tuple_lhs SELECT number, (number, reinterpretAsUUID(MD5(toString(number % 7)))) FROM numbers(5000);
CREATE TABLE tuple_rhs (t Tuple(UInt64, LowCardinality(UUID))) ENGINE = Memory;
INSERT INTO tuple_rhs SELECT (number * 3, reinterpretAsUUID(MD5(toString(number % 7)))) FROM numbers(1000);
CREATE TABLE tuple_set (t Tuple(UInt64, LowCardinality(UUID))) ENGINE = Set;
INSERT INTO tuple_set SELECT t FROM tuple_rhs;

SELECT 'IN', countIf(t IN (SELECT t FROM tuple_rhs)), countIf(t NOT IN (SELECT t FROM tuple_rhs)) FROM tuple_lhs;
SELECT 'GLOBAL IN', countIf(t GLOBAL IN (SELECT t FROM tuple_rhs)), countIf(t GLOBAL NOT IN (SELECT t FROM tuple_rhs))
FROM remote('127.0.0.{1,2}', currentDatabase(), tuple_lhs);
SELECT 'GLOBAL IN WHERE', count(), sum(number) FROM remote('127.0.0.{1,2}', currentDatabase(), tuple_lhs) WHERE t GLOBAL IN (SELECT t FROM tuple_rhs);
SELECT 'Set table', countIf(t IN tuple_set), countIf(t NOT IN tuple_set) FROM tuple_lhs;

-- The primary key on a tuple column uses the explicit elements of the set, which a set written to disk while
-- it is built does not keep.
DROP TABLE IF EXISTS tuple_key;
CREATE TABLE tuple_key (t Tuple(UInt64, LowCardinality(UUID)), v UInt64) ENGINE = MergeTree ORDER BY t SETTINGS index_granularity = 64;
INSERT INTO tuple_key SELECT (number, reinterpretAsUUID(MD5(toString(number % 13)))), number FROM numbers(10000);

SELECT 'primary key', count(), sum(v) FROM tuple_key WHERE t IN (SELECT t FROM tuple_rhs)
SETTINGS use_index_for_in_with_subqueries = 1, force_primary_key = 1,
    max_bytes_before_external_set = 0, max_bytes_ratio_before_external_set = 0;
SELECT 'primary key, other type', count(), sum(v) FROM tuple_key WHERE t IN (SELECT (number * 7, reinterpretAsUUID(MD5(toString(number * 7 % 13)))) FROM numbers(300))
SETTINGS use_index_for_in_with_subqueries = 1, force_primary_key = 1,
    max_bytes_before_external_set = 0, max_bytes_ratio_before_external_set = 0;
SELECT 'primary key, NOT IN', count(), sum(v) FROM tuple_key WHERE t NOT IN (SELECT t FROM tuple_rhs)
SETTINGS use_index_for_in_with_subqueries = 1;
SELECT 'without index', count(), sum(v) FROM tuple_key WHERE t IN (SELECT t FROM tuple_rhs)
SETTINGS use_index_for_in_with_subqueries = 0;
SELECT 'without index, NOT IN', count(), sum(v) FROM tuple_key WHERE t NOT IN (SELECT t FROM tuple_rhs)
SETTINGS use_index_for_in_with_subqueries = 0;

DROP TABLE tuple_key;
DROP TABLE tuple_set;
DROP TABLE tuple_rhs;
DROP TABLE tuple_lhs;

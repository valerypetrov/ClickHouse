import pytest

from helpers.cluster import ClickHouseCluster
from .prometheus_test_utils import (
    convert_metrics_metadata_to_protobuf,
    convert_time_series_to_protobuf,
    send_protobuf_to_remote_write,
)


cluster = ClickHouseCluster(__file__)

node = cluster.add_instance(
    "node",
    main_configs=["configs/prometheus.xml"],
    user_configs=["configs/allow_experimental_time_series_table.xml"],
)


@pytest.fixture(scope="module", autouse=True)
def start_cluster():
    try:
        cluster.start()
        yield cluster
    finally:
        cluster.shutdown()


@pytest.fixture(autouse=True)
def cleanup_after_test():
    try:
        yield
    finally:
        node.query("DROP TABLE IF EXISTS prometheus SYNC")


def get_skipped_series():
    return int(node.query("SELECT sum(value) FROM system.events WHERE event = 'PrometheusRemoteWriteSeriesSkippedByLabelLimits'"))


# Sends the time series and the metrics metadata in one request, returns the number of skipped series.
def remote_write(time_series, metrics_metadata=()):
    write_request = convert_time_series_to_protobuf(time_series)
    write_request.metadata.extend(convert_metrics_metadata_to_protobuf(metrics_metadata).metadata)
    skipped_before = get_skipped_series()
    send_protobuf_to_remote_write(node.ip_address, 9093, "/write", write_request)
    return get_skipped_series() - skipped_before


def get_stored_samples():
    return node.query("SELECT tags.metric_name, data.value FROM timeSeriesData(prometheus) AS data JOIN timeSeriesTags(prometheus) AS tags ON data.id = tags.id ORDER BY tags.metric_name")


def test_series_exceeding_label_limits_are_skipped():
    node.query("CREATE TABLE prometheus ENGINE=TimeSeries SETTINGS max_labels_per_series = 3, max_label_name_length = 10, max_label_value_length = 10")

    timestamp = 1724112000
    time_series = [
        ({"__name__": "ok", "job": "a"}, {timestamp: 1}),
        # Exactly at every limit.
        ({"__name__": "edge", "abcdefghij": "0123456789", "b": "x"}, {timestamp: 2}),
        ({"__name__": "many", "a": "1", "b": "2", "c": "3"}, {timestamp: 3}),
        ({"__name__": "longname", "abcdefghijk": "1"}, {timestamp: 4}),
        ({"__name__": "longvalue", "job": "0123456789a"}, {timestamp: 5}),
        ({"__name__": "metric_name"}, {timestamp: 6}),
    ]
    metrics_metadata = [
        ("ok", "GAUGE", "Stored metric", ""),
        ("many", "GAUGE", "Skipped metric", ""),
    ]

    assert remote_write(time_series, metrics_metadata) == 4
    assert get_stored_samples() == "edge\t2\nok\t1\n"
    assert node.query("SELECT count() FROM timeSeriesTags(prometheus)") == "2\n"
    # The metadata is not limited, and its rows stay aligned with the skipped series.
    assert node.query("SELECT metric_family, help FROM timeSeriesMetricFamilies(prometheus) ORDER BY metric_family") == "many\tSkipped metric\nok\tStored metric\n"


def test_label_limits_can_be_altered():
    node.query("CREATE TABLE prometheus ENGINE=TimeSeries SETTINGS max_labels_per_series = 1")

    time_series = [({"__name__": "altered", "job": "a"}, {1724112000: 1})]
    assert remote_write(time_series) == 1
    assert get_stored_samples() == ""

    node.query("ALTER TABLE prometheus MODIFY SETTING max_labels_per_series = 0")
    assert remote_write(time_series) == 0
    assert get_stored_samples() == "altered\t1\n"

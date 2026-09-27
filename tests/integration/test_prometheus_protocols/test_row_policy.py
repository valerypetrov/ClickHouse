"""A row policy on a TimeSeries table filters the time series returned by the Prometheus protocols."""

import pytest
import requests

from helpers.cluster import ClickHouseCluster
from .prometheus_test_utils import (
    convert_read_request_to_protobuf,
    receive_protobuf_from_remote_read,
)

cluster = ClickHouseCluster(__file__)

node = cluster.add_instance(
    "node",
    main_configs=["configs/prometheus.xml"],
    user_configs=["configs/allow_experimental_time_series_table.xml"],
)

USER = "restricted"


@pytest.fixture(scope="module", autouse=True)
def setup():
    try:
        cluster.start()
        node.query("CREATE TABLE prometheus ENGINE=TimeSeries")
        node.query(
            "INSERT INTO prometheus (metric_name, tags, samples) VALUES"
            " ('up', {'job': 'api'}, [(toDateTime64(1000, 3), 1)]),"
            " ('up', {'job': 'db', 'secret': 'x'}, [(toDateTime64(1000, 3), 2)])"
        )
        node.query(f"CREATE USER {USER}")
        node.query(f"GRANT SELECT ON default.* TO {USER}")
        node.query(f"GRANT CREATE TEMPORARY TABLE ON *.* TO {USER}")
        node.query(
            f"CREATE ROW POLICY api_only ON prometheus FOR SELECT USING tags['job'] = 'api' TO {USER}"
        )
        yield cluster
    finally:
        cluster.shutdown()


def get(path, user, **params):
    return requests.get(
        f"http://{node.ip_address}:9093{path}", params={"user": user, **params}
    )


def get_data(path, user, **params):
    response = get(path, user, **params)
    assert response.status_code == 200, response.text
    return response.json()["data"]


def test_query():
    for user, jobs in [("default", ["api", "db"]), (USER, ["api"])]:
        result = get_data("/api/v1/query", user, query="up", time="1000")["result"]
        assert sorted(series["metric"]["job"] for series in result) == jobs


def test_series():
    for user, jobs in [("default", ["api", "db"]), (USER, ["api"])]:
        data = get_data("/api/v1/series", user, **{"match[]": "up"})
        assert sorted(labels["job"] for labels in data) == jobs


def test_labels():
    assert get_data("/api/v1/labels", "default") == ["__name__", "job", "secret"]
    assert get_data("/api/v1/labels", USER) == ["__name__", "job"]
    assert get_data("/api/v1/label/job/values", "default") == ["api", "db"]
    assert get_data("/api/v1/label/job/values", USER) == ["api"]


def test_remote_read():
    read_request = convert_read_request_to_protobuf("up", 0, 2000)
    for user, count in [("default", 2), (USER, 1)]:
        response = receive_protobuf_from_remote_read(
            node.ip_address, 9093, f"read?user={user}", read_request
        )
        assert len(response.results[0].timeseries) == count


def test_metadata_is_refused():
    assert get("/api/v1/metadata", "default").status_code == 200
    response = get("/api/v1/metadata", USER)
    assert response.status_code == 400
    assert "Cannot read the metrics metadata" in response.json()["error"]


def test_policy_on_another_column_is_refused():
    node.query("ALTER ROW POLICY api_only ON prometheus USING type = 'gauge'")
    try:
        response = get("/api/v1/query", USER, query="up", time="1000")
        assert response.status_code == 400
        assert "Cannot read time series" in response.json()["error"]
    finally:
        node.query("ALTER ROW POLICY api_only ON prometheus USING tags['job'] = 'api'")

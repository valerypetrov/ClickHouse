"""Tests for the `extra_label` and `extra_filters` parameters of the Prometheus HTTP API."""

import pytest
import requests

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
    handle_prometheus_remote_write=(9093, "/write"),
)

SERIES_A_API = {"__name__": "requests", "tenant": "a", "job": "api"}
SERIES_B_API = {"__name__": "requests", "tenant": "b", "job": "api"}
SERIES_B_DB = {"__name__": "requests", "tenant": "b", "job": "db"}
SERIES_B_SECRET = {"__name__": "secret", "tenant": "b", "secret_label": "x"}

TENANT_A_FORMS = {
    "extra_label": [("extra_label", "tenant=a")],
    "extra_filters": [("extra_filters[]", '{tenant="a"}')],
    # Several filters are checked on the tags of each series instead of being added to the selectors.
    "several_extra_filters": [
        ("extra_label", "tenant=a"),
        ("extra_filters", '{job="api"}'),
        ("extra_filters[]", '{job=~"d.*"}'),
    ],
}


@pytest.fixture(scope="module", autouse=True)
def start_cluster():
    try:
        cluster.start()
        node.query("CREATE TABLE prometheus ENGINE=TimeSeries")
        time_series = [
            (SERIES_A_API, {100: 1, 110: 2}),
            (SERIES_B_API, {100: 10, 110: 20}),
            (SERIES_B_DB, {100: 100, 110: 200}),
            (SERIES_B_SECRET, {100: 7}),
        ]
        send_protobuf_to_remote_write(node.ip_address, 9093, "/write", convert_time_series_to_protobuf(time_series))
        metadata = convert_metrics_metadata_to_protobuf([("secret", "GAUGE", "Secret metric", "")])
        send_protobuf_to_remote_write(node.ip_address, 9093, "/write", metadata)
        yield cluster
    finally:
        cluster.shutdown()


def get_response(path, params):
    return requests.get(f"http://{node.ip_address}:9093{path}", params=params)


def get_data(path, params):
    response = get_response(path, params)
    assert response.status_code == 200, response.text
    return response.json()["data"]


def query(promql, params):
    return get_data("/api/v1/query", [("query", promql), ("time", "110")] + params)


def result_labels(data):
    return sorted(sorted(item["metric"].items()) for item in data["result"])


def labels_of(*series):
    return sorted(sorted(s.items()) for s in series)


@pytest.mark.parametrize("form", TENANT_A_FORMS)
def test_query_endpoints(form):
    params = TENANT_A_FORMS[form]
    assert result_labels(query("requests", [])) == labels_of(SERIES_A_API, SERIES_B_API, SERIES_B_DB)
    assert result_labels(query("requests", params)) == labels_of(SERIES_A_API)

    range_params = [("query", "requests"), ("start", "100"), ("end", "110"), ("step", "10")] + params
    data = get_data("/api/v1/query_range", range_params)
    assert result_labels(data) == labels_of(SERIES_A_API)
    assert data["result"][0]["values"] == [[100, "1"], [110, "2"]]


# Every selector of the query is filtered, whatever the query does with its labels.
@pytest.mark.parametrize("form", TENANT_A_FORMS)
def test_query_cannot_escape(form):
    params = TENANT_A_FORMS[form]
    for promql in [
        'requests{tenant="b"}',
        'requests{tenant!="a"}',
        'label_replace(requests{tenant="b"}, "tenant", "a", "", "")',
        "secret",
        "max_over_time(secret[1m:10s])",
        "sum(count_over_time(secret[1m]))",
        'secret or requests{job="db"} or requests{job="api"} offset 5s',
    ]:
        data = query(promql, params)
        assert all(item["metric"].get("tenant") in [None, "a"] for item in data["result"]), promql
        assert "secret" not in str(data), promql

    assert result_labels(query('requests{tenant=~".*"}', params)) == labels_of(SERIES_A_API)
    assert query("count(requests)", params)["result"][0]["value"][1] == "1"
    assert query("absent(secret)", params)["result"][0]["value"][1] == "1"


def test_several_extra_filters():
    params = [("extra_filters[]", '{tenant="a"}'), ("extra_filters[]", '{job="api"}')]
    assert result_labels(query("requests", params)) == labels_of(SERIES_A_API, SERIES_B_API)

    # A series matching both filters is read once.
    data = query("count_over_time(requests[1m])", params)
    assert [item["value"][1] for item in data["result"]] == ["2", "2"]

    # Regular expressions match whole values.
    params = [("extra_filters[]", '{job=~"ap"}'), ("extra_filters[]", '{job=~"d.|x"}')]
    assert result_labels(query("requests", params)) == labels_of(SERIES_B_DB)
    params = [("extra_filters[]", '{tenant="a"}'), ("extra_filters[]", '{job!~"a.*",__name__="requests"}')]
    assert result_labels(query("requests", params)) == labels_of(SERIES_A_API, SERIES_B_DB)


@pytest.mark.parametrize("form", TENANT_A_FORMS)
def test_metadata_endpoints(form):
    params = TENANT_A_FORMS[form]
    series = get_data("/api/v1/series", [("match[]", '{__name__=~".+"}')] + params)
    assert series == [SERIES_A_API]
    assert get_data("/api/v1/series", [("match[]", "secret")] + params) == []
    assert get_data("/api/v1/labels", params) == ["__name__", "job", "tenant"]
    assert get_data("/api/v1/labels", [("match[]", "secret")] + params) == []
    assert get_data("/api/v1/label/__name__/values", params) == ["requests"]
    assert get_data("/api/v1/label/tenant/values", params) == ["a"]

    assert "secret" in get_data("/api/v1/metadata", [])
    assert get_data("/api/v1/metadata", params) == {}


def test_metadata_endpoints_several_extra_filters():
    params = [("extra_filters[]", '{tenant="a"}'), ("extra_filters[]", '{job="db"}')]
    series = get_data("/api/v1/series", [("match[]", "requests"), ("match[]", '{job=~".+"}')] + params)
    assert sorted(sorted(s.items()) for s in series) == labels_of(SERIES_A_API, SERIES_B_DB)
    assert get_data("/api/v1/label/job/values", params) == ["api", "db"]
    assert get_data("/api/v1/label/__name__/values", params) == ["requests"]


# A proxy puts the filters into the URL, so the ones in the request body are ignored then.
def test_body_cannot_widen_url_filters():
    url = f"http://{node.ip_address}:9093/api/v1/query"
    body = {"query": "requests", "time": "110", "extra_filters[]": '{tenant="b"}'}
    response = requests.post(url + "?extra_label=tenant%3Da", data=body)
    assert result_labels(response.json()["data"]) == labels_of(SERIES_A_API)

    response = requests.post(url, data=body)
    assert result_labels(response.json()["data"]) == labels_of(SERIES_B_API, SERIES_B_DB)


def test_invalid_filters():
    for params, error in [
        ([("extra_label", "tenant")], "must have the format 'name=value'"),
        ([("extra_filters[]", "requests[5m]")], "is not an instant selector"),
        ([("extra_filters", "{")], "Cannot parse the value"),
    ]:
        response = get_response("/api/v1/query", [("query", "requests"), ("time", "110")] + params)
        assert response.status_code == 400, response.text
        assert response.json()["errorType"] == "bad_data"
        assert error in response.json()["error"]

    # A value is never parsed as a part of the query.
    params = [("extra_label", 'tenant=a"} or secret{tenant="b')]
    assert query("requests or secret", params)["result"] == []


def test_format_query_ignores_filters():
    assert get_data("/api/v1/format_query", [("query", "requests"), ("extra_label", "tenant=a")]) == "requests"

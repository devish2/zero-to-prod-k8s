import pytest
from main import app as flask_app


@pytest.fixture()
def client():
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as c:
        yield c


def test_health_status_code(client):
    r = client.get("/health")
    assert r.status_code == 200


def test_health_returns_ok(client):
    r = client.get("/health")
    assert r.get_json()["status"] == "ok"


def test_echo_mirrors_payload(client):
    payload = {"ping": "pong", "num": 42}
    r = client.post("/echo", json=payload)
    assert r.status_code == 200
    assert r.get_json()["body"] == payload


def test_echo_empty_body(client):
    r = client.post("/echo", json={})
    assert r.status_code == 200


def test_index(client):
    r = client.get("/")
    assert r.status_code == 200
    assert "service" in r.get_json()

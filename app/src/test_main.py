import pytest
from main import app as flask_app
@pytest.fixture()
def client():
flask_app.config['TESTING'] = True
with flask_app.test_client() as c:
yield c
def test_health_status_code(client):
    assert client.get('/health').status_code == 200
def test_health_returns_ok(client):
assert client.get('/health').get_json()['status'] == 'ok'
def test_echo_mirrors_payload(client):
r = client.post('/echo', json={'ping': 'pong'})
assert r.status_code == 200
assert r.get_json()['body'] == {'ping': 'pong'}
def test_index(client):
assert client.get('/').status_code == 200

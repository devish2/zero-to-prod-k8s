import os, datetime, urllib.request, psycopg2
DATABASE_URL = os.environ['DATABASE_URL']
APP_HEALTH_URL = os.getenv('APP_HEALTH_URL', 'http://app:5000/health')
def check_app() -> str:
    try:
with urllib.request.urlopen(APP_HEALTH_URL, timeout=5) as r:
return 'ok' if r.status == 200 else 'degraded'
except Exception as e:
print(f'Health check failed: {e}')
return 'down'
def write_result(status: str) -> None:
conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()
cur.execute('''CREATE TABLE IF NOT EXISTS checks (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
status TEXT NOT NULL, endpoint TEXT NOT NULL)''')
cur.execute('INSERT INTO checks (ts,status,endpoint) VALUES (%s,%s,%s)',
(datetime.datetime.utcnow(), status, APP_HEALTH_URL))
conn.commit(); cur.close(); conn.close()
if __name__ == '__main__':
s = check_app()
write_result(s)
print(f'[{datetime.datetime.utcnow().isoformat()}] status={s}')

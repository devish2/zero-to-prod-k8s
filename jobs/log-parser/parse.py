import csv, datetime, os, re
LOG_PATH = os.getenv('LOG_PATH', '/logs/access.log')
OUT_DIR = os.getenv('OUT_DIR', '/output')
PATTERN = re.compile(
r'(?P<ip>\S+) \[(?P<time>[^\]]+)\] '
r'"(?P<method>\S+) (?P<path>\S+) \S+" '
r'(?P<status>\d+) (?P<bytes>\d+) '
r'rt=(?P<rt>[\d.]+)'
)
def parse_log(path):
rows = []
try:
with open(path) as f:
for line in f:
m = PATTERN.search(line)
if m: rows.append(m.groupdict())
except FileNotFoundError:
print(f'Log not found: {path}')
return rows
if __name__ == '__main__':
rows = parse_log(LOG_PATH)
os.makedirs(OUT_DIR, exist_ok=True)
out = f'{OUT_DIR}/access_{datetime.date.today().isoformat()}.csv'
with open(out, 'w', newline='') as f:
w = csv.DictWriter(f,
fieldnames=['ip','time','method','path','status','bytes','rt'])
w.writeheader(); w.writerows(rows)
print(f'Parsed {len(rows)} lines → {out}')
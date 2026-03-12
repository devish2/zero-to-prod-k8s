import os, signal, sys, logging
from flask import Flask, jsonify, request
logging.basicConfig(level=logging.INFO,
format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger(__name__)
app = Flask(__name__)
@app.route('/health')
def health():
return jsonify(status='ok', version=os.getenv('APP_VERSION', 'dev')), 200
@app.route('/echo', methods=['POST'])
def echo():
payload = request.get_json(silent=True) or {}
return jsonify(body=payload), 200
@app.route('/')
def index():
return jsonify(service='uptime-app', docs='/health'), 200
def _handle_sigterm(signum, frame):
log.info('SIGTERM received — shutting down gracefully')
sys.exit(0)
signal.signal(signal.SIGTERM, _handle_sigterm)
if __name__ == '__main__':
app.run(host='0.0.0.0', port=int(os.getenv('APP_PORT', 5000)))
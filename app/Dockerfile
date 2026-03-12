# ╔══════════════════════════════════════════════════╗
# ║ Stage 1 — builder + test runner ║
# ╚══════════════════════════════════════════════════╝
FROM python:3.12-slim AS builder
WORKDIR /app
COPY src/requirements.txt src/requirements-dev.txt ./
RUN pip install --no-cache-dir -r requirements.txt -r requirements-dev.txt
COPY src/ .
# Build FAILS here if any test fails
RUN python -m pytest test_main.py -v --tb=short
# ╔══════════════════════════════════════════════════╗
# ║ Stage 2 — slim runtime (non-root, no dev deps) ║
# ╚══════════════════════════════════════════════════╝
FROM python:3.12-slim AS runtime
RUN adduser --disabled-password --uid 10001 --gecos "" appuser
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages \
/usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin/gunicorn /usr/local/bin/gunicorn
COPY --from=builder /app/main.py .
USER 10001
EXPOSE 5000
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
CMD python -c "import urllib.request;urllib.request.urlopen('http://localhost:5000/health')"
CMD ["gunicorn","--workers","2","--bind","0.0.0.0:5000","--timeout","10","--preload","main:app"]

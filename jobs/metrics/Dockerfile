FROM python:3.12-alpine
RUN adduser -D -u 10001 jobuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY healthcheck.py .
USER 10001
CMD ["python", "healthcheck.py"]
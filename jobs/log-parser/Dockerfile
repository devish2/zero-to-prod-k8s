FROM python:3.12-alpine
RUN adduser -D -u 10001 jobuser
WORKDIR /app
COPY parse.py .
USER 10001
CMD ["python", "parse.py"]
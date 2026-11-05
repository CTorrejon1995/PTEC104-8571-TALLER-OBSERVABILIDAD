FROM python:3.12.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY receiver.py validate_grafana.py ./
RUN mkdir -p /data && chown -R 10001:10001 /data /app
USER 10001:10001
EXPOSE 8080
CMD ["python", "/app/receiver.py", "--database", "/data/events.sqlite3"]

FROM python:3.12.12-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app
COPY generate_logs.py /app/generate_logs.py
RUN python -m py_compile /app/generate_logs.py \
    && mkdir -p /var/log/cloud \
    && chown 10001:10001 /var/log/cloud

USER 10001:10001
ENTRYPOINT ["python", "/app/generate_logs.py"]

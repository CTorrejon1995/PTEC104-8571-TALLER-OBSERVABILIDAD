FROM python:3.12.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/app
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir --disable-pip-version-check -r requirements.txt
COPY shared ./shared
COPY service-a ./service-a
COPY service-b ./service-b
USER 10001:10001
EXPOSE 8080
CMD ["python", "/app/service-a/main.py"]

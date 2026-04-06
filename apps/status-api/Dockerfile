FROM python:3.15-rc-alpine3.22

WORKDIR /app

# hadolint ignore=DL3018
RUN apk add --no-cache docker-cli

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

RUN adduser -D -u 1000 appuser && chown -R 1000:1000 /app
USER 1000

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "server:app"]

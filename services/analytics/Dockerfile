FROM python:3.15-rc-alpine3.22

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY tracker.py .

RUN adduser -D -u 1000 appuser && chown -R 1000:1000 /app
USER 1000

CMD ["python", "-u", "tracker.py"]

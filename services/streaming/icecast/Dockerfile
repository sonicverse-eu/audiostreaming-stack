FROM debian:13.4-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        icecast2 \
        gettext-base \
        curl && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/log/icecast2 && \
    chown -R icecast2:icecast /var/log/icecast2

COPY icecast.xml /etc/icecast2/icecast.xml.template

EXPOSE 8000

RUN useradd -U -u 1000 appuser && chown -R 1000:1000 /etc/icecast2 /var/log/icecast2
USER 1000

ENTRYPOINT ["sh", "-c", "envsubst < /etc/icecast2/icecast.xml.template > /etc/icecast2/icecast.xml && exec icecast2 -c /etc/icecast2/icecast.xml"]

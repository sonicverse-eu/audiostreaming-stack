FROM savonet/liquidsoap:v2.4.x-latest AS base

ARG DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3002
USER root

# Pull in patched Debian package metadata so the image does not inherit a
# vulnerable dpkg build from the upstream Liquidsoap base layer.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --only-upgrade -y --no-install-recommends dpkg \
    && rm -rf /var/lib/apt/lists/*

FROM base AS python-deps

ARG DEBIAN_FRONTEND=noninteractive

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY apps/status-api/requirements.txt /tmp/status-api-requirements.txt
COPY services/analytics/requirements.txt /tmp/analytics-requirements.txt

RUN python3 -m venv "$VIRTUAL_ENV" \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir \
        -r /tmp/status-api-requirements.txt \
        -r /tmp/analytics-requirements.txt

FROM base AS runtime

ARG DEBIAN_FRONTEND=noninteractive

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
ENV ICECAST_URL=http://127.0.0.1:8000
ENV ICECAST_INTERNAL_HOST=127.0.0.1
ENV ANALYTICS_ALERT_URL=http://127.0.0.1:8888
ENV STATUS_PANEL_HOST=127.0.0.1

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        gettext-base \
        icecast2 \
        nginx \
        python3 \
        python3-venv \
        tini \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p \
        /etc/nginx/rendered \
        /emergency-audio \
        /hls \
        /opt/sonicverse/analytics \
        /opt/sonicverse/status-api \
        /run/nginx \
        /usr/share/nginx/html \
        /var/cache/nginx/client_temp \
        /var/cache/nginx/proxy_temp \
        /var/cache/nginx/fastcgi_temp \
        /var/cache/nginx/uwsgi_temp \
        /var/cache/nginx/scgi_temp \
        /var/log/icecast2 \
    && chown -R icecast2:icecast /var/log/icecast2 \
    && chmod 0777 /hls

COPY --from=python-deps /opt/venv /opt/venv
COPY apps/status-api/server.py /opt/sonicverse/status-api/server.py
COPY services/analytics/tracker.py /opt/sonicverse/analytics/tracker.py
COPY services/streaming/icecast/icecast.xml /etc/icecast2/icecast.xml.template
COPY services/streaming/liquidsoap/radio.liq /etc/liquidsoap/radio.liq
COPY infrastructure/nginx/nginx.conf /etc/nginx/nginx.conf.template
COPY infrastructure/nginx/index.html.template /etc/nginx/index.html.template
COPY scripts/unified-entrypoint.sh /usr/local/bin/sonicverse-entrypoint

RUN chmod 0755 /usr/local/bin/sonicverse-entrypoint

EXPOSE 80 443 8000 8010 8011 8080 8888

ENTRYPOINT ["tini", "--", "/usr/local/bin/sonicverse-entrypoint"]

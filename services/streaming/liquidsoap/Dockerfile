FROM savonet/liquidsoap:v2.4.2

# hadolint ignore=DL3002
USER root

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends --only-upgrade libfreetype6 \
    && rm -rf /var/lib/apt/lists/*

COPY radio.liq /etc/liquidsoap/radio.liq

# Ensure HLS output directory is writable
RUN mkdir -p /hls && chmod 777 /hls

USER liquidsoap

EXPOSE 8010 8011

CMD ["liquidsoap", "/etc/liquidsoap/radio.liq"]

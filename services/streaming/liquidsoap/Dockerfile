FROM savonet/liquidsoap:v2.4.x-latest

ARG OPENSSL_PROVIDER_LEGACY_VERSION=3.5.4-1~deb13u2

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        "openssl-provider-legacy=${OPENSSL_PROVIDER_LEGACY_VERSION}" && \
    rm -rf /var/lib/apt/lists/*

COPY radio.liq /etc/liquidsoap/radio.liq

# Ensure HLS output directory is writable
RUN mkdir -p /hls && chmod 777 /hls

USER liquidsoap

EXPOSE 8010 8011

CMD ["liquidsoap", "/etc/liquidsoap/radio.liq"]

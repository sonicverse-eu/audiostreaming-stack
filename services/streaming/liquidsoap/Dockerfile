FROM savonet/liquidsoap:v2.4.2

# hadolint ignore=DL3002
USER root

# Pull the patched Debian libpng build called out by the vulnerability report.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends libpng16-16=1.6.48-1+deb13u4 \
    && rm -rf /var/lib/apt/lists/*

COPY radio.liq /etc/liquidsoap/radio.liq

# Ensure HLS output directory is writable
RUN mkdir -p /hls && chmod 777 /hls

EXPOSE 8010 8011

CMD ["liquidsoap", "/etc/liquidsoap/radio.liq"]

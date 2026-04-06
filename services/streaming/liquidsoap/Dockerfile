FROM savonet/liquidsoap:v2.4.2

# hadolint ignore=DL3002
USER root

# Pull in the latest patched Debian package metadata so the image does not
# inherit a vulnerable dpkg build from the upstream base layer.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --only-upgrade -y --no-install-recommends dpkg \
    && rm -rf /var/lib/apt/lists/*

COPY radio.liq /etc/liquidsoap/radio.liq

# Ensure HLS output directory is writable
RUN mkdir -p /hls && chmod 777 /hls

EXPOSE 8010 8011

CMD ["liquidsoap", "/etc/liquidsoap/radio.liq"]

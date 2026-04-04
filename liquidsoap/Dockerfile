FROM savonet/liquidsoap:v2.4.2

USER root

COPY radio.liq /etc/liquidsoap/radio.liq

# Ensure HLS output directory is writable
RUN mkdir -p /hls && chmod 777 /hls

EXPOSE 8010 8011

CMD ["liquidsoap", "/etc/liquidsoap/radio.liq"]

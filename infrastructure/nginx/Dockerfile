FROM nginx:1.29.7-alpine3.23-slim
RUN apk add --no-cache gettext=0.24.1-r1

COPY nginx.conf /etc/nginx/nginx.conf.template
COPY index.html.template /etc/nginx/index.html.template
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN adduser -D -u 1000 appuser && chown -R 1000:1000 /etc/nginx/nginx.conf.template /etc/nginx/index.html.template /docker-entrypoint.sh
USER 1000

ENTRYPOINT ["/docker-entrypoint.sh"]

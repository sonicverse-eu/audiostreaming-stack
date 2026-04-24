FROM nginx:1.28.3-alpine-slim

RUN apk add --no-cache gettext=0.24.1-r1

COPY nginx.conf /etc/nginx/nginx.conf.template
COPY index.html.template /etc/nginx/index.html.template
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN adduser -D -u 1000 appuser \
    && mkdir -p \
        /usr/share/nginx/html \
        /var/cache/nginx/client_temp \
        /var/cache/nginx/proxy_temp \
        /var/cache/nginx/fastcgi_temp \
        /var/cache/nginx/uwsgi_temp \
        /var/cache/nginx/scgi_temp \
        /var/run/nginx \
        /etc/nginx/rendered \
    && chown -R 1000:1000 \
        /etc/nginx \
        /usr/share/nginx/html \
        /var/cache/nginx \
        /var/run/nginx \
        /docker-entrypoint.sh
USER 1000

ENTRYPOINT ["/docker-entrypoint.sh"]

FROM lightpanda/browser:latest

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default

RUN cat > /etc/nginx/conf.d/lightpanda.conf <<'NGINX_EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

client_header_buffer_size 16k;
large_client_header_buffers 4 64k;

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 200m;
    proxy_connect_timeout 60s;

    location / {
        if ($request_method = OPTIONS) {
            add_header 'Access-Control-Allow-Origin'  '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD' always;
            add_header 'Access-Control-Allow-Headers' '*' always;
            add_header 'Access-Control-Expose-Headers' '*' always;
            add_header 'Access-Control-Max-Age'       86400 always;
            add_header 'Content-Type' 'text/plain; charset=utf-8' always;
            add_header 'Content-Length' 0;
            return 204;
        }

        proxy_pass         http://127.0.0.1:9222;
        proxy_http_version 1.1;

        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;

        proxy_buffering         off;
        proxy_request_buffering off;
        proxy_cache             off;
        proxy_read_timeout      86400s;
        proxy_send_timeout      86400s;

        add_header 'Access-Control-Allow-Origin'  '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD' always;
        add_header 'Access-Control-Allow-Headers' '*' always;
        add_header 'Access-Control-Expose-Headers' '*' always;
        add_header 'Access-Control-Max-Age'       86400 always;
    }
}
NGINX_EOF

RUN cat > /entrypoint.sh <<'ENTRY_EOF'
#!/bin/bash
set -e

LP_HOST="127.0.0.1"
LP_PORT="9222"
LP_BIN="/bin/lightpanda"

"${LP_BIN}" serve --host "${LP_HOST}" --port "${LP_PORT}" &
LP_PID=$!

for i in $(seq 1 120); do
    if curl -sf "http://127.0.0.1:${LP_PORT}/json/version" >/dev/null 2>&1 \
       || curl -sf "http://127.0.0.1:${LP_PORT}/" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "${LP_PID}" 2>/dev/null; then
        exit 1
    fi
    sleep 0.5
done

exec nginx -g 'daemon off;'
ENTRY_EOF

RUN chmod +x /entrypoint.sh

RUN ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]

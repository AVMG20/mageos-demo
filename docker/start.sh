#!/bin/bash
# Runs php-fpm and nginx side by side; the container stops when either one exits.
set -e
cd /var/www/html
mkdir -p /data/media var/log
if [ -f /data/etc/env.php ]; then
  cp /data/etc/env.php app/etc/env.php
  # Reindex in the background once the web server is up; this also refills OpenSearch,
  # which keeps no data across its own restarts.
  ( sleep 15; bin/magento indexer:reindex > /proc/1/fd/1 2>&1 || true ) &
fi

php-fpm -F &
FPM_PID=$!
nginx -e stderr -g 'daemon off;' &
NGINX_PID=$!

trap 'kill -TERM "$FPM_PID" "$NGINX_PID" 2>/dev/null' TERM INT
set +e
wait -n "$FPM_PID" "$NGINX_PID"
STATUS=$?
kill -TERM "$FPM_PID" "$NGINX_PID" 2>/dev/null
wait "$FPM_PID" "$NGINX_PID" 2>/dev/null
exit "$STATUS"

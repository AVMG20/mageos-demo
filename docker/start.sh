#!/bin/sh
set -e
cd /var/www/html
mkdir -p /data/media var/log
if [ -f /data/etc/env.php ]; then
  cp /data/etc/env.php app/etc/env.php
  # Reindex in the background once Apache is up; this also refills OpenSearch,
  # which keeps no data across its own restarts.
  ( sleep 15; bin/magento indexer:reindex > /proc/1/fd/1 2>&1 || true ) &
fi
exec apache2-foreground

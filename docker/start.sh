#!/bin/sh
set -e
cd /var/www/html
mkdir -p /data/media var/log
if [ -f /data/etc/env.php ]; then
  cp /data/etc/env.php app/etc/env.php
fi
exec apache2-foreground

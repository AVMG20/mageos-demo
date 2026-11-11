#!/bin/sh
# Runs as bitploy's before_deploy_command: installs Mage-OS on first deploy,
# runs setup:upgrade on later ones. env.php is kept in /data/etc.
set -eu
cd /var/www/html

OS_URL="http://${OPENSEARCH_HOST:-opensearch}:${OPENSEARCH_PORT:-9200}/"
echo "Waiting for OpenSearch at $OS_URL"
n=0
until php -r 'exit(@file_get_contents($argv[1]) === false ? 1 : 0);' "$OS_URL"; do
  n=$((n + 1))
  [ $n -lt 36 ] || { echo "OpenSearch did not answer within 3 minutes"; exit 1; }
  sleep 5
done

mkdir -p /data/etc /data/media
# Copy media shipped in the image (base files, sample-data images) without overwriting uploads.
cp -a -n .media-skel/. /data/media/

if [ -f /data/etc/env.php ]; then
  echo "Mage-OS already installed: running setup:upgrade"
  cp /data/etc/env.php app/etc/env.php
  bin/magento setup:upgrade --keep-generated --no-interaction
else
  echo "Installing Mage-OS"
  bin/magento setup:install --no-interaction \
    --base-url="${MAGENTO_BASE_URL}" \
    --base-url-secure="${MAGENTO_BASE_URL}" \
    --use-secure=1 --use-secure-admin=1 --use-rewrites=1 \
    --db-host="${MYSQL_HOST}:${MYSQL_PORT}" \
    --db-name="${MYSQL_DATABASE}" \
    --db-user="${MYSQL_USER}" \
    --db-password="${MYSQL_PASSWORD}" \
    --backend-frontname="${MAGENTO_ADMIN_PATH:-admin}" \
    --admin-firstname=Admin --admin-lastname=User \
    --admin-email="${MAGENTO_ADMIN_EMAIL:-admin@example.com}" \
    --admin-user="${MAGENTO_ADMIN_USER:-admin}" \
    --admin-password="${MAGENTO_ADMIN_PASSWORD}" \
    --language="${MAGENTO_LOCALE:-en_US}" \
    --currency="${MAGENTO_CURRENCY:-EUR}" \
    --timezone="${MAGENTO_TIMEZONE:-Europe/Amsterdam}" \
    --search-engine=opensearch \
    --opensearch-host="${OPENSEARCH_HOST:-opensearch}" \
    --opensearch-port="${OPENSEARCH_PORT:-9200}" \
    --opensearch-index-prefix=mageos \
    --session-save=db
fi

# Valkey (Redis protocol) for cache, full page cache and sessions, when the service is connected.
if [ -n "${REDIS_HOST:-}" ]; then
  echo "Configuring Valkey at ${REDIS_HOST}:${REDIS_PORT:-6379}"
  bin/magento setup:config:set --no-interaction \
    --cache-backend=redis \
    --cache-backend-redis-server="$REDIS_HOST" --cache-backend-redis-port="${REDIS_PORT:-6379}" \
    --cache-backend-redis-password="${REDIS_PASSWORD:-}" --cache-backend-redis-db=0 \
    --page-cache=redis \
    --page-cache-redis-server="$REDIS_HOST" --page-cache-redis-port="${REDIS_PORT:-6379}" \
    --page-cache-redis-password="${REDIS_PASSWORD:-}" --page-cache-redis-db=1 \
    --session-save=redis \
    --session-save-redis-host="$REDIS_HOST" --session-save-redis-port="${REDIS_PORT:-6379}" \
    --session-save-redis-password="${REDIS_PASSWORD:-}" --session-save-redis-db=2
fi

# Hyvä as the storefront theme (default, website and store scope).
THEME_ID="$(php -r '
  $e = include "app/etc/env.php";
  $c = $e["db"]["connection"]["default"];
  $hp = explode(":", $c["host"]);
  $pdo = new PDO("mysql:host={$hp[0]};port=" . ($hp[1] ?? 3306) . ";dbname={$c["dbname"]}", $c["username"], $c["password"]);
  $t = ($e["db"]["table_prefix"] ?? "") . "theme";
  echo $pdo->query("SELECT theme_id FROM $t WHERE area = \"frontend\" AND theme_path = \"Hyva/default\"")->fetchColumn();
')"
if [ -n "$THEME_ID" ]; then
  echo "Activating Hyvä (theme_id $THEME_ID)"
  bin/magento config:set design/theme/theme_id "$THEME_ID"
  bin/magento config:set --scope=websites --scope-code=base design/theme/theme_id "$THEME_ID"
  bin/magento config:set --scope=stores --scope-code=default design/theme/theme_id "$THEME_ID"
  # Luma sample data ships a Luma stylesheet in media that breaks Hyvä layouts.
  rm -f /data/media/styles.css
fi

cp app/etc/env.php /data/etc/env.php
# The full reindex runs in the background when the container starts (docker/start.sh):
# with sample data it does not fit in bitploy's 10-minute before-deploy limit.
bin/magento cache:flush
echo "Mage-OS ready"

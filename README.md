# Mage-OS demo on bitploy

Clean Mage-OS with Luma sample data and the Hyvä theme, running at https://mageos.bitploy.nl.

Every push to `main` builds the root `Dockerfile` and deploys the `mageos` app.

## Layout

- `Dockerfile`: nginx + PHP 8.4-FPM on port 8080, both running as `www-data`. Runs
  `composer create-project` for Mage-OS, adds the sample data and Hyvä (from
  `https://mageos.bougierepo.com/`, limited to `hyva-themes/*`), and turns off admin 2FA.
- `docker/nginx.conf`: the server block. It includes Magento's own `nginx.conf.sample` and passes PHP to
  FPM on `127.0.0.1:9000` (pool settings in `docker/php-fpm.conf`).
- `docker/install.sh`: bitploy's `before_deploy_command`. It runs `setup:install` on the first deploy
  and `setup:upgrade` on every later one, then configures Valkey and activates Hyvä.
- `docker/start.sh`: copies `app/etc/env.php` from `/data`, reindexes in the background and runs
  php-fpm and nginx. The container stops when either one exits.
- `scripts/warm-cache.py`: run locally to warm the full page cache. It crawls the storefront from the
  homepage and requests every cacheable page once (`python3 scripts/warm-cache.py --help`). It needs
  only the Python standard library.
- `opensearch/`: the private OpenSearch worker (`mageos-opensearch` app). It is deployed separately
  with file uploads, not from this repo.

## bitploy project "Mage-OS"

| App | What |
| --- | --- |
| `mageos` | the shop, `/data` holds `etc/env.php` and `media/` |
| `mageos-opensearch` (alias `opensearch`) | OpenSearch 2.19, no volume (rebuilt by reindex) |
| `db` | MariaDB 11.8 |
| `valkey` | cache, full page cache and sessions |

Admin: https://mageos.bitploy.nl/admin. The user is `admin`, and the password is the hidden
`MAGENTO_ADMIN_PASSWORD` variable on the `mageos` app.

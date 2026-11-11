# Clean Mage-OS (Magento Open Source distribution) on nginx + PHP 8.4-FPM.
# The database install runs as bitploy's before_deploy_command (docker/install.sh);
# app/etc/env.php and pub/media live in /data so they survive redeploys.
FROM php:8.4-fpm-bookworm

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN install-php-extensions bcmath gd intl pdo_mysql soap sockets xsl zip opcache ftp \
 && apt-get update && apt-get install -y --no-install-recommends nginx \
 && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY docker/php.ini /usr/local/etc/php/conf.d/zz-magento.ini

# nginx and php-fpm both run unprivileged as www-data (nginx temp files live in /var/lib/nginx)
RUN rm -rf /var/www/html/* \
 && mkdir /data && chown www-data:www-data /data /var/www/html \
 && chown -R www-data:www-data /var/lib/nginx /var/log/nginx

USER www-data
WORKDIR /var/www/html
ENV COMPOSER_HOME=/tmp/composer COMPOSER_MEMORY_LIMIT=-1

RUN composer create-project --no-interaction --no-progress \
      --repository-url=https://repo.mage-os.org/ mage-os/project-community-edition . \
 && rm -rf /tmp/composer

# Luma sample data (products, categories, CMS pages); installed into the database by setup:upgrade.
RUN bin/magento sampledata:deploy --no-interaction && rm -rf /tmp/composer

# Hyvä theme (open source) from the Mage-OS Hyvä mirror; only hyva-themes/* is taken from it.
RUN composer config repositories.hyva '{"type": "composer", "url": "https://mageos.bougierepo.com/", "only": ["hyva-themes/*"]}' \
 && composer require --no-interaction --no-progress hyva-themes/magento2-default-theme hyva-themes/magento2-luma-checkout \
 && rm -rf /tmp/composer

# Module list baked into the image (2FA off so the admin works without an authenticator app),
# accept any MariaDB 10.x/11.x version, and move pub/media to the volume.
COPY --chmod=0755 docker/disable-2fa.sh /usr/local/bin/magento-disable-2fa
RUN bin/magento module:enable --all \
 && /usr/local/bin/magento-disable-2fa \
 && sed -i 's#<argument name="supportedVersionPatterns" xsi:type="array">#&\n                <item name="MariaDB-any" xsi:type="string">^1[0-9]\\.</item>#' app/etc/di.xml \
 && grep -q 'MariaDB-any' app/etc/di.xml \
 && cp -a pub/media .media-skel && rm -rf pub/media && ln -s /data/media pub/media \
 && echo ok > pub/bitploy-health.txt

COPY docker/zz-logging.ini /usr/local/etc/php/conf.d/zz-logging.ini
COPY docker/php-fpm.conf /usr/local/etc/php-fpm.d/zz-magento.conf
COPY docker/nginx.conf /etc/nginx/nginx.conf
RUN nginx -t -e stderr && php-fpm -t
COPY --chmod=0755 docker/install.sh /usr/local/bin/magento-install
COPY --chmod=0755 docker/start.sh /usr/local/bin/magento-start

EXPOSE 8080
CMD ["magento-start"]

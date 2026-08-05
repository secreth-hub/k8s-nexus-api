# Multi-stage build: install PHP deps in a composer-only stage, then copy
# just the result into a slim runtime image — keeps composer/git/unzip etc.
# out of the final image.
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --ignore-platform-reqs

FROM php:8.4-cli
RUN apt-get update && apt-get install -y --no-install-recommends libzip-dev unzip git \
    && docker-php-ext-install pdo_mysql zip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /var/www/html
COPY --from=vendor /usr/bin/composer /usr/bin/composer
COPY --from=vendor /app/vendor ./vendor
COPY . .
RUN composer dump-autoload --optimize --no-dev --classmap-authoritative

# .dockerignore excludes storage/framework/{cache,sessions,views} and
# storage/logs (they only ever held local dev artifacts we don't want baked
# into the image) — but Laravel's file cache/session drivers need these
# DIRECTORIES to exist at runtime, so recreate them explicitly here.
RUN mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Deliberately NOT running `php artisan migrate` here — that's exclusively
# the Helm chart's migration Job's job (see nexus-helm), so multiple
# replicas never race each other running migrations simultaneously.
# LOG_CHANNEL=stderr means `kubectl logs` shows app logs directly, no log
# volume needed. CACHE_STORE=file/QUEUE_CONNECTION=sync avoid needing a
# separate cache/queue backend for this scope.
ENV LOG_CHANNEL=stderr \
    CACHE_STORE=file \
    QUEUE_CONNECTION=sync \
    APP_ENV=production \
    APP_DEBUG=false

EXPOSE 8000
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000"]

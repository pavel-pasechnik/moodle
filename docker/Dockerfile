FROM php:8.3-apache

LABEL maintainer="Pavel Pasechnik <Pavel.Pasechnik@gmail.com>" \
      org.opencontainers.image.source="https://github.com/pavel-pasechnik/moodle-docker" \
      org.opencontainers.image.description="Moodle 4.5.x on PHP 8.3 + Apache with PostgreSQL client, Redis, SOAP, and build-time plugin bootstrap"

ARG MOODLE_VERSION=MOODLE_405_STABLE
ARG GIT_BRANCH=main
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=${TZ:-Europe/Kiev}

# --- System deps & PHP extensions ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip libpng-dev libjpeg-dev libpq-dev libxml2-dev libzip-dev \
    zlib1g-dev libicu-dev g++ cron vim postgresql-client libssl-dev openssh-client tzdata patch ca-certificates \
 && docker-php-ext-configure gd --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" gd intl zip opcache pgsql pdo_pgsql soap \
 && pecl install redis \
 && docker-php-ext-enable redis \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /patches /backups /config

# --- PHP tuning (Moodle requirement) ---
RUN echo "max_input_vars = 5000" > /usr/local/etc/php/conf.d/99-max-input-vars.ini

# --- Git identity for non-interactive clones ---
RUN git config --global user.name "Moodle Docker" \
 && git config --global user.email "docker@moodle.local"

# --- Apache config ---
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf \
 && a2enmod rewrite

# --- Clone Moodle core ---
RUN git clone -b "${MOODLE_VERSION}" https://github.com/moodle/moodle.git /var/www/html

# --- Apply local Moodle patches (optional) ---
# --- Copy optional backup and patch directories ---
COPY ./patches /patches
COPY ./backups /backups
RUN if [ -d "/patches" ]; then \
      patch_count=$(find /patches -type f -name '*.patch' -size +0c | wc -l); \
      echo "Found $patch_count patch(es) to apply."; \
      for patch in /patches/*.patch; do \
        if [ -f "$patch" ] && [ -s "$patch" ]; then \
          echo "Applying $patch"; \
          patch -p1 < "$patch"; \
        fi; \
      done; \
    fi

# --- Copy environment files ---
COPY ./.env /config/.env
COPY ./.env.example /config/.env.example

# --- Permissions & working dir ---
RUN chown -R www-data:www-data /var/www/html
WORKDIR /var/www/html

# --- Runtime entrypoint script ---
COPY ./scripts/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

# --- Optional PHP config inside image (can be overridden by volume) ---
COPY ./config/php.ini /usr/local/etc/php/conf.d/php.ini

EXPOSE 80
RUN php -v && apache2ctl -v
CMD ["apache2-foreground"]
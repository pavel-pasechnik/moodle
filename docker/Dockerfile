FROM php:8.3-fpm

LABEL maintainer="Pavel Pasechnik <Pavel.Pasechnik@gmail.com>" \
      org.opencontainers.image.source="https://github.com/pavel-pasechnik/moodle-docker" \
      org.opencontainers.image.description="Moodle 4.5.x on PHP 8.3 FPM with PostgreSQL client, Redis, SOAP, and build-time plugin bootstrap"

ARG GIT_BRANCH=main
ARG TZ=Europe/Kyiv
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=${TZ}

# --- System deps & PHP extensions ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip libpng-dev libjpeg-dev libpq-dev libxml2-dev libzip-dev \
    zlib1g-dev libicu-dev g++ cron vim postgresql-client libssl-dev openssh-client tzdata patch ca-certificates \
    aspell graphviz ghostscript poppler-utils \
 && docker-php-ext-configure gd --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" gd intl zip opcache pgsql pdo_pgsql soap \
 && docker-php-ext-install exif \
 && pecl install redis \
 && docker-php-ext-enable redis \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /patches /backups /config

# --- PHP tuning (Moodle requirement) ---
RUN echo "max_input_vars = 5000" > /usr/local/etc/php/conf.d/99-max-input-vars.ini

# --- Git identity for non-interactive clones ---
RUN git config --global user.name "Moodle Docker" \
 && git config --global user.email "docker@moodle.local"

# --- Copy environment defaults (example only) ---
COPY ./.env.example /config/.env.example

# --- Permissions & working dir ---
RUN mkdir -p /var/www/html /var/moodledata \
 && chown -R www-data:www-data /var/www/html /var/moodledata
VOLUME ["/var/moodledata"]

WORKDIR /var/www/html

# --- Copy all runtime scripts ---
COPY ./scripts /scripts
RUN chmod +x /scripts/*.sh && ln -sf /scripts/setup.sh /usr/local/bin/setup.sh

# --- Optional PHP config inside image (can be overridden by volume) ---
COPY ./config/php/php.ini /usr/local/etc/php/conf.d/php.ini

EXPOSE 9000
RUN php -v
CMD ["/usr/local/bin/setup.sh"]

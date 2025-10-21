FROM php:8.3-apache
ARG MOODLE_VERSION=MOODLE_405_STABLE

# Installing dependencies
RUN apt-get update && apt-get install -y \
    git unzip libpng-dev libjpeg-dev libpq-dev libxml2-dev libzip-dev \
    zlib1g-dev libicu-dev g++ cron vim \
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install gd intl zip opcache pgsql pdo_pgsql

RUN apt-get install -y libssl-dev libonig-dev && docker-php-ext-install soap

# Installing the Redis PHP module
RUN pecl install redis && docker-php-ext-enable redis

# Cloning Moodle
RUN git clone -b ${MOODLE_VERSION} https://github.com/moodle/moodle.git /var/www/html

# Apache configuration
RUN a2enmod rewrite
RUN chown -R www-data:www-data /var/www/html

COPY ../scripts/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

# PHP configuration
COPY ./config/php.ini /usr/local/etc/php/php.ini

WORKDIR /var/www/html
EXPOSE 80
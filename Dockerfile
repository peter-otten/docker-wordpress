FROM php:7.2-fpm-alpine

### next is based on: https://github.com/docker-library/wordpress/blob/master/php7.2/fpm-alpine/Dockerfile
# docker-entrypoint.sh dependencies
RUN apk add --no-cache \
# in theory, docker-entrypoint.sh is POSIX-compliant, but priority is a working, consistent image
		bash \
# BusyBox sed is not sufficient for some of our sed expressions
		sed
### end

### own code
# Use the default production configuration
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN apk --update add git \
  build-base \
  libmemcached-dev \
  libmcrypt-dev \
  libxml2-dev \
  zlib-dev \
  autoconf \
  cyrus-sasl-dev \
  libgsasl-dev

RUN docker-php-ext-install mysqli mbstring pdo pdo_mysql tokenizer xml opcache zip

RUN pecl channel-update pecl.php.net
RUN pecl install mcrypt-1.0.1 && docker-php-ext-enable mcrypt

## install xdebug, make sure the ini is set
RUN yes | pecl install xdebug \
    && echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" > /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.remote_enable=on" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.remote_autostart=off" >> /usr/local/etc/php/conf.d/xdebug.ini
### end own code

### next is based on: https://github.com/docker-library/wordpress/blob/master/php7.2/fpm-alpine/Dockerfile
# install the PHP extensions we need for WP
RUN set -ex; \
	\
	apk add --no-cache --virtual .build-deps \
		libjpeg-turbo-dev \
		libpng-dev \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-install gd; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --virtual .wordpress-phpexts-rundeps $runDeps; \
	apk del .build-deps

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

VOLUME /var/www/html

ENV WORDPRESS_VERSION 5.0.1
ENV WORDPRESS_SHA1 298bd17feb7b4948e7eb8fa0cde17438a67db19a

RUN set -ex; \
	curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
	echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
	tar -xzf wordpress.tar.gz -C /usr/src/; \
	rm wordpress.tar.gz; \
	chown -R www-data:www-data /usr/src/wordpress

ENV PATH "$PATH:/usr/local/bin/"
COPY docker-entrypoint.sh /usr/local/bin/

# Install composer
ENV COMPOSER_ALLOW_SUPERUSER 1
RUN curl --silent --show-error https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]

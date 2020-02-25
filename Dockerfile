FROM php:7.3-fpm-stretch

RUN apt-get update && apt-get install -y mysql-client --no-install-recommends \
 && docker-php-ext-install pdo_mysql

RUN apt-get install -y software-properties-common
RUN apt-get update -q -y

RUN apt-get install -y libzip-dev

RUN set -xe \
    && buildDeps=" \
        $PHP_EXTRA_BUILD_DEPS \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libxpm-dev \
        libpng-dev \
        libicu-dev \
        libxslt1-dev \
        libmemcached-dev \
        libxml2-dev \
    " \
	&& apt-get update -q -y && apt-get install -q -y --no-install-recommends $buildDeps && rm -rf /var/lib/apt/lists/* \

# Extract php source and install missing extensions
    && docker-php-source extract \
    && docker-php-ext-configure mysqli --with-mysqli=mysqlnd \
    && docker-php-ext-configure pdo_mysql --with-pdo-mysql=mysqlnd \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ --with-png-dir=/usr/include/ --with-xpm-dir=/usr/include/ --enable-gd-jis-conv \
    && docker-php-ext-install exif gd mbstring intl xsl zip mysqli pdo_mysql soap \
    && docker-php-ext-enable opcache \
    && cp /usr/src/php/php.ini-production ${PHP_INI_DIR}/php.ini \
    \
# Install blackfire: https://blackfire.io/docs/integrations/docker
    && version=$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;") \
    && curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/linux/amd64/$version \
    && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp \
    && mv /tmp/blackfire-*.so $(php -r "echo ini_get('extension_dir');")/blackfire.so \
    && rm -f /tmp/blackfire-probe.tar.gz \
    \
# Install igbinary (for more efficient serialization in redis/memcached)
    && for i in $(seq 1 3); do pecl install -o igbinary && s=0 && break || s=$? && sleep 1; done; (exit $s) \
    && docker-php-ext-enable igbinary \
    \
# Install redis (manualy build in order to be able to enable igbinary)
    && for i in $(seq 1 3); do pecl install -o --nobuild redis && s=0 && break || s=$? && sleep 1; done; (exit $s) \
    && cd "$(pecl config-get temp_dir)/redis" \
    && phpize \
    && ./configure --enable-redis-igbinary \
    && make \
    && make install \
    && docker-php-ext-enable redis \
    && cd - \
    \
# Install memcached (manualy build in order to be able to enable igbinary)
    && for i in $(seq 1 3); do echo no | pecl install -o --nobuild memcached && s=0 && break || s=$? && sleep 1; done; (exit $s) \
    && cd "$(pecl config-get temp_dir)/memcached" \
    && phpize \
    && ./configure --enable-memcached-igbinary \
    && make \
    && make install \
    && docker-php-ext-enable memcached \
    && cd - \
    \
# Delete source & builds deps so it does not hang around in layers taking up space
    && pecl clear-cache \
    && rm -Rf "$(pecl config-get temp_dir)/*" \
    && docker-php-source delete \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $buildDeps


RUN apt-get update && apt-get install -yq \
    ca-certificates \
    curl \
    acl \
    sudo \
    wget \
   # Needed for the php extensions we enable below
    libfreetype6 \
    libjpeg62-turbo \
    libxpm4 \
    libpng16-16 \
    libicu57 \
    libxslt1.1 \
    libmemcachedutil2 \
    imagemagick \
    unzip \
    # ======= git =====
    git \
    nano \
    graphicsmagick \
    imagemagick \
    ghostscript \
    mysql-client \
    iputils-ping \
    apt-utils \
    locales \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install bcmath

## HHVM

RUN apt-get update && apt-get install -y gnupg2
RUN apt-get install -y apt-transport-https software-properties-common
RUN apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xB4112585D386EB94

RUN add-apt-repository https://dl.hhvm.com/debian
RUN apt-get update
RUN apt-get install -yq hhvm


# ======= composer =======
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

#envoy 

RUN composer global require laravel/envoy

# ======= nodejs =======
RUN curl -sL https://deb.nodesource.com/setup_6.x | bash - && apt-get install -y nodejs


WORKDIR /var/www/html

RUN composer global require "laravel/installer"

RUN echo "export PATH=/root/.composer/vendor/bin/:$PATH" >> ~/.bashrc
#RUN source ~/.bashrc

RUN npm install --global cross-env


#SUPERVISORD

RUN apt-get update && apt-get install -y --no-install-recommends --no-install-suggests supervisor

COPY supervisor/supervisor.conf /etc/supervisord.conf

COPY script.sh /var/www/script.sh

RUN chmod 744 /var/www/script.sh

CMD ["/var/www/script.sh"]

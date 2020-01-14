FROM php:7.0-fpm
MAINTAINER SWIM <kwebmaster@swimdhbw.de>

RUN mkdir ~/.gnupg
RUN echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf

# Change UID and GID of www-data user to match host privileges
RUN usermod -u 999 www-data && \
    groupmod -g 999 www-data

# Utilities
RUN apt-get update && \
    apt-get -y install apt-transport-https ca-certificates git curl --no-install-recommends && \
    rm -r /var/lib/apt/lists/*

# MySQL PHP extension
RUN docker-php-ext-install mysqli

# Pear mail
RUN curl -s -o /tmp/go-pear.phar http://pear.php.net/go-pear.phar && \
    echo '/usr/bin/php /tmp/go-pear.phar "$@"' > /usr/bin/pear && \
    chmod +x /usr/bin/pear && \
    pear install mail Net_SMTP

# Imagick with PHP extension
RUN apt-get update && apt-get install -y imagemagick libmagickwand-6.q16-dev --no-install-recommends && \
    ln -s /usr/lib/x86_64-linux-gnu/ImageMagick-6.8.9/bin-Q16/MagickWand-config /usr/bin/ && \
    pecl install imagick-3.4.0RC6 && \
    echo "extension=imagick.so" > /usr/local/etc/php/conf.d/ext-imagick.ini && \
    rm -rf /var/lib/apt/lists/*

# Intl PHP extension
RUN apt-get update && apt-get install -y libicu-dev g++ --no-install-recommends && \
    docker-php-ext-install intl && \
    apt-get install -y --auto-remove libicu57 g++ && \
    rm -rf /var/lib/apt/lists/*

# Zip PHP extension
RUN docker-php-ext-install zip

# APC PHP extension
RUN pecl install apcu && \
    pecl install apcu_bc-1.0.3 && \
    docker-php-ext-enable apcu --ini-name 10-docker-php-ext-apcu.ini && \
    docker-php-ext-enable apc --ini-name 20-docker-php-ext-apc.ini

# Nginx
RUN apt-get update && \
    apt-get -y install nginx && \
    rm -r /var/lib/apt/lists/*
COPY config/nginx/* /etc/nginx/

# PHP-FPM
COPY config/php-fpm/php-fpm.conf /usr/local/etc/
COPY config/php-fpm/php.ini /usr/local/etc/php/
RUN mkdir -p /var/run/php7-fpm/ && \
    chown www-data:www-data /var/run/php7-fpm/

# Supervisor
RUN apt-get update && \
    apt-get install -y supervisor --no-install-recommends && \
    rm -r /var/lib/apt/lists/*
COPY config/supervisor/supervisord.conf /etc/supervisor/conf.d/
COPY config/supervisor/kill_supervisor.py /usr/bin/

# NodeJS
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash - && \
    apt-get install -y nodejs --no-install-recommends

# Parsoid
RUN useradd parsoid --no-create-home --home-dir /usr/lib/parsoid --shell /usr/sbin/nologin
RUN apt-key advanced --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys AF380A3036A03444 && \
    echo "deb https://releases.wikimedia.org/debian jessie-mediawiki main" > /etc/apt/sources.list.d/parsoid.list && \
    apt-get update && \
    apt-get -y install parsoid --no-install-recommends --allow-unauthenticated && \
    apt-get -y install mysql-client
COPY config/parsoid/config.yaml /usr/lib/parsoid/src/config.yaml
ENV NODE_PATH /usr/lib/parsoid/node_modules:/usr/lib/parsoid/src

# Composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
    composer global require hirak/prestissimo

# MediaWiki
ARG MEDIAWIKI_VERSION_MAJOR=1
ARG MEDIAWIKI_VERSION_MINOR=32
ARG MEDIAWIKI_VERSION_BUGFIX=0

RUN curl -s -o /tmp/keys.txt https://www.mediawiki.org/keys/keys.txt && \
    curl -s -o /tmp/mediawiki.tar.gz https://releases.wikimedia.org/mediawiki/$MEDIAWIKI_VERSION_MAJOR.$MEDIAWIKI_VERSION_MINOR/mediawiki-$MEDIAWIKI_VERSION_MAJOR.$MEDIAWIKI_VERSION_MINOR.$MEDIAWIKI_VERSION_BUGFIX.tar.gz && \
    curl -s -o /tmp/mediawiki.tar.gz.sig https://releases.wikimedia.org/mediawiki/$MEDIAWIKI_VERSION_MAJOR.$MEDIAWIKI_VERSION_MINOR/mediawiki-$MEDIAWIKI_VERSION_MAJOR.$MEDIAWIKI_VERSION_MINOR.$MEDIAWIKI_VERSION_BUGFIX.tar.gz.sig && \
    gpg --import /tmp/keys.txt && \
    gpg --list-keys --fingerprint --with-colons | sed -E -n -e 's/^fpr:::::::::([0-9A-F]+):$/\1:6:/p' | gpg --import-ownertrust && \
    gpg --verify /tmp/mediawiki.tar.gz.sig /tmp/mediawiki.tar.gz && \
    mkdir -p /var/www/mediawiki /data /images && \
    tar -xzf /tmp/mediawiki.tar.gz -C /tmp && \
    mv /tmp/mediawiki-$MEDIAWIKI_VERSION_MAJOR.$MEDIAWIKI_VERSION_MINOR.$MEDIAWIKI_VERSION_BUGFIX/* /var/www/mediawiki && \
    rm -rf /tmp/mediawiki.tar.gz /tmp/mediawiki-$MEDIAWIKI_VERSION_MAJOR.$MEDIAWIKI_VERSION_MINOR.$MEDIAWIKI_VERSION_BUGFIX/ /tmp/keys.txt && \
    rm -rf /var/www/mediawiki/images && \
    ln -s /images /var/www/mediawiki/images && \
    chown -R www-data:www-data /data /images /var/www/mediawiki/images
COPY config/mediawiki/* /var/www/mediawiki/

# VisualEditor extension
RUN curl -s -o /tmp/extension-visualeditor.tar.gz https://extdist.wmflabs.org/dist/extensions/VisualEditor-REL${MEDIAWIKI_VERSION_MAJOR}_${MEDIAWIKI_VERSION_MINOR}-`curl -s https://extdist.wmflabs.org/dist/extensions/ | grep -o -P "(?<=VisualEditor-REL${MEDIAWIKI_VERSION_MAJOR}_${MEDIAWIKI_VERSION_MINOR}-)[0-9a-z]{7}(?=.tar.gz)" | head -1`.tar.gz && \
    tar -xzf /tmp/extension-visualeditor.tar.gz -C /var/www/mediawiki/extensions && \
    rm /tmp/extension-visualeditor.tar.gz

# User merge and delete extension
RUN curl -s -o /tmp/extension-usermerge.tar.gz https://extdist.wmflabs.org/dist/extensions/UserMerge-REL${MEDIAWIKI_VERSION_MAJOR}_${MEDIAWIKI_VERSION_MINOR}-`curl -s https://extdist.wmflabs.org/dist/extensions/ | grep -o -P "(?<=UserMerge-REL${MEDIAWIKI_VERSION_MAJOR}_${MEDIAWIKI_VERSION_MINOR}-)[0-9a-z]{7}(?=.tar.gz)" | head -1`.tar.gz && \
    tar -xzf /tmp/extension-usermerge.tar.gz -C /var/www/mediawiki/extensions && \
    rm /tmp/extension-usermerge.tar.gz

# MobileFrontend extension
RUN git clone -b REL${MEDIAWIKI_VERSION_MAJOR}_${MEDIAWIKI_VERSION_MINOR} https://github.com/wikimedia/mediawiki-extensions-MobileFrontend.git /var/www/mediawiki/extensions/MobileFrontend

# Comments extension
RUN git clone -b REL${MEDIAWIKI_VERSION_MAJOR}_${MEDIAWIKI_VERSION_MINOR} https://github.com/wikimedia/mediawiki-extensions-Comments.git /var/www/mediawiki/extensions/Comments

# CrossReference extension
RUN git clone https://github.com/staspika/mediawiki-crossreference.git /var/www/mediawiki/extensions/CrossReference

# OAuth2 extension
RUN git clone https://github.com/Schine/MW-OAuth2Client.git /var/www/mediawiki/extensions/MW-OAuth2Client
RUN cd /var/www/mediawiki/extensions/MW-OAuth2Client && git submodule update --init && cd vendors/oauth2-client && ls && composer install

# MinervaNeue skin
RUN git clone -b REL${MEDIAWIKI_VERSION_MAJOR}_${MEDIAWIKI_VERSION_MINOR} https://github.com/wikimedia/mediawiki-skins-MinervaNeue.git /var/www/mediawiki/skins/MinervaNeue

# Set work dir
WORKDIR /var/www/mediawiki

# Install composer dependencies
RUN composer update "mediawiki/lingo"

# Copy docker entry point script
COPY docker-entrypoint.sh /docker-entrypoint.sh

# Copy install and update script
RUN mkdir /script
RUN mkdir /backup
COPY script/* /script/
COPY script/mediawiki_backup.sh /etc/cron.daily/

# Copy SWIM wiki logo
COPY wiki.png /var/www/mediawiki/resources/assets/wiki.png

# Execute update script
RUN /script/update.sh
RUN composer install

# General setup
VOLUME ["/var/cache/nginx", "/data", "/images"]
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD []

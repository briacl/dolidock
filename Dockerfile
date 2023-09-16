FROM ${ARCH}php:8.1-apache AS busyboxbuilder
RUN cd / \
    && apt-get update -y \
    && apt-get install -y build-essential curl libntirpc-dev  \
    && curl -L https://busybox.net/downloads/busybox-1.36.1.tar.bz2 | tar -xjv \
    && cd /busybox-1.36.1/
COPY busybox.config /busybox-1.36.1/.config
RUN cd /busybox-1.36.1/ && make install

FROM ${ARCH}php:8.1-apache AS builder
ARG TARGETARCH
LABEL maintainer="Ronan <ronan.le_meillat@ismo-group.co.uk>"
RUN echo "Run for $TARGETARCH" && \
    if [[ "$TARGETARCH" == "amd64" ]] ; then \
        curl -fLSs https://repo.mysql.com/mysql-apt-config_0.8.22-1_all.deb > /tmp/mysql-apt-config_0.8.22-1_all.deb && \
        DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt-config_0.8.22-1_all.deb && \
        apt-get update -y &&\
        apt-get install -y --no-install-recommends mysql-client lsb-release wget gnupg ; \
    else \
        apt-get update -y &&\
        apt-get install -y --no-install-recommends default-mysql-client ; \
    fi

RUN apt-get update -y \
    && apt-get dist-upgrade -y \
    && apt-get install -y --no-install-recommends \
        git \
        libc-client-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libkrb5-dev \
        libldap2-dev \
        libpng-dev \
        libpq-dev \
        libxml2-dev \
        libzip-dev \
        libbz2-dev \
        libmemcached-dev \
        postgresql-client \
        cron 

RUN docker-php-ext-install opcache \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) calendar intl mysqli pdo_mysql gd soap zip \
    && docker-php-ext-configure pgsql -with-pgsql \
    && docker-php-ext-install pdo_pgsql pgsql \
    && docker-php-ext-configure ldap --with-libdir=lib/$(gcc -dumpmachine)/ \
    && docker-php-ext-install -j$(nproc) ldap \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-install imap \
    && docker-php-ext-configure bz2 \
    && docker-php-ext-install bz2
RUN mkdir -p /usr/src/php/ext/memcached && \
    git clone https://github.com/php-memcached-dev/php-memcached /usr/src/php/ext/memcached && \
    docker-php-ext-configure /usr/src/php/ext/memcached --disable-memcached-sasl \
    && docker-php-ext-install /usr/src/php/ext/memcached \
    && rm -rf /usr/src/php/ext/memcached \
    && mv ${PHP_INI_DIR}/php.ini-production ${PHP_INI_DIR}/php.ini \
    && rm -rf /var/lib/apt/lists/*
RUN cd / && apt-get update -y &&\
    apt-get install -y --no-install-recommends p7zip-full &&\
    git clone https://github.com/highcanfly-club/DoliMods.git && \
    cd /DoliMods/build && rm -f makepack-FacturX.conf makepack-Verifystock.conf && echo "all" | perl makepack-dolibarrmodule.pl && \
    mkdir /custom && for ZIP in *.zip; do 7z x -y -o/custom $ZIP; done

# Get Dolibarr
FROM ${ARCH}php:8.1-apache
LABEL maintainer="Ronan <ronan.le_meillat@ismo-group.co.uk>"
COPY --from=builder /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions/
COPY --from=busyboxbuilder /busybox-1.36.1/_install/bin/busybox /bin/busybox
ENV DOLI_VERSION 18.0.1
ENV DOLI_INSTALL_AUTO 1

ENV DOLI_DB_TYPE mysqli
ENV DOLI_DB_HOST mysql
ENV DOLI_DB_HOST_PORT 3306

ENV DOLI_URL_ROOT 'http://localhost'
ENV DOLI_NOCSRFCHECK 0

ENV DOLI_AUTH dolibarr
ENV DOLI_LDAP_HOST 127.0.0.1
ENV DOLI_LDAP_PORT 389
ENV DOLI_LDAP_VERSION 3
ENV DOLI_LDAP_SERVER_TYPE openldap
ENV DOLI_LDAP_LOGIN_ATTRIBUTE uid
ENV DOLI_LDAP_DN 'ou=users,dc=my-domain,dc=com'
ENV DOLI_LDAP_FILTER ''
ENV DOLI_LDAP_BIND_DN ''
ENV DOLI_LDAP_BIND_PASS ''
ENV DOLI_LDAP_DEBUG false

ENV DOLI_CRON 0

ENV WWW_USER_ID 33
ENV WWW_GROUP_ID 33

ENV PHP_INI_DATE_TIMEZONE 'UTC'
ENV PHP_INI_MEMORY_LIMIT 256M

RUN echo "Run for $TARGETARCH" && \
    if [[ "$TARGETARCH" == "amd64" ]] ; then \
        apt-get update -y \
        && apt-get dist-upgrade -y \
        && apt-get install -y --no-install-recommends && \
        curl -fLSs https://repo.mysql.com/mysql-apt-config_0.8.22-1_all.deb > /tmp/mysql-apt-config_0.8.22-1_all.deb && \
        DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt-config_0.8.22-1_all.deb && \
        apt-get update -y &&\
        apt-get install -y --no-install-recommends mysql-client lsb-release wget gnupg ; \
    else \
        apt-get update -y &&\
        apt-get install -y --no-install-recommends default-mysql-client ; \
    fi
RUN apt-get update -y \
    && apt-get dist-upgrade -y \
    && apt-get install -y --no-install-recommends \
        curl libzip4 libc-client2007e postgresql-client libpng16-16 \
        libjpeg62-turbo libfreetype6 vim libmemcached11
COPY docker-run.sh /usr/local/bin/
RUN mkdir -p /var/www/dolidock/html/custom && \
    curl -fLSs https://github.com/Dolibarr/dolibarr/archive/${DOLI_VERSION}.tar.gz |\
    tar -C /tmp -xz && \
    cp -r /tmp/dolibarr-${DOLI_VERSION}/htdocs/* /var/www/dolidock/html/ && \
    cp -r /tmp/dolibarr-${DOLI_VERSION}/scripts /var/www/ && \
    rm -rf /tmp/* && \
    chown -R www-data:www-data /var/www && \
    ln -svf /bin/busybox /usr/sbin/sendmail
RUN a2dissite 000-default &&\
    echo "<VirtualHost *:80>" >> /etc/apache2/sites-available/dolibarr.conf &&\
    echo "ServerAdmin webmaster@localhost" >> /etc/apache2/sites-available/dolibarr.conf &&\
    echo "DocumentRoot /var/www/dolidock/html" >> /etc/apache2/sites-available/dolibarr.conf &&\
    echo "ErrorLog ${APACHE_LOG_DIR}/error.log" >> /etc/apache2/sites-available/dolibarr.conf &&\
    echo "CustomLog ${APACHE_LOG_DIR}/access.log combined" >> /etc/apache2/sites-available/dolibarr.conf &&\
    echo "php_value error_reporting 0" >> /etc/apache2/sites-available/dolibarr.conf &&\
    echo "php_value session.save_path /var/www/dolidock/documents/sessions" >> /etc/apache2/sites-available/dolibarr.conf &&\
    echo "</VirtualHost>" >> /etc/apache2/sites-available/dolibarr.conf &&\
    a2ensite dolibarr
COPY patchs/fileconf-enable-dot-in-db-name.diff /var/www/dolidock/
COPY patchs/bug-mod-user-unavailable.diff /var/www/dolidock/
COPY patchs/pgsql-enable-ssl.diff /var/www/dolidock/
COPY patchs/bug-fk-soc-tier.diff /var/www/dolidock/
COPY patchs/bug-margin-pdf.diff /var/www/dolidock/
COPY patchs/bug-saphir.diff /var/www/dolidock/
RUN cd /var/www/dolidock/ &&\
    patch --fuzz=12 -p0 < fileconf-enable-dot-in-db-name.diff &&\
    patch --fuzz=12 -p0 < bug-mod-user-unavailable.diff &&\
    patch --fuzz=12 -p0 < pgsql-enable-ssl.diff &&\
    patch --fuzz=12 -p0 < bug-fk-soc-tier.diff &&\
    patch --fuzz=12 -p0 < bug-margin-pdf.diff &&\
    rm -f *.diff
COPY --from=builder /custom/htdocs /var/www/dolidock/html/custom/
EXPOSE 80
VOLUME /var/www/dolidock/documents

ENTRYPOINT ["/usr/local/bin/docker-run.sh"]

CMD ["apache2-foreground"]
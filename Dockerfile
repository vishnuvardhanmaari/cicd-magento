FROM vishnuvardhan95656/magento:latest
# LABEL author="Jameel Ahmad Ansari jameel@codilar.com"
# LABEL maintainer="Jameel Ahmad Ansari jameel@codilar.com"

# Set bash by default
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Default configuration, override in deploy/local.env for localsetup
# Do not remove variables, build depends on them,
# just add "" to empty variable, the latest stable version will used instead

# These arguments are defaults, to override them, use .env
# The list of ENVs must be matched to corresponfing ARGs, to persist values in runtime
# ARG PROJECT_TAG=local
# ARG BASEPATH=/var/www/html
# ARG COMPOSER_HOME=/var/lib/composer
# ARG COMPOSER_VERSION=latest
# ARG COMPOSER_ALLOW_SUPERUSER=1
# ARG PATH=$PATH:/usr/local/php/bin
# ARG DOCKER_DEBUG=false
# ARG GOSU_GPG_KEY=B42F6819007F00F88E364FD4036A9C25BF357DD4

# Set working directory so any relative configuration or scripts wont fail
WORKDIR /var/www/html/

# Set permissions for non privileged users to use stdout/stderr
RUN chmod augo+rwx /dev/stdout /dev/stderr /proc/self/fd/1 /proc/self/fd/2

# ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

# RUN chmod +x /usr/local/bin/install-php-extensions && \
#     install-php-extensions gd xdebug sodium  zip gd bcmath soap intl sockets xsl pdo_mysql bz2 imap ldap mcrypt mysqli opcache pcov redis xdebug 

# RUN export PATH

ENV TERM=xterm-256color \
    DEBIAN_FRONTEND=noninteractive \
    DOCKER_DEBUG=${DOCKER_DEBUG} \
    CPU_CORES=$(nproc) \
    # COMPOSER_ALLOW_SUPERUSER=$(COMPOSER_ALLOW_SUPERUSER) \
    COMPOSER_HOME=/var/lib/composer \
    MAKE_OPTS="-j $CPU_CORES" \
    PATH=${BASEPATH}/bin:/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Copy PHP configs
#COPY .codilar/www.conf  /usr/local/etc/php-fpm.d/www.conf
COPY .codilar/php.ini /usr/local/etc/php/php.ini
COPY .codilar/docker-php-fpm.conf /usr/local/etc/php-fpm.d/docker.conf
# COPY .codilar/env.php /home/root/env.php
# Copy waiter helper
# COPY .codilar/wait-for-it.sh /wait-for-it.sh
# RUN chmod +x /wait-for-it.sh

# # MSMTP config set
RUN { \
        echo 'defaults'; \
        echo 'logfile /proc/self/fd/2'; \
        echo 'timeout 30'; \
        echo 'host maildev'; \
        echo 'tls off'; \
        echo 'tls_certcheck off'; \
        echo 'port 25'; \
        echo 'auth off'; \
        echo 'from no-reply@docker'; \
        echo 'account default'; \
    } | tee /etc/msmtprc

# # Start script, executed upon container creation from image
COPY .codilar/start.sh /start.sh
RUN chmod +x /start.sh

# Clean up APT and temp when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# COPY .codilar/entrypoint.sh /usr/local/bin/entrypoint.sh
# RUN chmod +x /usr/local/bin/entrypoint.sh


# Copy project files
COPY . /var/www/html
EXPOSE 80 
EXPOSE 9000

# ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD [ "/start.sh"]



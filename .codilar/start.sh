#!/usr/bin/env bash
set -euo pipefail

start_time="$(date -u +%s.%N)"
### Debug options start.
# Uncomment next line for script debug
# set -euxo pipefail
# PATH=$PATH:/usr/local/php/bin
# export PATH testing git webhook
php-fpm -t
# Do not force container to restart in debug mode
if [ $DOCKER_DEBUG = "true" ]; then
set +e
fi

### Debug options end

#testing mirroring ignore this line

### Custom commands for assets compilation
# Add you custom tasks to execute them before magento static content deploy

################################################################################

# This script prepares docker environment for application

################################################################################

### Default env variables
export COMPOSER_NO_DEV="--no-dev"

### Colors in command output start

function bash_color_library {
# see if it supports colors...
ncolors=$(tput colors)
# shellcheck disable=SC2034
if test -n "$ncolors" && test $ncolors -ge 8; then

bold="$(tput bold)"
underline="$(tput smul)"
standout="$(tput smso)"
normal="$(tput sgr0)"
black="$(tput setaf 0)"
red="$(tput setaf 1)"
green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
blue="$(tput setaf 4)"
magenta="$(tput setaf 5)"
cyan="$(tput setaf 6)"
white="$(tput setaf 7)"
fi
}

bash_color_library
bash_colors=$(bash_color_library)
export bash_colors

### Colors in command output end

# Apply correct permissions for Magento
function magento_fix_permissions() {
echo "${blue}${bold}Applying correct permissions to internal folders${normal}"
chmod -R 777 var vendor generated pub/static  app/etc
# For windows
# chmod -R ugoa+rwX var generated pub/static pub/media app/etc

}

function in_basepath {
if [ -d $BASEPATH ]; then
#creating base-path
# export PATH
# php-fpm
cp -rf /var/www/magento/* $BASEPATH/
rm -rf /var/www/magento
# /etc/init.d/php7.4-fpm stop && /etc/init.d/php7.4-fpm start
# Change to base directory
cd $BASEPATH
else
echo "${red}${bold}Working directory does not exist or not accessible${normal}"
exit 1
fi
}

function composer_install {
# Check if COMPOSER_AUTH environment variable exists
# if [ -z ${COMPOSER_AUTH+x} ]; then echo "Please set COMPOSER_AUTH environment variable" && exit 1; fi
# Check environment to install Dev Dependencies on specific ones
if [ $MAGENTO_MODE = "developer" ]; then
COMPOSER_NO_DEV=""
fi

# Composer install
echo "${red}${bold}REMOVING ENV.PHP${normal}"
rm -rf /var/www/html/app/etc/env.php
echo "${blue}${bold}Installing magento dependencies${normal}"
# composer self-update --2
#composer require laminas/laminas-dependency-plugin -vvv
sed -i 's/5f5929ef9f2ec4ca048a2add261d22c92807630f/ce31e720d60451784b9fdb3769e43e149f50d436/g' composer.lock
#composer dump-autoload
rm -rf /var/www/html/app/code/Mageplaza/Core
rm -rf /var/www/html/vendor/
cp -r /home/root/env.php /var/www/html/app/etc/
composer install --ansi --no-interaction --prefer-dist -v

}

function magento_database_config {
echo "${blue}${bold}Setting magento database credentials${normal}"
php bin/magento setup:config:set \
--db-host $MYSQL_HOST \
--db-name $MYSQL_DATABASE \
--db-user $MYSQL_USER \
--db-password $MYSQL_PASSWORD \
--backend-frontname $MAGENTO_ADMINURI \
-n
}

function create_admin_user {
echo "${blue}${bold}Checking user $MAGENTO_USER ${normal}"
USER_STATUS=$(php bin/magento admin:user:unlock $MAGENTO_USER)
export USER_STATUS
if [[ $USER_STATUS =~ "Couldn't find the user account" ]]; then
php bin/magento admin:user:create \
--admin-firstname $MAGENTO_FIRST_NAME \
--admin-lastname $MAGENTO_LAST_NAME \
--admin-email $MAGENTO_EMAIL \
--admin-user $MAGENTO_USER \
--admin-password $MAGENTO_PASSWORD

echo "${blue}${bold}User $MAGENTO_USER created${normal}"
fi
}

function magento_database_migration {
# Check if magento already installed or not, ignoring exit statuses of eval, since it's magento subprocess
set +e
echo "${blue}${bold}Checking status of the magento database${normal}"
MAGENTO_STATUS=$(magento setup:db:status)
export MAGENTO_STATUS
echo $MAGENTO_STATUS;

# Set default value
export ME=0;

# We cannot rely on Magento Code, as these are update codes, not install codes. Therefore check the output for
# the specific message!
if [[ $MAGENTO_STATUS =~ "Magento application is not installed."$ ]]; then
php bin/magento setup:install \
--admin-firstname $MAGENTO_FIRST_NAME \
--admin-lastname $MAGENTO_LAST_NAME \
--admin-email $MAGENTO_EMAIL \
--admin-user $MAGENTO_USER \
--admin-password $MAGENTO_PASSWORD 
# --elasticsearch-host $ELASTICSEARCH_HOST \
# --elasticsearch-port $ELASTICSEARCH_PORT \
# --elasticsearch-index-prefix $ELASTICSEARCH_INDEX_PREFIX 
# --elasticsearch-username $ELASTICSEARCH_USER \
# --elasticsearch-password $ELASTICSEARCH_PASSWORD \
# --elasticsearch-enable-auth $ELASTICSEARCH_AUTH 
#--amqp-host $RABBITMQ_HOST \
#--amqp-port "5672" \
#--amqp-user $RABBITMQ_DEFAULT_USER \
#--amqp-password $RABBITMQ_DEFAULT_PASS \
#--amqp-virtualhost="/"
else
magento setup:db:status
export ME=$?
echo "${blue}${bold}DB STATUS: $ME ${normal}"
fi

## Parse exit codes (https://github.com/magento/magento2/blob/2.2-develop/setup/src/Magento/Setup/Console/Command/DbStatusCommand.php)
# Magento is not installed, then install it
if [ $ME = 1 ]; then
echo "${red}${bold}Cannot upgrade: manual action is required! ${normal}"
# Magento needs upgrade
elif [ $ME = 2 ]; then
echo "$yellow$bold Upgrading magento${normal}"
php bin/magento setup:upgrade
# Check returns All modules updated, move on.
elif [ $ME = 0 ]; then
echo "${blue}${bold}No upgrade/install is needed${normal}"
else
echo "${red}${bold}Database migration failed: manual action is required!${normal}"
fi
if [ $DOCKER_DEBUG != "true" ]; then
set -e
fi
}

function magento_redis_config {
echo "${blue}${bold}Setting redis as config cache${normal}"
bin/magento setup:config:set \
--cache-backend=redis \
--cache-backend-redis-server=$REDIS_HOST \
--cache-backend-redis-db=0 \
-n

echo "${blue}${bold}Setting redis as page cache${normal}"
bin/magento setup:config:set \
--page-cache=redis \
--page-cache-redis-server=$REDIS_HOST \
--page-cache-redis-db=1 \
-n

# Redis for sessions
echo "${blue}${bold}Setting redis as session storage${normal}"
bin/magento setup:config:set \
--session-save=redis \
--session-save-redis-host=$REDIS_HOST \
--session-save-redis-log-level=3 \
--session-save-redis-max-concurrency=30 \
--session-save-redis-db=1 \
--session-save-redis-disable-locking=1 \
-n

# Elasticsearch5 as a search engine
echo "${blue}${bold}Setting Elasticsearch7 as a search engine${normal}"
# php bin/magento config:set catalog/search/engine elasticsearch7

# elasticsearch container as a host name
echo "${blue}${bold}Setting elasticsearch as a host name for Elasticsearch5${normal}"
# php bin/magento config:set catalog/search/elasticsearch7_server_hostname elasticsearch
php bin/magento cache:enable
}

function magento_set_mode {
# Set Magento mode
if [[ -n ${MAGENTO_MODE+x} ]]; then
echo "${blue}${bold}Switching magento mode${normal}"
bin/magento deploy:mode:set $MAGENTO_MODE --skip-compilation
fi
}

function magento_compile {
if [[ $MAGENTO_MODE = "production" ]]; then
echo "${blue}${bold}Generating DI and assets${normal}"
bin/magento setup:di:compile
bin/magento setup:static-content:deploy
fi
}

function magento_set_baseurl {
if [[ -n ${MAGENTO_BASEURL+x} ]]; then
echo "${blue}${bold}Setting baseurl to $MAGENTO_BASEURL${normal}"
php bin/magento setup:store-config:set --base-url="$MAGENTO_BASEURL"
fi
if [[ -n ${MAGENTO_SECURE_BASEURL+x} ]]; then
echo "${blue}${bold}Setting secure baseurl to $MAGENTO_SECURE_BASEURL${normal}"
php bin/magento setup:store-config:set --base-url-secure="$MAGENTO_SECURE_BASEURL"
php bin/magento setup:store-config:set --use-secure 1
php bin/magento setup:store-config:set --use-secure-admin 1
fi
}

function magento_post_deploy {
echo "${blue}${bold}Flushing caches${normal}"
# rm -rf /var/www/html/pub/media
# ln -fs /data/media /var/www/html/pub/
#php bin/magento module:disable Magento_TwoFactorAuth
php bin/magento setup:di:compile
php bin/magento setup:static-content:deploy -f
php bin/magento indexer:reindex
php bin/magento cache:flush
echo "${blue}${bold}Disabling maintenance mode${normal}"
php bin/magento maintenance:disable
php bin/magento info:adminuri
}
function delay_in_time {
echo "${blue}${bold} WAITING_FOR_MYSQL_DB_IMPORT ${normal}"
sleep 5m
echo "${blue}${bold} ALL_DONE ${normal}"
}

function ssh_configure {
echo "${blue}${bold} INSTALLING AND CONFIGURING SSH ${normal}"
# apt update -y && apt install -y ca-certificates curl gzip ssh bc
service ssh stop && service ssh start
service nginx stop && service nginx start 
mkdir -p /root/.ssh
touch /root/.ssh/authorized_keys
cp /root/ssh/authorized_keys /root/.ssh/authorized_keys
chmod -R 644 /root/.ssh

echo "Installing cron and running magento cron and installing mysql-client"
apt update
apt install cron 
#php bin/magento cron:install
service cron start 
chown -R root:www-data var/
su -s /bin/bash www-data -c "cd /var/www/html && bin/magento cron:install --force"
apt install mysql-client -y
}

function magento_varnish_endpoint {
echo "${blue}${bold}Setting location for Varnish cache flushing${normal}"
bin/magento setup:config:set --http-cache-hosts $VARNISH_HOST
}

function magento_varnish_config {
echo "${blue}${bold}Setting Varnish config for Magento${normal}"
php bin/magento config:set system/full_page_cache/varnish/access_list $VARNISH_ACCESS_LIST
php bin/magento config:set system/full_page_cache/varnish/backend_host $VARNISH_BACKEND_HOST
php bin/magento config:set system/full_page_cache/varnish/backend_port 8080
php bin/magento config:set system/full_page_cache/caching_application 2

}

#function cron_run {
#echo "Installing cron and running magento cron"
#apt update
#apt install cron
#php bin/magento cron:install


#}
# function apache_configure {
# echo "${blue}${bold}configuring apache${normal}"
# apt update -y && apt install -y apache2 ca-certificates curl gzip
# mkdir -p /etc/apache/certs
# cp -rf /var/www/html/certs/* /etc/apache/certs/
# cp -rf /var/www/html/apache-conf/* /etc/apache2/sites-available/
# a2enmod rewrite && a2ensite magento.conf && a2ensite magento-ssl.conf && a2enmod ssl && service apache2 restart
# }

function exit_catch {
LAST_EXIT_CODE=$?
exit ${LAST_EXIT_CODE}
}

#triggering auto-build

### Deploy pipe start

# Switch current execution directory to WORKDIR (BASEPATH)
in_basepath
# Installing PHP Composer and packages
composer_install

# delay_in_time

# Flushing Magento configuration in Redis
# magento_flush_config
# Setting magento database credentials
magento_database_config
# Executing Magento install or migration
magento_database_migration
# Configuring Magento to use Redis for session and config storage
# magento_redis_config
# Create admin user if not exists
create_admin_user

# Set magento mode
magento_set_mode
# Static content deploy and DI compile, only in production mode
magento_compile

# Set magento baseurl and secure_baseurl
magento_set_baseurl

# varnish configuration

magento_varnish_endpoint

magento_varnish_config



# Appling correct folder permissions
magento_fix_permissions

# apache_configure
# Flushing all caches, removing maintenance mode
magento_post_deploy
# Fixing permissions again due c:f
magento_fix_permissions


# configuring ssh
ssh_configure

#cron_run 

end_time="$(date -u +%s.%N)"

elapsed="$(bc <<<"$end_time-$start_time")"
echo "Deployment executed in $bold$elapsed$normal seconds"

trap exit_catch EXIT
### Deploy pipe end

echo "${blue}${bold}Staring php fpm, ready to rock${normal}"
php-fpm -R


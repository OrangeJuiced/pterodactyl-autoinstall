#!/bin/bash
#Install script to install Pterodactyl panel v0.6.4 and Wings daemon v0.4.3 on Ubuntu 16.04
function output() {
  echo -e '\e[93m'$1'\e[0m'; #Yellow text
}

function installchoice {
  output "This install script is only meant for use on fresh OS installs. Installing on a non-fresh OS could break things."
  output "Please select what you would like to install:\n[1] Install the panel.\n[2] Install the daemon.\n[3] Install the panel and daemon."
  read choice
  case $choice in
      1 ) installoption=1
          output "You have selected panel installation only."
          ;;
      2 ) installoption=2
          output "You have selected daemon installation only."
          ;;
      3 ) installoption=3
          output "You have selected panel and daemon installation."
          ;;
      * ) output "You did not enter a a valid selection"
          installchoice
  esac
}

function webserverchoice {
  output "Please select which web server you would like to use:\n[1] nginx.\n[2] apache."
  read choice
  case $choice in
      1 ) webserver=1
          output "You have selected nginx."
          ;;
      2 ) webserver=2
          output "You have selected apache."
          ;;
      * ) output "You did not enter a a valid selection"
          webserverchoice
  esac
}

function required_vars_panel {
    output "Please enter your FQDN:"
    read FQDN

    output "Please enter your timezone in PHP format:"
    read timezone

    output "Please enter your desired first name:"
    read firstname

    output "Please enter your desired last name:"
    read lastname

    output "Please enter your desired username:"
    read username

    output "Please enter the desired user email address:"
    read email

    output "Please enter the desired password:"
    read userpassword
}

function required_vars_daemon {
  output "Please enter your FQDN"
  read FQDN
}

#All panel related install functions
function install_apache_dependencies {
  output "Installing apache dependencies"
  # Add additional PHP packages.
  add-apt-repository -y ppa:ondrej/php
  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

  # Update APT
  apt update

  # Install Dependencies
  apt-get -y install php7.1 php7.1-cli php7.1-gd php7.1-mysql php7.1-pdo php7.1-mbstring php7.1-tokenizer php7.1-bcmath php7.1-xml php7.1-curl php7.1-memcached php7.1-zip mariadb-server libapache2-mod-php apache2 curl tar unzip git memcached
}

function install_nginx_dependencies {
  output "Installing nginx dependencies"
  # Add additional PHP packages.
  add-apt-repository -y ppa:ondrej/php
  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

  # Update repositories list
  apt update

  # Install Dependencies
  apt-get -y install php7.1 php7.1-cli php7.1-gd php7.1-mysql php7.1-pdo php7.1-mbstring php7.1-tokenizer php7.1-bcmath php7.1-xml php7.1-fpm php7.1-memcached php7.1-curl php7.1-zip mariadb-server nginx curl tar unzip git memcached
}

function panel_downloading {
  output "Downloading the panel"
  mkdir -p /var/www/html/pterodactyl
  cd /var/www/html/pterodactyl

  curl -Lo v0.6.4.tar.gz https://github.com/pterodactyl/panel/releases/download/v0.7.10/panel.tar.gz
  tar --strip-components=1 -xzvf v0.7.10.tar.gz

  chmod -R 755 storage/* bootstrap/cache
}

function panel_installing {
  output "Installing the panel"
  curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

  cp .env.example .env
  composer install --no-dev
  php artisan key:generate --force

  #Create MySQL database with random password
  password=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`

  Q1="CREATE DATABASE IF NOT EXISTS pterodactyl;"
  Q2="GRANT ALL ON pterodactyl.* TO 'panel'@'localhost' IDENTIFIED BY '$password';"
  Q3="FLUSH PRIVILEGES;"
  SQL="${Q1}${Q2}${Q3}"

  mysql -u root -e "$SQL"

  php artisan pterodactyl:env --dbhost=localhost --dbport=3306 --dbname=pterodactyl --dbuser=panel --dbpass=$password --url=http://$FQDN --timezone=$timezone --driver=memcached --queue-driver=database --session-driver=database

  php artisan migrate --force
  php artisan db:seed --force

  php artisan pterodactyl:user --firstname=$firstname --lastname=$lastname --username=$username --email=$email --password=$userpassword --admin=1

  chown -R www-data:www-data *
}

function panel_queuelisteners {
  output "Creating panel queue listeners"
  (crontab -l ; echo "* * * * * php /var/www/pterodactyl/html/artisan schedule:run >> /dev/null 2>&1")| crontab -

cat > /etc/systemd/system/pteroq.service <<- "EOF"
# Pterodactyl Queue Worker File
[Unit]
Description=Pterodactyl Queue Worker

[Service]
User=www-data
Group=www-data
Restart=on-failure
ExecStart=/usr/bin/php /var/www/html/pterodactyl/artisan queue:work database --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable pteroq.service
  sudo systemctl start pteroq
}

function ssl_certs {
  output "Generating SSL certificates"
  cd /root
  curl https://get.acme.sh | sh
  cd /root/.acme.sh/
  sh acme.sh --issue --apache -d $FQDN

  mkdir -p /etc/letsencrypt/live/$FQDN
  ./acme.sh --install-cert -d $FQDN --certpath /etc/letsencrypt/live/$FQDN/cert.pem --keypath /etc/letsencrypt/live/$FQDN/privkey.pem --fullchainpath /etc/letsencrypt/live/$FQDN/fullchain.pem
}

function panel_webserver_configuration_nginx {
  output "ngingwebconf"
}

function panel_webserver_configuration_apache {
  output "Configuring apache"
cat > /etc/apache2/sites-available/pterodactyl.conf << EOF
<IfModule mod_ssl.c>
<VirtualHost *:443>
ServerAdmin webmaster@localhost
DocumentRoot "/var/www/html/pterodactyl/public"
AllowEncodedSlashes On
php_value upload_max_filesize 100M
php_value post_max_size 100M
<Directory "/var/www/html/pterodactyl/public">
AllowOverride all
</Directory>

SSLEngine on
SSLCertificateFile /etc/letsencrypt/live/$FQDN/fullchain.pem
SSLCertificateKeyFile /etc/letsencrypt/live/$FQDN/privkey.pem
ServerName $FQDN
</VirtualHost>
</IfModule>
EOF

echo -e "<VirtualHost *:80>\nRewriteEngine on\nRewriteCond %{SERVER_NAME} =$FQDN\nRewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,QSA,R=permanent]\n</VirtualHost>" > /etc/apache2/sites-available/000-default.conf

  sudo ln -s /etc/apache2/sites-available/pterodactyl.conf /etc/apache2/sites-enabled/pterodactyl.conf
  sudo a2enmod rewrite
  sudo a2enmod ssl
  service apache2 restart
}

#All daemon related install functions
function update_kernel {
  output "Updating kernel if needed"
  apt install -y linux-image-extra-$(uname -r) linux-image-extra-virtual
}

function daemon_dependencies {
  output "Installing daemon dependecies"
  #Docker
  curl -sSL https://get.docker.com/ | sh
  systemctl enable docker

  #Nodejs
  curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
  apt install -y nodejs

  #Additional
  apt install -y tar unzip make gcc g++ python
}

function daemon_install {
  output "Installing the daemon"
  mkdir -p /srv/daemon /srv/daemon-data
  cd /srv/daemon
  curl -Lo v0.4.3.tar.gz https://github.com/pterodactyl/daemon/releases/download/v0.6.7/daemon.tar.gz
  tar --strip-components=1 -xzvf v0.6.7.tar.gz
  npm install --only=production

  echo -e "[Unit]\nDescription=Pterodactyl Wings Daemon\nAfter=docker.service\n\n[Service]\nUser=root\n#Group=some_group\nWorkingDirectory=/srv/daemon\nLimitNOFILE=4096\nPIDFile=/var/run/wings/daemon.pid\nExecStart=/usr/bin/node /srv/daemon/src/index.js\nRestart=on-failure\nStartLimitInterval=600\n\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/wings.service
  systemctl daemon-reload
  systemctl enable wings
}

# Time for some user input
installchoice

# Let's figure out what we actually are going to install based on user input
case $installoption in
  1 ) webserverchoice #Panel only, so we show the webserver selection
      required_vars_panel #Gather some user data we need for the installation
      case $webserver in #Install based on choice
        1 ) install_nginx_dependencies
            panel_downloading
            panel_installing
            panel_queuelisteners
            panel_webserver_configuration_nginx
            output "Panel installation completed!"
            ;;
        2 ) install_apache_dependencies
            panel_downloading
            panel_installing
            panel_queuelisteners
            ssl_certs
            panel_webserver_configuration_apache
            output "Panel installation completed"
            ;;
      esac
      ;;
  2 ) #Daemon only
      update_kernel
      daemon_dependencies
      ;;
  3 ) webserverchoice #Panel and daemon, so we show the webserver selection
      required_vars_panel #Gather some user data we need for the installation
      case $webserver in #Install based on choice
        1 ) install_nginx_dependencies
            ;;
        2 ) install_apache_dependencies
            panel_downloading
            panel_installing
            panel_queuelisteners
            ssl_certs
            panel_webserver_configuration_apache
            output "Panel installation completed"

            update_kernel
            daemon_dependencies
            daemon_install
            output "Daemon installation completed"
            ;;
      esac
      ;;
esac

#!/bin/sh
DOMAIN=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
echo $DOMAIN

# Get the current machine IP address
CURRENT_IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

# Install core system packages
export DEBIAN_FRONTEND=noninteractive
sudo add-apt-repository universe
sudo add-apt-repository -yu ppa:ondrej/php
sudo apt install -y git apache2 php7.4 curl php7.4-fpm php7.4-curl php7.4-mbstring php7.4-ldap \
php7.4-xml php7.4-zip php7.4-gd php7.4-mysql mysql-server-5.7 libapache2-mod-php7.4

# Set up database
DB_PASS="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)"
sudo mysql -u root --execute="CREATE DATABASE bookstack;"
sudo mysql -u root --execute="CREATE USER 'bookstack'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -u root --execute="GRANT ALL ON bookstack.* TO 'bookstack'@'localhost';FLUSH PRIVILEGES;"

# Download BookStack
cd /var/www
sudo git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch bookstack
BOOKSTACK_DIR="/var/www/bookstack"
cd $BOOKSTACK_DIR

# Install composer
EXPECTED_SIGNATURE=$(wget https://composer.github.io/installer.sig -O - -q)
sudo curl -s https://getcomposer.org/installer > composer-setup.php
ACTUAL_SIGNATURE=$(php -r "echo hash_file('SHA384', 'composer-setup.php');")
if [ "$EXPECTED_SIGNATURE" = "$ACTUAL_SIGNATURE" ]
then
    php composer-setup.php --quiet
    RESULT=$?
    rm composer-setup.php
else
    >&2 echo 'ERROR: Invalid composer installer signature'
    rm composer-setup.php
    exit 1
fi

# Install BookStack composer dependencies
export COMPOSER_ALLOW_SUPERUSER=1
sudo apt-get install zip -y
sudo apt-get install unzip -y
sudo apt-get install php-curl -y
sudo apt install php-xml -y
sudo php composer.phar install --ignore-platform-req=ext-gd --no-dev --no-plugins --no-interaction

# Copy and update BookStack environment variables
sudo cp .env.example .env
sudo sed -i.bak "s@APP_URL=.*\$@APP_URL=http://$DOMAIN@" .env
sudo sed -i.bak 's/DB_DATABASE=.*$/DB_DATABASE=bookstack/' .env
sudo sed -i.bak 's/DB_USERNAME=.*$/DB_USERNAME=bookstack/' .env
sudo sed -i.bak "s/DB_PASSWORD=.*\$/DB_PASSWORD=$DB_PASS/" .env

# Generate the application key
sudo php artisan key:generate --no-interaction --force
# Migrate the databases
sudo apt install php-mysql -y
sudo php artisan migrate --no-interaction --force

# Set file and folder permissions
sudo chown www-data:www-data -R bootstrap/cache public/uploads storage && chmod -R 755 bootstrap/cache public/uploads storage

# Set up apache
sudo a2enmod rewrite
sudo a2enmod php7.4

sudo cat >/etc/apache2/sites-available/bookstack.conf <<EOL
<VirtualHost *:80>
	ServerName ${DOMAIN}

	ServerAdmin webmaster@localhost
	DocumentRoot /var/www/bookstack/public/

    <Directory /var/www/bookstack/public/>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
        <IfModule mod_rewrite.c>
            <IfModule mod_negotiation.c>
                Options -MultiViews -Indexes
            </IfModule>

            RewriteEngine On

            # Handle Authorization Header
            RewriteCond %{HTTP:Authorization} .
            RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

            # Redirect Trailing Slashes If Not A Folder...
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_URI} (.+)/$
            RewriteRule ^ %1 [L,R=301]

            # Handle Front Controller...
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteRule ^ index.php [L]
        </IfModule>
    </Directory>

	ErrorLog \${APACHE_LOG_DIR}/error.log
	CustomLog \${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
EOL

sudo a2dissite 000-default.conf
sudo a2ensite bookstack.conf

# Restart apache to load new config
sudo systemctl restart apache2

sudo echo ""
sudo echo "Setup Finished, Your BookStack instance should now be installed."
sudo echo "You can login with the email 'admin@admin.com' and password of 'password'"
sudo echo "MySQL was installed without a root password, It is recommended that you set a root MySQL password."
sudo echo ""
sudo echo "You can access your BookStack instance at: http://$CURRENT_IP/ or http://$DOMAIN/"
sudo mkdir /home/ubuntu/haha

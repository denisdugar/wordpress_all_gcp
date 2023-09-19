#!/bin/bash
sudo apt update
sudo apt install -y apache2 \
                 ghostscript \
                 libapache2-mod-php \
                 php \
                 php-bcmath \
                 php-curl \
                 php-imagick \
                 php-intl \
                 php-json \
                 php-mbstring \
                 php-mysql \
                 php-xml \
                 php-zip \
                 nfs-common \
                 cifs-utils \
                 curl
export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
echo "deb https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get update
sudo apt-get install gcsfuse
sudo mount -t gcsfuse -o implicit_dirs,allow_other,uid=33,gid=33 wordpress-dduha /mnt
ln -s /mnt/wordpress /var/www/
cat /var/www/wordpress/wp-config.php | sudo tee /var/wp-config.php
sudo sed -i "s/define( 'DB_HOST', '.*' );/define( 'DB_HOST', '${DB_HOST}' );/" /var/wp-config.php
sudo mv /var/wp-config.php /var/www/wordpress/
echo "<VirtualHost *:80>
    ServerName www.wordpressdduha.pp.ua
    ServerAlias wordpressdduha.pp.ua

    DocumentRoot /var/www/wordpress
    <Directory /var/www/wordpress>
        Options FollowSymLinks
        AllowOverride None
        DirectoryIndex index.php
        Require all granted
    </Directory>
    <Directory /var/www/wordpress/wp-content>
        Options FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    ServerName www.wordpressdduha.pp.ua
    ServerAlias wordpressdduha.pp.ua

    DocumentRoot /var/www/wordpress
    SSLEngine on
    SSLCertificateFile /var/www/wordpress/ssl/certificate.crt
    SSLCertificateKeyFile /var/www/wordpress/ssl/private.key
    <Directory /var/www/wordpress>
        Options FollowSymLinks
        AllowOverride None
        DirectoryIndex index.php
        Require all granted
    </Directory>
    <Directory /var/www/wordpress/wp-content>
        Options FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>" | sudo tee -a /etc/apache2/sites-available/wordpress.conf
sudo a2enmod ssl
sudo a2ensite wordpress
sudo a2enmod rewrite
sudo a2dissite 000-default
sudo systemctl restart apache2
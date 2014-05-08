#!/usr/bin/perl -w

use strict;
use warnings;

##################
## CLI switches ##
##################
my $switch;
$switch = shift;
if ( $switch and ( $switch eq "-h" or $switch eq "--help" or $switch eq "-?" ) )
{
    print(
"This script is meant to help you to install the latest version of Wordpress on a Debian or Ubuntu server\nIt is not recommended to use this script if your server is already being used in production.\nHelp and support: https://github.com/martin-denizet/wp_silex/\nAuthor: Martin DENIZET (http://martin-denizet.com)\nLicense: GPLv2"
    );
    exit 0;
}

##################
##### CONFIG #####
##################

my $ubuntu = `lsb_release -a | grep "Ubuntu" | wc -l` > 0;

my $workdir     = '/var/www/';
my $tempdir     = '/tmp/';
my $downloadto  = $tempdir . 'latest.tar.gz';
my $downloadurl = 'http://wordpress.org/latest.tar.gz';
my $saltsurl    = 'https://api.wordpress.org/secret-key/1.1/salt/';
my $dbserver    = '';
my $server      = '';
my $webuser     = 'www-data';
my $webgroup    = 'www-data';

my $tempnewinstance = $tempdir . 'wordpress';

my $nginxconfdir         = '/etc/nginx/sites-available/';
my $nginxenabledconfdir  = '/etc/nginx/sites-enabled/';
my $apacheconfdir        = '/etc/apache2/sites-available/';
my $apacheenabledconfdir = '/etc/apache2/sites-enabled/';
my $apacheextraconfdir   = '/etc/apache2/conf.d/';

my $ip =
`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`;
$ip =~ s/\R//g;

#For apache2
my $serveradmin = 'admin@domain.com';

##################
##### UTILS ######
##################
sub rndStr {
    join '', @_[ map { rand @_ } 1 .. shift ];
}

sub randomPassword {
    return rndStr( 20, 'A' .. 'Z', 0 .. 9, 'a' .. 'z', '-', '_', '.' );
}

sub stripNewLines {
    my $string = $_[0];
    $string =~ s/\R//g;
    return $string;

}

sub echoLine {
    print $_[0] . "\n";
}

sub echoWarn {
    echoLine( "!!!!!!!!!!!!!!!!!!!!!!!!\nWarning:"
          . $_[0]
          . "\n!!!!!!!!!!!!!!!!!!!!!!!!" );
}

sub echoTitle {
    echoLine(
        "========================\n" . $_[0] . "\n========================" );
}

sub readCleanLine {
    echoLine( $_[0] );
    my $tmp = readline(*STDIN);
    $tmp =~ s/\R//g;
    return $tmp;
}

sub installPackageString {
    my $string = 'apt-get install ' . $_[0];
    if ($ubuntu) {
        $string = 'sudo ' . $string;
    }
    return "apt-get update    \n" . $string;
}

sub addSudo {
    if ($ubuntu) {
        return 'sudo ';
    }
    return '';
}

##################
##### Checks #####
##################
unless ( `dpkg --get-selections | grep ca-certificates | wc -l` > 0 ) {
    die(
"It'n not possible to safely download salts without ca-certificates package. Please install it:\n    "
          . installPackageString('ca-certificates') );
}

my $packageToInstall = '';
## Web server detection
if ( `dpkg --get-selections | grep apache2 | wc -l` > 0 ) {
    $server = 'apache2';

    #Apache specific packages
    unless ( `dpkg --get-selections | grep apache2-mpm-worker  | wc -l` > 0 ) {
        $packageToInstall .= 'apache2-mpm-worker ';
    }

    unless (
        `dpkg --get-selections | grep libapache2-mod-fastcgi  | wc -l` > 0 )
    {
        $packageToInstall .= 'libapache2-mod-fastcgi ';
    }
}
else {
    if ( `dpkg --get-selections | grep nginx | wc -l` > 0 ) {
        $server = 'nginx';
    }
    else {
        echoWarn(
                "No web server detected\nYou may want to install Apache2:\n    "
              . installPackageString('apache2')
              . " \nOR you can also choose to use nginx (recommended):\n    "
              . installPackageString('nginx') );
        die();
    }
}
unless ( $server eq '' ) {
    echoLine("Webserver detected: {$server}");
}
## PHP detection
unless ( `dpkg --get-selections | grep php5-fpm | wc -l` > 0 ) {
    $packageToInstall .= 'php5-fpm ';
}
unless ( `dpkg --get-selections | grep php5-mysql | wc -l` > 0 ) {
    $packageToInstall .= 'php5-mysql ';
}

## DB Server detection
if ( `dpkg --get-selections | grep mysql-server | wc -l` > 0 ) {
    $dbserver = 'mysql';
    echoLine("DB server detected: {$dbserver}");
}
else {
    $packageToInstall .= 'mysql-server ';
}

## Install the missing packages
if ($packageToInstall) {
    echoWarn(
"Some packages are missing, you need to install them to have a functional instance:\n   "
          . installPackageString($packageToInstall) );
    die();
}

#Create dirs
unless ( -d $workdir ) {
    mkdir $workdir, oct('740') or die "$!";
}

# Delete if exists
if ( -f $downloadto ) {
    unlink $downloadto;
}
if ( -d $tempnewinstance ) {
    unlink $tempnewinstance;
}

#Fix perms
#nginx need the directory to be executable
system("chmod +x $workdir");

##################
##### PROCESS ####
##################

my $instance_name = readCleanLine(
    "New instance name - Alphanumerical without spaces - example: myblog");
unless ( $instance_name =~ m/[A-z0-9]/ ) {
    echoLine(
"Only alphanumerical characters without spaces are allowed- example: myblog"
    );
    exit 0;
}
my $mysql_admin_user =
  readCleanLine("MySQL administrative user - default if left empty: root");
if ( $mysql_admin_user eq '' ) {
    $mysql_admin_user = 'root';
}
my $mysql_admin_password =
  readCleanLine("MySQL administrative password - default: (empty)");
my $dnsname = readCleanLine(
"DNS domain name, required to configure the webserver, webserver configuration will be skipped if left empty.\nExample: myblog.domain.com"
);
$dnsname =~ s/\ //g;

#TODO: Check input

my $cmdmysql = "mysql -u$mysql_admin_user";
unless ( $mysql_admin_password eq '' ) {
    $cmdmysql .= " -p$mysql_admin_password";
}
$cmdmysql .= " -Bse ";
echoLine($cmdmysql);
my $db_user     = $instance_name;
my $db_password = randomPassword();
my $db_name     = $instance_name;

if ( $dbserver eq 'mysql' ) {

    #Create DB
    my $sql = "CREATE DATABASE $db_name;
  GRANT ALL PRIVILEGES ON $db_name.* TO \"$db_user\"@\"localhost\" IDENTIFIED BY \"$db_password\";
  FLUSH PRIVILEGES;";

    echoLine("SQL Command: $sql");
    my $sqlresult = system("$cmdmysql '$sql'");
    echoLine("SQL Result: $sqlresult");
    unless ( $sqlresult == 0 ) {
        die("Something went wrong creating the DB. Check your credentials!");
    }
}

chdir($tempdir);

# Download the tar
echoTitle("Downloading newest Wordpress version from $downloadurl");
`wget -O $downloadto $downloadurl`;

# Untar
`tar xzf $downloadto`;

# Move instance
my $instance_path = $workdir . $instance_name;
system("mv $tempnewinstance $instance_path");

chdir($instance_path);

# Fix perms
#FIXME: All dir could belong to web user
system("chown -R $webuser:$webgroup $instance_path/wp-content");
system("chmod +x $workdir $instance_path");

#Get salts
my $tempsalts = $tempdir . 'tempsalts.txt';
`wget -O $tempsalts $saltsurl`;
my $salts = `cat  $tempsalts`;
unlink($tempsalts);

# Write config file
my $wpconfigfile = $instance_path . '/wp-config.php';

echoLine("Writting WP config file in $wpconfigfile");
open( WPCONF, "> $wpconfigfile" );
print WPCONF "<?php
/**
 * The base configurations of the WordPress.
 *
 * This file has the following configurations: MySQL settings, Table Prefix,
 * Secret Keys, WordPress Language, and ABSPATH. You can find more information
 * by visiting {\@link http://codex.wordpress.org/Editing_wp-config.php Editing
 * wp-config.php} Codex page. You can get the MySQL settings from your web host.
 *
 * This file is used by the wp-config.php creation script during the
 * installation. You don't have to use the web site, you can just copy this file
 * to \"wp-config.php\" and fill in the values.
 *
 * \@package WordPress
 */

// ** MySQL settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define('DB_NAME', '$db_name');

/** MySQL database username */
define('DB_USER', '$db_user');

/** MySQL database password */
define('DB_PASSWORD', '$db_password');

/** MySQL hostname */
define('DB_HOST', 'localhost');

/** Database Charset to use in creating database tables. */
define('DB_CHARSET', 'utf8');

/** The Database Collate type. Don't change this if in doubt. */
define('DB_COLLATE', '');

/**#\@+
 * Authentication Unique Keys and Salts.
 *
 * Change these to different unique phrases!
 * You can generate these using the {\@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}
 * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.
 *
 * \@since 2.6.0
 */
$salts

/**#\@-*/

/**
 * WordPress Database Table prefix.
 *
 * You can have multiple installations in one database if you give each a unique
 * prefix. Only numbers, letters, and underscores please!
 */
\$table_prefix  = 'wp_';

/**
 * WordPress Localized Language, defaults to English.
 *
 * Change this to localize WordPress. A corresponding MO file for the chosen
 * language must be installed to wp-content/languages. For example, install
 * de_DE.mo to wp-content/languages and set WPLANG to 'de_DE' to enable German
 * language support.
 */
define('WPLANG', '');

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 */
define('WP_DEBUG', false);

/* That's all, stop editing! Happy blogging. */

/** Absolute path to the WordPress directory. */
if ( !defined('ABSPATH') )
	define('ABSPATH', dirname(__FILE__) . '/');

/** Sets up WordPress vars and included files. */
require_once(ABSPATH . 'wp-settings.php');
";
close(WPCONF);

# Create Web server configuration
unless ( $dnsname eq '' ) {
    if ( $server eq 'nginx' ) {
        my $filename        = $instance_name . '.conf';
        my $conffile        = $nginxconfdir . $filename;
        my $confenabledfile = $nginxenabledconfdir . $filename;
        echoLine("Writting $server config file in $conffile");
        open( NGINXCONF, "> $conffile" );
        print NGINXCONF "server {
  listen 80;
  root $instance_path;
  index index.php index.html index.htm;
  server_name $dnsname;
  access_log /var/log/nginx/$dnsname.access.log;
  error_log /var/log/nginx/$dnsname.error.log;
  
  location / {
    try_files \$uri \$uri/ /index.php?q=\$uri&\$args;
  }
  error_page 404 /404.html;
  error_page 500 502 503 504 /50x.html;
  location = /50x.html {
    root /usr/share/nginx/www;
  }
  # pass the PHP scripts to php5 fpm
  location ~ \.php\$ {
    # With php5-fpm:
    fastcgi_pass unix:/var/run/php5-fpm.sock;
    fastcgi_index index.php;
    include fastcgi_params;
  }
  location = /favicon.ico {
    log_not_found off;
    access_log off;
  }
  
  location = /robots.txt {
    allow all;
    log_not_found off;
    access_log off;
  }
  location ~* \.(js|css|png|jpg|jpeg|gif|ico)\$ {
    expires max;
    log_not_found off;
  }
}
";
        close(NGINXCONF);

        #Enable conf
        system("ln -s $conffile $confenabledfile");
        system("service nginx restart");
        my $defconf = $nginxenabledconfdir . 'default';
        if ( -f $defconf ) {
            echoWarn(
"The default configuration is enabled. It may prevent your site from working by showing you the message \"Welcome to nginx!\". You can disabled it with:\n    rm $defconf\n    service nginx restart"
            );
        }
    }

    if ( $server eq 'apache2' ) {

        my $phpfpmconffile = $apacheextraconfdir . 'php5-fpm.conf';
        unless ( -f $phpfpmconffile ) {

            #PHP5-FPM is not configured
            echoWarn(
"Could not find PHP5-FPM configuration in $phpfpmconffile, creating it now. If you already configured FPM and Apache2 wont start anymore, please remove the file with:\n"
                  . addSudo
                  . " rm $phpfpmconffile" );
            echoLine("Writting PHP5-FPM config file in $phpfpmconffile");
            open( PHPFPMCONF, "> $phpfpmconffile" );
            print PHPFPMCONF
'# Configuration courtesy of http://www.queryadmin.com/506/apache2-php5-fpm-fastcgi-apc-debian-wheezy/
# Configure all that stuff needed for using PHP-FPM as FastCGI
# Set handlers for PHP files.
# application/x-httpd-php                        phtml pht php
# application/x-httpd-php3                       php3
# application/x-httpd-php4                       php4
# application/x-httpd-php5                       php
<FilesMatch ".+\.ph(p[345]?|t|tml)$">
    SetHandler application/x-httpd-php
</FilesMatch>
 
# application/x-httpd-php-source                 phps
<FilesMatch ".+\.phps$">
    SetHandler application/x-httpd-php-source
    # Deny access to raw php sources by default
    # To re-enable it\'s recommended to enable access to the files
    # only in specific virtual host or directory
    Order Deny,Allow
    Deny from all
</FilesMatch>
 
# Deny access to files without filename (e.g. \'.php\')
<FilesMatch "^\.ph(p[345]?|t|tml|ps)$">
    Order Deny,Allow
    Deny from all
</FilesMatch>
 
# Define Action and Alias needed for FastCGI external server.
Action application/x-httpd-php /fcgi-bin/php5-fpm virtual
Alias /fcgi-bin/php5-fpm /fcgi-bin-php5-fpm
<Location /fcgi-bin/php5-fpm>
  # here we prevent direct access to this Location url,
  # env=REDIRECT_STATUS will let us use this fcgi-bin url
  # only after an internal redirect (by Action upper)
  Order Deny,Allow
  Deny from All
  Allow from env=REDIRECT_STATUS
</Location>
 
FastCgiExternalServer /fcgi-bin-php5-fpm -socket /var/run/php5-fpm.sock -pass-header Authorization
';
        }
        my $filename        = $instance_name . '.vhost';
        my $conffile        = $apacheconfdir . $filename;
        my $confenabledfile = $apacheenabledconfdir . $filename;
        echoLine("Writting $server config file in $conffile");
        open( APACHECONF, "> $conffile" );
        print APACHECONF "<VirtualHost *:80>
    ServerAdmin $serveradmin
    ServerName $dnsname

    DocumentRoot $instance_path
    
    FastCgiExternalServer /var/www/php5.external -host 127.0.0.1:9000
    AddHandler php5-fcgi .php
    Action php5-fcgi /usr/lib/cgi-bin/php5.external
    
    <Directory />
        Options FollowSymLinks
        AllowOverride None
    </Directory>
    <Directory $instance_path>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
    </Directory>

    ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/
    <Directory \"/usr/lib/cgi-bin\">
        AllowOverride None
        Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
        Order allow,deny
        Allow from all
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$dnsname.error.log

    # Possible values include: debug, info, notice, warn, error, crit,
    # alert, emerg.
    LogLevel warn

    CustomLog \${APACHE_LOG_DIR}/$dnsname.access.log combined
</VirtualHost>
";
        close(APACHECONF);

        #Enable modules
        system( addSudo . 'a2enmod actions fastcgi rewrite' );

        #Enable conf
        system( addSudo . "ln -s $conffile $confenabledfile" );
        my $restartApache = addSudo . "service apache2 restart";
        system($restartApache);
        my $defconf = $apacheenabledconfdir . '000-default';
        if ( -f $defconf ) {
            echoWarn(
"The default configuration is enabled.\nIt may prevent your site from working by showing you the message \"It works!\". You can disabled it with:\n   "
                  . addSudo
                  . " rm $defconf\n    $restartApache" );
        }
    }
    echoTitle(
"Your installation should be available:\n    http://$dnsname/ OR http://$ip/\n!Go to setup your instance now before someone else does!\nNote that you have to take care of DNS setup yourself"
    );
}
else {
    echoLine("No DNS name specified, skipping server configuration");
}

echoLine("Finished!");

#!/usr/bin/perl -w

use strict;
use warnings;

##################
##### CONFIG #####
##################
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
##################
## CLI switches ##
##################
my $switch;
$switch = shift;
if ( $switch and $switch eq "-h" ) {
    die("Help");
    exit 0;
}
##################
##### Checks #####
##################
unless ( `dpkg --get-selections | grep ca-certificates | wc -l` > 0 ) {
    die(
"It'n not possible to safely download salts without ca-certificates package. Please install it:\n    apt-get install ca-certificates"
    );
}

# Check server installed
if ( `dpkg --get-selections | grep apache2 | wc -l` > 0 ) {
    $server = 'apache2';
}
else {
    if ( `dpkg --get-selections | grep nginx | wc -l` > 0 ) {
        $server = 'nginx';
    }
    else {
        echoWarn(
"No web server detected\nYou may want to install Apache2:\n    apt-get install apache2\nOR you can also choose to use nginx:\n    apt-get install nginx\n"
        );
    }
}
unless ( `dpkg --get-selections | grep php5-fpm | wc -l` > 0 ) {
    echoWarn(
"PHP5 FPM is not installed, you may want to install it:\n    apt-get install php5-fpm php5-mysql"
    );
}
unless ( `dpkg --get-selections | grep php5-mysql | wc -l` > 0 ) {
    echoWarn(
"php5-mysql is not installed, you may want to install it:\n    apt-get install php5-mysql"
    );
}

unless ( $server eq '' ) {
    echoLine("Webserver detected: {$server}");
}

if ( `dpkg --get-selections | grep mysql-server | wc -l` > 0 ) {
    $dbserver = 'mysql';
    echoLine("DB detected: {$dbserver}");
}
else {
    echoTitle(
"MySQL server not installed. DB wont be created. MySQL can be installed with:\n    apt-get install mysql-server\n"
    );
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
my $dnsname =~ s/\ //g;

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
print WPCONF
"<?php\n/**\n * The base configurations of the WordPress.\n *\n * This file has the following configurations: MySQL settings, Table Prefix,\n * Secret Keys, WordPress Language, and ABSPATH. You can find more information\n * by visiting {\@link http://codex.wordpress.org/Editing_wp-config.php Editing\n * wp-config.php} Codex page. You can get the MySQL settings from your web host.\n *\n * This file is used by the wp-config.php creation script during the\n * installation. You don't have to use the web site, you can just copy this file\n * to \"wp-config.php\" and fill in the values.\n *\n * \@package WordPress\n */\n\n// ** MySQL settings - You can get this info from your web host ** //\n/** The name of the database for WordPress */\ndefine('DB_NAME', '$db_name');\n\n/** MySQL database username */\ndefine('DB_USER', '$db_user');\n\n/** MySQL database password */\ndefine('DB_PASSWORD', '$db_password');\n\n/** MySQL hostname */\ndefine('DB_HOST', 'localhost');\n\n/** Database Charset to use in creating database tables. */\ndefine('DB_CHARSET', 'utf8');\n\n/** The Database Collate type. Don't change this if in doubt. */\ndefine('DB_COLLATE', '');\n\n/**#\@+\n * Authentication Unique Keys and Salts.\n *\n * Change these to different unique phrases!\n * You can generate these using the {\@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}\n * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.\n *\n * \@since 2.6.0\n */\n$salts\n\n/**#\@-*/\n\n/**\n * WordPress Database Table prefix.\n *\n * You can have multiple installations in one database if you give each a unique\n * prefix. Only numbers, letters, and underscores please!\n */\n\$table_prefix  = 'wp_';\n\n/**\n * WordPress Localized Language, defaults to English.\n *\n * Change this to localize WordPress. A corresponding MO file for the chosen\n * language must be installed to wp-content/languages. For example, install\n * de_DE.mo to wp-content/languages and set WPLANG to 'de_DE' to enable German\n * language support.\n */\ndefine('WPLANG', '');\n\n/**\n * For developers: WordPress debugging mode.\n *\n * Change this to true to enable the display of notices during development.\n * It is strongly recommended that plugin and theme developers use WP_DEBUG\n * in their development environments.\n */\ndefine('WP_DEBUG', false);\n\n/* That's all, stop editing! Happy blogging. */\n\n/** Absolute path to the WordPress directory. */\nif ( !defined('ABSPATH') )\n	define('ABSPATH', dirname(__FILE__) . '/');\n\n/** Sets up WordPress vars and included files. */\nrequire_once(ABSPATH . 'wp-settings.php');\n";
close(WPCONF);

# Create Web server configuration
unless ( $dnsname eq '' ) {
    if ( $server eq 'nginx' ) {
        my $filename        = $instance_name . '.conf';
        my $conffile        = $nginxconfdir . $filename;
        my $confenabledfile = $nginxenabledconfdir . $filename;
        echoLine("Writting $server config file in $conffile");
        open( NGINXCONF, "> $conffile" );
        print NGINXCONF
"server {\n  listen 80;\n  root $instance_path;\n  index index.php index.html index.htm;\n  server_name $dnsname;\n  access_log /var/log/nginx/$dnsname.access.log;\n  error_log /var/log/nginx/$dnsname.error.log;\n  \n  location / {\n    try_files \$uri \$uri/ /index.php?q=\$uri&\$args;\n  }\n  error_page 404 /404.html;\n  error_page 500 502 503 504 /50x.html;\n  location = /50x.html {\n    root /usr/share/nginx/www;\n  }\n  # pass the PHP scripts to php5 fpm\n  location ~ \.php\$ {\n    # With php5-fpm:\n    fastcgi_pass unix:/var/run/php5-fpm.sock;\n    fastcgi_index index.php;\n    include fastcgi_params;\n  }\n  location = /favicon.ico {\n    log_not_found off;\n    access_log off;\n  }\n  \n  location = /robots.txt {\n    allow all;\n    log_not_found off;\n    access_log off;\n  }\n  location ~* \.(js|css|png|jpg|jpeg|gif|ico)\$ {\n    expires max;\n    log_not_found off;\n  }\n}\n";
        close(NGINXCONF);

        #Enable conf
        system("ln -s $conffile $confenabledfile");
        system("service nginx restart");
        my $defconf = $nginxenabledconfdir . 'default';
        if ( -f $defconf ) {
            echoWarn(
"The default configuration is enabled. It may prevent your site from working. You can disabled it with:\n    rm $defconf\n    service nginx restart"
            );
        }
        echoTitle(
            "Your installation should be available:\n    http://$dnsname/");
    }
    if ( $server eq 'apache2' ) {
        my $filename        = $instance_name . '.vhost';
        my $conffile        = $apacheconfdir . $filename;
        my $confenabledfile = $apacheenabledconfdir . $filename;
        echoLine("Writting $server config file in $conffile");
        open( APACHECONF, "> $conffile" );
        print APACHECONF "<VirtualHost *:80>
    ServerAdmin $serveradmin
    ServerName $dnsname

    DocumentRoot $instance_path
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

        #Enable conf
        system("ln -s $conffile $confenabledfile");
        system("service apache2 restart");
        my $defconf = $apacheenabledconfdir . 'default';
        if ( -f $defconf ) {
            echoWarn(
"The default configuration is enabled.\nIt may prevent your site from working by showing you the message \"Welcome to nginx!\". You can disabled it with:\n    rm $defconf\n    apache2ctrl restart"
            );
        }
        echoTitle(
            "Your installation should be available:\n    http://$dnsname/");
    }
}
else {
    echoLine("No DNS name specified, skipping server configuration");
}

echoLine("Finished!");

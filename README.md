#Wordpress Silex

WP Silex is a Perl script that helps to deploys Wordpress in seconds.
Still beta, use at your own risk! But you're welcome to help improve it!

## What it does

Makes you install proper packages.
Downloads latest Wordpress version.
Creates the database (MySQL).
Configures Wordpress and the web server (Apache2 or Nginx)

## Compatibility

### Database

* MySQL

### Web Server

* Apache2 (Lacks testing!)
* Nginx (Prefered)

### Operating System

Should be compatible with:
* Debian 6 to Debian 8

Tested on Debian 7.4 (Wheezy) minimal

## Installation

### Debian

As a root user:

```
wget https://raw.githubusercontent.com/martin-denizet/wp_silex/master/silex.pl
chmod +x silex.pl
./silex.pl
```

### Ubuntu

As a root user:

```
wget https://raw.githubusercontent.com/martin-denizet/wp_silex/master/silex.pl
chmod +x silex.pl
sudo ./silex.pl
```
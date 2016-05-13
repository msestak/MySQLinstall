# NAME

MySQLinstall - is installation script (modulino) that installs MySQL::Sandbox using cpanm, MySQL in a sandbox, additional engines like TokuDB and Deep and updates configuration. If you want to install newer Perl on your machine you can use ["To install Perl use Perlinstall.pm."](#to-install-perl-use-perlinstall-pm)

# SYNOPSIS

    MySQLinstall.pm --mode=install_sandbox --sandbox=/msestak/sandboxes/ --opt=/msestak/opt/mysql/

    MySQLinstall.pm --mode=wget_mysql -url http://downloads.mysql.com/archives/get/file/mysql-5.6.29-linux-glibc2.5-x86_64.tar.gz
    MySQLinstall.pm --mode=wget_mysql -url https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.29-76.2/binary/tarball/Percona-Server-5.6.29-rel76.2-Linux.x86_64.ssl101.tar.gz

    MySQLinstall.pm --mode=install_mysql --infile=mysql-5.6.29-linux-glibc2.5-x86_64.tar.gz

    MySQLinstall.pm --mode=install_mysql_with_prefix --prefix=deep_ --infile=mysql-5.6.28-linux-glibc2.5-x86_64.tar.gz
    MySQLinstall.pm --mode=install_mysql_with_prefix --prefix=tokudb_ --infile=Percona-Server-5.6.29-rel76.2-Linux.x86_64.ssl101.tar.gz

    MySQLinstall.pm --mode=edit_tokudb --optedit=/home/msestak/opt/mysql/5.6.25/ --sandedit=/home/msestak/sandboxes/msb_5_6_25/

    MySQLinstall.pm --mode=edit_deep -i deep-mysql-5.6.25-community-plugin-3.2.0.19654-1.el6.x86_64.rpm --sand=/msestak/sandboxes/msb_5_6_25/ --opt=/msestak/opt/mysql/5.6.25/
    or with reporting
    MySQLinstall.pm --mode=edit_deep_report -i ./download/deep-mysql-5.6.26-community-plugin-3.2.0.19896.el6.x86_64.tar.gz --sand=/home/msestak/sandboxes/msb_5_6_26 --opt=/home/msestak/opt/mysql/5.6.26

# DESCRIPTION

MySQLinstall is installation script that installs MySQL::Sandbox using cpanm, MySQL in a sandbox, additional engines like TokuDB and Deep and updates configuration for MySQL.

    --mode=mode                            Description
    --mode=install_sandbox         installs MySQL::Sandbox and prompts for modification of .bashrc
    --mode=wget_mysql                      downloads MySQL from Oracle or Percona serer from Percona site
    --mode=install_mysql           installs MySQL and modifies my.cnf for performance
    --mode=edit_deep_report        installs Deep plugin
    --mode=edit_tokudb                     installs TokuDB plugin
    
    For help write:
    MySQLinstall.pm -h
    MySQLinstall.pm -m

## MODES

- install\_sandbox

        # options from command line
        MySQLinstall.pm --mode=install_sandbox --sandbox=$HOME/sandboxes/ --opt=$HOME/opt/mysql/

        # options from config
        MySQLinstall.pm --mode=install_sandbox

    Install MySQL::Sandbox, set environment variables (SANDBOX\_HOME and SANBOX\_BINARY) and create these directories if needed.

- wget\_mysql

        #option from command line (can also come from config)
        MySQLinstall.pm --mode=wget_mysql --url http://dev.mysql.com/get/Downloads/MySQL-5.6/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz

    Downloads MySQL binary from internet link. Resumes broken downloads.

- install\_mysql

        #option from command line (can also come from config)
        MySQLinstall.pm --mode=install_mysql --infile mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz

    Installs MySQL in sandbox named after MySQL version and puts binary into "opt/mysql" directory. It rewrites existing installation.

- install\_mysql\_with\_prefix

        MySQLinstall.pm --mode=install_mysql_with_prefix --prefix=deep_ --infile=mysql-5.6.28-linux-glibc2.5-x86_64.tar.gz
        MySQLinstall.pm --mode=install_mysql_with_prefix --prefix=tokudb_ --infile=Percona-Server-5.6.29-rel76.2-Linux.x86_64.ssl101.tar.gz

    Installs MySQL with port checking and prefix. It doesn't rewrite previous MySQL instance. Useful for installing multiple MySQL servers with same version but different storage engines.

- edit\_tokudb

        MySQLinstall.pm --mode=edit_tokudb --sandedit=/home/msestak/sandboxes/msb_5_6_27 --optedit=/home/msestak/opt/mysql/5.6.27

    Installs TokuDB storage engine if transparent\_hugepage=never is already set. It also updates MySQL config for TokuDB setting it as default\_storage\_engine (and for tmp tables too).

- edit\_deep\_report

        MySQLinstall.pm --mode=edit_deep_report --infile=./download/deep-mysql-5.6.26-community-plugin-3.2.0.19896.el6.x86_64.tar.gz --sandedit=/home/msestak/sandboxes/msb_5_6_27 --optedit=/home/msestak/opt/mysql/5.6.27

    Installs Deep storage engine from downloaded tar.gz archive. It also updates MySQL config for Deep setting it as default\_storage\_engine (and for tmp tables too).

- install\_scaledb

        # not finished (doesn't work)
        MySQLinstall.pm --mode=install_scaledb -if /home/msestak/scaledb-15.10.1-mariadb-10.0.14.tgz --prefix=scaledb_ --plugin=/home/msestak/scaledb-15.10.1-13199-ude.tgz

    Installs MariaDB with ScaleDB storage engine from downloaded tar.gz archive. It also updates MySQL config for ScaleDB setting it as default\_storage\_engine (and for tmp tables too).

# CONFIGURATION

All configuration in set in mysqlinstall.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows [Config::Std](https://metacpan.org/pod/Config::Std) format and rules.
Example:

    [General]
    sandbox  = /home/msestak/sandboxes
    opt      = /home/msestak/opt/mysql
    #url      = http://downloads.mysql.com/archives/get/file/mysql-5.6.29-linux-glibc2.5-x86_64.tar.gz
    #url      = https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.29-76.2/binary/tarball/Percona-Server-5.6.29-rel76.2-Linux.x86_64.ssl101.tar.gz
    #out      = /msestak/gitdir/MySQLinstall
    #infile   = mysql-5.6.29-linux-glibc2.5-x86_64.tar.gz
    #infile   = Percona-Server-5.6.29-rel76.2-Linux.x86_64.ssl101.tar.gz
    #sandedit = /home/msestak/sandboxes/msb_5_6_29
    #optedit  = /home/msestak/opt/mysql/5.6.29
    #plugin   = /home/msestak/scaledb-15.10.1-13199-ude.tgz
    
    [Database]
    host     = localhost
    database = test
    user     = msandbox
    password = msandbox
    port     = 5629
    socket   = /tmp/mysql_sandbox5629.sock
    innodb   = 1G
    prefix   = tokudb_
    #prefix   = deep_

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

mocnii <msestak@irb.hr>

# POD ERRORS

Hey! **The above document had some coding errors, which are explained below:**

- Around line 2080:

    Unterminated L< ... > sequence

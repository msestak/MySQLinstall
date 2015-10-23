# NAME

MySQLinstall - It's new $module

# SYNOPSIS

    perl install_mysql_within_sandbox.pl --mode=install_perl

    perl install_mysql_within_sandbox.pl --mode=install_sandbox --sandbox=/msestak/sandboxes/ --opt=/msestak/opt/mysql/

    perl install_mysql_within_sandbox.pl --mode=wget_mysql -url http://dev.mysql.com/get/Downloads/MySQL-5.5/mysql-5.5.43-linux2.6-x86_64.tar.gz

    perl install_mysql_within_sandbox.pl --mode=wget_percona -url https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.24-72.2/binary/tarball/Percona-Server-5.6.24-rel72.2-Linux.x86_64.ssl101.tar.gz -url_tokudb https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.24-72.2/binary/tarball/Percona-Server-5.6.24-rel72.2-TokuDB.Linux.x86_64.ssl101.tar.gz

    perl ./bin/install_mysql_within_sandbox.pl --mode=install_mysql -i ./download/mysql-5.6.26-linux-glibc2.5-x86_64.tar.gz
    perl ./bin/install_mysql_within_sandbox.pl --mode=install_mysql --in=./download/Percona-Server-5.6.25-rel73.1-Linux.x86_64.ssl101.tar.gz

    perl ./bin/install_mysql_within_sandbox.pl --mode=edit_tokudb --opt=/home/msestak/opt/mysql/5.6.25/ --sand=/home/msestak/sandboxes/msb_5_6_25/

    perl install_mysql_within_sandbox.pl --mode=edit_deep -i deep-mysql-5.6.25-community-plugin-3.2.0.19654-1.el6.x86_64.rpm --sand=/msestak/sandboxes/msb_5_6_25/ --opt=/msestak/opt/mysql/5.6.25/
    or with reporting
    perl ./bin/install_mysql_within_sandbox.pl --mode=edit_deep_report -i ./download/deep-mysql-5.6.26-community-plugin-3.2.0.19896.el6.x86_64.tar.gz --sand=/home/msestak/sandboxes/msb_5_6_26 --opt=/home/msestak/opt/mysql/5.6.26

# DESCRIPTION

MySQLinstall is ...

    --mode=mode                            Description
    --mode=install_perl            installs latest Perl with perlenv and cpanm
    --mode=install_sandbox         installs MySQL::Sandbox and prompts for modification of .bashrc
    --mode=wget_mysql                      downloads MySQL from Oracle
    --mode=wget_percona            downloads Percona Server with TokuDB
    --mode=install_mysql           installs MySQL and modifies my.cnf for performance
    --mode=edit_deep_report        installs TokuDB plugin
    --mode=edit_tokudb                     installs Deep plugin
    
    For help write:
    perl install_mysql_within_sandbox.pl -h
    perl install_mysql_within_sandbox.pl -m

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

mocnii <msestak@irb.hr>

# EXAMPLE
 perl ./bin/install\_mysql\_within\_sandbox.pl --mode=install\_mysql --in=./download/Percona-Server-5.6.25-rel73.1-Linux.x86\_64.ssl101.tar.gz
 perl ./bin/install\_mysql\_within\_sandbox.pl --mode=edit\_tokudb --opt=/home/msestak/opt/mysql/5.6.25/ --sand=/home/msestak/sandboxes/msb\_5\_6\_25/

    perl install_mysql_within_sandbox.pl --mode=install_mysql -i mysql-5.6.24-linux-glibc2.5-x86_64.tar.gz
    perl install_mysql_within_sandbox.pl --mode=edit_deep -i deep-mysql-5.6.24-community-plugin-3.2.0.19297-1.el6.x86_64.rpm --sand=/msestak/sandboxes/msb_5_6_24/ --opt=/msestak/opt/mysql/5.6.24/

    perl install_mysql_within_sandbox.pl --mode=install_mysql -i mysql-5.6.24-linux-glibc2.5-x86_64.tar.gz
    perl install_mysql_within_sandbox.pl --mode=edit_deep_report -i deep-mysql-5.6.24-community-plugin-3.2.0.19654.el6.x86_64.tar.gz --sand=/msestak/sandboxes/msb_5_6_24/ --opt=/msestak/opt/mysql/5.6.24/

    [msestak@tiktaalik benchmark_mysql]$ perl ./bin/install_mysql_within_sandbox.pl --mode=install_mysql -i ./download/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz
    [msestak@tiktaalik benchmark_mysql]$ perl ./bin/install_mysql_within_sandbox.pl --mode=edit_deep_report -i ./download/deep-mysql-5.6.27-community-plugin-3.3.0.20340.el6.x86_64.tar.gz --sand=/home/msestak/sandboxes/msb_5_6_27/ --opt=/home/msestak/opt/mysql/5.6.27/

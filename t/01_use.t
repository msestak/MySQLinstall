#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

my $module = 'MySQLinstall';
my @subs = qw( 
  run
  init_logging
  get_parameters_from_cmd
  _capture_output
  _exec_cmd
  install_sandbox
  wget_mysql
  install_mysql
  install_mysql_with_prefix
  edit_tokudb
  edit_deep_report

);

use_ok( $module, @subs);

foreach my $sub (@subs) {
    can_ok( $module, $sub);
}

done_testing();

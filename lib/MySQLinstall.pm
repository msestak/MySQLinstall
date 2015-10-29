#!/usr/bin/env perl
package MySQLinstall;

use 5.010001;
use strict;
use warnings;
use File::Spec::Functions qw(:ALL);
use Carp;
use Getopt::Long;
use Pod::Usage;
use Capture::Tiny qw/capture/;
use Data::Dumper;
#use Regexp::Debugger;
use Log::Log4perl;
use File::Find::Rule;
use IO::Prompter;
use Config::Std { def_sep => '=' };   #MySQL uses =

our $VERSION = "0.01";

our @EXPORT_OK = qw{
  run
  init_logging
  get_parameters_from_cmd

};

#MODULINO - works with debugger too
run() if !caller() or (caller)[0] eq 'DB';

### INTERFACE SUB starting all others ###
# Usage      : main();
# Purpose    : it starts all other subs and entire modulino
# Returns    : nothing
# Parameters : none (argument handling by Getopt::Long)
# Throws     : lots of exceptions from logging
# Comments   : start of entire module
# See Also   : n/a
sub run {
    croak 'main() does not need parameters' unless @_ == 0;

    #first capture parameters to enable verbose flag for logging
    my ($param_href) = get_parameters_from_cmd();

    #preparation of parameters
    my $verbose    = $param_href->{verbose};
    my $quiet      = $param_href->{quiet};
    my @mode     = @{ $param_href->{mode} };
	my $URL      = $param_href->{url};
	my $OPT      = $param_href->{opt};
    my $SANDBOX = $param_href->{sandbox};
    my $INFILE   = $param_href->{infile};
    my $OUT      = $param_href->{out};   #not used
    my $HOST     = $param_href->{host};
    my $DATABASE = $param_href->{database};   #not used
    my $USER     = $param_href->{user};
    my $PASSWORD = $param_href->{password};
    my $PORT     = $param_href->{port};
    my $SOCKET   = $param_href->{socket};

    #start logging for the rest of program (without capturing of parameters)
    init_logging($verbose);
    ##########################
    # ... in some function ...
    ##########################
    my $log = Log::Log4perl::get_logger("main");

    # Logs both to Screen and File appender
    $log->info("This is start of logging for $0");
    $log->trace("This is example of trace logging for $0");

    #get dump of param_href if -v (verbose) flag is on (for debugging)
    my $dump_print = sprintf( Dumper($param_href) ) if $verbose;
    $log->debug( '$param_href = ', "$dump_print" ) if $verbose;

    #call write modes (different subs that print different jobs)
	my %dispatch = (
        install_perl             => \&install_perl,                  #using perlenv
        install_sandbox          => \&install_sandbox,               #and create dirs
        wget_mysql               => \&wget_mysql,                    #from mysql
        wget_percona             => \&wget_percona_with_tokudb,      #from percona
        install_mysql            => \&install_mysql,                 #edit also general options in my.cnf for InnoDB
        edit_tokudb              => \&edit_tokudb,                   #not implemented
        edit_deep                => \&edit_deep,                     #edit my.cnf for Deep engine and install it
        edit_deep_report         => \&edit_deep_report,              #edit my.cnf for Deep engine and install it (with reporting to deep.is)

    );

    foreach my $mode (@mode) {
        if ( exists $dispatch{$mode} ) {
            $log->info("RUNNING ACTION for mode: ", $mode);

            $dispatch{$mode}->( $param_href );

            $log->info("TIME when finished for: $mode");
        }
        else {
            #complain if mode misspelled or just plain wrong
            $log->logcroak( "Unrecognized mode --mode={$mode} on command line thus aborting");
        }
    }

    return;
}

### INTERNAL UTILITY ###
# Usage      : my ($param_href) = get_parameters_from_cmd();
# Purpose    : processes parameters from command line
# Returns    : $param_href --> hash ref of all command line arguments and files
# Parameters : none -> works by argument handling by Getopt::Long
# Throws     : lots of exceptions from die
# Comments   : it starts logger at start
# See Also   : init_logging()
sub get_parameters_from_cmd {

    #no logger here
	# setup config file location
	my ($volume, $dir_out, $perl_script) = splitpath( $0 );
	$dir_out = rel2abs($dir_out);
    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};
	$app_name = lc $app_name;
    my $config_file = catfile($volume, $dir_out, $app_name . '.cnf' );
	$config_file = canonpath($config_file);

	#read config to setup defaults
	read_config($config_file => my %config);
	#print 'config:', Dumper(\%config);
	#push all options into one hash no matter the section
	my %opts;
	foreach my $key (keys %config) {
		%opts = (%opts, %{ $config{$key} });
	}
	#say 'opts:', Dumper(\%opts);

	#cli part
	my @arg_copy = @ARGV;
	my (%cli, @mode);
	$cli{quiet} = 0;
	$cli{verbose} = 0;

	#mode, quiet and verbose can only be set on command line
    GetOptions(
        'help|h'        => \$cli{help},
        'man|m'         => \$cli{man},
        'url=s'         => \$cli{url},
        'sandbox|sand=s'=> \$cli{sandbox},
        'opt=s'         => \$cli{opt},

        'infile|if=s'   => \$cli{infile},
        'out|o=s'       => \$cli{out},
        'host|h=s'      => \$cli{host},
        'database|d=s'  => \$cli{database},
        'user|u=s'      => \$cli{user},
        'password|p=s'  => \$cli{password},
        'port|po=i'     => \$cli{port},
        'socket|s=s'    => \$cli{socket},
        'mode|mo=s{1,}' => \$cli{mode},       #accepts 1 or more arguments
        'quiet|q'       => \$cli{quiet},      #flag
        'verbose+'      => \$cli{verbose},    #flag
    ) or pod2usage( -verbose => 1 );

	#you can specify multiple modes at the same time
	@mode = split( /,/, $cli{mode} );
	$cli{mode} = \@mode;
	die 'No mode specified on command line' unless $cli{mode};
	
	pod2usage( -verbose => 1 ) if $cli{help};
	pod2usage( -verbose => 2 ) if $cli{man};
	
	#if not -q or --quit print all this (else be quiet)
	if ($cli{quiet} == 0) {
		print STDERR 'My @ARGV: {', join( "} {", @arg_copy ), '}', "\n";
		#no warnings 'uninitialized';
		print STDERR 'Extra options from config: {', join( "} {", %opts), '}', "\n";
	
		if ($cli{infile}) {
			say 'My input file: ', canonpath($cli{infile});
			$cli{infile} = rel2abs($cli{infile});
			$cli{infile} = canonpath($cli{infile});
			say "My absolute input file: $cli{infile}";
		}
		if ($cli{out}) {
			say 'My output path: ', canonpath($cli{out});
			$cli{out} = rel2abs($cli{out});
			$cli{out} = canonpath($cli{out});
			say "My absolute output path: $cli{out}";
		}
	}
	else {
		$cli{verbose} = -1;   #and logging is OFF
	}
	
	#insert config values into cli options if cli is not present on command line
	foreach my $key (keys %cli) {
		if ( ! defined $cli{$key} ) {
			$cli{$key} = $opts{$key};
		}
	}

    return ( \%cli );
}


### INTERNAL UTILITY ###
# Usage      : init_logging();
# Purpose    : enables Log::Log4perl log() to Screen and File
# Returns    : nothing
# Parameters : doesn't need parameters (logfile is in same directory and same name as script -pl +log
# Throws     : croaks if it receives parameters
# Comments   : used to setup a logging framework
# See Also   : Log::Log4perl at https://metacpan.org/pod/Log::Log4perl
sub init_logging {
    croak 'init_logging() needs verbose parameter' unless @_ == 1;
    my ($verbose) = @_;

    #create log file in same dir where script is running
	#removes perl script and takes absolute path from rest of path
	my ($volume,$dir_out,$perl_script) = splitpath( $0 );
	#say '$dir_out:', $dir_out;
	$dir_out = rel2abs($dir_out);
	#say '$dir_out:', $dir_out;

    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};   #takes name of the script and removes .pl or .pm or .t
    #say '$app_name:', $app_name;
    my $logfile = catfile( $volume, $dir_out, $app_name . '.log' );    #combines all of above with .log
	#say '$logfile:', $logfile;
	$logfile = canonpath($logfile);
	#say '$logfile:', $logfile;

    #colored output on windows
    my $osname = $^O;
    if ( $osname eq 'MSWin32' ) {
        require Win32::Console::ANSI;                                 #require needs import
        Win32::Console::ANSI->import();
    }

    #enable different levels based on verbose flag
    my $log_level;
    if    ($verbose == 0)  { $log_level = 'INFO';  }
    elsif ($verbose == 1)  { $log_level = 'DEBUG'; }
    elsif ($verbose == 2)  { $log_level = 'TRACE'; }
    elsif ($verbose == -1) { $log_level = 'OFF';   }
	else                   { $log_level = 'INFO';  }

    #levels:
    #TRACE, DEBUG, INFO, WARN, ERROR, FATAL
    ###############################################################################
    #                              Log::Log4perl Conf                             #
    ###############################################################################
    # Configuration in a string ...
    my $conf = qq(
      log4perl.category.main              = $log_level, Logfile, Screen
     
      log4perl.appender.Logfile           = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.Threshold = TRACE
      log4perl.appender.Logfile.filename  = $logfile
      log4perl.appender.Logfile.mode      = append
      log4perl.appender.Logfile.autoflush = 1
      log4perl.appender.Logfile.umask     = 0022
      log4perl.appender.Logfile.header_text = INVOCATION:$0 @ARGV
      log4perl.appender.Logfile.layout    = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Logfile.layout.ConversionPattern = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%m%n
     
      log4perl.appender.Screen            = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.stderr     = 1
      log4perl.appender.Screen.layout     = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern  = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%m%n
    );

    # ... passed as a reference to init()
    Log::Log4perl::init( \$conf );

    return;
}


### INTERNAL UTILITY ###
# Usage      : my ($stdout, $stderr, $exit) = capture_output( $cmd, $param_href );
# Purpose    : accepts command, executes it, captures output and returns it in vars
# Returns    : STDOUT, STDERR and EXIT as vars
# Parameters : ($cmd_to_execute)
# Throws     : 
# Comments   : second param is verbose flag (default off)
# See Also   :
sub capture_output {
    my $log = Log::Log4perl::get_logger("main");
    $log->logdie( 'capture_output() needs a $cmd' ) unless (@_ ==  2 or 1);
    my ($cmd, $param_href) = @_;

    my $verbose = defined $param_href->{verbose}  ? $param_href->{verbose}  : undef;   #default is silent
    $log->info(qq|Report: COMMAND is: $cmd|);

    my ( $stdout, $stderr, $exit ) = capture {
        system($cmd );
    };

    if ($verbose == 2) {
        $log->trace( 'STDOUT is: ', "$stdout", "\n", 'STDERR  is: ', "$stderr", "\n", 'EXIT   is: ', "$exit" );
    }

    return  $stdout, $stderr, $exit;
}


### INTERFACE SUB ###
# Usage      : install_perl( $param_href );
# Purpose    : install latest perl if not installed
# Returns    : nothing
# Parameters : ( $param_href ) params from command line
# Throws     : croaks if wrong number of parameters
# Comments   : first sub in chain, run only once at start
# See Also   :
sub install_perl {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('install_perl() needs a $param_href' ) unless @_ == 1;
    my ( $param_href ) = @_;

    #check perl version
    my $cmd_perl_version = 'perl -v';
    my ($stdout, $stderr, $exit) = capture_output( $cmd_perl_version, $param_href );
    if ($exit == 0) {
        $log->debug( 'Checking Perl version with perl -v' );
        if ( $stdout =~ m{v(\d+\.(\d+)\.\d+)}g ) {
            my $perl_ver = $1;
            my $ver_num = $2;
            $log->debug( "We have Perl $perl_ver" );

            #start perlenv install
            $log->info( 'Checking if we can install plenv' );
            my $cmd_plenv = 'git clone git://github.com/tokuhirom/plenv.git ~/.plenv';
            my ($stdout_env, $stderr_env, $exit_env) = capture_output( $cmd_plenv, $param_href );
            my ($git_missing) = $stderr_env =~ m{(git)};
            my ($plenv_exist) = $stderr_env =~ m{(plenv)};

            if ($exit_env != 0 ) {
                if ( $git_missing ) {
                    $log->warn( 'Need to install git' );
                    my $cmd_git = 'sudo yum -y install git';
                    my ($stdout_git, $stderr_git, $exit_git) = capture_output( $cmd_git, $param_href );
                    if ($exit_git == 0 ) {
                        $log->trace( 'git successfully installed' );
                    }
					else {
                        $log->trace( 'git installation failed' );
					}

					#if git is missing other tools are missing too
                    my $cmd_tools = q{sudo yum -y groupinstall "Development tools"};
					my ($stdout_tools, $stderr_tools, $exit_tools) = capture_output( $cmd_tools, $param_href );
                    if ($exit_tools == 0 ) {
                        $log->trace( 'Development tools successfully installed' );
                    }
					else {
                        $log->trace( 'Development tools installation failed' );
					}

                    system $cmd_tools;
                }
                elsif ( $plenv_exist ) {
                    $log->warn( "plenv already installed: $stderr_env" );
                }
            }
            else {
                $log->trace( 'Installed plenv' );
                
                #updating .bash_profile for plenv to work
                my $cmd_path = q{echo 'export PATH="$HOME/.plenv/bin:$PATH"' >> ~/.bash_profile};
                my $cmd_eval = q{echo 'eval "$(plenv init -)"' >> ~/.bash_profile};
                my $cmd_exec = q{source $HOME/.bash_profile};
                system ($cmd_path);
                system ($cmd_eval);
                system ($cmd_exec);
                $log->trace( 'Updated $PATH variable and initiliazed plenv' );
                
                #installing Perl-Build plugin for install function in plenv
                my $cmd_perl_build = q{git clone git://github.com/tokuhirom/Perl-Build.git ~/.plenv/plugins/perl-build/};
                my ($stdout_bp, $stderr_bp, $exit_bp) = capture_output( $cmd_perl_build, $param_href );
                if ($exit_bp == 0) {
                    $log->trace( 'Installed Perl-Build plugin for plenv from github' );
                }
				else {
                    $log->trace( 'Perl-Build installation failed' );
				}
			}

            #list all perls available
            my $cmd_list_perls = q{plenv install --list};
            my ($stdout_list, $stderr_list, $exit_list) = capture_output( $cmd_list_perls, $param_href );
            my @perls = split("\n", $stdout_list);
            #say @perls;
            
            #ask to choose which Perl to install
            my $perl_to_install
              = prompt 'Choose which Perl version you want to install',
              -number,
              -menu => [ @perls ],
              '>';
            my @thread_options = qw/usethreads nothreads/;
            my $thread_option
              = prompt 'Do you want to install Perl with or without threads?',
              -menu => [ @thread_options ],
              '>';
            $log->trace( "Will install $perl_to_install with $thread_option" );

            #install Perl
            my $cmd_install;
            if ($thread_option eq 'nothreads') {
                $cmd_install = qq{plenv install -j 8 -Dcc=gcc $perl_to_install};
            }
            else {
                $cmd_install = qq{plenv install -j 8 -Dcc=gcc -D usethreads $perl_to_install};
            }
            my ($stdout_ins, $stderr_ins, $exit_ins) = capture_output( $cmd_install, $param_href );
            if ($exit_ins == 0) {
                $log->trace( "Perl $perl_to_install installed successfully!" );
            }
			else {
                $log->trace( "Perl $perl_to_install failed" );
			}

            #finish installation, set perl as global
            my $cmd_rehash = q{plenv rehash};
            my $cmd_global = qq{plenv global $perl_to_install};
            my $cmd_cpanm = q{plenv install-cpanm};
            #my $cmd_lib   = q{sudo cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)};
            system ($cmd_rehash);
            system ($cmd_global);
            my ($stdout_cp, $stderr_cp, $exit_cp) = capture_output( $cmd_cpanm, $param_href );
            if ($exit_cp == 0) {
                $log->trace( "Perl $perl_to_install is now global and cpanm installed" );
            }
			else {
                $log->trace( 'cpanm installation failed' );
			}

            #check if right Perl installed
            my ($stdout_ver, $stderr_ver, $exit_ver) = capture_output( $cmd_perl_version, $param_href );
            if ($exit_ver == 0) {
                $log->debug( 'Checking Perl version after install' );
                if ( $stdout_ver =~ m{v(\d+\.(\d+)\.\d+)}g ) {
                    my $perl_ver2 = $1;
                    $log->info( "We have Perl $perl_ver2 " );
                }
            }
        }
    }
    else {
        $log->logcarp( 'Got lost checking Perl version' );
    }

    return;
}


1;
__END__

=encoding utf-8

=head1 NAME

MySQLinstall - is installation script that installs Perl using plenv, MySQL::Sandbox using cpanm, MySQL in a sandbox, additional engines like TokuDB and Deep and updates configuration.

=head1 SYNOPSIS

 MySQLinstall --mode=install_perl

 MySQLinstall --mode=install_sandbox --sandbox=/msestak/sandboxes/ --opt=/msestak/opt/mysql/

 MySQLinstall --mode=wget_mysql -url http://dev.mysql.com/get/Downloads/MySQL-5.5/mysql-5.5.43-linux2.6-x86_64.tar.gz

 MySQLinstall --mode=wget_percona -url https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.24-72.2/binary/tarball/Percona-Server-5.6.24-rel72.2-Linux.x86_64.ssl101.tar.gz -url_tokudb https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.24-72.2/binary/tarball/Percona-Server-5.6.24-rel72.2-TokuDB.Linux.x86_64.ssl101.tar.gz

 MySQLinstall --mode=install_mysql -i ./download/mysql-5.6.26-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall --mode=install_mysql --in=./download/Percona-Server-5.6.25-rel73.1-Linux.x86_64.ssl101.tar.gz

 MySQLinstall --mode=edit_tokudb --opt=/home/msestak/opt/mysql/5.6.25/ --sand=/home/msestak/sandboxes/msb_5_6_25/

 MySQLinstall --mode=edit_deep -i deep-mysql-5.6.25-community-plugin-3.2.0.19654-1.el6.x86_64.rpm --sand=/msestak/sandboxes/msb_5_6_25/ --opt=/msestak/opt/mysql/5.6.25/
 or with reporting
 MySQLinstall --mode=edit_deep_report -i ./download/deep-mysql-5.6.26-community-plugin-3.2.0.19896.el6.x86_64.tar.gz --sand=/home/msestak/sandboxes/msb_5_6_26 --opt=/home/msestak/opt/mysql/5.6.26



=head1 DESCRIPTION

 MySQLinstall is installation script that installs Perl using plenv, MySQL::Sandbox using cpanm, MySQL in a sandbox, additional engines like TokuDB and Deep and updates configuration. 

 --mode=mode				Description
 --mode=install_perl		installs latest Perl with perlenv and cpanm
 --mode=install_sandbox		installs MySQL::Sandbox and prompts for modification of .bashrc
 --mode=wget_mysql			downloads MySQL from Oracle
 --mode=wget_percona		downloads Percona Server with TokuDB
 --mode=install_mysql		installs MySQL and modifies my.cnf for performance
 --mode=edit_deep_report	installs TokuDB plugin
 --mode=edit_tokudb			installs Deep plugin
 
 For help write:
 MySQLinstall -h
 MySQLinstall -m


=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

mocnii E<lt>msestak@irb.hrE<gt>

=head1 EXAMPLE
 MySQLinstall --mode=install_mysql --in=./download/Percona-Server-5.6.25-rel73.1-Linux.x86_64.ssl101.tar.gz
 MySQLinstall --mode=edit_tokudb --opt=/home/msestak/opt/mysql/5.6.25/ --sand=/home/msestak/sandboxes/msb_5_6_25/
 
 MySQLinstall --mode=install_mysql -i mysql-5.6.24-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall --mode=edit_deep -i deep-mysql-5.6.24-community-plugin-3.2.0.19297-1.el6.x86_64.rpm --sand=/msestak/sandboxes/msb_5_6_24/ --opt=/msestak/opt/mysql/5.6.24/

 MySQLinstall --mode=install_mysql -i mysql-5.6.24-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall --mode=edit_deep_report -i deep-mysql-5.6.24-community-plugin-3.2.0.19654.el6.x86_64.tar.gz --sand=/msestak/sandboxes/msb_5_6_24/ --opt=/msestak/opt/mysql/5.6.24/

 MySQLinstall --mode=install_mysql -i ./download/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall --mode=edit_deep_report -i ./download/deep-mysql-5.6.27-community-plugin-3.3.0.20340.el6.x86_64.tar.gz --sand=/home/msestak/sandboxes/msb_5_6_27/ --opt=/home/msestak/opt/mysql/5.6.27/

=cut


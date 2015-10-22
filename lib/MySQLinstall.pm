#!/usr/bin/env perl
package MySQLinstall;

use 5.010001;
use strict;
use warnings;
no warnings 'experimental';
use autodie;
use Carp;
use Path::Tiny;
use v5.010;
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

    #first capture parameters to enable VERBOSE flag for logging
    my ($param_href) = get_parameters_from_cmd();

    #preparation of parameters
    my $VERBOSE    = $param_href->{VERBOSE};
    my $QUIET      = $param_href->{QUIET};
    my @MODE     = @{ $param_href->{MODE} };
	my $URL      = $param_href->{URL};
    my $URL_TOKUDB = $param_href->{URL_TOKUDB};
	my $OPT      = $param_href->{OPT};
    my $SANDBOX = $param_href->{SANDBOX};
    my $INFILE   = $param_href->{INFILE};
    my $OUT      = $param_href->{OUT};   #not used
    my $HOST     = $param_href->{HOST};
    my $DATABASE = $param_href->{DATABASE};   #not used
    my $USER     = $param_href->{USER};
    my $PASSWORD = $param_href->{PASSWORD};
    my $PORT     = $param_href->{PORT};
    my $SOCKET   = $param_href->{SOCKET};

    #start logging for the rest of program (without capturing of parameters)
	
    init_logging($VERBOSE);
    ##########################
    # ... in some function ...
    ##########################
    my $log = Log::Log4perl::get_logger("main");
	print Dumper($log);

    # Logs both to Screen and File appender
    $log->info("This is start of logging for $0");

    #get dump of param_href if -v (VERBOSE) flag is on (for debugging)
    my $dump_print = sprintf( Dumper($param_href) ) if $VERBOSE;
    $log->debug( '$param_href = ', "$dump_print" ) if $VERBOSE;

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

    foreach my $mode (@MODE) {
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
	my @arg_copy = @ARGV;
    my ( $help, $man, $URL, $SANDBOX, $OPT, $INFILE, $OUT, $HOST, $DATABASE, $USER, $PASSWORD, $PORT, $SOCKET, @MODE );
    my $QUIET   = 0;    #by default it is verbose with INFO level
    my $VERBOSE = 0;    #default INFO log level

    GetOptions(
        'help|h'        => \$help,
        'man|m'         => \$man,
        'url=s'         => \$URL,
        'sandbox|sand=s'=> \$SANDBOX,
        'opt=s'         => \$OPT,

        'infile|if=s'   => \$INFILE,
        'out|o=s'       => \$OUT,
        'host|h=s'      => \$HOST,
        'database|d=s'  => \$DATABASE,
        'user|u=s'      => \$USER,
        'password|p=s'  => \$PASSWORD,
        'port|po=i'     => \$PORT,
        'socket|s=s'    => \$SOCKET,
        'mode|mo=s{1,}' => \@MODE,       #accepts 1 or more arguments
        'quiet|q'       => \$QUIET,      #flag
        'verbose+'      => \$VERBOSE,    #flag
    ) or pod2usage( -verbose => 1 );

    @MODE = split( /,/, join( ',', @MODE ) );
    die 'No @MODE specified on command line' unless @MODE;

    pod2usage( -verbose => 1 ) if $help;
    pod2usage( -verbose => 2 ) if $man;

	#if not -q or --quit print all this (else be quiet)
	if ($QUIET == 0) {
		print STDERR 'My @ARGV: {', join( "} {", @arg_copy ), '}', "\n";
	
		if ($INFILE) {
			say 'My input file: ', path($INFILE);
			$INFILE = path($INFILE)->absolute->canonpath;
			say 'My absolute input file: ', path($INFILE);
		}
		if ($OUT) {
			say 'My output path: ', path($OUT);
			$OUT = path($OUT)->absolute->canonpath;
			say 'My absolute output path: ', path($OUT);
		}
	}
	else {
		$VERBOSE = -1;
	}

    return (
        {   MODE     => \@MODE,
            VERBOSE  => $VERBOSE,
            QUIET    => $QUIET,
            INFILE   => $INFILE,
            URL      => $URL,
            SANDBOX  => $SANDBOX,
            OPT      => $OPT,
            OUT      => $OUT,
            HOST     => $HOST,
            DATABASE => $DATABASE,
            USER     => $USER,
            PASSWORD => $PASSWORD,
            PORT     => $PORT,
            SOCKET   => $SOCKET,
        }
    );
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
    croak 'init_logging() needs VERBOSE parameter' unless @_ == 1;
    my ($VERBOSE) = @_;

    #create log file in same dir where script is running
    my $dir_out = path($0)->parent->absolute;    #removes perl script and takes absolute path from rest of path
                                                 #say '$dir_out:', $dir_out;
    my ($app_name) = path($0)->basename =~ m{\A(.+)\.(?:.+)\z};   #takes name of the script and removes .pl or .pm or .t
                                                                  #say '$app_name:', $app_name;
    my $logfile = path( $dir_out, $app_name . '.log' )->canonpath;    #combines all of above with .log
                                                                      #say '$logfile:', $logfile;
    #colored output on windows
    my $osname = $^O;
    if ( $osname eq 'MSWin32' ) {
        require Win32::Console::ANSI;                                 #require needs import
        Win32::Console::ANSI->import();
    }

    #enable different levels based on VERBOSE flag
    my $log_level;
    foreach ($VERBOSE) {
        when (0) { $log_level = 'INFO'; }
        when (1) { $log_level = 'DEBUG'; }
        when (2) { $log_level = 'TRACE'; }
        when (-1) { $log_level = 'OFF'; }
        default  { $log_level = 'INFO'; }
    }

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
	print 'conf', Dumper($conf);
	print 'appender', Dumper( $Log::Log4perl::Logger::APPENDER_BY_NAME{'Logfile'} );
	#print 'appender', Dumper( $Log::Log4perl::Logger::APPENDER_BY_NAME{'Screen'} );
	my $ap = $Log::Log4perl::Logger::APPENDER_BY_NAME{'Logfile'};
	$ap->threshold( 'TRACE' );

    return;
}


### INTERNAL UTILITY ###
# Usage      : capture_output();
# Purpose    : accepts command, executes it, captures output and returns it in vars
# Returns    : STDOUT, STDERR and EXIT as vars
# Parameters : ($cmd_to_execute)
# Throws     : 
# Comments   : 
# See Also   :
sub capture_output {
    croak 'capture_output() needs a $cmd' unless @_ == 1;
    my ($cmd) = @_;
    my $log = Log::Log4perl::get_logger("main");

    $log->info( 'COMMAND is: ', "$cmd" );

    my ( $stdout, $stderr, $exit ) = capture {
        system($cmd );
    };

	#$log->trace( 'STDOUT  is: ', "$stdout", "\n", 'STDERR  is: ', "$stderr", "\n", 'EXIT    is: ', "$exit" );

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
    my ( $param_href ) = @_;   #not used we don't need parameters here

    #check perl version (if larger than 5.10 leave it alone, else install new one)
    my $cmd_perl_version = 'perl -v';
    my ($stdout, $stderr, $exit) = capture_output( $cmd_perl_version );
    if ($exit == 0) {
        $log->info( 'Checking Perl version with perl -v' );
        if ( $stdout =~ m{v(\d+\.(\d+)\.\d+)}g ) {
            my $perl_ver = $1;
            my $ver_num = $2;
            #say $perl_ver, $ver_num;
            if ( $ver_num <= 10 ) {
                $log->warn( "We have Perl $perl_ver and we need to update" );

                #start perlenv install
                $log->info( 'Checking if we can install plenv' );
                my $cmd_plenv = 'git clone git://github.com/tokuhirom/plenv.git ~/.plenv';
                my ($stdout_env, $stderr_env, $exit_env) = capture_output( $cmd_plenv );
                my ($git_missing) = $stderr_env =~ m{(git)};
                my ($plenv_exist) = $stderr_env =~ m{(plenv)};

                if ($exit_env != 0 ) {
                    if ( $git_missing ) {
                        $log->warn( 'Need to install git' );
                        my $cmd_git = 'sudo yum -y install git';
                        my ($stdout_git, $stderr_git, $exit_git) = capture_output( $cmd_git );
                        if ($exit_git == 0 ) {
                            $log->trace( 'git successfully installed' );
                        }
                        my $cmd_tools = q{sudo yum -y groupinstall "Development tools"};
                        system $cmd_tools;
                    }
                    elsif ( $plenv_exist ) {
                        $log->trace( "plenv already installed: $stderr_env" );
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
                    my ($stdout_bp, $stderr_bp, $exit_bp) = capture_output( $cmd_perl_build );
                    if ($exit_bp == 0) {
                        $log->trace( 'Installed Perl-Build plugin for plenv from github' );
                    }

                    #list all perls available
                    my $cmd_list_perls = q{plenv install --list};
                    my ($stdout_list, $stderr_list, $exit_list) = capture_output( $cmd_list_perls );
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
                    my ($stdout_ins, $stderr_ins, $exit_ins) = capture_output( $cmd_install );
                    if ($exit_ins == 0) {
                        $log->trace( "Perl $perl_to_install installed successfully!" );
                    }

                    #finish installation, set perl as global
                    my $cmd_rehash = q{plenv rehash};
                    my $cmd_global = qq{plenv global $perl_to_install};
                    my $cmd_cpanm = q{plenv install-cpanm};
                    #my $cmd_lib   = q{sudo cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)};
                    system ($cmd_rehash);
                    system ($cmd_global);
                    my ($stdout_cp, $stderr_cp, $exit_cp) = capture_output( $cmd_cpanm );
                    if ($exit_cp == 0) {
                        $log->trace( "Perl $perl_to_install is now global and cpanm installed" );
                    }

                    #check if right Perl installed
                    my ($stdout_ver, $stderr_ver, $exit_ver) = capture_output( $cmd_perl_version );
                    if ($exit_ver == 0) {
                        $log->info( 'Checking Perl version with perl -v' );
                        if ( $stdout_ver =~ m{v(\d+\.(\d+)\.\d+)}g ) {
                            my $perl_ver2 = $1;
                            $log->warn( "We have Perl $perl_ver2 " );
                        }
                    }
                }
            }
            else {
                $log->debug( "Move along Perl version is fine: $perl_ver" );
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

MySQLinstall - It's new $module

=head1 SYNOPSIS

    use MySQLinstall;

=head1 DESCRIPTION

MySQLinstall is ...

=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

mocnii E<lt>msestak@irb.hrE<gt>

=cut


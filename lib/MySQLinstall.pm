#!/usr/bin/env perl
package MySQLinstall;

use 5.010001;
use strict;
use warnings;
use File::Spec::Functions qw(:ALL);
use Path::Tiny;
use Carp;
use Getopt::Long;
use Pod::Usage;
use Capture::Tiny qw/capture/;
use Data::Dumper;
#use Regexp::Debugger;
use Log::Log4perl;
use File::Find::Rule;
use Config::Std { def_sep => '=' };   #MySQL uses =

our $VERSION = "0.01";

our @EXPORT_OK = qw{
  run
  init_logging
  get_parameters_from_cmd
  _capture_output
  _exec_cmd
  wget_mysql
  install_mysql
  install_mysql_with_prefix
  edit_tokudb
  edit_deep_report
  install_scaledb

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
    my $verbose  = $param_href->{verbose};
    my $quiet    = $param_href->{quiet};
    my @mode     = @{ $param_href->{mode} };
    my $URL      = $param_href->{url};
    my $opt      = $param_href->{opt};
    my $sandbox  = $param_href->{sandbox};
    my $infile   = $param_href->{infile};
    my $OUT      = $param_href->{out};         #not used
    my $HOST     = $param_href->{host};
    my $DATABASE = $param_href->{database};    #not used
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
        install_sandbox           => \&install_sandbox,              # and create dirs
        wget_mysql                => \&wget_mysql,                   # from mysql internet site
        install_mysql             => \&install_mysql,                # and edit general options in my.sandbox.cnf for InnoDB
        install_mysql_with_prefix => \&install_mysql_with_prefix,    # installs MySQL with different port and prefix
        edit_tokudb               => \&edit_tokudb,                  # install TokuDB storage engine with Percona
        edit_deep_report          => \&edit_deep_report,             # install Deep engine (with reporting to deep.is)
        install_scaledb           => \&install_scaledb,              # install MariaDB with ScaleDB engine

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
	# put config location to %opts
	$opts{config} = $config_file;
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
        'sandedit|se=s' => \$cli{sandedit},
        'optedit=s'     => \$cli{optedit},
		'config|cnf=s'  => \$cli{config},
        'in|i=s'        => \$cli{in},
        'infile|if=s'   => \$cli{infile},
        'out|o=s'       => \$cli{out},
        'outfile|of=s'  => \$cli{outfile},
		'prefix=s'      => \$cli{prefix},
		'plugin=s'      => \$cli{plugin},

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
		print STDERR "Extra options from config:", Dumper(\%opts);
	
		if ($cli{in}) {
			say 'My input path: ', canonpath($cli{in});
			$cli{in} = rel2abs($cli{in});
			$cli{in} = canonpath($cli{in});
			say "My absolute input path: $cli{in}";
		}
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
		if ($cli{outfile}) {
			say 'My outfile: ', canonpath($cli{outfile});
			$cli{outfile} = rel2abs($cli{outfile});
			$cli{outfile} = canonpath($cli{outfile});
			say "My absolute outfile: $cli{outfile}";
		}
	}
	else {
		$cli{verbose} = -1;   #and logging is OFF
	}

    #copy all config opts
	my %all_opts = %opts;
	#update with cli options
	foreach my $key (keys %cli) {
		if ( defined $cli{$key} ) {
			$all_opts{$key} = $cli{$key};
		}
	}

    return ( \%all_opts );
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
      log4perl.appender.Logfile.layout.ConversionPattern = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
     
      log4perl.appender.Screen            = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.stderr     = 1
      log4perl.appender.Screen.layout     = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern  = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
    );

    # ... passed as a reference to init()
    Log::Log4perl::init( \$conf );

    return;
}


### INTERNAL UTILITY ###
# Usage      : my ($stdout, $stderr, $exit) = _capture_output( $cmd, $param_href );
# Purpose    : accepts command, executes it, captures output and returns it in vars
# Returns    : STDOUT, STDERR and EXIT as vars
# Parameters : ($cmd_to_execute)
# Throws     : 
# Comments   : second param is verbose flag (default off)
# See Also   :
sub _capture_output {
    my $log = Log::Log4perl::get_logger("main");
    $log->logdie( '_capture_output() needs a $cmd' ) unless (@_ ==  2 or 1);
    my ($cmd, $param_href) = @_;

    my $verbose = $param_href->{verbose};
    $log->debug(qq|Report: COMMAND is: $cmd|);

    my ( $stdout, $stderr, $exit ) = capture {
        system($cmd );
    };

    if ($verbose == 2) {
        $log->trace( 'STDOUT is: ', "$stdout", "\n", 'STDERR  is: ', "$stderr", "\n", 'EXIT   is: ', "$exit" );
    }

    return  $stdout, $stderr, $exit;
}

### INTERNAL UTILITY ###
# Usage      : _exec_cmd($cmd_git, $param_href, $cmd_info);
# Purpose    : accepts command, executes it and checks for success
# Returns    : prints info
# Parameters : ($cmd_to_execute, $param_href)
# Throws     : 
# Comments   : second param is verbose flag (default off)
# See Also   :
sub _exec_cmd {
    my $log = Log::Log4perl::get_logger("main");
    $log->logdie( '_exec_cmd() needs a $cmd, $param_href and info' ) unless (@_ ==  2 or 3);
	croak( '_exec_cmd() needs a $cmd' ) unless (@_ == 2 or 3);
    my ($cmd, $param_href, $cmd_info) = @_;
	if (!defined $cmd_info) {
		($cmd_info)  = $cmd =~ m/\A(\w+)/;
	}
    my $verbose = $param_href->{verbose};

    my ($stdout, $stderr, $exit) = _capture_output( $cmd, $param_href );
    if ($exit == 0 and $verbose > 1) {
        $log->trace( "$cmd_info success!" );
    }
	else {
        $log->trace( "$cmd_info failed!" );
	}
	return $exit;
}


### INTERFACE SUB ###
# Usage      : install_sandbox( $param_href );
# Purpose    : install MySQL::Sandbox module and create dir for MySQL binaries 
# Returns    : nothing
# Parameters : no params
# Throws     : croaks if wrong number of parameters
# Comments   : updates .bashrc with sandbox environmental variables
# See Also   :
sub install_sandbox {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('install_sandbox() needs a $param_href' ) unless @_ == 1;
    my ( $param_href ) = @_;

    my $sandbox = $param_href->{sandbox} or $log->logcroak( 'no $sandbox specified on command line!' );
    my $opt     = $param_href->{opt}     or $log->logcroak( 'no $opt specified on command line!' );

	#create $opt dir (not automatically created)
	my @dirs = path($opt)->mkpath({ chmod => 0766 });
	if (@dirs == 0) {
		 $log->trace( "SANDBOX_BINARY $opt already exists!" );
	}
	elsif (@dirs > 0) {
		 $log->trace( "SANDBOX_BINARY $opt created!" );
	}
	elsif (!@dirs) {
		 $log->warn( "SANDBOX_BINARY $opt creation failed!" );
	}

	#create $sandbox dir
	my @dirs2 = path($sandbox)->mkpath({ chmod => 0766 });
	if (@dirs2 == 0) {
		 $log->trace( "SANDBOX_HOME $sandbox already exists!" );
	}
	elsif (@dirs2 > 0) {
		 $log->trace( "SANDBOX_HOME $sandbox created!" );
	}
	elsif (!@dirs2) {
		 $log->warn( "SANDBOX_HOME $sandbox creation failed!" );
	}

	#check .bashrc for sandbox environmental variables and set them up
	#possible only after you have created directories
	_install_sandbox_env_setup($param_href);

	#execute cpanm install or upgrade
    my $cmd_cpanm = q{cpanm MySQL::Sandbox};
    my ($stdout, $stderr, $exit) = _capture_output( $cmd_cpanm, $param_href );
    if ($exit == 0) {
        $log->info( 'MySQL::Sandbox installed!' );
    }

    return;
}


### INTERNAL UTILITY ###
# Usage      : _install_sandbox_env_setup( $param_href );
# Purpose    : it checks .bashrc for sandbox environmental variables and sets them up
# Returns    : nothing
# Parameters : $param_href
# Throws     : 
# Comments   : part of install_sandbox mode
# See Also   : install_sandbox()
sub _install_sandbox_env_setup {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_install_sandbox_env_setup() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $sandbox = $param_href->{sandbox} or $log->logcroak( 'no $sandbox specified on command line!' );
    my $opt     = $param_href->{opt}     or $log->logcroak( 'no $opt specified on command line!' );

	#check .bashrc for SANDBOX_HOME and SANBOX_BINARY variables
	my $bashrc_path = path($ENV{HOME}, '.bashrc');
	open (my $bashrc_fh, "+<", $bashrc_path) or $log->logdie( "Can't open $bashrc_path:$!" );
	
	my $found_sandbox = 0;   #set flag for finding a variable SANDBOX_HOME
	my $found_opt     = 0;   #set flag for finding a variable SANDBOX_BINARY
	while (<$bashrc_fh>) {
		chomp;
		
		if (/SANDBOX_HOME/) {
			$log->trace( "sandbox_HOME variable set in $bashrc_path {$_}" );
			$found_sandbox = 1;
		}

		if (/SANDBOX_BINARY/) {
			$log->trace( "sandbox_BINARY variable set in $bashrc_path {$_}" );
			$found_opt = 1;
		}
	}   #end while

	#update env variables
	if ($found_sandbox == 0) {
		say {$bashrc_fh} "export SANDBOX_HOME=$sandbox";
		#my $cmd_sand = qq{export "SANDBOX_HOME=$sandbox"};
		#_exec_cmd($cmd_sand, $param_href);
		$ENV{SANDBOX_HOME} = "$sandbox";
	}
	if ($found_opt == 0) {
		say {$bashrc_fh} "export SANDBOX_BINARY=$opt";
		#my $cmd_opt = qq{export "SANDBOX_BINARY=$opt"};
		#_exec_cmd($cmd_opt, $param_href);
		$ENV{SANDBOX_BINARY} = "$opt";
	}

	return;
}


### INTERFACE SUB ###
# Usage      : wget_mysql( $param_href );
# Purpose    : dowloads MySQL binary from specified url
# Returns    : nothing
# Parameters : ( $param_href ) -i from command line
# Throws     : croaks if wrong number of parameters
# Comments   :
# See Also   :
sub wget_mysql {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('wget_mysql() needs a $param_href' ) unless @_ == 1;
    my ( $param_href ) = @_;

    my $url = $param_href->{url} or $log->logcroak( 'no $url specified on command line!' );

    my $cmd_wget = qq{wget -c $url};
	my $num_tries = 0;
	TRY_AGAIN: {
	    my ($stdout, $stderr, $exit) = _capture_output( $cmd_wget, $param_href );
	    if ($exit == 0) {
	        $log->info( "$url downloaded!" );
	    }
		else {
			$num_tries++;
			if ($num_tries < 10) {
				goto TRY_AGAIN;
			}
		}
	}

    return;
}


### INTERFACE SUB ###
# Usage      : install_mysql( $param_href );
# Purpose    : installs MySQL binary using MySQL::Sandbox
# Returns    : nothing
# Parameters : ( $param_href ) --infile from command line
# Throws     : croaks if wrong number of parameters
# Comments   : it modifies my.cnf for high performance too
# See Also   :
sub install_mysql {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('install_mysql() needs a $param_href' ) unless @_ == 1;
    my ( $param_href ) = @_;
    my $infile = $param_href->{infile} or $log->logcroak( 'no $infile specified on command line!' );

	# setup of sandbox and opt names
	my ( $mysql_ver, $mysql_num, $sandbox_path, $opt_path ) = _get_sandbox_name_from( $infile );

    #install MySQL with default options
	# delete sandbox if exists
    if (-d $sandbox_path) {
        $log->info( "sandbox $sandbox_path already exists" );
        my $cmd_del = qq{sbtool -o delete -s $sandbox_path};
        my ($stdout_del, $stderr_del, $exit_del) = _capture_output( $cmd_del, $param_href );
        if ($exit_del == 0) {
            $log->warn( "SANDBOX $sandbox_path deleted" );
		}
		else {
			$log->warn( "ERROR: SANDBOX $sandbox_path failed to delete, removing manually" );
			path($sandbox_path)->remove_tree and $log->warn( "SANDBOX $sandbox_path deleted!" );
		}
	}

	#delete binary directory if exists
	if (-d $opt_path) {
		$log->info( "extracted $mysql_ver already exists in $opt_path" );
		path($opt_path)->remove_tree and $log->warn( "OPT $opt_path deleted!" );
	}
    
    #fresh install
    $log->info( "Installing $mysql_ver to $sandbox_path and extracting MySQL binary to $opt_path" );
    my $cmd_make = qq{make_sandbox --export_binaries $infile -- --no_confirm};   #infile needed for absolute path
    my ($stdout, $stderr, $exit) = _capture_output( $cmd_make, $param_href );
    if ($exit == 0) {
            #install succeeded
            $log->info( "Sandbox installed in $sandbox_path with MySQL in $opt_path" );
    }
	else {
		$log->error( "Action: MySQL failed to install to $sandbox_path with MySQL in $opt_path" );
		$log->logexit( "Report: $stderr" );
	}

    #check my.cnf options
	my ($mysql_cnf_path, $mysql_datadir) = _check_my_cnf_for( $sandbox_path, $opt_path );

    #change my.cnf options
    open my $sandbox_cnf_fh, ">>", $mysql_cnf_path or $log->logdie( "Can't find cnf: $!" );
	#set innodb-buffer-pool-size
	my $innodb_buffer = defined $param_href->{innodb} ? $param_href->{innodb} : '1G';

my $cnf_options = <<"SQL";

# MyISAM #
key-buffer-size                = 32M
myisam-recover-options         = FORCE,BACKUP

# SAFETY #
max-allowed-packet             = 16M
max-connect-errors             = 1000000
skip-name-resolve
sql-mode                       = STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_AUTO_VALUE_ON_ZERO,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE
sysdate-is-now                 = 1
#innodb                         = FORCE
innodb-strict-mode             = 1

# TRANSACTION ISOLATION
# default is: transaction-isolation = REPEATABLE-READ
transaction-isolation          = READ-COMMITTED

# BINARY LOGGING #
#server-id                      = $mysql_num
#log-bin                        = mysql-bin
#expire-logs-days               = 14
#sync-binlog                    = 1

# CACHES AND LIMITS #
#warning: large tmp table sizes (use for OLAP only)
tmp-table-size                 = 100M
max-heap-table-size            = 100M
query-cache-type               = 0
query-cache-size               = 0
max-connections                = 500
thread-cache-size              = 50
open-files-limit               = 65535
table-definition-cache         = 1024
table-open-cache               = 2048

# INNODB #
innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-log-file-size           = 1G
innodb-flush-log-at-trx-commit = 2
innodb-file-per-table          = 1
innodb-buffer-pool-size        = $innodb_buffer
#default: innodb-buffer-pool-instances   = 8
innodb-buffer-pool-instances   = 1
innodb_doublewrite             = OFF

# TIMEZONE #
character_set_server           = latin1
collation_server               = latin1_swedish_ci

# LOGGING #
slow-query-log                 = off
#slow-query-log-file            = $sandbox_path/data/msandbox-slow.log
#log-queries-not-using-indexes  = 1
#long_query_time                = 0
#log-error                      = $sandbox_path/data/msandbox.err
performance_schema             = off

# TokuDB #
#tokudb_cache_size              = 1G
#tokudb_data_dir                = $sandbox_path/data
#tokudb_log_dir                 = $sandbox_path/data
#tokudb_tmp_dir                 = $sandbox_path/data
#tokudb_commit_sync             = 1
#tokudb_directio                = 0
#tokudb_load_save_space         = 1
#default_storage_engine         = TokuDB
#default_tmp_storage_engine     = TokuDB
SQL

    print {$sandbox_cnf_fh} $cnf_options, "\n";
    $log->info("MySQL config $mysql_cnf_path modified for InnoDB" );
    close $sandbox_cnf_fh;

    #delete InnoDB logfiles (else it doesn't start)
    foreach my $i (0..1) {
        my $log_file = path($mysql_datadir, 'ib_logfile' . $i);
        unlink $log_file or $log->logdie( "Error: InnoDB file: $log_file not found: $!" );
	    $log->trace( "Action: InnoDB logfile $log_file deleted" )
    }

    #restart MySQl to check if config ok
    my $cmd_restart = path($sandbox_path, 'restart');
    my ($stdout_res, $stderr_res, $exit_res) = _capture_output( $cmd_restart, $param_href );
        if ($exit_res == 0) {
                #restart succeeded
                $log->warn( "Action: sandbox $sandbox_path restarted with MySQL in $opt_path" );
        }
		else {
			#restart failed
			$log->logexit( "Action: sandbox $sandbox_path failed to restart AFTER updating InnoDB options" );
		}

    return;
}


### INTERNAL UTILITY ###
# Usage      : my ( $mysql_ver, $mysql_num, $sandbox_path, $opt_path ) = _get_sandbox_name_from( $infile );
# Purpose    : returns sandbox and opt path from binary and SANDBOX_HOME and SANDBOX_BINARY variables
# Returns    : $mysql_ver, $mysql_num, $sandbox_path, $opt_path
# Parameters : ( $infile ) location of MySQL binary
# Throws     : croaks for wrong num of parameters
# Comments   : part of install_mysql mode
# See Also   : install_mysql()
sub _get_sandbox_name_from {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_get_sandbox_name_from() needs a $infile') unless @_ == 1 or 2;
    my $infile = shift;
	my $prefix = shift // ''; 

    # get name of MySQL binary without location
    my $mysql_binary = path($infile)->basename;
    $log->trace("MySQL binary: $mysql_binary");

    # extract version and num from binary
    ( my $mysql_ver = $mysql_binary ) =~ s/\A.+?-(5\.\d+\.\d+)-.+?\z/$1/;
	$mysql_ver = $prefix . $mysql_ver;
    $log->trace("MySQL version: $mysql_ver");
    (my $mysql_num = $mysql_ver) =~ s/\.//g;
	($mysql_num) = ($mysql_num =~ m/\A\D*(\d+)\z/);
    $log->trace( "MySQL num: $mysql_num" );

    # get opt path
    my $opt_path = path( $ENV{SANDBOX_BINARY}, $mysql_ver );
    $log->trace("Specific SANDBOX_BINARY path: $opt_path");

    # get sandbox home path
    ( my $sandbox_name = $mysql_ver ) =~ s/\./_/g;
    $log->trace("Sandbox name: $sandbox_name");
    my $sandbox_path = path( $ENV{SANDBOX_HOME}, 'msb_' . $sandbox_name );
    $log->trace("Specific SANDBOX_HOME path: $sandbox_path");

    return $mysql_ver, $mysql_num, $sandbox_path, $opt_path;

}


### INTERNAL UTILITY ###
# Usage      : my ( $mysql_ver, $mysql_num, $sandbox_path, $opt_path ) = _get_sandbox_name_from_maria( $infile );
# Purpose    : returns sandbox and opt path from binary and SANDBOX_HOME and SANDBOX_BINARY variables
# Returns    : $mysql_ver, $mysql_num, $sandbox_path, $opt_path
# Parameters : ( $infile ) location of MariaDB binary
# Throws     : croaks for wrong num of parameters
# Comments   : part of install_mysql mode
# See Also   : install_mysql()
sub _get_sandbox_name_from_maria {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_get_sandbox_name_from() needs a $infile') unless @_ == 1 or 2;
    my $infile = shift;
	my $prefix = shift // ''; 

    # get name of MariaDB binary without location
    my $mysql_binary = path($infile)->basename;
    $log->trace("MariaDB binary: $mysql_binary");

    # extract version and num from binary
    ( my $mysql_ver = $mysql_binary ) =~ s/\A(?:[^\d]+)(\d+\.\d+\.\d+).+\z/$1/;
	$mysql_ver = $prefix . $mysql_ver;
    $log->trace("MariaDB version: $mysql_ver");
    (my $mysql_num = $mysql_ver) =~ s/\.//g;
	($mysql_num) = ($mysql_num =~ m/\A\D*(\d+)\z/);
    $log->trace( "MariaDB num: $mysql_num" );

    # get opt path
    my $opt_path = path( $ENV{SANDBOX_BINARY}, $mysql_ver );
    $log->trace("Specific SANDBOX_BINARY path: $opt_path");

    # get sandbox home path
    ( my $sandbox_name = $mysql_ver ) =~ s/\./_/g;
    $log->trace("Sandbox name: $sandbox_name");
    my $sandbox_path = path( $ENV{SANDBOX_HOME}, 'msb_' . $sandbox_name );
    $log->trace("Specific SANDBOX_HOME path: $sandbox_path");

    return $mysql_ver, $mysql_num, $sandbox_path, $opt_path;

}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : my ($mysql_cnf_path, $mysql_datadir) = _check_my_cnf_for( $sandbox_path, $opt_path );
# Purpose    : checks to see if MySQL installed in right location
# Returns    : ($mysql_cnf_path, $mysql_datadir)
# Parameters : ( $sandbox_path, $opt_path )
# Throws     : croaks if wrong number of parameters
# Comments   : part of install_mysql() mode
# See Also   : install_mysql()
sub _check_my_cnf_for {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_check_my_cnf_for() needs $sandbox_path and $opt_path') unless @_ == 2;
    my ($sandbox_path, $opt_path) = @_;

    #check my.cnf options
    my $mysql_cnf_path = path($sandbox_path, 'my.sandbox.cnf');
    read_config "$mysql_cnf_path" => my %config;
	#print Dumper(\%config);

    my $basedir = $config{mysqld}{basedir};
    if ($basedir eq $opt_path) {
        $log->debug( "MySQL binaries are in right place: $basedir" );
    }
    else {
        $log->warn( "MySQL binaries installed in wrong place: $basedir" );
    }

    my $mysql_datadir = $config{mysqld}{datadir};
    my $path_to_datadir = path($sandbox_path, 'data');
    if ($mysql_datadir eq $path_to_datadir) {
        $log->debug( "MySQL data directory is in right place: $mysql_datadir" );
    }
    else {
        $log->warn( "MySQL data directory installed in wrong place: $mysql_datadir" );
    }

    return $mysql_cnf_path, $mysql_datadir;
}


### INTERFACE SUB ###
# Usage      : install_mysql_with_prefix( $param_href );
# Purpose    : installs MySQL binary using MySQL::Sandbox with check port enabled
# Returns    : nothing
# Parameters : ( $param_href ) --infile from command line
# Throws     : croaks if wrong number of parameters
# Comments   : it modifies my.cnf for high performance too
# See Also   :
sub install_mysql_with_prefix {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('install_mysql_with_prefix() needs a $param_href' ) unless @_ == 1;
    my ( $param_href ) = @_;
    my $infile = $param_href->{infile} or $log->logcroak( 'no $infile specified on command line!' );
    my $prefix = $param_href->{prefix} or $log->logcroak( 'no $prefix specified on command line!' );
    my $opt = $param_href->{opt}       or $log->logcroak( 'no $opt specified on command line!' );

	# setup of sandbox and opt names
	my ( $mysql_ver, $mysql_num, $sandbox_path, $opt_path ) = _get_sandbox_name_from( $infile, $prefix );

	# check for existence of sandbox dir
    if (-d $sandbox_path) {
        $log->warn( "Report: sandbox $sandbox_path already exists" );
	}

	# check for existence of opt/mysql dir
	if (-d $opt_path) {
		$log->warn( "Report: extracted $mysql_ver already exists in $opt_path" );
	}

    #fresh install
	#set variables for sandbox, opt, new port
	my ($sandbox_port, $sandbox_dir, $opt_basedir);
    $log->info( "Action: installing $mysql_ver with port checking and prefix={$prefix}" );
    my $cmd_make = qq{make_sandbox --export_binaries $infile --add_prefix=$prefix -- --check_port --no_confirm};
    my ($stdout, $stderr, $exit) = _capture_output( $cmd_make, $param_href );
    if ($exit == 0) {
        #install succeeded
		open (my $stdout_fh, "<", \$stdout) or $log->logdie( "Error: can't open $stdout for reading:$!" );

		while (<$stdout_fh>) {
			chomp;
			if (m{\Asandbox_port\s+=\s+(\d+)\z}) {
				$sandbox_port = $1;
			}
			if (m{\Asandbox_directory\s+=\s+(.+)\z}) {
				$sandbox_dir = $1;
				$sandbox_dir = path($ENV{SANDBOX_HOME}, $sandbox_dir);
			}
			if (m{\Abasedir\s+=\s+(.+)\z}) {
				$opt_basedir = $1;
			}
		}   # end while

        $log->info( "Report: sandbox installed in $sandbox_dir with MySQL in $opt_basedir port:{$sandbox_port}" );
    }
	else {
		$log->error( "Error: MySQL$mysql_ver failed to install" );
		$log->logexit( "Error: $stderr" );
	}

    #check my.cnf options
	my ($mysql_cnf_path, $mysql_datadir) = _check_my_cnf_for( $sandbox_dir, $opt_basedir );

    #change my.cnf options
    open my $sandbox_cnf_fh, ">>", $mysql_cnf_path or $log->logdie( "Can't find cnf: $!" );
	#set innodb-buffer-pool-size
	my $innodb_buffer = defined $param_href->{innodb} ? $param_href->{innodb} : '1G';

my $cnf_options = <<"SQL";

# MyISAM #
key-buffer-size                = 32M
myisam-recover-options         = FORCE,BACKUP

# SAFETY #
max-allowed-packet             = 16M
max-connect-errors             = 1000000
skip-name-resolve
sql-mode                       = STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_AUTO_VALUE_ON_ZERO,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE
sysdate-is-now                 = 1
#innodb                         = FORCE
innodb-strict-mode             = 1

# TRANSACTION ISOLATION
# default is: transaction-isolation = REPEATABLE-READ
transaction-isolation          = READ-COMMITTED

# BINARY LOGGING #
#server-id                      = $sandbox_port
#log-bin                        = mysql-bin
#expire-logs-days               = 14
#sync-binlog                    = 1

# CACHES AND LIMITS #
#warning: large tmp table sizes (use for OLAP only)
tmp-table-size                 = 100M
max-heap-table-size            = 100M
query-cache-type               = 0
query-cache-size               = 0
max-connections                = 500
thread-cache-size              = 50
open-files-limit               = 65535
table-definition-cache         = 1024
table-open-cache               = 2048

# INNODB #
innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-log-file-size           = 1G
innodb-flush-log-at-trx-commit = 2
innodb-file-per-table          = 1
innodb-buffer-pool-size        = $innodb_buffer
#default: innodb-buffer-pool-instances   = 8
innodb-buffer-pool-instances   = 1
innodb_doublewrite             = OFF

# TIMEZONE #
character_set_server           = latin1
collation_server               = latin1_swedish_ci

# LOGGING #
slow-query-log                 = off
#slow-query-log-file            = $sandbox_dir/data/msandbox-slow.log
#log-queries-not-using-indexes  = 1
#long_query_time                = 0
#log-error                      = $sandbox_dir/data/msandbox.err
performance_schema             = off

# TokuDB #
#tokudb_cache_size              = 1G
#tokudb_data_dir                = $sandbox_dir/data
#tokudb_log_dir                 = $sandbox_dir/data
#tokudb_tmp_dir                 = $sandbox_dir/data
#tokudb_commit_sync             = 1
#tokudb_directio                = 0
#tokudb_load_save_space         = 1
#default_storage_engine         = TokuDB
#default_tmp_storage_engine     = TokuDB
SQL

    print {$sandbox_cnf_fh} $cnf_options, "\n";
    $log->info("MySQL config $mysql_cnf_path modified for InnoDB" );
    close $sandbox_cnf_fh;


    #delete InnoDB logfiles (else it doesn't start)
    foreach my $i (0..1) {
        my $log_file = path($mysql_datadir, 'ib_logfile' . $i);
        unlink $log_file and $log->trace( "Action: InnoDB logfile $log_file deleted" ) 
          or $log->error( "Error: InnoDB file: $log_file not found: $!" );
    }

    #restart MySQl to check if config ok
    my $cmd_restart = path($sandbox_dir, 'restart');
    my ($stdout_res, $stderr_res, $exit_res) = _capture_output( $cmd_restart, $param_href );
        if ($exit_res == 0) {
                #restart succeeded
                $log->warn( "Action: sandbox $sandbox_dir restarted with MySQL in $opt_basedir port{$sandbox_port}" );
        }
		else {
			#restart failed
			$log->logexit( "Error: sandbox $sandbox_dir failed to restart AFTER updating InnoDB options" );
		}

    return;
}


### INTERFACE SUB ###
# Usage      : edit_tokudb( $param_href );
# Purpose    : installs TokuDB storage engine to MySQL 5.6
# Returns    : nothing
# Parameters : ( $param_href ) -if from command line and others for MySQL server
# Throws     : croaks if wrong number of parameters
# Comments   : it modifies my.cnf for TokuDB Engine (incompatible with Deep)
# See Also   : run install_mysql() before this sub
sub edit_tokudb {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('edit_tokudb() needs a $param_href' ) unless @_ == 1;
    my ( $param_href ) = @_;

    my $optedit  = $param_href->{optedit}  or $log->logcroak( 'no $optedit specified on command line!' );
    $log->trace( "MySQL installation in: $optedit" );
    my $sandedit = $param_href->{sandedit} or $log->logcroak( 'no $sandedit specified on command line!' );
    $log->trace( "MySQL Sandbox in : $sandedit" );

	# check transparent_hugepage=never to disable it permanently (needed for TokuDB)
	_check_transparent_hugepage();

	# update my.sandbox.cnf with libjemalloc location
	#_jemalloc_setup( $param_href );
	
	# install libjemalloc from Percona repository
	_jemalloc_install( $param_href );

	#install plugin inside MySQL
	_install_tokudb( $param_href );

    # for enabling TokuDB options (only after TokuDB plugin install)
	_enable_tokudb_options( $param_href );

    return;
}


### INTERNAL UTILITY ###
# Usage      : _jemalloc_install( $param_href )
# Purpose    : install libjemalloc from Percona repository
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
#            : exit if install of jemalloc fails
# Comments   : installs libjemalloc system wide
# See Also   : tokudb_edit()
sub _jemalloc_install {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_jemalloc_install() needs a $param_href') unless @_ == 1;
    my ( $param_href ) = @_;
    my $sandedit = $param_href->{sandedit} or $log->logcroak( 'no $sandedit specified on command line!' );

	# check PID of mysqld to check if loaded with jemalloc
	my $malloc_type_href = _check_malloc_type_for( $param_href );

	# if loaded with jemalloc (then installed)
	if (exists $malloc_type_href->{jemalloc}) {
		$log->warn( "jemalloc installed systemwide in $malloc_type_href->{jemalloc}" );
	}
	else { 
		#install jemalloc from Percona repository
		my $cmd_jemalloc = q{sudo yum install -y http://repo.percona.com/centos/6/os/x86_64/jemalloc-3.6.0-1.el6.x86_64.rpm};
		$cmd_jemalloc .= q{ http://repo.percona.com/centos/6/os/x86_64/jemalloc-devel-3.6.0-1.el6.x86_64.rpm};
	    my ($stdout, $stderr, $exit) = _capture_output( $cmd_jemalloc, $param_href );
		my $jemalloc_path = path('/usr/lib64/libjemalloc.so');
	    if ($exit == 0 or $exit == 256) {
	        # install succeeded
			if (-e $jemalloc_path) {
				$log->warn( "jemalloc installed systemwide in $jemalloc_path" );
			}
			else {
				$log->warn( "jemalloc installed systemwide in unknown location" );
			}
	    }
		else {
			# install failed
			$log->logexit( "jemalloc install failed" );
		}

		#restart MySQl to load with jemalloc (else TokuDB install fails)
	    my $cmd_restart = path($sandedit, 'restart');
	    my ($stdout_res, $stderr_res, $exit_res) = _capture_output( $cmd_restart, $param_href );
	    if ($exit_res == 0) {
	        #restart succeeded
	        $log->warn( "Sandbox $sandedit restarted for jemalloc LD_PRELOAD" );
	    }
		else {
			#restart failed
			$log->logexit( "Sandbox $sandedit failed to restart AFTER jemalloc install" );
		}

	}

    return;
}


### INTERNAL UTILITY ###
# Usage      : my $malloc_type_href = _check_malloc_type_for( $param_href );
# Purpose    : check which malloc used to start application (MySQL server in a sandbox)
# Returns    : $malloc_type_href
# Parameters : $param_href with $sandedit
# Throws     : croaks if wrong number of parameters
# Comments   : part of _jemalloc_install() of tokudb_edit()
# See Also   : _jemalloc_install() and tokudb_edit()
sub _check_malloc_type_for {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_check_malloc_type_for() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my $sandedit = $param_href->{sandedit} or $log->logcroak( 'no $sandedit specified on command line!' );

	#check PID of mysqld to check if loaded with jemalloc or tcmalloc
	my $datadir = path($sandedit, 'data');
	my ($mysqld_pid_file) = File::Find::Rule->file()->name( '*.pid' )->in($datadir);
	#/home/msestak/sandboxes/msb_5_6_27/data/mysql_sandbox5627.pid
	$log->trace( "Action: found $mysqld_pid_file" );

	# get pid from .pid file
    open my $pid_fh, '<', $mysqld_pid_file or $log->logdie( "Error: can't open pid file:$mysqld_pid_file:$!" );
    chomp(my $mysqld_pid = <$pid_fh>);
    close $pid_fh;
	$log->trace( "Action: found mysqld PID:$mysqld_pid" );

	#check LD_PRELOAD variable
	my %malloc_type;
	my $pid_environ = path('/proc', $mysqld_pid, 'environ')->canonpath;
	my $entire_environ = path($pid_environ)->slurp;   # read entire binary file
	if ($entire_environ =~ m{jemalloc}) {
		$log->info( "Report: jemalloc found for $sandedit:$pid_environ" );
		if ($entire_environ =~ m{LD_PRELOAD=([^[:upper:]]+)}) {
			$malloc_type{jemalloc} = $1;
		}
	}
	elsif ($entire_environ =~ m{tcmalloc}) {
		$log->info( "Report: tcmalloc found for $sandedit:$pid_environ" );
		if ($entire_environ =~ m{LD_PRELOAD=([^[:upper:]]+)}) {
			$malloc_type{tcmalloc} = $1;
		}
	}
	else {
		$log->info( "Report: standard malloc found for $sandedit:$pid_environ" );
		$malloc_type{malloc} = 1;
	}

	return \%malloc_type;
}


### INTERNAL UTILITY ###
# Usage      : _jemalloc_setup_old( $param_href);
# Purpose    : add jemalloc library to my.sandbox.cnf
# Returns    : nothing
# Parameters : $param_href with $sandedit and $optedit
# Throws     : croaks if wrong number of parameters
# Comments   : BROKEN (jemmaloc doesn't ship with Percona by default)
# See Also   : edit_tokudb()
sub _jemalloc_setup_old {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_jemalloc_setup_old() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $optedit  = $param_href->{optedit}  or $log->logcroak( 'no $optedit specified on command line!' );
    my $sandedit = $param_href->{sandedit} or $log->logcroak( 'no $sandedit specified on command line!' );

    # locations of config files and jemalloc library in Percona installation
    my $config_path   = path( $sandedit, 'my.sandbox.cnf' );                   # for reading
    my $config_path2  = path( $sandedit, 'my.sandbox.cnf2' );                  # for writing
    my $jemalloc_path = path( $optedit,  'lib', 'mysql', 'plugin', 'libjemalloc.so' );   # libjemalloc location

    # add jemalloc location to my.sandbox.cnf
    my $cnf_mysqld_safe = <<"MYSQLD";

# UPDATED FOR TOKUDB #
[mysqld_safe]
malloc_lib=$jemalloc_path
#thp-setting=never

MYSQLD

    #add mysqld_safe section to my.sandbox.cnf2
    open my $sandbox_cnf_write_fh, ">", $config_path2 or $log->logdie( "Error: can't find cnf at $config_path2: $!" );
	my $cnf_old = path($config_path)->slurp;   #read old version
    print {$sandbox_cnf_write_fh} $cnf_mysqld_safe;
    print {$sandbox_cnf_write_fh} $cnf_old;
	close $sandbox_cnf_write_fh;

	# rename new with old my.sandbox.cnf (update config)
	path($config_path2)->move($config_path) 
	  and $log->trace( "Renamed $config_path2 to original $config_path, UPDATED with jemalloc" );
	
    # check visually new config if all ok
	my $cmd_cat = qq{cat $config_path};
	my ($stdout_cat, $stderr_cat, $exit_cat) = _capture_output( $cmd_cat, $param_href );
	if ($exit_cat == 0) {
		#$log->trace( "$stdout_cat" );
	}

    #restart MySQl to check if config ok
    my $cmd_restart = path($sandedit, 'restart');
    my ($stdout_res, $stderr_res, $exit_res) = _capture_output( $cmd_restart, $param_href );
    if ($exit_res == 0) {
        #restart succeeded
        $log->warn( "Sandbox $sandedit restarted with MySQL in $optedit and $jemalloc_path added to $config_path" );
    }
	else {
		#restart failed
		$log->logexit( "Sandbox $sandedit failed to restart during $jemalloc_path UPDATE to $config_path" );
	}

    return;
}


### INTERNAL UTILITY ###
# Usage      : _check_transparent_hugepage()
# Purpose    : checks if transparent_hugepage=never in /etc/grub_cnf
# Returns    : nothing
# Parameters : nothing
# Throws     : croaks if wrong number of parameters
#            : exit if transparent_hugepage enabled
# Comments   : part of edit_tokudb() mode
# See Also   : edit_tokudb()
sub _check_transparent_hugepage {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_check_transparent_hugepage() needs zero params') unless @_ == 0;

	# check for enabled
	# always madvise [never]
	my $sys_kernel_mm = path('/sys/kernel/mm/transparent_hugepage/enabled');
	open (my $fh_sys, "<", $sys_kernel_mm) or $log->logdie( "Error: can't open $sys_kernel_mm for reading:$!" );
	while (<$fh_sys>) {
		chomp;
		if (m{\[always\]}) {
			$log->logexit( "Remember to edit /etc/grub.cnf to add transparent_hugepage=never to latest installation" );
		}
		elsif (m{\[never\]}) {
			$log->info( "transparent_hugepage=never OK" );
		}
		else {
			$log->error( "Error: wrong regex" );
		}

	}   #end while

    return;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : _install_tokudb( $param_href );
# Purpose    : install TokuDB storage engine
# Returns    : nothing
# Parameters : $param_href with $sandedit and $optedit
# Throws     : croaks if wrong number of parameters
#            : exit if install fails
# Comments   : part of edit_tokudb() mode
# See Also   : edit_tokudb()
sub _install_tokudb {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_install_tokudb() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $optedit  = $param_href->{optedit}  or $log->logcroak( 'no $optedit specified on command line!' );
    my $sandedit = $param_href->{sandedit} or $log->logcroak( 'no $sandedit specified on command line!' );

	# install plugin inside MySQL (manual way)
    my $cmd_toku = path($sandedit, 'use -e ');
    $cmd_toku .= qq{"INSTALL PLUGIN tokudb SONAME 'ha_tokudb.so'"};
    my ($stdout_toku1, $stderr_toku1, $exit_toku1) = _capture_output( $cmd_toku, $param_href );
    if ($exit_toku1 == 0) {
        $log->info( "Action: Sandbox $sandedit in $optedit: tokudb installed" );
    }
	else {
		$log->error( "Action: Sandbox $sandedit in $optedit: tokudb install failed" );
		$log->logexit( qq|Report: $stderr_toku1| );
	}

    my $cmd_toku2 = path($sandedit, 'use -e ');
    $cmd_toku2 .= qq{"INSTALL PLUGIN tokudb_file_map SONAME 'ha_tokudb.so'"};
    my ($stdout_toku2, $stderr_toku2, $exit_toku2) = _capture_output( $cmd_toku2, $param_href );
    if ($exit_toku2 == 0) {
        $log->info( "Action: Sandbox $sandedit in $optedit: tokudb_file_map installed" );
    }
	else {
		$log->error( "Action: Sandbox $sandedit in $optedit: tokudb_file_map install failed" );
		$log->logexit( qq|Report: $stderr_toku2| );
	}

    my $cmd_toku3 = path($sandedit, 'use -e ');
    $cmd_toku3 .= qq{"INSTALL PLUGIN tokudb_fractal_tree_info SONAME 'ha_tokudb.so'"};
    my ($stdout_toku3, $stderr_toku3, $exit_toku3) = _capture_output( $cmd_toku3, $param_href );
    if ($exit_toku3 == 0) {
        $log->info( "Action: Sandbox $sandedit in $optedit: tokudb_fractal_tree_info installed" );
    }
	else {
		$log->error( "Action: Sandbox $sandedit in $optedit: tokudb_fractal_tree_info install failed" );
		$log->logexit( qq|Report: $stderr_toku3| );
	}

    my $cmd_toku4 = path($sandedit, 'use -e ');
    $cmd_toku4 .= qq{ "INSTALL PLUGIN tokudb_fractal_tree_block_map SONAME 'ha_tokudb.so'"};
    my ($stdout_toku4, $stderr_toku4, $exit_toku4) = _capture_output( $cmd_toku4, $param_href );
    if ($exit_toku4 == 0) {
        $log->info( "Action: Sandbox $sandedit in $optedit: tokudb_fractal_tree_block_map installed" );
    }
	else {
		$log->error("Action: Sandbox $sandedit in $optedit: tokudb_fractal_tree_block_map install failed" );
		$log->logexit( qq|Report: $stderr_toku4| );
	}

    my $cmd_toku5 = path($sandedit, 'use -e ');
    $cmd_toku5 .= qq{"INSTALL PLUGIN tokudb_trx SONAME 'ha_tokudb.so'"};
    my ($stdout_toku5, $stderr_toku5, $exit_toku5) = _capture_output( $cmd_toku5, $param_href );
    if ($exit_toku5 == 0) {
        $log->info( "Action: Sandbox $sandedit in $optedit: tokudb_trx installed" );
    }
	else {
		$log->error( "Action: Sandbox $sandedit in $optedit: tokudb_trx install failed" );
		$log->logexit( qq|Report: $stderr_toku5| );
	}

    my $cmd_toku6 = path($sandedit, 'use -e ');
    $cmd_toku6 .= qq{"INSTALL PLUGIN tokudb_locks SONAME 'ha_tokudb.so'"};
    my ($stdout_toku6, $stderr_toku6, $exit_toku6) = _capture_output( $cmd_toku6, $param_href );
    if ($exit_toku6 == 0) {
        $log->info( "Action: Sandbox $sandedit in $optedit: tokudb_locks installed" );
    }
	else {
		$log->error( "Action: Sandbox $sandedit in $optedit: tokudb_locks install failed" );
		$log->logexit( qq|Report: $stderr_toku6| );
	}

    my $cmd_toku7 = path($sandedit, 'use -e ');
    $cmd_toku7 .= qq{"INSTALL PLUGIN tokudb_lock_waits SONAME 'ha_tokudb.so'"};
    my ($stdout_toku7, $stderr_toku7, $exit_toku7) = _capture_output( $cmd_toku7, $param_href );
    if ($exit_toku7 == 0) {
        $log->info( "Action: Sandbox $sandedit in $optedit: tokudb_lock_waits installed" );
    }
	else {
		$log->error( "Action: Sandbox $sandedit in $optedit: tokudb_lock_waits install failed" );
		$log->logexit( qq|Report: $stderr_toku7| );
	}

    #restart MySQl to check if TokuDB works
    my $cmd_restart2 = path($sandedit, 'restart');
    my ($stdout_res2, $stderr_res2, $exit_res2) = _capture_output( $cmd_restart2, $param_href );
    if ($exit_res2 == 0) {
        #restart succeeded
        $log->warn( "Sandbox $sandedit restarted with MySQL in $optedit and TokuDB engine added" );
    }
	else {
		#restart failed
		$log->logexit( "Sandbox $sandedit failed to restart AFTER TokuDB install" );
	}

    return;
}


### INTERNAL UTILITY ###
# Usage      : _enable_tokudb_options( $param_href );
# Purpose    : enables TokuDB options in my.sandbox.cnf after TokuDB is running
# Returns    : nothing
# Parameters : $partam_href with $sandedit and $optedit
# Throws     : croaks if wrong number of parameters
#            : exit if restart fails
# Comments   : part of edit_tokudb() mode
# See Also   : edit_tokudb()
sub _enable_tokudb_options {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_enable_tokudb_options() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my $optedit  = $param_href->{optedit}  or $log->logcroak( 'no $optedit specified on command line!' );
    my $sandedit = $param_href->{sandedit} or $log->logcroak( 'no $sandedit specified on command line!' );

    # locations of config files in Percona installation
    my $config_path   = path( $sandedit, 'my.sandbox.cnf' );    # for reading
    my $config_path2  = path( $sandedit, 'my.sandbox.cnf2' );   # for writing

    # for enabling TokuDB options (only after TokuDB plugin install)
	my $cnf_new = path($config_path)->slurp;   #read old version
    $cnf_new =~ s/#tokudb_/tokudb_/g;                                #enable TokuDB options
    $cnf_new =~ s/#default_storage_engine/default_storage_engine/;   #enable TokuDB as default engine
	#enable TokuDB as default explicit temporary table engine
	#implicit Memory for memory tables, and MyISAM for tables on disk
    $cnf_new =~ s/#default_tmp_storage_engine/default_tmp_storage_engine/;
	open my $sandbox_cnf_new_fh, ">", $config_path2 or $log->logdie( "Error: can't find cnf at $config_path2: $!" );
    print {$sandbox_cnf_new_fh} $cnf_new;
	close $sandbox_cnf_new_fh;

	# rename configs
	path($config_path2)->move($config_path) 
	  and $log->trace( "Renamed $config_path2 to original $config_path UPDATED with TokuDB options" );
	
    #check visually if all OK
	my $cmd_cat2 = qq{cat $config_path};
	my ($stdout_cat2, $stderr_cat2, $exit_cat2) = _capture_output( $cmd_cat2, $param_href );
	if ($exit_cat2 == 0) {
		#$log->trace( "$stdout_cat2" );
	}

	#restart MySQl to check if TokuDB works (after enabling options)
	my $cmd_restart3 = path($sandedit, 'restart');
	my ($stdout_res3, $stderr_res3, $exit_res3) = _capture_output( $cmd_restart3, $param_href );
    if ($exit_res3 == 0) {
            #restart succeeded
            $log->warn( "Sandbox $sandedit restarted with MySQL in $optedit and TokuDB options enabled in my.sandbox.cnf" );
    }
	else {
		#restart failed
		$log->logexit( "Sandbox $sandedit failed to restart AFTER enabling TokuDB options" );
	}

    return;
}


### INTERFACE SUB ###
# Usage      : edit_deep_report( $param_href );
# Purpose    : installs Deep storage engine to MySQL (adds cron job with reporting to deep.is
# Returns    : nothing
# Parameters : ( $param_href ) -if from command line
# Throws     : croaks if wrong number of parameters
# Comments   : it modifies my.cnf for Deep Engine (incompatible with TokuDB)
# See Also   : run install_mysql() before this sub
sub edit_deep_report {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('edit_deep_report() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $infile   = $param_href->{infile}   or $log->logcroak('no $infile specified on command line!');
    my $optedit  = $param_href->{optedit}  or $log->logcroak('no $optedit specified on command line!');
    my $sandedit = $param_href->{sandedit} or $log->logcroak('no $sandedit specified on command line!');
    $log->trace("Deep plugin in tar.gz format: $infile");
    $log->trace("MySQL installation in: $optedit");
    $log->trace("MySQL sandbox in : $sandedit");

    # extracts Deep engine tar files and moves them into location
    _extract_deep($param_href);

    # updates my.sandbox.cnf to add tcmalloc to mysqld_safe section
    _add_tcmalloc_to_config($param_href);

    # install Deep plugin inside MySQL and add Deep options to my.sandbox.cnf
    _deep_install_and_enable_options($param_href);

    return;
}


### INTERNAL UTILITY ###
# Usage      : _extract_deep( $param_href );
# Purpose    : extracts Deep engine tar files and moves them into location
# Returns    : nothing
# Parameters : $param_href for infile amd out
# Throws     : croaks if wrong number of parameters
#            : exit if untar fails
# Comments   : part of edit_deep_report()
# See Also   : edit_deep_report()
sub _extract_deep {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_extract_deep() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my $infile = $param_href->{infile} or $log->logcroak('no $infile specified on command line!');
    my $sandedit = $param_href->{sandedit} or $log->logcroak('no $sandedit specified on command line!');
    my $optedit  = $param_href->{optedit}  or $log->logcroak( 'no $optedit specified on command line!' );

	#remove dir with extracted files
	my $path_extract_here = path($infile)->parent;
	(my $path_extracted = $infile) =~ s/\A(.+?)\.tar\.gz\z/$1/;
	if (-d $path_extracted) {
		$log->warn( "$path_extracted found: deleting it!" );
		path($path_extracted)->remove_tree and $log->warn( "$path_extracted deleted!" );
	}

	#now extract files and do something for each file
    my $cmd_untar = qq{tar -xzvf $infile -C $path_extract_here};
    my ($stdout_untar, $stderr_untar, $exit_untar) = _capture_output( $cmd_untar, $param_href );
        if ($exit_untar == 0 and -d $path_extracted) {
            #extract succeeded
            $log->trace( "Deep tar.gz extracted to $path_extracted" );

			# collect all extracted files
			my @deep_files = File::Find::Rule->file()
                             ->name( '*' )
                             ->in( $path_extracted );
			
			#print found files to log
			if (@deep_files) {
				my $deep_files = join("\n", @deep_files);
				$log->trace( qq|Report:$deep_files| );
			}
			else {
				$log->logexit( qq|No deep_files found| );
			}

            #move files to $optedit (MySQL installation dir)
            DEEPFILES:
            foreach my $file (@deep_files) {
                if ($file =~ /ha_deep.so/) {
					my $path_plugins = path($optedit, 'lib', 'plugin');
                    path($file)->copy($path_plugins)
				      and $log->info( "Action: file $file copied to MySQL plugin dir at $path_plugins" );
                }
                elsif($file =~ /libtcmalloc_minimal.so/) {
					my $path_tcmalloc = path($optedit, 'lib', 'libtcmalloc_minimal.so');
                    path($file)->move($path_tcmalloc)
                      and $log->info( "Action: file $file replaced MySQL's original lib at $path_tcmalloc" );
                }
                elsif($file =~ /deep-license.sh/) {
					#first copy it
					my $path_opt_scripts = path($optedit, 'scripts');
					path($file)->copy($path_opt_scripts)
                      and $log->info( "Action: licence $file copied to $path_opt_scripts!" );

				    #make it executable to be able to run it
				    my $path_license = path($path_opt_scripts, 'deep-license.sh')->canonpath;
					chmod 0777, $path_license and $log->trace( "Action: license $path_license mode changed to 0777" );

					#run a license file to create a log
					my $path_datadir = path($sandedit, 'data')->canonpath;
					my $path_datadir_log = path($path_datadir, 'deep_usage.log')->canonpath;
					my $cmd_run = qq{$path_license -a install -p yes -l $path_datadir_log -d $path_datadir};
					my ($stdout_run, $stderr_run, $exit_run) = _capture_output( $cmd_run, $param_href );
					if ($exit_run == 0) {
						$log->trace( "Action: Deep log created at $path_datadir_log!" );
					}

					#change permissions on deep_usage_log
					chmod 0777, $path_datadir_log and $log->trace( "Action: license's $path_datadir_log mode changed to 0777" );

					#setup a cron job for report
					_setup_cron_job_for( $param_href, $path_datadir_log, $path_datadir, $path_opt_scripts);


                }
				else {
					$log->error( "Error: new $file found" );
				}
            }
        }
	#exit if untar fails
	else {
		$log->logexit( qq|Error: $stdout_untar| );
	}
	
	#clean extracted dir
	if (-d $path_extracted) {
		$log->trace( "$path_extracted left: cleaning it!" );
		path($path_extracted)->remove_tree and $log->info( "$path_extracted deleted!" );
	}

    return;
}


### INTERNAL UTILITY ###
# Usage      : _setup_cron_job_for( $param_href, $path_datadir_log, $path_datadir, $path_opt_scripts);
# Purpose    : setup a cron job to report Deep usage to Deep.is
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : part of _extract_deep() of edit_deep_report()
# See Also   : _extract_deep()
sub _setup_cron_job_for {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_setup_cron_job_for() needs a $param_href + 3 other') unless @_ == 4;
    my ($param_href, $path_datadir_log, $path_datadir, $path_opt_scripts) = @_;
	my $path_license = path($path_opt_scripts, 'deep-license.sh')->canonpath;

	#command to run in cron
	my $cmd = qq{$path_license -a stats -p yes -l $path_datadir_log -d $path_datadir};

	#making a new crontab from scratch
	require Config::Crontab;

	#make a new crontab object
	my $ct = new Config::Crontab;
	$ct->owner("$ENV{HOME}");

	#make a new Event object
	my $event = new Config::Crontab::Event(
	  -minute  => 02,
	  -hour    => 4,
	  -command => "$cmd");

	#make a new Block object
	my $block = new Config::Crontab::Block;
	#add created event to the block object
	$block->last($event);
	#add this block to the crontab object
	$ct->last($block);

	## write out crontab file
	my $mysql_name = path($param_href->{optedit})->basename;
	$mysql_name =~ s/\.//g;
	my $path_cron = path($path_opt_scripts, 'deep_license' . $mysql_name);
	$ct->write($path_cron) and $log->debug( "Cron job created at $path_cron" ) or do {
		warn "Error: " . $ct->error . "\n";
		return;
	};

	#add to crontab
	my $cmd_add_to_crontab = qq{crontab $path_cron};
	my ($stdout_cronadd, $stderr_cronadd, $exit_cronadd) = _capture_output( $cmd_add_to_crontab, $param_href );
	if ($exit_cronadd == 0) {
		$log->info( qq|Action: crontab $path_cron added to crontab| );
	}
	else {
		#not installed
		my $cmd_crontab = q{sudo yum install -y cronie};
		_exec_cmd($cmd_crontab, $param_href, 'yum cronie install');
	}
	
	#check for existence of created crontab
	# same as 'crontab -l' except pretty-printed
	my $ct_check = new Config::Crontab;
	$ct_check->read;
	my $crontab = sprintf("%s", $ct_check->dump);
	$log->debug( qq|Report: $crontab| );

    return;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : _add_tcmalloc_to_config( $param_href );
# Purpose    : updates my.sandbox.cnf to add tcmalloc to mysqld_safe section
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : part of edit_deep_report()
# See Also   : edit_deep_report()
sub _add_tcmalloc_to_config {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_add_tcmalloc_to_config() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my $optedit  = $param_href->{optedit}  or $log->logcroak('no $optedit specified on command line!');
    my $sandedit = $param_href->{sandedit} or $log->logcroak('no $sandedit specified on command line!');

    #change my.cnf options
    my $config_path  = path( $sandedit, 'my.sandbox.cnf' );     # original config
    my $config_path2 = path( $sandedit, 'my.sandbox.cnf2' );    # modified config
    my $cnf_mysqld_safe = <<"MYSQLD";

[mysqld_safe]
malloc_lib=tcmalloc

MYSQLD

    #add mysqld_safe section
    open my $sandbox_cnf_write_fh, ">", $config_path2 or $log->logdie("Can't find cnf at $config_path2: $!");
    my $cnf_old = path($config_path)->slurp;                    #read old version

    print {$sandbox_cnf_write_fh} $cnf_mysqld_safe;
    print {$sandbox_cnf_write_fh} $cnf_old;
    close $sandbox_cnf_write_fh;

    path($config_path2)->move($config_path)
      and $log->trace("Action: renamed $config_path2 to original $config_path");

    my $cmd_cat = qq{cat $config_path};
    my ( $stdout_cat, $stderr_cat, $exit_cat ) = _capture_output( $cmd_cat, $param_href );

    #restart MySQl to check if config ok
    my $cmd_restart = path( $sandedit, 'restart' );
    my ( $stdout_res, $stderr_res, $exit_res ) = _capture_output( $cmd_restart, $param_href );
    if ( $exit_res == 0 ) {
        #restart succeeded
        $log->warn(
            "Report: sandbox $sandedit restarted with MySQL in $optedit and tcmalloc options added to $config_path");
    }
    else {
        #restart failed
        $log->error(qq|Error: $stderr_res|);
        $log->logexit("Error: sandbox $sandedit failed to restart during tcmalloc UPDATE to $config_path");
    }

	#check if MySQL server started with tcmalloc (then installed)
	my $malloc_type_href = _check_malloc_type_for( $param_href );
	if (exists $malloc_type_href->{tcmalloc}) {
		$log->warn( "Report: tcmalloc installed in $malloc_type_href->{tcmalloc}" );
	}

    return;
}



### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : _deep_install_and_enable_options( $param_href );
# Purpose    : installs Deep engine and updated my.sandbox.cnf for Deep options
# Returns    : nothing
# Parameters : $param_href for sandedit and optedit
# Throws     : croaks if wrong number of parameters
# Comments   : part of edit_deep_report()
# See Also   : edit_deep_report()
sub _deep_install_and_enable_options {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_deep_install_and_enable_options() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my $optedit  = $param_href->{optedit}  or $log->logcroak('no $optedit specified on command line!');
    my $sandedit = $param_href->{sandedit} or $log->logcroak('no $sandedit specified on command line!');

    # install Deep plugin inside MySQL
    my $cmd_deep = path( $sandedit, 'use' );
    $cmd_deep .= qq{ -e "INSTALL PLUGIN Deep SONAME 'ha_deep.so'"};
    my ( $stdout_deep, $stderr_deep, $exit_deep ) = _capture_output( $cmd_deep, $param_href );
    if ( $exit_deep == 0 ) {
        #installation succeeded
        $log->info("Action: sandbox $sandedit in $optedit: Deep engine INSTALLED");
    }
    else {
        #installation failed
        $log->error(qq|Error: $stderr_deep|);
        $log->logexit(qq|Error: sandbox $sandedit in $optedit: Deep engine failed to install|);
    }

    #update MySQL config files with Deep options
    my $config_path = path( $sandedit, 'my.sandbox.cnf' );
    open my $sandbox_cnf_fh, ">>", $config_path or $log->logdie("Can't find my.sandbox.cnf at $config_path: $!");
    my $cnf_activation = <<"SQL";

## Deep #
deep-activation-key            = 01010100a0y13000006QeuR1463097600
deep_mode_key_compress         = ON
deep_mode_value_compress       = ON
deep_cache_size                = 1G
default_storage_engine         = Deep
default_tmp_storage_engine     = Deep
deep_value_compress_percent    = 15
deep_mode_durable              = OFF
deep_durable_sync_interval     = 0
deep_worker_threads            = 6

SQL

    #add activation
    print {$sandbox_cnf_fh} $cnf_activation, "\n";
    $log->info("Action: MySQL config $config_path modified with activation for Deep");
    close $sandbox_cnf_fh;

    my $cmd_cat = qq{cat $config_path};
    my ( $stdout_cat, $stderr_cat, $exit_cat ) = _capture_output( $cmd_cat, $param_href );

    #restart MySQl to check if Deep works
    my $cmd_restart = path( $sandedit, 'restart' );
    my ( $stdout_res, $stderr_res, $exit_res ) = _capture_output( $cmd_restart, $param_href );
    if ( $exit_res == 0 ) {
        #restart succeeded
        $log->warn(
            "Action: sandbox $sandedit restarted with MySQL in $optedit and Deep engine added (and activation to my.cnf)"
        );
    }
    else {
        #restart failed
        $log->error(qq|Error: $stderr_res|);
        $log->logexit("Error: sandbox $sandedit failed to restart AFTER Deep install and activation to my.cnf");
    }

    return;
}

### INTERFACE SUB ###
# Usage      : install_scaledb( $param_href );
# Purpose    : installs MariaDB binary using MySQL::Sandbox with check port enabled and ScaleDB
# Returns    : nothing
# Parameters : ( $param_href ) --infile from command line
# Throws     : croaks if wrong number of parameters
# Comments   : it modifies my.cnf for high performance too
# See Also   :
sub install_scaledb {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('install_scaledb() needs a $param_href' ) unless @_ == 1;
    my ( $param_href ) = @_;
    my $infile = $param_href->{infile} or $log->logcroak( 'no $infile specified on command line!' );
    my $prefix = $param_href->{prefix} or $log->logcroak( 'no $prefix specified on command line!' );
    my $opt = $param_href->{opt}       or $log->logcroak( 'no $opt specified on command line!' );

	# install libraries needed by ScaleDB
	_install_scaledb_prereq( $param_href );

	# repack MariaDB to be usable by MySQL::Sandbox
	my $maria_end_archive = _repack_maria( $param_href );

	# repack ScaldDB UDE to the installed sandbox
	my $scaledb_end_archive = _repack_scaledb( $param_href );

	# setup of sandbox and opt names
	my ( $mysql_ver, $mysql_num, $sandbox_path, $opt_path ) = _get_sandbox_name_from_maria( $maria_end_archive, $prefix );

	# check for existence of sandbox dir
    if (-d $sandbox_path) {
        $log->warn( "Report: sandbox $sandbox_path already exists" );
	}

	# check for existence of opt/mysql dir
	if (-d $opt_path) {
		$log->warn( "Report: extracted $mysql_ver already exists in $opt_path" );
	}

    #fresh install
	#set variables for sandbox, opt, new port
	my ($sandbox_port, $sandbox_dir, $opt_basedir);
    $log->info( "Action: installing $mysql_ver with port checking and prefix={$prefix}" );
    my $cmd_make = qq{make_sandbox --export_binaries $maria_end_archive --add_prefix=$prefix -- --check_port --no_confirm};
    my ($stdout, $stderr, $exit) = _capture_output( $cmd_make, $param_href );
    if ($exit == 0) {
        #install succeeded
		open (my $stdout_fh, "<", \$stdout) or $log->logdie( "Error: can't open $stdout for reading:$!" );

		while (<$stdout_fh>) {
			chomp;
			if (m{\Asandbox_port\s+=\s+(\d+)\z}) {
				$sandbox_port = $1;
			}
			if (m{\Asandbox_directory\s+=\s+(.+)\z}) {
				$sandbox_dir = $1;
				$sandbox_dir = path($ENV{SANDBOX_HOME}, $sandbox_dir);
			}
			if (m{\Abasedir\s+=\s+(.+)\z}) {
				$opt_basedir = $1;
			}
		}   # end while

        $log->info( "Report: sandbox installed in $sandbox_dir with MySQL in $opt_basedir port:{$sandbox_port}" );
    }
	else {
		$log->error( "Error: MySQL$mysql_ver failed to install" );
		$log->logexit( "Error: $stderr" );
	}

    #check my.cnf options
	my ($mysql_cnf_path, $mysql_datadir) = _check_my_cnf_for( $sandbox_dir, $opt_basedir );

    #change my.cnf options
    open my $sandbox_cnf_fh, ">>", $mysql_cnf_path or $log->logdie( "Can't find cnf: $!" );
	#set innodb-buffer-pool-size
	my $innodb_buffer = defined $param_href->{innodb} ? $param_href->{innodb} : '1G';

my $cnf_options = <<"SQL";

# MyISAM #
key-buffer-size                = 32M
myisam-recover-options         = FORCE,BACKUP

# SAFETY #
max-allowed-packet             = 16M
max-connect-errors             = 1000000
skip-name-resolve
sql-mode                       = STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_AUTO_VALUE_ON_ZERO,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE
sysdate-is-now                 = 1
#innodb                         = FORCE
innodb-strict-mode             = 1

# TRANSACTION ISOLATION
# default is: transaction-isolation = REPEATABLE-READ
transaction-isolation          = READ-COMMITTED

# BINARY LOGGING #
#server-id                      = $sandbox_port
#log-bin                        = mysql-bin
#expire-logs-days               = 14
#sync-binlog                    = 1

# CACHES AND LIMITS #
#warning: large tmp table sizes (use for OLAP only)
tmp-table-size                 = 100M
max-heap-table-size            = 100M
query-cache-type               = 0
query-cache-size               = 0
max-connections                = 500
thread-cache-size              = 50
open-files-limit               = 65535
table-definition-cache         = 1024
table-open-cache               = 2048

# INNODB #
innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-log-file-size           = 1G
innodb-flush-log-at-trx-commit = 2
innodb-file-per-table          = 1
innodb-buffer-pool-size        = $innodb_buffer
#default: innodb-buffer-pool-instances   = 8
innodb-buffer-pool-instances   = 1
innodb_doublewrite             = OFF

# TIMEZONE #
character_set_server           = latin1
collation_server               = latin1_swedish_ci

# LOGGING #
slow-query-log                 = off
#slow-query-log-file            = $sandbox_dir/data/msandbox-slow.log
#log-queries-not-using-indexes  = 1
#long_query_time                = 0
#log-error                      = $sandbox_dir/data/msandbox.err
performance_schema             = off

# TokuDB #
#tokudb_cache_size              = 1G
#tokudb_data_dir                = $sandbox_dir/data
#tokudb_log_dir                 = $sandbox_dir/data
#tokudb_tmp_dir                 = $sandbox_dir/data
#tokudb_commit_sync             = 1
#tokudb_directio                = 0
#tokudb_load_save_space         = 1
#default_storage_engine         = TokuDB
#default_tmp_storage_engine     = TokuDB
SQL

    print {$sandbox_cnf_fh} $cnf_options, "\n";
    $log->info("MySQL config $mysql_cnf_path modified for InnoDB" );
    close $sandbox_cnf_fh;


    #delete InnoDB logfiles (else it doesn't start)
    foreach my $i (0..1) {
        my $log_file = path($mysql_datadir, 'ib_logfile' . $i);
        unlink $log_file and $log->trace( "Action: InnoDB logfile $log_file deleted" ) 
          or $log->logdie( "Error: InnoDB file: $log_file not found: $!" );
    }

    #restart MySQl to check if config ok
    my $cmd_restart = path($sandbox_dir, 'restart');
    my ($stdout_res, $stderr_res, $exit_res) = _capture_output( $cmd_restart, $param_href );
    if ($exit_res == 0) {
            #restart succeeded
            $log->warn( "Action: sandbox $sandbox_dir restarted with MySQL in $opt_basedir port{$sandbox_port}" );
    }
	else {
		#restart failed
		$log->logexit( "Error: sandbox $sandbox_dir failed to restart AFTER updating InnoDB options" );
	}

	# unpack ScaleDB plugin on top of MariaDB installation
	_extract_to_sandbox();

    return;
}

### INTERNAL UTILITY ###
# Usage      : _install_scaledb_prereq( $param_href )
# Purpose    : installs prerequisites for installing MariaDb with ScaleDB ()
# Returns    : hash with flags
# Parameters : $param_href
# Throws     :
# Comments   : first part of install_scaledb() mode
# See Also   : install_scaledb() mode
sub _install_scaledb_prereq {
    die('_install_scaledb_prereq() needs $param_href') unless @_ == 1;
    my ($param_href) = @_;
	my %flags;

	#install prerequisites for ScaleDB
	# check OS version
	$flags{installer} = do {
		if    (-e '/etc/debian_version') { 'apt-get' }
		elsif (-e '/etc/centos-release') { 'yum' }
		elsif (-e '/etc/redhat-release') { 'yum' }
		else                             { 'yum' }
	};

	#install nc, nmap, libaio
	my $cmd_nc = "sudo $flags{installer} -y install nmap nc nettools libaio libaio1 nmap-ncat";
	my $exit_nc = _exec_cmd($cmd_nc, $param_href, 'nc and tools install');
	$flags{nc} = 1 if $exit_nc == 0;

    return %flags;
}

### INTERNAL UTILITY ###
# Usage      : _repack_maria( $param_href )
# Purpose    : repacks MariaDB to be installable my MySQL::Sandbox
# Returns    : nothing
# Parameters : $param_href
# Throws     : 
# Comments   : second utility of install_scaledb() mode
# See Also   : install_scaledb() mode
sub _repack_maria {
    my $log = Log::Log4perl::get_logger("main");
    die('_repack_maria() needs $param_href') unless @_ == 1;
    my ($param_href) = @_;
	my %flags;

    my $mariadb_org_path = $param_href->{infile};
	my $mariadb_archive = path($mariadb_org_path)->basename;
	say "ORG:$mariadb_archive";
	my ($maria_end_path) = $mariadb_archive =~ m{scaledb\-(?:[^-]+)\-(.+?)\.(?:tgz|tar\.gz)\z};
	say "New path:$maria_end_path";
	$maria_end_path = path($ENV{HOME}, $maria_end_path)->canonpath;
	say "New path:$maria_end_path";
	my $maria_end_archive = $maria_end_path . '.tar.gz';
	$maria_end_archive = path($maria_end_archive)->canonpath;

	#scaledb-15.10.1-mariadb-10.0.14.tgz
	
	# check for existence of tmp dir
	my $tmp_dir = path('/tmp/maria/');
    if (-d $tmp_dir) {
        $log->warn( "Report: tmpdir $tmp_dir already exists" );
		path($tmp_dir)->remove_tree( { safe => 0 } ) and $log->warn( "$tmp_dir deleted!" );   # force remove
	}

	# untar MariaDB to repack it later
	my $cmd_untar = "mkdir /tmp/maria && tar -xzf $mariadb_org_path -C /tmp/maria";
	my $exit_untar = _exec_cmd($cmd_untar, $param_href, 'untar mariadb');
	$flags{untar} = 1 if $exit_untar == 0;

	# tar MariaDB to use it by MySQL::Sandbox
	my $cmd_tar = "cd /tmp/maria/usr/local/mysql/ && tar -czf $maria_end_archive *";
	my $exit_tar = _exec_cmd($cmd_tar, $param_href, 'tar mariadb');
	$flags{tar} = 1 if $exit_untar == 0;

	#change path 
	#cd && mkdir $maria_end_path
	my $cmd_cd = "cd && mkdir -p $maria_end_path";
	my $exit_cd = _exec_cmd($cmd_cd, $param_href, 'mariadb dir created');
	$flags{cd} = 1 if $exit_cd == 0;

	# untar MariaDB to repack it later
	my $cmd_untar2 = "tar -xzf $maria_end_archive -C $maria_end_path";
	my $exit_untar2 = _exec_cmd($cmd_untar2, $param_href, 'untar mariadb');
	$flags{untar2} = 1 if $exit_untar2 == 0;

	# tar MariaDB to use it by MySQL::Sandbox
	my $cmd_tar2 = "cd && tar -czf $maria_end_archive $maria_end_path";
	my $exit_tar2 = _exec_cmd($cmd_tar2, $param_href, 'tar mariadb');
	$flags{tar2} = 1 if $exit_untar2 == 0;

	say "Maria END archive path:$maria_end_archive";
    return $maria_end_archive;
}


### INTERNAL UTILITY ###
# Usage      : _repack_scaledb( $param_href )
# Purpose    : repacks MariaDB to be installable my MySQL::Sandbox
# Returns    : nothing
# Parameters : $param_href
# Throws     : 
# Comments   : second utility of install_scaledb() mode
# See Also   : install_scaledb() mode
sub _repack_scaledb {
    my $log = Log::Log4perl::get_logger("main");
    die('_repack_scaledb() needs $param_href') unless @_ == 1;
    my ($param_href) = @_;
	my %flags;

    my $scaledb_org_path = $param_href->{plugin};
	my $scaledb_archive = path($scaledb_org_path)->basename;
	say "ORG:$scaledb_archive";
	my ($scaledb_end_path) = $scaledb_archive =~ m{(.+?)(?:tgz|tar\.gz)\z};
	say "New path:$scaledb_end_path";
	$scaledb_end_path = path($ENV{HOME}, $scaledb_end_path)->canonpath;
	say "New path:$scaledb_end_path";
	my $scaledb_end_archive = $scaledb_end_path . '.tar.gz';
	$scaledb_end_archive = path($scaledb_end_archive)->canonpath;

	#scaledb-15.10.1-13199-ude.tgz
	
	# check for existence of tmp dir
	my $tmp_dir = path('/tmp/scaledb/');
    if (-d $tmp_dir) {
        $log->warn( "Report: tmpdir $tmp_dir already exists" );
		path($tmp_dir)->remove_tree( { safe => 0 } ) and $log->warn( "$tmp_dir deleted!" );   # force remove
	}

	# untar ScaleDB plugin to repack it later
	my $cmd_untar = "mkdir /tmp/scaledb && tar -xzf $scaledb_org_path -C /tmp/scaledb";
	my $exit_untar = _exec_cmd($cmd_untar, $param_href, 'untar scaledb');
	$flags{untar} = 1 if $exit_untar == 0;

	# tar ScaleDB plugin to use it by MySQL::Sandbox
	my $cmd_tar = "cd /tmp/scaledb/usr/local/scaledb/ && tar -czf $scaledb_end_archive *";
	my $exit_tar = _exec_cmd($cmd_tar, $param_href, 'tar scaledb');
	$flags{tar} = 1 if $exit_untar == 0;

	#change path 
	#cd && mkdir $scaledb_end_path
	my $cmd_cd = "cd && mkdir -p $scaledb_end_path";
	my $exit_cd = _exec_cmd($cmd_cd, $param_href, 'scaledb dir created');
	$flags{cd} = 1 if $exit_cd == 0;

	# untar ScaleDB plugin to repack it later
	my $cmd_untar2 = "tar -xzf $scaledb_end_archive -C $scaledb_end_path";
	my $exit_untar2 = _exec_cmd($cmd_untar2, $param_href, 'untar scaledb');
	$flags{untar2} = 1 if $exit_untar2 == 0;

	# tar ScaleDB plugin to use it by MySQL::Sandbox
	my $cmd_tar2 = "cd && tar -czf $scaledb_end_archive $scaledb_end_path";
	my $exit_tar2 = _exec_cmd($cmd_tar2, $param_href, 'tar scaledb');
	$flags{tar2} = 1 if $exit_untar2 == 0;

	say "ScaleDB END archive path:$scaledb_end_archive";
    return $scaledb_end_archive;
}





















1;
__END__

=encoding utf-8

=head1 NAME

MySQLinstall - is installation script (modulino) that installs MySQL::Sandbox using cpanm, MySQL in a sandbox, additional engines like TokuDB and Deep and updates configuration. If you want to install newer Perl on your machine you can use L<< To install Perl use Perlinstall.pm.

=head1 SYNOPSIS

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


=head1 DESCRIPTION

MySQLinstall is installation script that installs MySQL::Sandbox using cpanm, MySQL in a sandbox, additional engines like TokuDB and Deep and updates configuration for MySQL.

 --mode=mode				Description
 --mode=install_sandbox		installs MySQL::Sandbox and prompts for modification of .bashrc
 --mode=wget_mysql			downloads MySQL from Oracle or Percona serer from Percona site
 --mode=install_mysql		installs MySQL and modifies my.cnf for performance
 --mode=edit_deep_report	installs Deep plugin
 --mode=edit_tokudb			installs TokuDB plugin
 
 For help write:
 MySQLinstall.pm -h
 MySQLinstall.pm -m

=head2 MODES

=over 4

=item install_sandbox

 # options from command line
 MySQLinstall.pm --mode=install_sandbox --sandbox=$HOME/sandboxes/ --opt=$HOME/opt/mysql/

 # options from config
 MySQLinstall.pm --mode=install_sandbox

Install MySQL::Sandbox, set environment variables (SANDBOX_HOME and SANBOX_BINARY) and create these directories if needed.

=item wget_mysql

 #option from command line (can also come from config)
 MySQLinstall.pm --mode=wget_mysql --url http://dev.mysql.com/get/Downloads/MySQL-5.6/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz

Downloads MySQL binary from internet link. Resumes broken downloads.

=item install_mysql

 #option from command line (can also come from config)
 MySQLinstall.pm --mode=install_mysql --infile mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz

Installs MySQL in sandbox named after MySQL version and puts binary into "opt/mysql" directory. It rewrites existing installation.

=item install_mysql_with_prefix

 MySQLinstall.pm --mode=install_mysql_with_prefix --prefix=deep_ --infile=mysql-5.6.28-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall.pm --mode=install_mysql_with_prefix --prefix=tokudb_ --infile=Percona-Server-5.6.29-rel76.2-Linux.x86_64.ssl101.tar.gz

Installs MySQL with port checking and prefix. It doesn't rewrite previous MySQL instance. Useful for installing multiple MySQL servers with same version but different storage engines.

=item edit_tokudb

 MySQLinstall.pm --mode=edit_tokudb --sandedit=/home/msestak/sandboxes/msb_5_6_27 --optedit=/home/msestak/opt/mysql/5.6.27

Installs TokuDB storage engine if transparent_hugepage=never is already set. It also updates MySQL config for TokuDB setting it as default_storage_engine (and for tmp tables too).

=item edit_deep_report

 MySQLinstall.pm --mode=edit_deep_report --infile=./download/deep-mysql-5.6.26-community-plugin-3.2.0.19896.el6.x86_64.tar.gz --sandedit=/home/msestak/sandboxes/msb_5_6_27 --optedit=/home/msestak/opt/mysql/5.6.27

Installs Deep storage engine from downloaded tar.gz archive. It also updates MySQL config for Deep setting it as default_storage_engine (and for tmp tables too).

=item install_scaledb

 # not finished (doesn't work)
 MySQLinstall.pm --mode=install_scaledb -if /home/msestak/scaledb-15.10.1-mariadb-10.0.14.tgz --prefix=scaledb_ --plugin=/home/msestak/scaledb-15.10.1-13199-ude.tgz

Installs MariaDB with ScaleDB storage engine from downloaded tar.gz archive. It also updates MySQL config for ScaleDB setting it as default_storage_engine (and for tmp tables too).

=back

=head1 CONFIGURATION

All configuration in set in mysqlinstall.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows L<< Config::Std|https://metacpan.org/pod/Config::Std >> format and rules.
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


=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

mocnii E<lt>msestak@irb.hrE<gt>

=cut


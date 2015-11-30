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
        install_sandbox          => \&install_sandbox,               #and create dirs
        wget_mysql               => \&wget_mysql,                    #from mysql internet site
        install_mysql            => \&install_mysql,                 #edit also general options in my.cnf for InnoDB
        install_mysql_with_prefix => \&install_mysql_with_prefix,      # installs MySQL with different port if version port used
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
		'config|cnf=s'  => \$cli{config},
        'in|i=s'        => \$cli{in},
        'infile|if=s'   => \$cli{infile},
        'out|o=s'       => \$cli{out},
        'outfile|of=s'  => \$cli{outfile},
		'prefix=s'      => \$cli{prefix},

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
# Usage      : _exec_cmd($cmd_git, $param_href);
# Purpose    : accepts command, executes it and checks for success
# Returns    : prints info
# Parameters : ($cmd_to_execute, $param_href)
# Throws     : 
# Comments   : second param is verbose flag (default off)
# See Also   :
sub _exec_cmd {
    my $log = Log::Log4perl::get_logger("main");
    $log->logdie( '_exec_cmd() needs a $cmd, $param_href and info' ) unless (@_ ==  2 or 1);
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
        unlink $log_file and $log->trace( "InnoDB logfile $log_file deleted" ) 
          or $log->logdie( "InnoDB file: $log_file not found: $!" );
    }

    #restart MySQl to check if config ok
    my $cmd_restart = path($sandbox_path, 'restart');
    my ($stdout_res, $stderr_res, $exit_res) = _capture_output( $cmd_restart, $param_href );
        if ($exit_res == 0) {
                #restart succeeded
                $log->warn( "Sandbox $sandbox_path restarted with MySQL in $opt_path" );
        }
		else {
			#restart failed
			$log->logexit( "Sandbox $sandbox_path failed to restart AFTER updating InnoDB options" );
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

    return;
}





1;
__END__

=encoding utf-8

=head1 NAME

MySQLinstall - is installation script (modulino) that installs MySQL::Sandbox using cpanm, MySQL in a sandbox, additional engines like TokuDB and Deep and updates configuration. To install Perl use Perlinstall.pm.

=head1 SYNOPSIS

 MySQLinstall --mode=install_sandbox --sandbox=/msestak/sandboxes/ --opt=/msestak/opt/mysql/

 MySQLinstall --mode=wget_mysql -url http://dev.mysql.com/get/Downloads/MySQL-5.5/mysql-5.5.43-linux2.6-x86_64.tar.gz

 MySQLinstall --mode=install_mysql -i ./download/mysql-5.6.26-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall --mode=install_mysql --in=./download/Percona-Server-5.6.25-rel73.1-Linux.x86_64.ssl101.tar.gz

 MySQLinstall --mode=edit_tokudb --opt=/home/msestak/opt/mysql/5.6.25/ --sand=/home/msestak/sandboxes/msb_5_6_25/

 MySQLinstall --mode=edit_deep -i deep-mysql-5.6.25-community-plugin-3.2.0.19654-1.el6.x86_64.rpm --sand=/msestak/sandboxes/msb_5_6_25/ --opt=/msestak/opt/mysql/5.6.25/
 or with reporting
 MySQLinstall --mode=edit_deep_report -i ./download/deep-mysql-5.6.26-community-plugin-3.2.0.19896.el6.x86_64.tar.gz --sand=/home/msestak/sandboxes/msb_5_6_26 --opt=/home/msestak/opt/mysql/5.6.26


=head1 DESCRIPTION

MySQLinstall is installation script that installs MySQL::Sandbox using cpanm, MySQL in a sandbox, additional engines like TokuDB and Deep and updates configuration for MySQL.

 --mode=mode				Description
 --mode=install_sandbox		installs MySQL::Sandbox and prompts for modification of .bashrc
 --mode=wget_mysql			downloads MySQL from Oracle
 --mode=wget_percona		downloads Percona Server with TokuDB
 --mode=install_mysql		installs MySQL and modifies my.cnf for performance
 --mode=edit_deep_report	installs TokuDB plugin
 --mode=edit_tokudb			installs Deep plugin
 
 For help write:
 MySQLinstall -h
 MySQLinstall -m

=head2 MODES

=over 4

=item install_sandbox

 # options from command line
 MySQLinstall --mode=install_sandbox --sandbox=$HOME/sandboxes/ --opt=$HOME/opt/mysql/

 # options from config
 MySQLinstall --mode=install_sandbox

Install MySQL::Sandbox, set environment variables (SANDBOX_HOME and SANBOX_BINARY) and create these directories if needed.

=item wget_mysql

 #option from command line (can also come from config)
 MySQLinstall --mode=wget_mysql --url http://dev.mysql.com/get/Downloads/MySQL-5.6/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz

Downloads MySQL binary from internet link. Resumes broken downloads.

=item install_mysql

 #option from command line (can also come from config)
 MySQLinstall --mode=install_mysql --infile mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz

Installs MySQL in sandbox named after MySQL version and puts binary into "opt/mysql" directory. It rewrites existing installation.

=item install_mysql_with_prefix

 MySQLinstall.pm --mode=install_mysql_with_prefix --prefix=tokudb_
 MySQLinstall.pm --mode=install_mysql_with_prefix --prefix=deep_

Installs MySQL with port checking and prefix. It doesn't rewrite previous MySQL instance. Useful for installing multiple MySQL servers with same version but different storage engines.

=back

=head1 CONFIGURATION

All configuration in set in mysqlinstall.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows L<< Config::Std|https://metacpan.org/pod/Config::Std >> format and rules.
Example:

 [General]
 sandbox  = /home/msestak/sandboxes
 opt      = /home/msestak/opt/mysql
 url      = http://dev.mysql.com/get/Downloads/MySQL-5.6/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz
 #url      = https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.27-75.0/binary/tarball/Percona-Server-5.6.27-rel75.0-Linux.x86_64.ssl101.tar.gz
 out      = /msestak/gitdir/MySQLinstall
 infile   = $HOME/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz
 
 [Database]
 host     = localhost
 database = test
 user     = msandbox
 password = msandbox
 port     = 5625
 socket   = /tmp/mysql_sandbox5625.sock
 innodb   = 1G
 prefix   = tokudb_

=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

mocnii E<lt>msestak@irb.hrE<gt>

=head1 EXAMPLE

 #install all modules
 cpanm -n Path::Tiny Capture::Tiny File::Find::Rule Log::Log4perl Config::Std

 MySQLinstall --mode=install_mysql --in=./download/Percona-Server-5.6.25-rel73.1-Linux.x86_64.ssl101.tar.gz
 MySQLinstall --mode=edit_tokudb --opt=/home/msestak/opt/mysql/5.6.25/ --sand=/home/msestak/sandboxes/msb_5_6_25/
 
 MySQLinstall --mode=install_mysql -i mysql-5.6.24-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall --mode=edit_deep -i deep-mysql-5.6.24-community-plugin-3.2.0.19297-1.el6.x86_64.rpm --sand=/msestak/sandboxes/msb_5_6_24/ --opt=/msestak/opt/mysql/5.6.24/

 MySQLinstall --mode=install_mysql -i mysql-5.6.24-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall --mode=edit_deep_report -i deep-mysql-5.6.24-community-plugin-3.2.0.19654.el6.x86_64.tar.gz --sand=/msestak/sandboxes/msb_5_6_24/ --opt=/msestak/opt/mysql/5.6.24/

 MySQLinstall --mode=install_mysql -i ./download/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz
 MySQLinstall --mode=edit_deep_report -i ./download/deep-mysql-5.6.27-community-plugin-3.3.0.20340.el6.x86_64.tar.gz --sand=/home/msestak/sandboxes/msb_5_6_27/ --opt=/home/msestak/opt/mysql/5.6.27/

=cut


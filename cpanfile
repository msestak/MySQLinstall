requires 'perl', '5.010001';

on 'test' => sub {
    requires 'Test::More', '0.98';
}'

requires 'strict';
requires 'warnings';
requires 'autodie';
requires 'Carp';
requires 'Path::Tiny';
requires 'Getopt::Long';
requires 'Pod::Usage';
requires 'Capture::Tiny';
requires 'Data::Dumper';
requires 'Log::Log4perl';
requires 'File::Find::Rule';
requires 'IO::Prompter';
requires 'Config::Std';

on 'develop' => sub {
  recommends 'Regexp::Debugger';
};


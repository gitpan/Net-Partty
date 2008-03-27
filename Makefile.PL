use inc::Module::Install;
name 'Net-Partty';
all_from 'lib/Net/Partty.pm';

requires $_ for (qw/ /);

build_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;

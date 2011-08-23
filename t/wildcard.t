# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl App-ConfigWild.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('Config::Wild') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $cfg = Config::Wild->new( 'cfgs/wildcard.cnf' );

ok( 1234 == $cfg->value('goo_1'), 'wildcard 1' );
ok( 5678 == $cfg->value('foo_cas'), 'wildcard 2' );

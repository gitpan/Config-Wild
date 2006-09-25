# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl App-ConfigWild.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('Config::Wild') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $cfg = Config::Wild->new( 'cfgs/blanks.cnf' );

ok( 'bar' eq $cfg->value('foo'), 'trailing blanks' );
ok( 'good' eq $cfg->value('too'), 'leading blanks' );

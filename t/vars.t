# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl App-ConfigWild.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 7;
BEGIN { use_ok('Config::Wild') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $cfg = Config::Wild->new( 'cfgs/vars.cnf' );

ok( 'here/there' eq $cfg->value('twig'), 'internal vars' );

$ENV{CWTEST} = 'not now';

ok( 'not now or then' eq $cfg->value( 'entvar' ), 'env vars' );

ok( 'not now or where' eq $cfg->value( 'bothvarenv' ), 'both vars (env)' );

ok( 'here or not' eq $cfg->value( 'bothvarint' ), 'both vars (internal)' );

ok( '0/1/2/3' eq $cfg->value( 'nest3' ), 'nested internal' );

ok( 'not now/or then/or how' eq $cfg->value( 'enest2' ), 'nested internal/env' );

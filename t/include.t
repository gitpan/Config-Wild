#!perl

use Test::More tests => 3;
BEGIN { use_ok('Config::Wild') };

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

{
    my $cfg = Config::Wild->new( 'cfgs/include0.cnf' );

    ok( 1.234 == $cfg->value('foo') , 'include' );
}

{
    my $cfg = Config::Wild->new( 'include0-rel.cnf', { dir => 'cfgs' } );

    ok( 1.234 == $cfg->value('foo') , 'relative includes' );
}

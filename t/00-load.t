#!perl -T

use Test::More;

BEGIN {
    use_ok( 'Device::FTDI' ) || print "Bail out!\n";
}

diag( "Testing Device::FTDI $Device::FTDI::VERSION, Perl $], $^X" );

done_testing;

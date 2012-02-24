#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Device::FTDI' ) || print "Bail out!\n";
}

diag( "Testing Device::FTDI $Device::FTDI::VERSION, Perl $], $^X" );

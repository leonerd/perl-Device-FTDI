#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::HexString;

use Device::FTDI::MPSSE qw(
    CLOCK_RISING CLOCK_FALLING
);

my $GOT_WRITE;
my $SEND_READ;

my $mpsse = Device::FTDI::MPSSE->new( ftdi => "MockFTDI" );

isa_ok( $mpsse, "Device::FTDI::MPSSE", '$mpsse' );

$mpsse->set_clock_edges( CLOCK_RISING, CLOCK_FALLING );

sub is_write
{
    my ( $write, $name ) = @_;

    undef $GOT_WRITE;
    # Gutwrench - a 'flush' operation
    my $f = $mpsse->_send_bytes( "" );
    $f->get;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_hexstr( $GOT_WRITE, $write, $name );
}

sub is_writeread
{
    my ( $write, $read, $name ) = @_;

    undef $GOT_WRITE;
    $SEND_READ = $read;
    # Gutwrench - a 'flush' operation
    my $f = $mpsse->_send_bytes( "" );
    $f->get;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_hexstr( $GOT_WRITE, $write, $name );
    ok( !length $SEND_READ, "All data consumed for $name" );
}

# Initial setup
is_write
    "\x80\x00\x0B" . # CMD_SET_DBUS
    "\x82\x00\x00",  # CMD_SET_CBUS
    'write_data for initialisation';

# write_bytes
{
    my $f = $mpsse->write_bytes( "\x55\xAA" );

    is_write
        "\x11\x01\x00\x55\xAA", # CMD_WRITE|CMD_CLK_ON_WRITE len=1
        'write_data for write_bytes';

    is( scalar $f->get, undef, '$f->get' );
}

# read_bytes
{
    my $f = $mpsse->read_bytes( 2 );

    is_writeread
        "\x20\x01\x00" . # CMD_READ len=1
            "\x87",      # CMD_SEND_IMMEDIATE
        "\x5A\xA5",
        'write_data for read_bytes';

    is( scalar $f->get, "\x5A\xA5" );
}

done_testing;

package MockFTDI;

use Future;

sub reset {}

sub read_data_set_chunksize {}
sub write_data_set_chunksize {}

sub purge_buffers {}

my $bitmode;
sub set_bitmode { ( undef, undef, $bitmode ) = @_; }

sub write_data
{
    shift;
    my ( $bytes ) = @_;

    $GOT_WRITE .= $bytes;
    return Future->done;
}

sub read_data
{
    shift;
    my ( undef, $len ) = @_;

    die "ARGH need $len more bytes of data" unless length $SEND_READ;
    $_[0] = substr( $SEND_READ, 0, $len, "" );
    return Future->done;
}

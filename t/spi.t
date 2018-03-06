#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use MockFTDI qw( is_write is_writeread );

use Device::FTDI::SPI;

my $spi = Device::FTDI::SPI->new( ftdi => "MockFTDI" );
$MockFTDI::MPSSE = $spi;

isa_ok( $spi, "Device::FTDI::SPI", '$spi' );

$spi->set_clock_rate( 1E6 );
$spi->set_spi_mode( 0 );

is_write
    "\x80\x00\x0B" .     # CMD_SET_DBUS
        "\x82\x00\x00" . # CMD_SET_CBUS
        "\x9E\x00\x00" . # CMD_SET_OPEN_COLLECTOR
        "\x80\x08\x0B" . # CMD_SET_DBUS release SS
        "\x8B" .         # CMD_CLKDIV5_ON
        "\x86\x05\x00" . # CMD_SET_CLOCK_DIVISOR
        "\x80\x08\x0B",  # CMD_SET_DBUS release SS, CLK idle
    'write_data for initialisation';

# write
{
    my $f = $spi->write( "\x55\xAA" );

    is_write
        "\x80\x00\x0B" .             # CMD_SET_DBUS assert SS
            "\x11\x01\x00\x55\xAA" . # CMD_WRITE|CMD_CLK_ON_WRITE len=2
            "\x80\x08\x0B",          # CMD_SET_DBUS release SS
        'write_data for write';

    is( scalar $f->get, undef, '$f->get' );
}

# read
{
    my $f = $spi->read( 2 );

    is_writeread
        "\x80\x00\x0B" .     # CMD_SET_DBUS assert SS
            "\x20\x01\x00" . # CMD_READ len=2
            "\x80\x08\x0B" . # CMD_SET_DBUS release SS
            "\x87",          # CMD_SEND_IMMEDIATE
        "\x5A\xA5",
        'write_data for read';

    is( scalar $f->get, "\x5A\xA5", '$f->get for read' );
}

# readwrite
{
    my $f = $spi->readwrite( "\xAA\x55" );

    is_writeread
        "\x80\x00\x0B" .             # CMD_SET_DBUS assert SS
            "\x31\x01\x00\xAA\x55" . # CMD_WRITE|CMD_READ|CMD_CLK_ON_WRITE len=2
            "\x80\x08\x0B" .         # CMD_SET_DBUS release SS
            "\x87",                  # CMD_SEND_IMMEDIATE
        "\xA5\x5A",
        'write_data for readwrite';

    is( scalar $f->get, "\xA5\x5A", '$f->get for readwrite' );
}

done_testing;

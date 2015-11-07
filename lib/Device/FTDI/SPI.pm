#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2015 -- leonerd@leonerd.org.uk

package Device::FTDI::SPI;

use strict;
use warnings;
use base qw( Device::FTDI::MPSSE );

our $VERSION = '0.07';

=head1 NAME

C<Device::FTDI::SPI> - use an I<FTDI> chip to talk the SPI protocol

=cut

=head1 DESCRIPTION

This subclass of L<Device::FTDI::MPSSE> provides helpers around the basic
MPSSE to fully implement the SPI protocol.

=cut

use Device::FTDI::MPSSE qw(
    CLOCK_FALLING CLOCK_RISING
    DBUS
);

use Carp;

use constant {
    SPI_SCK  => (1<<0),
    SPI_MOSI => (1<<1),
    SPI_MISO => (1<<2),
    SPI_CS   => (1<<3),
};

use constant { HIGH => 0xff, LOW => 0 };

=head1 CONSTRUCTOR

=cut

=head2 new

    $spi = Device::FTDI::SPI->new( %args )

In addition to the arguments taken by L<Device::FTDI::MPSSE/new>, this
constructor also accepts:

=over 4

=item mode => INT

The required SPI mode. Should be 0, 1, 2, or 3.

=back

=cut

sub new
{
    my $class = shift;
    my %args = @_;

    my $mode = delete $args{mode};

    my $self = $class->SUPER::new( %args );

    $self->set_spi_mode( $mode ) if defined $mode;

    $self->set_open_collector( 0, 0 );

    $self->write_gpio( DBUS, HIGH, SPI_CS );

    return $self;
}

=head1 METHODS

Any of the following methods documented with a trailing C<< ->get >> call
return L<Future> instances.

=cut

=head2 set_clock_rate

    $i2c->set_clock_rate( $rate )->get

Sets the clock rate for data transfers, in units of bits per second.

=cut

sub set_clock_rate
{
    my $self = shift;
    my ( $rate ) = @_;

    my $baserate = 6E6;
    if( $rate > $baserate ) {
        $self->set_clkdiv5( 0 );
        $baserate *= 5;
    }
    else {
        $self->set_clkdiv5( 1 );
    }

    $self->set_clock_divisor( ( $baserate / $rate ) - 1 );
}

=head2 set_spi_mode

    $spi->set_spi_mode( $mode )->get

Sets the current SPI mode. This will affect the clock sense and the idle
state of the C<CLK> pin.

=cut

sub set_spi_mode
{
    my $self = shift;
    my ( $mode ) = @_;

    my $idle;

    if( $mode == 0 ) {
        # CPOL=0, CPHA=0
        $idle = LOW;
        $self->set_clock_edges( CLOCK_RISING, CLOCK_FALLING );
    }
    elsif( $mode == 1 ) {
        # CPOL=0, CPHA=1
        $idle = LOW;
        $self->set_clock_edges( CLOCK_FALLING, CLOCK_RISING );
    }
    elsif( $mode == 2 ) {
        # CPOL=1, CPHA=0
        $idle = HIGH;
        $self->set_clock_edges( CLOCK_FALLING, CLOCK_RISING );
    }
    elsif( $mode == 3 ) {
        # CPOL=1, CPHA=1
        $idle = HIGH;
        $self->set_clock_edges( CLOCK_RISING, CLOCK_FALLING );
    }
    else {
        croak "Bad SPI mode";
    }

    $self->write_gpio( DBUS, $idle, SPI_SCK );
}

=head2 write

    $spi->write( $bytes )->get

=cut

sub write
{
    my $self = shift;
    my ( $bytes ) = @_;

    $self->write_gpio( DBUS, LOW, SPI_CS );
    $self->write_bytes( $bytes );
    $self->write_gpio( DBUS, HIGH, SPI_CS );
}

=head2 read

    $bytes = $spi->read( $len )->get;

=cut

sub read
{
    my $self = shift;
    my ( $len ) = @_;

    $self->write_gpio( DBUS, LOW, SPI_CS );
    my $f = $self->read_bytes( $len );
    $self->write_gpio( DBUS, HIGH, SPI_CS );

    return $f;
}

=head2

    $bytes_in = $spi->readwrite( $bytes_out )->get;

Performs a full SPI write, or read-and-write operation, consisting of
asserting the C<CS> pin, transferring bytes, and deasserting it again.

=cut

sub readwrite
{
    my $self = shift;
    my ( $bytes ) = @_;

    $self->write_gpio( DBUS, LOW, SPI_CS );
    my $f = $self->readwrite_bytes( $bytes );
    $self->write_gpio( DBUS, HIGH, SPI_CS );

    return $f;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

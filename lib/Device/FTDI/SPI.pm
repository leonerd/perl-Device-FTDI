package Device::FTDI::SPI;

use strict;
use warnings;
use base qw( Device::FTDI::MPSSE );

use Device::FTDI::MPSSE qw(
    WRCLOCK_FALLING WRCLOCK_RISING RDCLOCK_RISING RDCLOCK_FALLING
    DBUS
);

use Carp;

use constant {
    SPI_SCK  => (1<<0),
    SPI_MOSI => (1<<1),
    SPI_MISO => (1<<2),
    SPI_CS   => (1<<3),
};

sub new
{
    my $class = shift;
    my %args = @_;

    my $mode = delete $args{mode};

    my $self = $class->SUPER::new( %args );

    $self->set_spi_mode( $mode ) if defined $mode;

    $self->set_open_collector( 0, 0 );

    $self->write_gpio( DBUS, SPI_CS, SPI_CS );

    return $self;
}

=head2 $spi->set_spi_mode( $mode )->get

=cut

sub set_spi_mode
{
    my $self = shift;
    my ( $mode ) = @_;

    my $idle;
    my $clock_sense;

    if( $mode == 0 ) {
        # CPOL=0, CPHA=0
        $idle = 0;
        $clock_sense = WRCLOCK_FALLING | RDCLOCK_RISING;
    }
    elsif( $mode == 1 ) {
        # CPOL=0, CPHA=1
        $idle = 0;
        $clock_sense = WRCLOCK_RISING | RDCLOCK_FALLING;
    }
    elsif( $mode == 2 ) {
        # CPOL=1, CPHA=0
        $idle = SPI_SCK;
        $clock_sense = WRCLOCK_RISING | RDCLOCK_FALLING;
    }
    elsif( $mode == 3 ) {
        # CPOL=1, CPHA=1
        $idle = SPI_SCK;
        $clock_sense = WRCLOCK_FALLING | RDCLOCK_RISING;
    }
    else {
        croak "Bad SPI mode";
    }

    $self->set_clock_sense( $clock_sense );
    $self->write_gpio( DBUS, $idle, SPI_SCK );
}

=head2 $spi->write( $bytes )->get

=cut

sub write
{
    my $self = shift;
    my ( $bytes ) = @_;

    $self->write_gpio( DBUS, 0, SPI_CS );
    $self->write_bytes( $bytes );
    $self->write_gpio( DBUS, SPI_CS, SPI_CS );
}

=head2 $bytes = $spi->read( $len )->get

=cut

=head2 $bytes_out = $spi->readwrite( $bytes_in )->get;

=cut

sub readwrite
{
    my $self = shift;
    my ( $bytes ) = @_;

    $self->write_gpio( DBUS, 0, SPI_CS );
    my $f = $self->readwrite_bytes( $bytes );
    $self->write_gpio( DBUS, SPI_CS, SPI_CS );

    return $f;
}

0x55AA;

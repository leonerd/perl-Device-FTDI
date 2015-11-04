package Device::FTDI::MPSSE;

use strict;
use warnings;
use base qw( Device::FTDI );

use constant PID_FT232H => 0x6014;

use Exporter 'import';

our @EXPORT_OK = qw(
    DBUS CBUS
);

use constant {
    DBUS => 0,
    CBUS => 1,
};

sub new
{
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new( product => PID_FT232H, %args );

    $self->reset;

    $self->read_data_set_chunksize( 65536 );
    $self->write_data_set_chunksize( 65536 );

    $self->purge_buffers;

    # default tristate output on SCK/DO/TMS/DBUS4..7
    #                  input on DI
    my $tris = 0xff & ~(1<<2);

    $self->set_bitmode( 0, Device::FTDI::BITMODE_RESET );
    $self->set_bitmode( $tris, Device::FTDI::BITMODE_MPSSE );

    $self->set_adaptive_clock( 0 );
    $self->set_3phase_clock( 0 );
    $self->set_loopback( 0 );
    $self->set_open_collector( 0, 0 );

    $self->{mpsse_writebuff} = "";

    $self->{mpsse_setup} = 0;

    $self->{mpsse_gpio}[DBUS] = [ 0, $tris ];
    $self->_mpsse_gpio_set( DBUS, 0, $tris );

    $self->{mpsse_gpio}[CBUS] = [ 0, 0xff ];
    $self->_mpsse_gpio_set( CBUS, 0, 0xff );

    return $self;
}

# MPSSE command bits
use constant {
    # u16 quantities are little-endian

    # Synchronous read bitmasks when !(1<<7)
    CMD_CLK_ON_WRITE => 1<<0,
    CMD_BITMODE      => 1<<1,
    CMD_CLK_ON_READ  => 1<<2,
    CMD_LSBFIRST     => 1<<3,
    CMD_WRITE        => 1<<4,
    CMD_READ         => 1<<5,
    CMD_WRITE_TMS    => 1<<6,
    # followed by: !BITMODE    BITMODE
    #              u16 bytes   u8 bits
    #              u8*$N data  u8 data   if WRITE/WRITE_TMS

    CMD_SET_DBUS => 0x80, # u8 value, u8 direction
    CMD_SET_CBUS => 0x82, # u8 value, u8 direction
    CMD_GET_DBUS => 0x81,
    CMD_GET_CBUS => 0x83,

    CMD_LOOPBACK_ON  => 0x84,
    CMD_LOOPBACK_OFF => 0x85,

    CMD_SET_CLOCK_DIVISOR => 0x86, # u16 div

    CMD_SEND_IMMEDIATE => 0x87,

    CMD_WAIT_IO_HIGH => 0x88,
    CMD_WAIT_IO_LOW  => 0x89,

    CMD_CLKDIV5_OFF => 0x8A,
    CMD_CLKDIV5_ON  => 0x8B,

    CMD_3PHASECLK_ON  => 0x8C,
    CMD_3PHASECLK_OFF => 0x8D,

    CMD_CLOCK_BYTES => 0x8E, # u8 bits
    CMD_CLOCK_BITS  => 0x8F, # u16 bytes

    # Ignore CPU mode instructions 0x90-0x93

    CMD_CLOCK_UNTIL_IO_HIGH => 0x94,
    CMD_CLOCK_UNTIL_IO_LOW  => 0x95,

    CMD_ADAPTIVE_CLOCK_ON  => 0x96,
    CMD_ADAPTIVE_CLOCK_OFF => 0x97,

    CMD_NCLOCK_UNTIL_IO_HIGH => 0x9C, # u16 bytes
    CMD_NCLOCK_UNTIL_IO_LOW  => 0x9D, # u16 bytes

    CMD_SET_OPEN_COLLECTOR => 0x9E, # u8 dbus, u8 cbus
};

=head2 $mpsse->set_bit_order( $lsbfirst )

=cut

push @EXPORT_OK, qw(
    MSBFIRST LSBFIRST
);
use constant {
    MSBFIRST => 0,
    LSBFIRST => CMD_LSBFIRST,
};

sub set_bit_order
{
    my $self = shift;
    my ( $lsbfirst ) = @_;

    ( $self->{mpsse_setup} &= ~CMD_LSBFIRST )
                           |= ( $lsbfirst & CMD_LSBFIRST );

    # TODO: Consider a token-effort Future->done for completeness?
}

=head2 $mpsse->set_clock_sense( $sense )

=cut

push @EXPORT_OK, qw(
    RDCLOCK_FALLING RDCLOCK_RISING WRCLOCK_FALLING WRCLOCK_RISING
);
use constant {
    RDCLOCK_FALLING => CMD_CLK_ON_READ,
    RDCLOCK_RISING  => 0,
    WRCLOCK_FALLING => CMD_CLK_ON_WRITE,
    WRCLOCK_RISING  => 0,
};

sub set_clock_sense
{
    my $self = shift;
    my ( $sense ) = @_;

    ( $self->{mpsse_setup} &= ~(CMD_CLK_ON_READ|CMD_CLK_ON_WRITE) )
                           |= ( $sense & (CMD_CLK_ON_READ|CMD_CLK_ON_WRITE) );
}

=head2 $mpsse->write_bytes( $data_out )->get

=head2 $data_in = $mpsse->read_bytes( $len )->get

=head2 $data_in = $mpsse->readwrite_bytes( $data_out )->get

=cut

sub _readwrite_bytes
{
    my $self = shift;
    my ( $cmd, $len, $data ) = @_;

    $cmd |= $self->{mpsse_setup};

    $data = substr( $data, 0, $len );
    $data .= "\0" x ( $len - length $data );

    die "Read not yet supported" if $cmd & CMD_READ;
    $self->_push_bytes( pack( "C v", $cmd, $len - 1 ) . ( $cmd & CMD_WRITE ? $data : "" ) );
}

sub write_bytes
{
    my $self = shift;
    $self->_readwrite_bytes( CMD_WRITE, length $_[0], $_[0] );
}

sub read_bytes
{
    my $self = shift;
    $self->_readwrite_bytes( CMD_READ,  $_[0], "" );
}

sub readwrite_bytes
{
    my $self = shift;
    $self->_readwrite_bytes( CMD_WRITE|CMD_READ, length $_[0], $_[0] );
}

=head2 $mpsse->tris_gpio( $port, $tris, $mask )->get

=head2 $mpsse->write_gpio( $port, $val, $mask )->get

=cut

sub _mpsse_gpio_set
{
    my $self = shift;
    my ( $port, $val, $mask ) = @_;

    $self->_push_bytes( pack "C C C", CMD_SET_DBUS + ( $port * 2 ), $val, $mask );
}

sub tris_gpio
{
    my $self = shift;
    my ( $port, $tris, $mask ) = @_;

    my $state = $self->{mpsse_gpio}[$port];

    ( $state->[1] &= ~$mask ) |= ( $tris & $mask );

    $self->_mpsse_gpio_set( $port, $state->[0], $state->[1] );
}

sub write_gpio
{
    my $self = shift;
    my ( $port, $val, $mask ) = @_;

    my $state = $self->{mpsse_gpio}[$port];

    ( $state->[0] &= ~$mask ) |= ( $val & $mask );

    $self->_mpsse_gpio_set( $port, $state->[0], $state->[1] );
}

=head2 $mpsse->set_loopback( $on )->get

=cut

sub set_loopback
{
    my $self = shift;
    my ( $on ) = @_;

    $self->_push_bytes( pack "C", $on ? CMD_LOOPBACK_ON : CMD_LOOPBACK_OFF );
}

=head2 $mpsse->set_clock_divisor( $div )->get

=cut

sub set_clock_divisor
{
    my $self = shift;
    my ( $div ) = @_;

    $self->_push_bytes( pack "C v", CMD_SET_CLOCK_DIVISOR, $div );
}

=head2 $mpsse->set_clkdiv5( $on )->get

=cut

sub set_clkdiv5
{
    my $self = shift;
    my ( $on ) = @_;

    $self->_push_bytes( pack "C", $on ? CMD_CLKDIV5_ON : CMD_CLKDIV5_OFF );
}

=head2 $mpsse->set_3phase_clock( $on )->get

=cut

sub set_3phase_clock
{
    my $self = shift;
    my ( $on ) = @_;

    $self->_push_bytes( pack "C", $on ? CMD_3PHASECLK_ON : CMD_3PHASECLK_OFF );
}

=head2 $mpsse->set_adaptive_clock( $on )->get

=cut

sub set_adaptive_clock
{
    my $self = shift;
    my ( $on ) = @_;

    $self->_push_bytes( pack "C", $on ? CMD_ADAPTIVE_CLOCK_ON : CMD_ADAPTIVE_CLOCK_OFF );
}

=head2 $mpsse->set_open_collector( $dbus, $cbus )->get

=cut

sub set_open_collector
{
    my $self = shift;
    my ( $dbus, $cbus ) = @_;

    $self->_push_bytes( pack "C C C", CMD_SET_OPEN_COLLECTOR, $dbus, $cbus );
}

# Future/buffering support
sub _push_bytes
{
    my $self = shift;
    my ( $bytes ) = @_;

    # TODO: bounds-check the buffer
    $self->{mpsse_writebuff} .= $bytes;

    my $f = Device::FTDI::MPSSE::_Future->new( $self );
    push @{ $self->{mpsse_done_on_write} }, $f;
    return $f;
}

package
    Device::FTDI::MPSSE::_Future;
use base qw( Future );

sub new
{
    my $class = shift;
    my ( $mpsse ) = @_;
    my $self = $class->SUPER::new();

    $self->{mpsse} = $mpsse;

    return $self;
}

sub await
{
    my $self = shift;

    my $mpsse = $self->{mpsse};

    if( length $mpsse->{mpsse_writebuff} ) {
        $mpsse->write_data( $mpsse->{mpsse_writebuff} );
        $mpsse->{mpsse_writebuff} = "";

        $_->done() for splice @{ $mpsse->{mpsse_done_on_write} };
    }
}

0x55AA;

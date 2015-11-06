#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2015 -- leonerd@leonerd.org.uk

package Device::FTDI::MPSSE;

use strict;
use warnings;
use base qw( Device::FTDI );

our $VERSION = '0.07';

=head1 NAME

C<Device::FTDI::MPSSE> - use the MPSSE mode of an I<FDTI> chip

=head1 DESCRIPTION

This subclass of L<Device::FTDI> provides convenient methods to access the
Multi-Protocol Synchronous Serial Engine (MPSSE) mode of certain I<FTDI>
chips. It provides methods to wrap the various commands that control the
MPSSE and interpret their responses.

The following subclasses exist to simplify implementation of particular
serial protocols:

=over 2

=item *

L<Device::FTDI::SPI> for SPI

=back

=head2 FUTURES AND BUFFERING

Unlike most L<Future>-returning modules, it is not usually necessary to
actually store the results of returned L<Future> instances from most of these
methods. The C<$mpsse> object itself will store them.

Especially in cases of C<set_*> or C<write_> methods, the caller is free
to drop them in void context.

You should, however, be aware of the deferred nature of the activities of
these methods. The reason they return futures is that none of these methods
really acts immediately on the chip. Instead, pending commands are stored
internally in a buffer, and emitted at once to the chip over USB, where it can
act on them all, and send all the responses at once. The reason to do this is
to gain a much improved performance over the USB connection.

Because of this, while it is not necessary to wait on or call L<Future/get> on
every returned future, it I<is> required that the very last of a sequence of
operations is waited on (usually by calling its C<get> method). When
implementing library functions it is usually sufficient simply to let the last
operation be returned in non-void context to the caller, so the caller can
await it themself.

=cut

use Device::FTDI qw( PID_FT232H );

use Exporter 'import';

our @EXPORT_OK = qw(
    DBUS CBUS
);

use constant {
    DBUS => 0,
    CBUS => 1,
};

=head1 CONSTRUCTOR

=cut

=head2 new

    $mpsse = Device::FTDI::MPSSE->new( %args )

Takes the same arguments as L<Device::FTDI/new>, except that it applies a
default C<product> parameter of the product ID identifying the I<FT232H>
device.

This constructor performs all the necessary setup to initialse the MPSSE.

=cut

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

=head2 METHODS

Any of the following methods documented with a trailing C<< ->get >> call
return L<Future> instances.

=cut

=head2 set_bit_order

    $mpsse->set_bit_order( $lsbfirst )

Configures the bit order of subsequent L</write_bytes> or L</readwrite_bytes>
calls.

Takes either of the following exported constants

    MSBFIRST, LSBFIRST

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

=head2 set_clock_sense

    $mpsse->set_clock_sense( $sense )

Configures the clocking sense of subsequent read or write operations.

I<$sense> should be a bitwise-or combination of one of each of the following
two pairs of exported constants

    RDCLOCK_FALLING, RDCLOCK_RISING
    WRCLOCK_FALLING, WRCLOCK_RISING

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

=head2 write_bytes

=head2 read_bytes

=head2 readwrite_bytes

    $mpsse->write_bytes( $data_out )->get

    $data_in = $mpsse->read_bytes( $len )->get

    $data_in = $mpsse->readwrite_bytes( $data_out )->get

Perform a bytewise clocked serial transfer. These are the "main" methods of
the class; they invoke the main core of the MPSSE.

In each case, the C<CLK> pin will count the specified length of bytes of
transfer. For the C<write_> and C<readwrite_> methods this count is implied by
the length of the inbound buffer; during the operation the specified bytes
will be sent out of the C<DO> pin.

For the C<read_> and C<readwrite_> methods, the returned future will yield the
bytes that were received in the C<DI> pin during this time.

=cut

sub _readwrite_bytes
{
    my $self = shift;
    my ( $cmd, $len, $data ) = @_;

    $cmd |= $self->{mpsse_setup};

    $data = substr( $data, 0, $len );
    $data .= "\0" x ( $len - length $data );

    my $f = $self->_send_bytes( pack( "C v", $cmd, $len - 1 ) . ( $cmd & CMD_WRITE ? $data : "" ) );
    $f = $self->_recv_bytes( $len ) if $cmd & CMD_READ;

    return $f;
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

=head2 tris_gpio

    $mpsse->tris_gpio( $port, $dir, $mask )->get

"tristate" the pins on a GPIO port. This method affects only the pins
specified by the C<$mask> bitmask, on the specified C<$port>. Pins whose
corresponding bit in C<$dir> is 0 are set to inputs; whose bit is 1 are set
to outputs. Pins not covered by the mask remain unaffected.

=head2 write_gpio

    $mpsse->write_gpio( $port, $val, $mask )->get

Write a new value to the pins on a GPIO port. This method affects only the
pins specified by the C<$mask> bitmask, on the specified port. Pins not
covered by the mask remain unaffected. Additionally, any pins whose state has
been written will additionally need to be set as outputs by the L</tris_gpio>
method, either before or after this call.

=head2 read_gpio

    $val = $mpsse->read_gpio( $port )->get

Reads the state of the pins on a GPIO port. The returned future will yield an
8-bit integer. The state of any bits corresponding to pins currently
configured as outputs (by the L</tris_gpio> method) is undefined.

In each of the above methods, the GPIO port is specified by one of the
following exported constants

    DBUS, CBUS

=cut

sub _mpsse_gpio_set
{
    my $self = shift;
    my ( $port, $val, $dir ) = @_;

    $self->_send_bytes( pack "C C C", CMD_SET_DBUS + ( $port * 2 ), $val, $dir );
}

use constant { VAL => 0, DIR => 1 };

sub tris_gpio
{
    my $self = shift;
    my ( $port, $dir, $mask ) = @_;

    my $state = $self->{mpsse_gpio}[$port];

    ( $state->[1] &= ~$mask ) |= ( $dir & $mask );

    $self->_mpsse_gpio_set( $port, $state->[VAL], $state->[DIR] );
}

sub write_gpio
{
    my $self = shift;
    my ( $port, $val, $mask ) = @_;

    my $state = $self->{mpsse_gpio}[$port];

    ( $state->[0] &= ~$mask ) |= ( $val & $mask );

    $self->_mpsse_gpio_set( $port, $state->[VAL], $state->[DIR] );
}

sub read_gpio
{
    my $self = shift;
    my ( $port ) = @_;

    $self->_send_bytes( pack "C", CMD_GET_DBUS + ( $port * 2 ) );
    $self->_recv_bytes( 1 )
        ->transform( done => sub { unpack "C", $_[0] } );
}

=head2 set_loopback

    $mpsse->set_loopback( $on )->get

If enabled, loopback mode bypasses the actual IO pins from the chip and
connects the chip's internal output to its own input. This can be useful for
testing whether the chip is mostly functioning correctly.

=cut

sub set_loopback
{
    my $self = shift;
    my ( $on ) = @_;

    $self->_send_bytes( pack "C", $on ? CMD_LOOPBACK_ON : CMD_LOOPBACK_OFF );
}

=head2 set_clock_divisor

    $mpsse->set_clock_divisor( $div )->get

Sets the divider the chip uses to determine the output clock frequency. The
eventual frequency will be

    $freq_Hz = 12E6 / (( 1 + $div ) * 2 )

=cut

sub set_clock_divisor
{
    my $self = shift;
    my ( $div ) = @_;

    $self->_send_bytes( pack "C v", CMD_SET_CLOCK_DIVISOR, $div );
}

=head2 set_clkdiv5

    $mpsse->set_clkdiv5( $on )->get

Disables or enables the divide-by-5 clock prescaler.

Some I<FTDI> chips are capable of faster clock speeds. These chips use a base
frequency of 60MHz rather than 12MHz, but divide it down by 5 by default to
remain compatible with code unaware of this. To access the higher speeds
available on these chips, disable the divider by using this method. The clock
rate implied by C<set_clock_divisor> will then be 5 times faster.

=cut

sub set_clkdiv5
{
    my $self = shift;
    my ( $on ) = @_;

    $self->_send_bytes( pack "C", $on ? CMD_CLKDIV5_ON : CMD_CLKDIV5_OFF );
}

=head2 set_3phase_clock

    $mpsse->set_3phase_clock( $on )->get

If enabled, data is clocked in/out using a 3-phase strategy compatible with
the I2C protocol. If this is set, the effective clock rate becomes 2/3 that
implied by the clock divider.

=cut

sub set_3phase_clock
{
    my $self = shift;
    my ( $on ) = @_;

    $self->_send_bytes( pack "C", $on ? CMD_3PHASECLK_ON : CMD_3PHASECLK_OFF );
}

=head2 set_adaptive_clock

    $mpsse->set_adaptive_clock( $on )->get

If enabled, the chip waits for acknowledgement of a clock signal on the
C<GPIOL3> pin before continuing for every bit transferred. This may be used by
I<ARM> processors.

=cut

sub set_adaptive_clock
{
    my $self = shift;
    my ( $on ) = @_;

    $self->_send_bytes( pack "C", $on ? CMD_ADAPTIVE_CLOCK_ON : CMD_ADAPTIVE_CLOCK_OFF );
}

=head2 set_open_collector

    $mpsse->set_open_collector( $dbus, $cbus )->get

I<Only on FT232H chips>.

Enables open-collector mode on the output pins given by the bitmasks. This
mode is useful to avoid bus drive contention, especially when implementing
I2C.

=cut

sub set_open_collector
{
    my $self = shift;
    my ( $dbus, $cbus ) = @_;

    $self->_send_bytes( pack "C C C", CMD_SET_OPEN_COLLECTOR, $dbus, $cbus );
}

# Future/buffering support
sub _send_bytes
{
    my $self = shift;
    my ( $bytes ) = @_;

    # TODO: bounds-check the buffer
    $self->{mpsse_writebuff} .= $bytes;

    my $f = Device::FTDI::MPSSE::_Future->new( $self );
    push @{ $self->{mpsse_send_f} }, $f;
    return $f;
}

sub _recv_bytes
{
    my $self = shift;
    my ( $len ) = @_;

    my $f = Device::FTDI::MPSSE::_Future->new( $self );
    push @{ $self->{mpsse_recv_f} }, [ $len, $f ];
    $self->{mpsse_recv_len} += $len;

    return $f;
}

package
    Device::FTDI::MPSSE::_Future;
use base qw( Future );

use constant CMD_SEND_IMMEDIATE => Device::FTDI::MPSSE::CMD_SEND_IMMEDIATE;

sub new
{
    my $proto = shift;
    my $self = $proto->SUPER::new();

    $self->{mpsse} = ref $proto ? $proto->{mpsse} : $_[0];

    return $self;
}

sub await
{
    my $self = shift;

    my $mpsse = $self->{mpsse};

    if( $mpsse->{mpsse_recv_len} ) {
        $mpsse->{mpsse_writebuff} .= pack "C", CMD_SEND_IMMEDIATE;
    }

    if( length $mpsse->{mpsse_writebuff} ) {
        $mpsse->write_data( $mpsse->{mpsse_writebuff} );
        $mpsse->{mpsse_writebuff} = "";

        $_->done() for splice @{ $mpsse->{mpsse_send_f} };
    }

    my $recvbuff = "";
    my $recv_f = $mpsse->{mpsse_recv_f};

    while( $mpsse->{mpsse_recv_len} ) {
        $mpsse->read_data( my $more, $mpsse->{mpsse_recv_len} );

        $recvbuff .= $more;
        $mpsse->{mpsse_recv_len} -= length $more;

        while( @$recv_f and length $recvbuff >= $recv_f->[0][0] ) {
            my ( $len, $f ) = @{ shift @$recv_f };
            $f->done( substr $recvbuff, 0, $len, "" );
        }
    }
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

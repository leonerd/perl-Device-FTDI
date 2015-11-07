#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2015 -- leonerd@leonerd.org.uk

package Device::FTDI::I2C;

use strict;
use warnings;
use base qw( Device::FTDI::MPSSE );

our $VERSION = '0.07';

use Device::FTDI::MPSSE qw(
    DBUS
    CLOCK_RISING CLOCK_FALLING
);

use Future::Utils qw( repeat );

use constant {
    I2C_SCL     => (1<<0),
    I2C_SDA_OUT => (1<<1),
    I2C_SDA_IN  => (1<<2),
};

use constant { HIGH => 0xff, LOW => 0 };

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new( @_ );

    $self->set_3phase_clock( 1 );
    $self->set_open_collector( I2C_SCL|I2C_SDA_OUT, 0 );

    $self->set_clock_edges( CLOCK_RISING, CLOCK_FALLING );

    # Idle high
    $self->write_gpio( DBUS, HIGH, I2C_SCL | I2C_SDA_OUT );

    return $self;
}

sub set_clock_rate
{
    my $self = shift;
    my ( $rate ) = @_;

    $self->set_clock_divisor( ( 4E6 / $rate ) - 1 );
}

sub i2c_start
{
    my $self = shift;

    my $f;

    # S&H delay
    $self->write_gpio( DBUS, LOW, I2C_SDA_OUT ) for 1 .. 10;
    $f = $self->write_gpio( DBUS, LOW, I2C_SCL ) for 1 .. 10;

    return $f;
}

sub i2c_repeated_start
{
    my $self = shift;

    # Release the lines without appearing as STOP
    $self->write_gpio( DBUS, HIGH, I2C_SDA_OUT ) for 1 .. 10;
    $self->write_gpio( DBUS, HIGH, I2C_SCL ) for 1 .. 10;

    $self->i2c_start;
}

sub i2c_stop
{
    my $self = shift;

    my $f;

    # S&H delay
    $self->write_gpio( DBUS, HIGH, I2C_SCL ) for 1 .. 10;
    $f = $self->write_gpio( DBUS, HIGH, I2C_SDA_OUT ) for 1 .. 10;

    return $f;
}

sub i2c_send
{
    my $self = shift;
    my ( $data ) = @_;

    $self->write_bytes( $data );
    # Release SDA
    $self->write_gpio( DBUS, HIGH, I2C_SDA_OUT );

    $self->read_bits( 1 )
        ->transform( done => sub {
            !( ord $_[0] & 0x80 );
        });
}

sub i2c_recv
{
    my $self = shift;
    my ( $ack ) = @_;

    my $f = $self->read_bytes( 1 );

    $self->write_bits( 1, chr( $ack ? LOW : HIGH ) );
    # Release SDA
    $self->write_gpio( DBUS, HIGH, I2C_SDA_OUT );

    return $f;
}

sub write
{
    my $self = shift;
    my ( $addr, $data ) = @_;

    $self->i2c_start;

    $self->i2c_send( pack "C", $addr << 1 )
    ->then( sub {
        my ( $ack ) = @_;
        # $ack or die "received ACK from device\n";

        repeat {
            $self->i2c_send( $_[0] )
                ->on_done( sub { my ( $ack ) = @_; } )
        } foreach => [ split m//, $data ];
    })->then( sub {
        $self->i2c_stop;
    });
}

sub write_then_read
{
    my $self = shift;
    my ( $addr, $data_out, $len_in ) = @_;

    my $data_in = "";

    $self->i2c_start;

    $self->i2c_send( pack "C", $addr << 1 )
    ->then( sub {
        my ( $ack ) = @_;

        repeat {
            $self->i2c_send( $_[0] )
        } foreach => [ split m//, $data_out ];
    })->then( sub {
        $self->i2c_repeated_start;

        $self->i2c_send( pack "C", 1 | ( $addr << 1 ) );
    })->then( sub {
        my ( $ack ) = @_;

        repeat {
            $self->i2c_recv( $_[0] )
                ->on_done( sub { $data_in .= $_[0] } )
        } foreach => [ ( 1 ) x ( $len_in - 1 ), 0 ]
    })->then( sub {
        $self->i2c_stop
            ->then_done( $data_in );
    });
}

0x55AA;

package Device::FTDI;

use 5.010;
use strict;
use warnings;

=head1 NAME

Device::FTDI - perl extension to talk to F<FTDI> chips

=head1 VERSION

Version 0.06

=cut

our $VERSION = '0.06';

use Carp;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    FLOW_RTS_CTS
    FLOW_DTR_DSR
    FLOW_XON_XOFF
    FLOW_DISABLE

    BITS_7
    BITS_8

    STOP_BIT_1
    STOP_BIT_2
    STOP_BIT_15

    PARITY_NONE
    PARITY_ODD
    PARITY_EVEN
    PARITY_MARK
    PARITY_SPACE

    BREAK_ON
    BREAK_OFF

    INTERFACE_ANY
    INTERFACE_A
    INTERFACE_B
    INTERFACE_C
    INTERFACE_D

    BITMODE_RESET
    BITMODE_BITBANG
    BITMODE_MPSSE
    BITMODE_SYNCBB
    BITMODE_MCU
    BITMODE_OPTO
    BITMODE_CBUS
    BITMODE_SYNCFF
);

our %EXPORT_TAGS = (all => \@EXPORT_OK);

require XSLoader;
XSLoader::load('Device::FTDI', $VERSION);

=head1 SYNOPSIS

    use Device::FTDI;

    my $dev = Device::FTDI->new();
    ...

=head1 DESCRIPTION

B<WARNING:> this is an alpha version

This is Perl bindings to F<libftdi> library. It allows you to communicate with
F<FTDI> chips supported by this library.

=head1 CLASS METHODS

=cut

=head2 $class->find_all(%params)

Finds all connected devices with specified vendor and product codes. Returns
list of hashes describing devices. Following parameters are accepted:

=over 4

=item B<vendor>

vendor code. Default C<0x0403>.

=item B<product>

product code. Default C<0x6001>.

=back

=cut

sub find_all {
    my ($class, %params) = @_;
    $params{vendor} ||= 0x0403;
    $params{product} ||= 0x6001;
    my @list = _find_all($params{vendor}, $params{product});
    return map { bless $_, 'Device::FTDI::Description' } @list;
}

=head2 $class->new(%params)

Opens specified device and returns the corresponding object reference. Dies if
an attempt to open the device has failed. Accepts following parameters:

=over 4

=item B<vendor>

vendor code. Default C<0x0403>.

=item B<product>

product code. Default C<0x6001>.

=item B<description>

device description string. By default undefined.

=item B<serial>

device serial ID. By default undefined.

=item B<index>

device index. By default 0.

=back

=cut

sub new {
    my ($class, %params) = @_;
    $params{vendor} ||= 0x0403;
    $params{product} ||= 0x6001;
    $params{index} ||= 0;
    my $dev = _open_device($params{vendor}, $params{product}, $params{description}, $params{serial}, $params{index});
    return bless { _ctx => $dev }, $class;
}

=head1 DEVICE METHODS

Most of device methods return negative value in case of error. You can get
error description using L</error_string> method.

=cut

=head2 $dev->error_string
X<error_string>

Returns string describing error after last operation

=cut

sub error_string {
    return _error_string( shift->{_ctx} );
}

=head2 $dev->reset

Resets the device

=cut

sub reset {
    return _reset(shift->{_ctx});
}

=head2 $dev->set_interface($interface)

Open selected channels on a chip, otherwise use first channel. I<$interface> may
be one of: C<INTERFACE_A>, C<INTERFACE_B>, C<INTERFACE_C>, C<INTERFACE_D>, or
C<INTERFACE_ANY>.

=cut

sub set_interface {
    my ( $self, $interface ) = @_;
    return _set_interface( $self->{_ctx}, $interface );
}

=head2 $dev->purge_rx_buffer

Clears the read buffer on the chip and the internal read buffer. Returns 0 on
success or negative error code otherwise.

=cut

sub purge_rx_buffer {
    return _purge_rx_buffer(shift->{_ctx});
}

=head2 $dev->purge_tx_buffer

Clears the write buffer on the chip. Returns 0 on success or negative error
code otherwise.

=cut

sub purge_tx_buffer {
    return _purge_tx_buffer(shift->{_ctx});
}

=head2 $dev->purge_buffers

Clears the buffers on the chip and the internal read buffer. Returns 0 on
success or negative error code otherwise.

=cut

sub purge_buffers {
    return _purge_buffers(shift->{_ctx});
}

=head2 $dev->set_flow_control($flowctrl)

Set flow control for ftdi chip. Allowed values for I<$flowctrl> are:
FLOW_RTS_CTS, FLOW_DTR_DSR, FLOW_XON_XOFF, FLOW_DISABLE.
Returns 0 on success or negative error code otherwise.

This method is also available aliased as C<setflowctrl> for back-compatibility
and to match the name used by F<libftdi> itself.

=cut

sub set_flow_control {
    my ( $self, $flowctrl ) = @_;
    return _setflowctrl( $self->{_ctx}, $flowctrl );
}
*setflowctrl = \&set_flow_control;

=head2 $dev->set_line_property($bits, $stop_bit, $parity, $break)

Sets line characteristics. Last parameters may be ommited. Following values are
acceptable for parameters (* marks default value):

=over 4

=item B<$bits>

C<BITS_7>, C<BITS_8> (*)

=item B<$stop_bit>

C<STOP_BIT_1>, C<STOP_BIT_2>, C<STOP_BIT_15> (*)

=item B<$parity>

C<PARITY_NONE> (*), C<PARITY_EVEN>, C<PARITY_ODD>, C<PARITY_MARK>,
C<PARITY_SPACE>

=item B<$parity>

C<BREAK_OFF> (*), C<BREAK_ON>

=back

Note, that you have to import constants you need. You can import all constants
using C<:all> tag.

Returns 0 on success or negative error code otherwise.

=cut

sub set_line_property {
    my ( $self, $bits, $stop_bit, $parity, $break ) = @_;
    defined($bits)     or $bits     = BITS_8();
    defined($stop_bit) or $stop_bit = STOP_BIT_15();
    defined($parity)   or $parity   = PARITY_NONE();
    defined($break)    or $break    = BREAK_OFF();

    return _set_line_property2( $self->{_ctx}, $bits, $stop_bit, $parity, $break );
}

=head2 $dev->set_baudrate($baudrate)

Sets the chip baudrate. Returns 0 on success or negative error code otherwise.

=cut

sub set_baudrate {
    my ($self, $baudrate) = @_;
    return _set_baudrate($self->{_ctx}, $baudrate);
}

=head2 $dev->set_latency_timer($latency)

Sets latency timer. The FTDI chip keeps data in the internal buffer for a
specific amount of time if the buffer is not full yet to decrease load on the
USB bus. Latency must be between 1 and 255.

Returns 0 on success or negative error code otherwise.

=cut

sub set_latency_timer {
    my ( $self, $latency ) = @_;
    croak "latency must be between 1 and 255" unless $latency >= 1 && $latency <= 255;
    return _set_latency_timer( $self->{_ctx}, $latency );
}

=head2 $dev->get_latency_timer

Returns latency timer value or negative error code.

=cut

sub get_latency_timer {
    return _get_latency_timer( shift->{_ctx} );
}

=head2 $dev->write_data_set_chunksize($chunksize)

Sets write buffer chunk size. Default C<4096>. Returns 0 on success or
negative error code otherwise.

=cut

sub write_data_set_chunksize {
    my ( $self, $chunksize ) = @_;
    return _write_data_set_chunksize( $self->{_ctx}, $chunksize );
}

=head2 $dev->write_data_get_chunksize

Returns write buffer chunk size or negative error code.

=cut

sub write_data_get_chunksize {
    return _write_data_get_chunksize( shift->{_ctx} );
}

=head2 $dev->read_data_set_chunksize($chunksize)

Sets read buffer chunk size. Default 4096. Returns 0 on success or negative
error code otherwise.

=cut

sub read_data_set_chunksize {
    my ( $self, $chunksize ) = @_;
    return _read_data_set_chunksize( $self->{_ctx}, $chunksize );
}

=head2 $dev->read_data_get_chunksize

Returns read buffer chunk size or negative error code.

=cut

sub read_data_get_chunksize {
    return _read_data_get_chunksize( shift->{_ctx} );
}

=head2 $dev->write_data($data)

Writes data to the chip in chunks. Returns number of bytes written on success
or negative error code otherwise.

=cut

sub write_data {
    my ($self, $data) = @_;
    return _write_data( $self->{_ctx}, $data );
}

=head2 $dev->read_data($buffer, $size)

Reads data from the chip (up to I<$size> bytes) and stores it in I<$buffer>.
Returns when at least one byte is available or when the latency timer has
elapsed. Automatically strips the two modem status bytes transfered during
every read.

Returns number of bytes read on success or negative error code otherwise. Note,
that if no data available it will return 0.

=cut

sub read_data {
    my ($self, $size) = @_[0,2];
    return _read_data( $self->{_ctx}, $_[1], $size);
}

=head2 $dev->set_bitmode($mask, $mode)

Enable/disable bitbang modes. I<$mask> -- bitmask to configure lines, High/ON
value configures a line as output. I<$mode> may be one of the following:
C<BITMODE_RESET>, C<BITMODE_BITBANG>, C<BITMODE_MPSSE>, C<BITMODE_SYNCBB>,
C<BITMODE_MCU>, C<BITMODE_OPTO>, C<BITMODE_CBUS>, C<BITMODE_SYNCFF>.

=cut

sub set_bitmode {
    my ($self, $mask, $mode) = @_;
    return _set_bitmode($self->{_ctx}, $mask, $mode);
}

sub DESTROY {
    my $self = shift;
    _close_device($self->{_ctx});
}

1;

__END__

=head1 SEE ALSO

L<FTDI>, L<Win32::FTDI::FTD2XX>,
L<http://www.intra2net.com/en/developer/libftdi/>

=head1 AUTHOR

Pavel Shaydo, C<< <zwon at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests via GitHub bugtracker for this project:
L<https://github.com/trinitum/perl-Device-FTDI/issues>.

=head1 LICENSE AND COPYRIGHT

Copyright 2012,2015 Pavel Shaydo.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

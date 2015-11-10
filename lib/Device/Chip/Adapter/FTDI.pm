#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2015 -- leonerd@leonerd.org.uk

package Device::Chip::Adapter::FTDI;

use strict;
use warnings;
use base qw( Device::Chip::Adapter );

=head1 NAME

C<Device::Chip::Adapter::FTDI> - a C<Device::Chip::Adapter> implementation

=head1 DESCRIPTION

This class implements the L<Device::Chip::Adapter> interface for the I<FDTI>
communication devices, allowing an instance of a L<Device::Chip> driver to
communicate with the actual chip hardware by using an I<FDTI> USB-attached
chip as a hardware adapter.

=cut

=head1 CONSTRUCTOR

=cut

=head2 new

    $adapter = Device::Chip::Adapter::FTDI->new( %args )

Returns a new instance of a C<Device::Chip::Adapter::FTDI>. Takes the same
named argmuents as L<Device::FTDI/new>.

=cut

sub new
{
    my $class = shift;
    # TODO: at some point try to split the FTDI objects up so we can obtain a
    # handle on the basic USB object, and later upgrade it to e.g. SPI
    return bless { ftdi_args => [ @_ ] }, $class;
}

sub shutdown { }

sub make_protocol_SPI
{
    my $self = shift;
    my $spi = Device::Chip::Adapter::FTDI::_SPI->new( @{ $self->{ftdi_args} } );

    $self->{protocol} = $spi;

    Future->done( $spi );
}

package
    Device::Chip::Adapter::FTDI::_SPI;
use base qw( Device::FTDI::SPI );

use Carp;

sub configure
{
    my $self = shift;
    my %args = @_;

    my $mode        = delete $args{mode};
    my $max_bitrate = delete $args{max_bitrate};

    croak "Unrecognised configuration options: " . join( ", ", keys %args )
        if %args;

    $self->set_spi_mode( $mode )          if defined $mode;
    $self->set_clock_rate( $max_bitrate ) if defined $max_bitrate;

    Future->done;
}

# Basic FTDI has no control of power
sub power { Future->done }

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

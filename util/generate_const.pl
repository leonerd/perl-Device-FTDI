use strict;
use warnings;
use FindBin;

my %const = (
    BREAK_OFF => "BREAK_OFF",
    BREAK_ON => "BREAK_ON",

    BITS_7 => "BITS_7",
    BITS_8 => "BITS_8",

    PARITY_NONE => "NONE",
    PARITY_EVEN => "EVEN",
    PARITY_ODD => "ODD",
    PARITY_MARK => "3",
    PARITY_SPACE => "SPACE",

    FLOW_DISABLE => "SIO_DISABLE_FLOW_CTRL",
    FLOW_DTR_DSR => "SIO_DTR_DSR_HS",
    FLOW_RTS_CTS => "SIO_RTS_CTS_HS",
    FLOW_XON_XOFF => "SIO_XON_XOFF_HS",

    STOP_BIT_1 => "STOP_BIT_1",
    STOP_BIT_2 => "STOP_BIT_2",
    STOP_BIT_15 => "STOP_BIT_15",
);

open my $fh, ">", "$FindBin::Bin/../const_xs.inc" or die $!;

for (sort keys %const) {
    print $fh <<EOC;
int
dftdi$_()
    CODE:
        RETVAL = $const{$_};
    OUTPUT:
        RETVAL

EOC
}

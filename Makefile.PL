use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Device::FTDI',
    AUTHOR        => q{Pavel Shaydo <zwon@cpan.org>},
    VERSION_FROM  => 'lib/Device/FTDI.pm',
    ABSTRACT_FROM => 'lib/Device/FTDI.pm',
    LIBS          => ['-lusb -lftdi'],
    ( $ExtUtils::MakeMaker::VERSION >= 6.3002
        ? ( 'LICENSE' => 'perl' )
        : () ),
    PL_FILES       => {},
    PREREQ_PM      => { 'Test::More' => 0, },
    BUILD_REQUIRES => { 'Test::More' => 0.94, },
    dist           => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean      => { FILES => 'Device-FTDI-*' },
    META_MERGE => {
        resources => {
            homepage   => 'https://github.com/trinitum/perl-Device-FTDI',
            bugtracker => 'https://github.com/trinitum/perl-Device-FTDI/issues',
            repository => 'git://github.com/trinitum/perl-Device-FTDI',
            license    => 'http://dev.perl.org/licenses/',
        },
    },
);

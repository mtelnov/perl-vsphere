#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'VMware::vSphere',
    VERSION_FROM => 'lib/VMware/vSphere.pm',
    ABSTRACT     => 'Pure perl interface for VMware vSphere Web Services',
    AUTHOR       => 'Mikhail Telnov <Mikhail.Telnov@gmail.com>',
    LICENSE      => 'perl',
    PREREQ_PM    => {
        'Carp'                  => 0,
        'Data::Dumper'          => 0,
        'HTTP::Cookies'         => 0,
        'HTTP::Request::Common' => 0,
        'IO::Socket::SSL'       => 0,
        'LWP::UserAgent'        => 0,
        'LWP::Protocol::https'  => 0,
        'XML::Simple'           => 0,
        'XML::Writer'           => 0,
    },
    EXE_FILES => [ 'bin/vsphere', ],
    test      => { TESTS => "t/*.t" },
);

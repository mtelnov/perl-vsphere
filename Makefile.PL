#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'VMware::vSphere',
    VERSION_FROM => 'lib/VMware/vSphere.pm',
    ABSTRACT     => 'Perl interface to VMware vSphere for testing purposes',
    AUTHOR       => 'Mikhail Telnov <Mikhail.Telnov@gmail.com>',
    LICENSE      => 'perl',
    BUILD_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
        'Test::More'          => 0,
    },
    PREREQ_PM => {
        'Carp'            => 0,
        'Data::Dumper'    => 0,
        'File::Basename'  => 0,
        'List::Util'      => 0,
        'Pod::Find'       => 0,
        'Pod::Usage'      => 0,
        'WWW::Curl::Easy' => 0,
        'XML::Simple'     => 0,
        'XML::Writer'     => 0,
    },
    EXE_FILES => [ 'bin/vsphere', ],
    test      => { TESTS => "t/*.t" },
);

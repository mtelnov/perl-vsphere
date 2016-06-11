use strict;
use Test::More;

my @missed_envvar = grep { not defined $ENV{$_} }
                    qw{VSPHERE_HOST VSPHERE_USER VSPHERE_PASS};

if (@missed_envvar) {
    plan skip_all => 'Set environment variables '.join(', ', @missed_envvar).
                     ' to run this test suite.';
} else {
    plan tests => 14;
}

use VMware::vSphere;

my $v = VMware::vSphere->new(
    host     => $ENV{VSPHERE_HOST},
    username => $ENV{VSPHERE_USER},
    password => $ENV{VSPHERE_PASS},
);

is($v->debug, 0);
$v->debug(1);
is($v->debug, 1);
$v->debug(0);
is($v->debug, 0);
$v->debug(100500);
is($v->debug, 1);
$v->debug('');
is($v->debug, 0);

ok(defined $v->refresh_service, 'refresh_service');

isnt(
    $v->request(ServiceInstance => 'ServiceInstance', CurrentTime => undef),
    '',
    'request',
);

isnt($v->_get_object_set_for_vm, '', '_get_object_set_for_vm');
isnt($v->_get_object_set_for_host, '', '_get_object_set_for_host');
isnt($v->_get_object_set_for_datastore, '', '_get_object_set_for_datastore');
isnt($v->_get_object_set_for_cluster, '', '_get_object_set_for_cluster');
isnt($v->_get_object_set_for_datacenter, '', '_get_object_set_for_datacenter');

ok(defined $v->get_properties(of => 'HostSystem'), 'get_properties');

ok(defined $v->get_property('datastoreBrowser', of => 'HostSystem'), 'get_property');

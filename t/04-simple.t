use strict;
use Test::More;

if ($ENV{VSPHERE_HOST} and $ENV{VSPHERE_USER} and $ENV{VSPHERE_PASS}) {
    plan tests => 14;
} else {
    plan skip_all => 'Set environment variables VSPHERE_HOST, VSPHERE_USER, '.
                     'VSPHERE_PASS to run this test suite.';
}

use VMware::vSphere::Simple;

my $host = $ENV{VSPHERE_HOST};
my $user = $ENV{VSPHERE_USER};
my $pass = $ENV{VSPHERE_PASS};

my $v = VMware::vSphere::Simple->new(
    host => $host, username => $user, password => $pass,
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

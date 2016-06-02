use strict;
use Test::More;

if ($ENV{VSPHERE_HOST} and $ENV{VSPHERE_USER} and $ENV{VSPHERE_PASS}) {
    plan tests => 5;
} else {
    plan skip_all => 'Set environment variables VSPHERE_HOST, VSPHERE_USER, '.
                     'VSPHERE_PASS to run this test suite.';
}

use VMware::vSphere;
use VMware::vSphere::Simple;

my $host = $ENV{VSPHERE_HOST};
my $user = $ENV{VSPHERE_USER};
my $pass = $ENV{VSPHERE_PASS};

my $v = new_ok('VMware::vSphere' => [
    host => $host, username => $user, password => $pass,
]);
my @vsphere_methods = qw{
    debug
    get_object_set
    get_properties
    get_property
    login
    refresh_service
    request
    run_task
    wait_for_task
};
can_ok($v, @vsphere_methods);

my $vs = new_ok('VMware::vSphere::Simple' => [
    host => $host, username => $user, password => $pass,
]);
can_ok($vs, @vsphere_methods);
can_ok($vs, qw{
    add_nas_storage
    connect_cdrom
    connect_floppy
    create_disk
    create_snapshot
    disconnect_cdrom
    disconnect_floppy
    find_files
    get_datastore_url
    get_moid
    get_vm_path
    get_vm_powerstate
    linked_clone
    mount_tools_installer
    poweroff_vm
    poweron_vm
    reboot_vm
    reconfigure_vm
    register_vm
    remove_disk
    shutdown_vm
    tools_is_running
});

use strict;
use Test::More;

my @missed_envvar = grep { not defined }
                    qw{VSPHERE_HOST VSPHERE_USER VSPHERE_PASS VSPHERE_TEST_VM};

if (@missed_envvar) {
    plan skip_all => 'Set environment variables '.join(', ', @missed_envvar).
                     ' to run this test suite.';
} else {
    plan tests => 12;
}

my $vm_name = $ENV{VSPHERE_TEST_VM};

use VMware::vSphere::Simple;

my $v = VMware::vSphere::Simple->new(
    host     => $ENV{VSPHERE_HOST},
    username => $ENV{VSPHERE_USER},
    password => $ENV{VSPHERE_PASS},
);

ok($v->get_moid($vm_name), 'get_moid');
ok($v->get_vm_path($vm_name), 'get_vm_path');
my $powerstate = $v->get_vm_powerstate($vm_name);
like($powerstate, qr{(powered(Off|On)|suspended)}, 'get_vm_powerstate');
my $tools_is_running = $v->tools_is_running($vm_name);
ok(defined $tools_is_running, 'tools_is_running');

sub wait_for_powerstate {
    my $state = shift;
    my $start = time;
    while ($v->get_vm_powerstate($vm_name) ne $state) {
        die "VM '$vm_name' isn't $state in 3 minutes"
            if time - $start >= 180;
        sleep 5;
    }
    return 1;
}

sub wait_for_vmtools {
    my $start = time;
    while (not $v->tools_is_running($vm_name)) {
        return if time - $start >= 120;
        sleep 5;
    }
    return 1;
}

sub wait_until_vmtools_is_off {
    my $start = time;
    while (not $v->tools_is_running($vm_name)) {
        die "VMware Tools isn't stopped on $vm_name in 2 minutes"
            if time - $start >= 120;
        sleep 5;
    }
    return 1;
}

# resume VM if it was suspended before following tests
if ($powerstate eq 'suspended') {
    $v->poweron_vm($vm_name);
    &wait_for_powerstate('poweredOn');
}

# poweroff VM if it was running or resumed before following tests
if ($powerstate eq 'poweredOn') {
    if ($tools_is_running) {
        $v->shutdown_vm($vm_name);
    } else {
        $v->poweroff_vm($vm_name);
    }
    &wait_for_powerstate('poweredOff');
}

ok($v->create_snapshot(vm_name => $vm_name, name => 'test'), 'create_snapshot');
ok($v->poweron_vm($vm_name), 'poweron_vm');
my $tools_is_running = &wait_for_vmtools;

SKIP: {
    skip "VMware Tools isn't installed on $vm_name", 2 until $tools_is_running;

    ok($v->shutdown_vm($vm_name), 'shutdown_vm');
    &wait_for_powerstate('poweredOff');
    $v->poweron_vm($vm_name);
    &wait_for_powerstate('poweredOn');
    &wait_for_vmtools;
    ok($v->reboot_vm($vm_name), 'reboot_vm');
    &wait_until_vmtools_is_off;
    &wait_for_vmtools;
}

ok($v->mount_tools_installer($vm_name), 'mount_tools_installer');
ok($v->poweroff_vm($vm_name), 'poweroff_vm');
&wait_for_powerstate('poweredOff');
ok(
    $v->reconfigure_vm(
        vm_name           => $vm_name,
        numCPUs           => 2,
        numCoresPerSocket => 2,
        memoryMB          => 142,
    ),
    'reconfigure_vm'
);
ok($v->create_disk(vm_name => $vm_name, size => 42 * 1024), 'create_disk');

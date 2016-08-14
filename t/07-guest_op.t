use strict;
use Test::More;

my @missed_envvar = grep { not defined $ENV{$_} }
                    qw{VSPHERE_HOST VSPHERE_USER VSPHERE_PASS
                       VSPHERE_TEST_VM VSPHERE_TEST_VM_USER VSPHERE_TEST_VM_PASS
                       VSPHERE_TEST_CMD};

if (@missed_envvar) {
    plan skip_all => 'Set environment variables '.join(', ', @missed_envvar).
                     ' to run this test suite.';
} else {
    plan tests => 6;
}

my $vm_name = $ENV{VSPHERE_TEST_VM};
my $vm_user = $ENV{VSPHERE_TEST_VM_USER};
my $vm_pass = $ENV{VSPHERE_TEST_VM_PASS};
my $test_cmd = $ENV{VSPHERE_TEST_CMD};

use VMware::vSphere::Simple;

my $v = VMware::vSphere::Simple->new(
    host     => $ENV{VSPHERE_HOST},
    username => $ENV{VSPHERE_USER},
    password => $ENV{VSPHERE_PASS},
);

sub wait_for_vmtools {
    my $start = time;
    while (not $v->tools_is_running($vm_name)) {
        return if time - $start >= 120;
        sleep 5;
    }
    return 1;
}

# start vm if it isn't started yet
if ($v->get_vm_powerstate($vm_name) ne 'poweredOn') {
    $v->poweron_vm($vm_name);
    wait_for_vmtools() or die "VMware Tools isn't running on $vm_name";
}

my $pid = $v->run_in_vm($vm_name, $vm_user, $vm_pass, $test_cmd);
ok(defined $pid, 'run_in_vm');

my $proc_info = $v->list_vm_processes($vm_name, $vm_user, $vm_pass, $pid);
ok(defined $proc_info, 'list_vm_processes');
for (qw{ startTime cmdLine name owner }) {
    ok(defined $proc_info->{$pid}{$_}, 'list_vm_processes returns $_');
}

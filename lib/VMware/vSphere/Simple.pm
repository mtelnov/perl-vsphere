package VMware::vSphere::Simple;

our $VERSION = '1.03';

use strict;
use warnings;

use Carp;
use Net::SSLeay qw{ get_https3 };
use Scalar::Util qw{ blessed };
use URI::Escape;
use VMware::vSphere::MOID;
use WWW::Curl::Easy;
use XML::Simple;
use XML::Writer;

BEGIN {
    require VMware::vSphere;
    our @ISA = qw{ VMware::vSphere };
}

=head1 NAME

VMware::vSphere::Simple - simple interface for VMware vSphere Web Services

=head1 SYNOPSIS

    my $v = VMware::vSphere::Simple->new(
        host => $vcenter_host,
        username => $vcenter_username,
        password => $vcenter_password,
    );

    $v->poweron_vm($vm_name);

=head1 DESCRIPTION

This module provides an easy interface to VMware vSphere Web Services
(management interface for VMware vCenter and VMware ESXi products).

L<VMware::vSphere::Simple> extands L<VMware::vSphere>, so look its documentation
if you didn't read this yet.

=head1 METHODS

This module inherits all methods from L<VMware::vSphere>.

=cut

=head2 new

    $v = VMware::vSphere::Simple(
        host     => 'vc.example.com',
        username => 'Administrator@vsphere.local',
        password => 'secret',
    )

The constructor extends L<VMware::vSphere/new> with followin options:

=over

=item disable_name_cache =E<gt> $boolean

By default VMware::vSphere::Simple resolves name to the moid only once and then
uses the cached value. This option disables this cache.

=back

=cut

sub new {
    my $class = shift;
    my %args = @_;
    my $self = $class->SUPER::new(%args);
    $self->{disable_name_cache} = 1 if $args{disable_name_cache};
    return $self;
}
#-------------------------------------------------------------------------------

=head2 list

    @mo_names = $v->list()
    @mo_names = $v->list($type)

Returns a list with names of Managed Objects with specified C<$type>
('VirtualMachine' by default).

=cut

sub list {
    my ($self, $type) = @_;
    $type ||= 'VirtualMachine';
    my $p = $self->get_properties(of => $type, properties => ['name']);
    my @list = sort map { $p->{$_}{name} } keys %$p;
    return @list;
}
#-------------------------------------------------------------------------------

=head2 delete

    $v->delete($vm_name);
    $v->delete($mo_name, $mo_type);

Removes the managed object (and related files if exist) by its name.
C<$mo_type> is 'VirtualMachine' by default.

=cut

sub delete {
    my ($self, $name, $type) = @_;
    croak "Name of the managed object isn't defined" if not defined $name;
    $type ||= 'VirtualMachine';

    print STDERR "Delete $type with name '$name'\n" if $self->debug;

    $self->run_task($type => $self->get_moid($name, $type), 'Destroy_Task');
    return 1;
}
#-------------------------------------------------------------------------------

=head2 get_moid

    $moid = $v->get_moid($name)
    $moid = $v->get_moid($mo_name, $mo_type)

Returns ID of the managed object by its name. C<$mo_type> is 'VirtualMachine' by
default.

=cut

sub get_moid {
    my ($self, $name, $type) = @_;
    croak "Name of the managed object isn't defined" if not defined $name;
    return $name if blessed $name and $name->isa('VMware::vSphere::MOID');
    $type ||= 'VirtualMachine';
    return $self->{name_cache}{$type}{$name}
        if not $self->{disable_name_cache}
           and defined $self->{name_cache}{$type}{$name};

    my $p = $self->get_properties(
        of         => $type,
        where      => { name => $name },
        properties => [ 'name' ],
    );
    my $moid = (keys %$p)[0];
    croak "Can't find $type with name $name" if not defined $moid;
    $self->{name_cache}{$type}{$name} = $moid;
    return VMware::vSphere::MOID->new($moid);
}
#-------------------------------------------------------------------------------

=head2 clear_name_cache

    $v->clear_name_cache

Resets the local cache with MOIDs and object's names. It's required if you need
to access a newly created object with name as deleted one.

=cut

sub clear_name_cache {
    my ($self) = @_;
    $self->{name_cache} = {};
    return 1;
}
#-------------------------------------------------------------------------------

=head2 reload {

    $v->reload($name)
    $v->reload($name, $mo_type)

Reload the entity state. Clients only need to call this method if they changed
some external state that affects the service without using the Web service
interface to perform the change. For example, hand-editing a virtual machine
configuration file affects the configuration of the associated virtual machine
but the service managing the virtual machine might not monitor the file for
changes. In this case, after such an edit, a client would call "reload" on the
associated virtual machine to ensure the service and its clients have current
data for the virtual machine.
C<$mo_type> is 'VirtualMachine' by default.

=cut

sub reload {
    my ($self, $name, $type) = @_;
    croak "Name of the managed object isn't defined" if not defined $name;
    $type ||= 'VirtualMachine';

    $self->request(
        $type => $self->get_moid($name, $type),
        'Reload'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 get_vm_path

    $path = $v->get_vm_path($vm_name)

Returns path to the VM configuration file.

=cut

sub get_vm_path {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    return $self->get_property('config.files.vmPathName',
        of   => 'VirtualMachine',
        moid => $self->get_moid($vm_name),
    );
}
#-------------------------------------------------------------------------------

=head2 get_vm_powerstate

    $powerstate = $v->get_vm_powerstate($vm_name)

Returns the string representation of VM powersate: poweredOff, poweredOn,
suspended or unknown.

=cut

sub get_vm_powerstate {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    my $powerstate = $self->get_property('runtime.powerState',
        of   => 'VirtualMachine',
        moid => $self->get_moid($vm_name),
    ) || 'unknown';
    return $powerstate;
}
#-------------------------------------------------------------------------------

=head2 tools_is_running

    $boolean = $v->tools_is_running($vm_name)

Returns true if VMware Tools is running on the VM.

=cut

sub tools_is_running {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    return $self->get_property('guest.toolsRunningStatus',
        of   => 'VirtualMachine',
        moid => $self->get_moid($vm_name),
    ) eq 'guestToolsRunning';
}
#-------------------------------------------------------------------------------

=head2 get_datastore_url

    $datastore_url = $v->get_datastore_url($datastore_name)

Returns unique locator for the datastore.

=cut

sub get_datastore_url {
    my ($self, $name) = @_;
    croak "Datastore name isn't defined" if not defined $name;

    return $self->get_property('info.url',
        of   => 'Datastore',
        moid => $self->get_moid($name, 'Datastore'),
    );
}
#-------------------------------------------------------------------------------

=head2 poweron_vm

    $v->poweron_vm($vm_name)

Powers on the virtual machine. If the virtual machine is suspended, this method
resumes execution from the suspend point.

=cut

sub poweron_vm {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;
    print STDERR "Power on VM '$vm_name'\n" if $self->debug;
    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        'PowerOnVM_Task'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 poweroff_vm

    $v->poweroff_vm($vm_name)

Powers off the virtual machine. If this virtual machine is a fault tolerant
primary virtual machine, this will result in the secondary virtual machine(s)
getting powered off as well.

=cut

sub poweroff_vm {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;
    print STDERR "Power off VM '$vm_name'\n" if $self->debug;
    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        'PowerOffVM_Task'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 shutdown_vm

    $v->shutdown_vm($vm_name)

Issues a command to the guest operating system asking it to perform a clean
shutdown of all services. Returns immediately and does not wait for the guest
operating system to complete the operation.

=cut

sub shutdown_vm {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;
    print STDERR "Shutdown VM '$vm_name'\n" if $self->debug;
    $self->request(
        VirtualMachine => $self->get_moid($vm_name),
        'ShutdownGuest'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 reboot_vm

    $v->reboot_vm($vm_name)

Issues a command to the guest operating system asking it to perform a reboot.
Returns immediately and does not wait for the guest operating system to
complete the operation.

=cut

sub reboot_vm {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;
    print STDERR "Reboot VM '$vm_name'\n" if $self->debug;
    $self->request(
        VirtualMachine => $self->get_moid($vm_name),
        'RebootGuest'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 list_snapshots

    $v->list_snapshots($vm_name)

Returns a plain list with snapshots of the virtual machine as a hash reference
with $snapshot_id =E<gt> $snapshot_name elements.

=cut

sub list_snapshots {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;
    my $p = $self->get_property('snapshot.rootSnapshotList',
        moid => $self->get_moid($vm_name),
    );
    my %snapshots;
    if (exists $p->{VirtualMachineSnapshotTree}{snapshot}) {
        my $root = $p->{VirtualMachineSnapshotTree};
        $snapshots{$root->{snapshot}} = $root->{name};
        my $traverse;
        $traverse = sub {
            my $node = shift;
            if (exists $node->{childSnapshotList}) {
                my $c = $node->{childSnapshotList};
                for (keys %$c) {
                    $snapshots{$_} = $c->{$_}{name};
                    &{$traverse}($c->{$_});
                }
            }
        };
        &{$traverse}($root);
    }
    return \%snapshots;
}
#-------------------------------------------------------------------------------

=head2 create_snapshot

    $v->create_snapshot($vm_name, name => $snapshot_name, %options)

Creates a new snapshot of the virtual machine. As a side effect, this updates
the current snapshot.

Required parameters:

=over

=item $vm_name

Name of the target virtual machine.

=item name =E<gt> $snapshot_name

Name for the new snapshot.

=back

Optional parameters:

=over

=item description =E<gt> $description

Description for this snapshot.

=item memory =E<gt> $boolean

If TRUE, a dump of the internal state of the virtual machine (basically a memory
dump) is included in the snapshot. Memory snapshots consume time and resources,
and thus take longer to create. When set to FALSE, the power state of the
snapshot is set to powered off.


=item quiesce =E<gt> $boolean

If TRUE and the virtual machine is powered on when the snapshot is taken, VMware
Tools is used to quiesce the file system in the virtual machine. This assures
that a disk snapshot represents a consistent state of the guest file systems.
If the virtual machine is powered off or VMware Tools are not available, the
quiesce flag is ignored.

=back

=cut

sub create_snapshot {
    my $self = shift;
    my $vm_name = shift;
    my %args = (
        name        => undef,
        description => '',
        memory      => 0,
        quiesce     => 0,
        @_
    );
    croak "VM name isn't defined" if not defined $vm_name;
    for (qw{ name }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    print STDERR "Create the snapshot '$args{name}' for VM '$vm_name'\n"
        if $self->debug;

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement($_ => $args{$_})
        for qw{name description memory quiesce};
    $w->end;
    return $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        CreateSnapshot_Task => $spec
    );
}
#-------------------------------------------------------------------------------

=head2 revert_to_current_snapshot

    $v->revert_to_current_snapshot($vm_name)

Reverts the virtual machine to the current snapshot. If no snapshot exists, then
the operation does nothing, and the virtual machine state remains unchanged.

=cut

sub revert_to_current_snapshot {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    print STDERR "Revert VM '$vm_name' to the current snapshot\n"
        if $self->debug;

    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        'RevertToCurrentSnapshot_Task'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 revert_to_snapshot

    $v->revert_to_snapshot($snapshot_id)

Reverts the virtual machine to the snapshot specified by ID.

=cut

sub revert_to_snapshot {
    my ($self, $snapshot_id) = @_;
    croak "Snapshot id isn't defined" if not defined $snapshot_id;

    print STDERR "Revert to snapshot $snapshot_id\n"
        if $self->debug;

    $self->run_task(
        VirtualMachineSnapshot => $snapshot_id,
        'RevertToSnapshot_Task'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 remove_snapshot

    $v->remove_snapshot($snapshot_moid, %opts)

Removes this snapshot and deletes any associated storage.

Following options are available:

=over

=item removeChildren =E<gt> $boolean

Flag to specify removal of the entire snapshot subtree (enabled by default).

=item consolidate =E<gt> $boolean

If set to true, the virtual disk associated with this snapshot will be merged
with other disk if possible. Defaults to true.

=back

=cut

sub remove_snapshot {
    my $self = shift;
    my $snapshot_moid = shift;
    my %args = (
        removeChildren => 1,
        consolidate => 1,
        @_
    );
    croak "Snapshot ID isn't defined" if not defined $snapshot_moid;

    print STDERR "Remove snapshot with ID = $snapshot_moid\n"
        if $self->debug;

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement($_ => $args{$_} ? 'true': 'false')
        for qw{removeChildren consolidate};
    $w->end;
    $self->run_task(
        VirtualMachineSnapshot => $snapshot_moid,
        RemoveSnapshot_Task => $spec
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 reconfigure_vm

    $v->reconfigure_vm($vm_name, %options)

Modifies virtual hardware or configuration of the virtual machine.

The following options are available:

=over

=item numCPUs =E<gt> $int

Number of virtual processors in a virtual machine.

=item numCoresPerSocket =E<gt> $int

Number of cores among which to distribute CPUs in this virtual machine.

=item memoryMB =E<gt> $int

Size of a virtual machine's memory, in MB.

=back

=cut

sub reconfigure_vm {
    my $self = shift;
    my $vm_name = shift;
    my %args = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    print STDERR "Reconfigure VM '$vm_name'\n" if $self->debug;

    # TODO list all
    my @order = qw{ numCPUs numCoresPerSocket memoryMB };

    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    foreach (@order) {
        next unless defined $args{$_};
        print STDERR "Set '$_' to '$args{$_}'\n" if $self->debug;
        $w->dataElement($_ => $args{$_});
    }
    $w->endTag('spec');
    $w->end;
    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        ReconfigVM_Task => $spec
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 connect_cdrom

    $v->connect_cdrom($vm_name, $iso)

Mounts an ISO image to the virtual CD/DVD device.

=cut

sub connect_cdrom {
    my ($self, $vm_name, $iso) = @_;

    print STDERR "Connect ISO '$iso' to VM '$vm_name'\n" if $self->debug;

    #TODO remove hardcode
    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    $w->startTag('deviceChange');
    $w->dataElement(operation => 'edit');
    $w->startTag('device', 'xsi:type' => 'VirtualCdrom');
    $w->dataElement(key => 3002);
    $w->startTag('deviceInfo');
    $w->dataElement(label => 'CD/DVD drive 1');
    $w->dataElement(summary => 'Remote device');
    $w->endTag('deviceInfo');
    $w->startTag('backing', 'xsi:type' => 'VirtualCdromIsoBackingInfo');
    $w->dataElement(fileName => $iso);
    $w->endTag('backing');
    $w->startTag('connectable');
    $w->dataElement(startConnected => 'false');
    $w->dataElement(allowGuestControl => 'true');
    $w->dataElement(connected => 'true');
    $w->dataElement(status => 'ok');
    $w->endTag('connectable');
    $w->dataElement(controllerKey => 201);
    $w->dataElement(unitNumber => 0);
    $w->endTag('device');
    $w->endTag('deviceChange');
    $w->endTag('spec');
    $w->end;
    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        ReconfigVM_Task => $spec
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 disconnect_cdrom

    $v->disconnect_cdrom($vm_name)

Unmounts the virtual CD/DVD device.

=cut

sub disconnect_cdrom {
    my ($self, $vm_name) = @_;

    print STDERR "Disconnect virtal CD/DVD from VM '$vm_name'\n"
        if $self->debug;

    #TODO remove hardcode
    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    $w->startTag('deviceChange');
    $w->dataElement(operation => 'edit');
    $w->startTag('device', 'xsi:type' => 'VirtualCdrom');
    $w->dataElement(key => 3002);
    $w->startTag('deviceInfo');
    $w->dataElement(label => 'CD/DVD drive 1');
    $w->dataElement(summary => 'Remote device');
    $w->endTag('deviceInfo');
    $w->startTag('backing', 'xsi:type' => 'VirtualCdromRemoteAtapiBackingInfo');
    $w->dataElement(deviceName => '');
    $w->endTag('backing');
    $w->startTag('connectable');
    $w->dataElement(startConnected => 'false');
    $w->dataElement(allowGuestControl => 'true');
    $w->dataElement(connected => 'false');
    $w->dataElement(status => 'ok');
    $w->endTag('connectable');
    $w->dataElement(controllerKey => 201);
    $w->dataElement(unitNumber => 0);
    $w->endTag('device');
    $w->endTag('deviceChange');
    $w->endTag('spec');
    $w->end;
    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        ReconfigVM_Task => $spec
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 connect_floppy

    $v->connect_floppy($vm_name, $image)

Connects floppy image to the VM.

=cut

sub connect_floppy {
    my ($self, $vm_name, $image) = @_;

    print STDERR "Connect floppy-image '$image' to VM '$vm_name'\n"
        if $self->debug;

    #TODO remove hardcode
    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    $w->startTag('deviceChange');
    $w->dataElement(operation => 'edit');
    $w->startTag('device', 'xsi:type' => 'VirtualFloppy');
    $w->dataElement(key => 8000);
    $w->startTag('deviceInfo');
    $w->dataElement(label => 'Floppy drive 1');
    $w->dataElement(summary => 'Remote');
    $w->endTag('deviceInfo');
    $w->startTag('backing', 'xsi:type' => 'VirtualFloppyImageBackingInfo');
    $w->dataElement(fileName => $image);
    $w->endTag('backing');
    $w->startTag('connectable');
    $w->dataElement(startConnected => 'false');
    $w->dataElement(allowGuestControl => 'true');
    $w->dataElement(connected => 'true');
    $w->dataElement(status => 'untried');
    $w->endTag('connectable');
    $w->dataElement(controllerKey => 400);
    $w->dataElement(unitNumber => 0);
    $w->endTag('device');
    $w->endTag('deviceChange');
    $w->endTag('spec');
    $w->end;
    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        ReconfigVM_Task => $spec
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 disconnect_floppy

    $v->disconnect_floppy($vm_name)

Disconnects virtual floppy drive.

=cut

sub disconnect_floppy {
    my ($self, $vm_name) = @_;

    print STDERR "Disconnect virtual floppy from VM '$vm_name'\n"
        if $self->debug;

    #TODO remove hardcode
    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    $w->startTag('deviceChange');
    $w->dataElement(operation => 'edit');
    $w->startTag('device', 'xsi:type' => 'VirtualFloppy');
    $w->dataElement(key => 8000);
    $w->startTag('deviceInfo');
    $w->dataElement(label => 'Floppy drive 1');
    $w->dataElement(summary => 'Client Device');
    $w->endTag('deviceInfo');
    $w->startTag(
        'backing', 'xsi:type' => 'VirtualFloppyRemoteDeviceBackingInfo'
    );
    $w->dataElement(deviceName => '');
    $w->endTag('backing');
    $w->startTag('connectable');
    $w->dataElement(startConnected => 'false');
    $w->dataElement(allowGuestControl => 'true');
    $w->dataElement(connected => 'false');
    $w->dataElement(status => 'ok');
    $w->endTag('connectable');
    $w->dataElement(controllerKey => 400);
    $w->dataElement(unitNumber => 0);
    $w->endTag('device');
    $w->endTag('deviceChange');
    $w->endTag('spec');
    $w->end;
    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        ReconfigVM_Task => $spec
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 add_disk

    $v->add_disk($vm_name, size => $disk_size, %options)
    $v->add_disk($vm_name, file => $existent_vmdk, %options)

Creates a new virtual disk in the virtual machine.

Required parameters:

=over

=item $vm_name

Name of the target virtual machine.

=item size =E<gt> $disk_size

Size of the disk in KB. Can be ommited if existent C<file> is specified.

=item file =E<gt> $existent_vmdk

Path to the existent file with virtual disk in format '[datastore_name] 
path/file.vmdk'. Can be ommited in case of creating a new disk.

=back

Options:

=over

=item thin =E<gt> $boolean

Enables Thin Provisioning (enabled by default).

=item controller =E<gt> $controller_id

Controller ID (1000 by default).

=item unit =E<gt> $unit_number

Unit number. It will be set to the first spare unit number if not specified.

=item mode =E<gt> $disk_mode

Availabel values:

=over

=item persistent (default)

Changes are immediately and permanently written to the virtual disk.

=item nonpersistent

Changes to virtual disk are made to a redo log and discarded at power off.

=item independent_nonpersistent

Same as nonpersistent, but not affected by snapshots.

=item independent_persistent

Same as persistent, but not affected by snapshots.

=item append

Changes are appended to the redo log; you revoke changes by removing the undo 
log.

=item undoable

Changes are made to a redo log, but you are given the option to commit or undo.

=back

=back

=cut

sub add_disk {
    my $self = shift;
    my $vm_name = shift;
    my %args = (
        size       => undef, # in KB
        thin       => 1,     # enable Thin Provisioning
        controller => 1000,  # controller ID
        unit       => undef, # unit number
        file       => undef, # path to existent disk file
        mode       => 'persistent', # disk mode
        @_,
    );
    croak "VM name isn't defined" if not defined $vm_name;
    $args{file} ||= '';

    if ($args{file}) {
        print STDERR "Add virtual disk '$args{file}' to VM '$vm_name'"
            if $self->debug;
    } else {
        for (qw{ size }) {
            croak "Required parameter '$_' isn't defined"
                if not defined $args{$_};
        }

        print STDERR "Create virtual disk in VM '$vm_name' with size ".
                     "$args{size}KB\n" if $self->debug;
    }
    $args{size} ||= '';

    my $moid = $self->get_moid($vm_name);
    my $controller = $args{controller};
    my $unit = $args{unit};
    if (not defined $unit) {
        my $p = $self->get_property(
            'config.hardware.device', moid => $moid, force_array => ['device']
        );
        $p = $p->{VirtualDevice};
        my $devices = $p->{$controller}{device};
        $unit = 0;
        if (defined ref $devices and ref $devices eq 'ARRAY') {
            my %used_units = map { $p->{$_}{unitNumber} => 1 } @$devices;
            $used_units{$p->{$controller}{scsiCtlrUnitNumber}} = 1;
            $unit++ while exists $used_units{$unit};
        }
    }

    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    $w->startTag('deviceChange');
    $w->dataElement(operation => 'add');
    $w->dataElement(fileOperation => 'create') unless $args{file};
    $w->startTag('device', 'xsi:type' => 'VirtualDisk');
    $w->dataElement(key => '-100');
    $w->startTag(
        'backing', 'xsi:type' => 'VirtualDiskFlatVer2BackingInfo'
    );
    $w->dataElement(fileName => $args{file});
    $w->dataElement(diskMode => $args{mode});
    $w->dataElement(split => 'false');
    $w->dataElement(writeThrough => 'false');
    $w->dataElement(thinProvisioned => $args{thin} ? 'true' : 'false');
    $w->dataElement(eagerlyScrub => 'false');
    $w->endTag('backing');
    $w->startTag('connectable');
    $w->dataElement(startConnected => 'true');
    $w->dataElement(allowGuestControl => 'false');
    $w->dataElement(connected => 'true');
    $w->endTag('connectable');
    $w->dataElement(controllerKey => $controller);
    $w->dataElement(unitNumber => $unit);
    $w->dataElement(capacityInKB => $args{size});
    $w->endTag('device');
    $w->endTag('deviceChange');
    $w->endTag('spec');
    $w->end;
    $self->run_task(
        VirtualMachine => $moid,
        ReconfigVM_Task => $spec
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 create_disk

Alias for L<add_disk>

=cut

sub create_disk {
    return add_disk(@_);
}
#-------------------------------------------------------------------------------

=head2 remove_disk

    $v->remove_disk($vm_name, $key)

Removes a virtual disk from the virtual machine by its ID (C<$key>).

The following options are available:

=over

=item destroy =E<gt> $boolean

Deletes files from disk (enabled by default).

=back

=cut

sub remove_disk {
    my $self    = shift;
    my $vm_name = shift;
    my $key     = shift;
    my %args    = (
        destroy => 1,
        @_
    );
    croak "vm_name isn't defined" if not defined $vm_name;
    croak "key isn't defined" if not defined $key;

    print STDERR "Remove virtual disk #$key from the VM '$vm_name'\n"
        if $self->debug;

    my $vm_id = $self->get_moid($vm_name);
    my $p = $self->get_property('config.hardware.device', moid => $vm_id);
    my $d = $p->{VirtualDevice}{$key}
        or croak "Can't find virtual device with key = $key";

    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    $w->startTag('deviceChange');
    $w->dataElement(operation => 'remove');
    $w->dataElement(fileOperation => 'destroy') if $args{destroy};
    $w->startTag('device', 'xsi:type' => 'VirtualDisk');
    $w->dataElement(key => $key);
    $w->startTag('deviceInfo');
    $w->dataElement(label => $d->{deviceInfo}{label});
    $w->dataElement(summary => $d->{deviceInfo}{summary});
    $w->endTag('deviceInfo');
    $w->startTag(
        'backing', 'xsi:type' => 'VirtualDiskFlatVer2BackingInfo'
    );
    $w->dataElement($_ => $d->{backing}{$_})
        for qw{ fileName diskMode split writeThrough thinProvisioned uuid
            contentId digestEnabled };

    $w->endTag('backing');
    $w->dataElement($_ => $d->{$_})
        for qw{ controllerKey unitNumber capacityInKB };
    $w->startTag('shares');
    $w->dataElement($_ => $d->{shares}{$_})
        for qw{ shares level };
    $w->endTag('shares');
    $w->startTag('storageIOAllocation');
    $w->dataElement(limit => $d->{storageIOAllocation}{limit});
    $w->startTag('shares');
    $w->dataElement($_ => $d->{storageIOAllocation}{shares}{$_})
        for qw{ shares level };
    $w->endTag('shares');
    $w->endTag('storageIOAllocation');
    $w->endTag('device');
    $w->endTag('deviceChange');
    $w->endTag('spec');
    $w->end;
    $self->run_task(
        VirtualMachine => $self->get_moid($vm_name),
        ReconfigVM_Task => $spec
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 add_nas_storage

    $v->add_nas_storage(%parameters)

Adds a NAS storage to the host and returns its MOID.

Required parameters:

=over

=item host_name =E<gt> $host_name

Display name of the host system (ESXi).

=item remote_host =E<gt> $remote_host

Hostname or IP address of the NAS.

=item remote_path =E<gt> $remote_path

Path to the NAS storage.

=item local_path =E<gt> $local_path

Name for the local mount point.

=item type =E<gt> $type

NAS type ('nfs' by default).

=item access_mode =E<gt> $access_mode

Access mode to mount ('readWrite' by default).

=back

=cut

sub add_nas_storage {
    my $self = shift;
    my %args = (
        host_name   => undef,
        remote_host => undef,
        remote_path => undef,
        local_path  => undef,
        type        => 'nfs',
        access_mode => 'readWrite',
        @_,
    );
    for (qw{ host_name remote_host remote_path local_path }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    print STDERR "Mount NAS $args{type} $args{remote_host}:$args{remote_path} ".
                 "to $args{local_path} at $args{host_name} with ".
                 "$args{access_mode} access mode\n" if $self->debug;

    # Get HostDatastoreSystem
    my $datastoreSystem = $self->get_property('configManager.datastoreSystem',
        of   => 'HostSystem',
        moid => $self->get_moid($args{host_name}, 'HostSystem'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    $w->dataElement(remoteHost => $args{remote_host});
    $w->dataElement(remotePath => $args{remote_path});
    $w->dataElement(localPath  => $args{local_path});
    $w->dataElement(accessMode => $args{access_mode});
    $w->dataElement(type       => $args{type});
    $w->endTag('spec');
    $w->end;
    my $response = $self->request(
        HostDatastoreSystem => $datastoreSystem,
        CreateNasDatastore  => $spec,
    );
    croak "Wrong response from the server: $response"
        if $response !~ /<returnval type="Datastore">([^<]+)<\/returnval>/;
    return $1;
}
#-------------------------------------------------------------------------------

=head2 find_files

    $v->find_files(datastore => $datastore, pattern = $pattern, %options)

Searches files on the C<$datastore> by C<$pattern> and returns an array 
reference with pathes or a hash reference if C<with_info> option is true.

The following options are available:

=over

=item path =E<gt> $path

Top level directory at the storage to start search (root of datastore by
default).

=item case_sensitive =E<gt> $boolean

This flag indicates whether or not to search using a case insensitive match on
type (disabled by default).

=item with_info =E<gt> $boolean

Extends return with file info.

=back

=cut

sub find_files {
    my $self = shift;
    my %args = (
        datastore      => undef,    # name of the datastore
        pattern        => undef,    # pattern for filenames
        path           => undef,    # TODO
        case_sensitive => 0,        # TODO
        with_info      => 0,        # also return file info
        @_,
    );
    for (qw{ datastore pattern }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    my $datastore_path = "[$args{datastore}]";
    $datastore_path .= " $args{path}" if defined $args{path};

    # Get HostDatastoreBrowser
    my $browser = $self->get_property('browser',
        of   => 'Datastore',
        moid => $self->get_moid($args{datastore}, 'Datastore'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(datastorePath => $datastore_path);
    $w->startTag('searchSpec');
    $w->emptyTag('query', 'xsi:type' => 'FolderFileQuery');
    $w->emptyTag('query');
    $w->startTag('details');
    $w->dataElement($_ => ($args{with_info} ? 'true' : 'false'))
        for qw{ fileType fileSize modification fileOwner };
    $w->endTag('details');
    $w->dataElement(
        searchCaseInsensitive => $args{case_sensitive} ? 'false' : 'true',
    );
    $w->dataElement(matchPattern => $args{pattern});
    $w->dataElement(sortFoldersFirst => 'false');
    $w->endTag('searchSpec');
    $w->end;
    my $result = $self->run_task(
        HostDatastoreBrowser => $browser,
        SearchDatastoreSubFolders_Task => $spec,
    );
    if ($args{with_info}) {
        my %info;
        for my $file (@{$result->{HostDatastoreBrowserSearchResults}}) {
            next unless defined $file->{file};
            my $path = $file->{folderPath}.$file->{file}{path};
            for (keys %{$file->{file}}) {
                next if $_ eq 'path';
                $info{$path}->{$_} = $file->{file}{$_};
            }
        }
        return \%info;
    }
    my @pathes;
    for (@{$result->{HostDatastoreBrowserSearchResults}}) {
        push @pathes, $_->{folderPath}.$_->{file}{path}
            if defined $_->{folderPath} and defined $_->{file}{path};

    }
    return \@pathes;
}
#-------------------------------------------------------------------------------

=head2 register_vm

    $v->register_vm($vm_name, %parameters)

Registers a virtual machine in the inventory.

Required parameters:

=over

=item datacenter =E<gt> $datacenter

Name of the target datacenter.

=item cluster =E<gt> $cluster

Name of the target cluster.

=item host =E<gt> $host

Name of the target host system.

=item path =E<gt> $path

Path to the config file of virtual machine.

=back

Optional parameters:

=over

=item as_template =E<gt> $boolean

Register as a VM template.

=back

=cut

sub register_vm {
    my $self = shift;
    my $vm_name = shift;
    my %args = (
        datacenter => undef, # Datacenter name
        cluster => undef, # Cluster name
        host    => undef, # Host name
        path    => undef, # Path to the VM config file
        as_template => 0, # Add as template
        @_,
    );
    croak "VM name isn't defined" if not defined $vm_name;
    for (qw{ datacenter host path }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    print STDERR "Register $args{path} as $vm_name at $args{host}\n"
        if $self->debug;

    my $datacenter = $self->get_property('vmFolder',
        of => 'Datacenter',
        moid => $self->get_moid($args{datacenter}, 'Datacenter'),
    );

    my $cluster;
    if (defined $args{cluster}) {
        $cluster = $self->get_property('resourcePool',
            of   => 'ClusterComputeResource',
            moid => $self->get_moid($args{cluster}, 'ClusterComputeResource'),
        );
    } else {
        $cluster = $self->get_property('resourcePool',
            of   => 'ComputeResource',
            moid => $self->get_moid($args{host}, 'ComputeResource'),
        );
    }

    my $host = $self->get_moid($args{host}, 'HostSystem');

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(path => $args{path});
    $w->dataElement(name => $vm_name);
    $w->dataElement(asTemplate => $args{as_template} ? 'true' : 'false');
    $w->dataElement(pool => $cluster, type => 'ResourcePool');
    $w->dataElement(host => $host, type => 'HostSystem');
    $w->end;

    return $self->run_task(
        Folder          => $datacenter,
        RegisterVM_Task => $spec,
    );
}
#-------------------------------------------------------------------------------

=head2 unregister_vm

    $v->unregister_vm($vm_name)

Removes this virtual machine from the inventory without removing any of the
virtual machine's files on disk. All high-level information stored with the
management server (ESX Server or VirtualCenter) is removed, including
information such as statistics, resource pool association, permissions, and
alarms.

=cut

sub unregister_vm {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    print STDERR "Unregister the VM $vm_name\n"
        if $self->debug;

    $self->request(
        VirtualMachine => $self->get_moid($vm_name),
        'UnregisterVM'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 mount_tools_installer

    $v->mount_tools_installer($vm_name)

Mounts the VMware Tools CD installer as a CD-ROM for the guest operating system.

=cut

sub mount_tools_installer {
    my ($self, $vm_name) = @_;
    print STDERR "Mount VMware Tools installer to VM '$vm_name'\n"
        if $self->debug;
    $self->request(
        VirtualMachine => $self->get_moid($vm_name),
        'MountToolsInstaller'
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 clone

    $v->clone($vm_name, $clone_name, %parameters)

Creates a clone of this virtual machine. If the virtual machine is used as a
template, this method corresponds to the deploy command.

Optional parameters:

=over

=item datastore =E<gt> $datastore_name

Name of the target datastore.

=back

=item folder =E<gt> $folder_moid

MOID of the destination folder.

=back

=cut

sub clone {
    my $self       = shift;
    my $vm_name    = shift;
    my $clone_name = shift;
    my %args = (
        datastore => undef,
        folder    => undef,
        @_,
    );

    print STDERR "Clone '$vm_name' as '$clone_name'.\n"
        if $self->debug;

    my $p = $self->get_properties(
        properties => [qw{ parent parentVApp datastore }],
        moid       => $self->get_moid($vm_name),
    );

    my $vm_id = (keys %$p)[0]
        or croak "Can't get info for VM '$vm_name'";

    my $datastore;
    if (defined $args{datastore}) {
        $datastore = $self->get_moid($args{datastore}, 'Datastore');
    } else {
        $datastore = $p->{$vm_id}{datastore}{ManagedObjectReference}
            or croak "Can't get datastore of the VM '$vm_name'";
        croak "VM '$vm_name' located at more than one datastore, ".
              "please specify 'datastore' option"
            if ref $datastore;
    }

    my $parent = $args{folder};
    if (not defined $parent) {
        $parent = $p->{$vm_id}{parent};
        if (defined $p->{$vm_id}{parentVApp}) {
            $parent = $self->get_property('parentFolder',
                of => 'VirtualApp',
                moid => $p->{$vm_id}{parentVApp},
            );
        }
        croak "Can't get parent folder for VM '$vm_name'"
            if not defined $parent;
    }

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(folder => $parent, type => 'Folder');
    $w->dataElement(name => $clone_name);
    $w->startTag('spec');
    $w->startTag('location');
    $w->dataElement(datastore => $datastore, type => 'Datastore');
    $w->endTag('location');
    $w->dataElement(template => 0);
    $w->dataElement(powerOn => 0);
# TODO
#    $w->dataElement(snapshot => $snapshot, type => 'VirtualMachineSnapshot');
    $w->endTag('spec');
    $w->end;

    return $self->run_task(
        VirtualMachine => $vm_id,
        CloneVM_Task   => $spec,
    );
}
#-------------------------------------------------------------------------------

=head2 linked_clone

    $v->linked_clone($vm_name, $clone_name)

Creates a linked clone from the VM snapshot.

=cut

sub linked_clone {
    my ($self, $vm_name, $clone_name) = @_;

    print STDERR "Create linked clone with name '$clone_name' from VM $vm_name\n"
        if $self->debug;

    my $p = $self->get_properties(
        properties => [qw{ parent parentVApp snapshot.currentSnapshot }],
        moid       => $self->get_moid($vm_name),
    );

    my $vm_id = (keys %$p)[0]
        or croak "Can't get info for VM '$vm_name'";
    my $snapshot = $p->{$vm_id}{'snapshot.currentSnapshot'}
        or croak "Can't get current snapshot for VM '$vm_name'";
    my $parent = $p->{$vm_id}{parent};
    if (defined $p->{$vm_id}{parentVApp}) {
        $parent = $self->get_property('parentFolder',
            of => 'VirtualApp',
            moid => $p->{$vm_id}{parentVApp},
        );
    }
    croak "Can't get parent folder for VM '$vm_name'"
        if not defined $parent;

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(folder => $parent, type => 'Folder');
    $w->dataElement(name => $clone_name);
    $w->startTag('spec');
    $w->startTag('location');
    $w->dataElement(diskMoveType => 'createNewChildDiskBacking');
    $w->endTag('location');
    $w->dataElement(template => 0);
    $w->dataElement(powerOn => 0);
    $w->dataElement(snapshot => $snapshot, type => 'VirtualMachineSnapshot');
    $w->endTag('spec');
    $w->end;

    return $self->run_task(
        VirtualMachine => $vm_id,
        CloneVM_Task   => $spec,
    );
}
#-------------------------------------------------------------------------------

=head2 make_tmpdir_in_vm

    $v->make_tmpdir_in_vm
        $vm_name,
        username => $username,
        password => $password,
        prefix   => $prefix,
        suffix   => $suffix,
        path     => $path,
    )

Creates a new unique temporary directory for the user to use as needed. The user
is responsible for removing it when it is no longer needed.

=cut

sub make_tmpdir_in_vm {
    my $self    = shift;
    my $vm_name = shift;
    my %args = (
        username => undef,
        password => undef,
        prefix   => '',
        suffix   => '',
        path     => '',
        @_
    );

    for (qw{ username password }) {
        croak "Missed required argument '$_'" unless defined $args{$_};
    }

    print STDERR "Make temporary directory in $vm_name\n"
        if $self->debug;

    my $file_manager = $self->get_property('fileManager',
        of   => 'GuestOperationsManager',
        moid => $self->{service}{guestOperationsManager},
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(vm => $self->get_moid($vm_name), type => 'VirtualMachine');
    $w->startTag('auth', 'xsi:type' => 'NamePasswordAuthentication');
    $w->dataElement(interactiveSession => 'false');
    $w->dataElement(username => $args{username});
    $w->dataElement(password => $args{password});
    $w->endTag('auth');
    $w->dataElement(prefix => $args{prefix}) if defined $args{prefix};
    $w->dataElement(suffix => $args{suffix}) if defined $args{suffix};
    $w->dataElement(directoryPath => $args{path}) if defined $args{path};
    $w->end;

    my $response = $self->request(
        GuestFileManager => $file_manager,
        CreateTemporaryDirectoryInGuest => $spec,
    );
    my $xml = XMLin($response);
    croak "Invalid response: $response" unless ref $xml and ref $xml eq 'HASH';
    my $path = $xml->{'soapenv:Body'}{CreateTemporaryDirectoryInGuestResponse}{returnval}
        or croak "Invalid response: $response";
    return $path;
}
#-------------------------------------------------------------------------------

=head2 make_tmpfile_in_vm

    $v->make_tmpfile_in_vm
        $vm_name,
        username => $username,
        password => $password,
        prefix   => $prefix,
        suffix   => $suffix,
        path     => $path,
    )

Creates a new unique temporary file for the user to use as needed. The user is
responsible for removing it when it is no longer needed.

=cut

sub make_tmpfile_in_vm {
    my $self    = shift;
    my $vm_name = shift;
    my %args = (
        username => undef,
        password => undef,
        prefix   => '',
        suffix   => '',
        path     => '',
        @_
    );

    for (qw{ username password }) {
        croak "Missed required argument '$_'" unless defined $args{$_};
    }

    print STDERR "Make temporary file in $vm_name\n"
        if $self->debug;

    my $file_manager = $self->get_property('fileManager',
        of   => 'GuestOperationsManager',
        moid => $self->{service}{guestOperationsManager},
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(vm => $self->get_moid($vm_name), type => 'VirtualMachine');
    $w->startTag('auth', 'xsi:type' => 'NamePasswordAuthentication');
    $w->dataElement(interactiveSession => 'false');
    $w->dataElement(username => $args{username});
    $w->dataElement(password => $args{password});
    $w->endTag('auth');
    $w->dataElement(prefix => $args{prefix}) if defined $args{prefix};
    $w->dataElement(suffix => $args{suffix}) if defined $args{suffix};
    $w->dataElement(directoryPath => $args{path}) if defined $args{path};
    $w->end;

    my $response = $self->request(
        GuestFileManager => $file_manager,
        CreateTemporaryFileInGuest => $spec,
    );
    my $xml = XMLin($response);
    croak "Invalid response: $response" unless ref $xml and ref $xml eq 'HASH';
    my $path = $xml->{'soapenv:Body'}{CreateTemporaryFileInGuestResponse}{returnval}
        or croak "Invalid response: $response";
    return $path;
}
#-------------------------------------------------------------------------------

=head2 copy_into_vm

    $v->copy_into_vm(
        $vm_name,
        username  => $username,
        password  => $password,
        local     => $local_path,
        remote    => $remote_path,
        overwrite => $boolean,
    )

Copies a local file into the guest operating system.

=cut

sub copy_into_vm {
    my $self    = shift;
    my $vm_name = shift;
    my %args = (
        username  => undef,
        password  => undef,
        local     => undef,
        remote    => undef,
        permissions => undef,
        overwrite   => 0,
        @_
    );

    for (qw{ username password local remote }) {
        croak "Missed required argument '$_'" unless defined $args{$_};
    }

    print STDERR "Copy '$args{local}' to '$args{remote}' into $vm_name\n"
        if $self->debug;

    my $size = (stat $args{local})[7];
    croak "Can't get size of file '$args{local}'" unless defined $size;

    my $file_manager = $self->get_property('fileManager',
        of   => 'GuestOperationsManager',
        moid => $self->{service}{guestOperationsManager},
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(vm => $self->get_moid($vm_name), type => 'VirtualMachine');
    $w->startTag('auth', 'xsi:type' => 'NamePasswordAuthentication');
    $w->dataElement(interactiveSession => 'false');
    $w->dataElement(username => $args{username});
    $w->dataElement(password => $args{password});
    $w->endTag('auth');
    $w->dataElement(guestFilePath => $args{remote});
    if (defined $args{permissions}) {
        $w->startTag('fileAttributes', 'xsi:type' => 'GuestPosixFileAttributes');
        $w->dataElement(
            permissions => oct($args{permissions}),
            'xsi:type'  => 'xsd:long'
        );
        $w->endTag('fileAttributes');
    } else {
        $w->startTag('fileAttributes', 'xsi:type' => 'GuestFileAttributes');
        $w->endTag('fileAttributes');
    }
    $w->dataElement(fileSize => $size);
    $w->dataElement(overwrite => $args{overwrite} ? 'true' : 'false');
    $w->end;

    my $response = $self->request(
        GuestFileManager => $file_manager,
        InitiateFileTransferToGuest => $spec,
    );
    my $xml = XMLin($response);
    croak "Invalid response: $response" unless ref $xml and ref $xml eq 'HASH';
    my $url = $xml->{'soapenv:Body'}{InitiateFileTransferToGuestResponse}{returnval}
        or croak "Invalid response: $response";
    my $host = $self->{host};
    $host =~ s/:\d+$//s;
    $url =~ s{://\*}{://$host};

    open my $fh, '<', $args{local}
        or croak "Can't open local file '$args{local}': $!";
    binmode $fh;

    my $curl = $self->{curl};
    $curl->setopt(CURLOPT_URL, $url);
    $curl->setopt(CURLOPT_POST, 0);
    $curl->setopt(CURLOPT_HTTPHEADER, []);
    $curl->setopt(CURLOPT_UPLOAD, 1);
    $curl->setopt(CURLOPT_PUT, 1);
    $curl->setopt(CURLOPT_INFILESIZE_LARGE, $size);
    $curl->setopt(CURLOPT_READDATA, $fh);

    $response = undef;
    $curl->setopt(CURLOPT_WRITEDATA, \$response);
    my $retcode = $curl->perform;
    close $fh;
    croak "Can't upload file to $url: $retcode ".$curl->strerror($retcode).
          " ".$curl->errbuf if $retcode;
    print STDERR "Got response:\n", '-'x80, "\n", $response, "\n", '-'x80, "\n"
        if $self->{debug} and defined $response;

    my $http_code = $curl->getinfo(CURLINFO_HTTP_CODE);
    return 1 if $http_code == 200;
    croak "Host returned an error: $http_code" if not defined $response;
    croak "Host returned an error: $response";
}
#-------------------------------------------------------------------------------

=head2 copy_from_vm

    $v->copy_from_vm(
        $vm_name,
        username  => $username,
        password  => $password,
        remote    => $remote_path,
        local     => $local_path,
    )

Copies a file from the guest operating system.

=cut

sub copy_from_vm {
    my $self    = shift;
    my $vm_name = shift;
    my %args = (
        username => undef,
        password => undef,
        remote   => undef,
        local    => undef,
        @_
    );

    for (qw{ username password local remote }) {
        croak "Missed required argument '$_'" unless defined $args{$_};
    }

    print STDERR "Copy '$args{remote}' from $vm_name to '$args{local}'\n"
        if $self->debug;

    my $file_manager = $self->get_property('fileManager',
        of   => 'GuestOperationsManager',
        moid => $self->{service}{guestOperationsManager},
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(vm => $self->get_moid($vm_name), type => 'VirtualMachine');
    $w->startTag('auth', 'xsi:type' => 'NamePasswordAuthentication');
    $w->dataElement(interactiveSession => 'false');
    $w->dataElement(username => $args{username});
    $w->dataElement(password => $args{password});
    $w->endTag('auth');
    $w->dataElement(guestFilePath => $args{remote});
    $w->end;

    my $response = $self->request(
        GuestFileManager => $file_manager,
        InitiateFileTransferFromGuest => $spec,
    );
    my $xml = XMLin($response);
    croak "Invalid response: $response" unless ref $xml and ref $xml eq 'HASH';
    my $r = $xml->{'soapenv:Body'}{InitiateFileTransferFromGuestResponse}{returnval}
        or croak "Invalid response: $response";
    my $host = $self->{host};
    $host =~ s/:\d+$//s;
    $r->{url} =~ s{://\*}{://$host};

    open my $fh, '>', $args{local}
        or croak "Can't open local file '$args{local}': $!";
    binmode $fh;

    my $curl = $self->{curl};
    $curl->setopt(CURLOPT_URL, $r->{url});
    $curl->setopt(CURLOPT_POST, 0);
    $curl->setopt(CURLOPT_UPLOAD, 0);
    $curl->setopt(CURLOPT_PUT, 0);
    $curl->setopt(CURLOPT_HTTPGET, 1);
    $curl->setopt(CURLOPT_HTTPHEADER, []);
    $curl->setopt(CURLOPT_WRITEDATA, $fh);
    my $retcode = $curl->perform;
    close $fh or croak "Can't close local file '$args{local}': $!";
    croak "Can't download $r->{url}: $retcode ".$curl->strerror($retcode).
          " ".$curl->errbuf if $retcode;
    my $http_code = $curl->getinfo(CURLINFO_HTTP_CODE);
    return 1 if $http_code == 200;
    croak "Host returned an error: $http_code";
}
#-------------------------------------------------------------------------------

=head2 run_in_vm

    $pid = $v->run_in_vm(
        $vm_name,
        username => $username,
        password => $password,
        path     => $cmd,
        %options
    )

Starts a program in the guest operating system and returns its pid. When the 
process completes, its exit code and end time will be available for 5 minutes 
after completion.

Required arguments:

=over

=item $vm_name

Name of the target virtual machine.

=item username =E<gt> $username

Login to authenticate in the guest operating system.

=item password =E<gt> $password

Password for this login.

=item path =E<gt> $path

The absolute path to the program to start. For Linux guest operating systems, 
/bin/bash is used to start the program. For Solaris guest operating systems, 
/bin/bash is used to start the program if it exists. Otherwise /bin/sh is used.
If /bin/sh is used, then the process ID will be that of the shell used to start 
the program, rather than the program itself, due to the differences in how 
/bin/sh and /bin/bash work.

=back

Optional parameters:

=over

=item args =E<gt> $arguments

The arguments to the program. In Linux and Solaris guest operating systems, the 
program will be executed by a guest shell. This allows stdio redirection, but 
may also require that characters which must be escaped to the shell also be 
escaped on the command line provided. For Windows guest operating systems, 
prefixing the command with "cmd /c" can provide stdio redirection. 

=item dir =E<gt> $working_directory

The absolute path of the working directory for the program to be run. VMware 
recommends explicitly setting the working directory for the program to be run. 
If this value is unset or is an empty string, the behavior depends on the guest 
operating system. For Linux guest operating systems, if this value is unset or 
is an empty string, the working directory will be the home directory of the user 
associated with the guest authentication. For other guest operating systems, if 
this value is unset, the behavior is unspecified.

=item env =E<gt> \@environment_variables

An array of environment variables, specified in the guest OS notation 
(eg PATH=c:\bin;c:\windows\system32 or LD_LIBRARY_PATH=/usr/lib:/lib), to be set 
for the program being run. Note that these are not additions to the default 
environment variables; they define the complete set available to the program. 
If none are specified the values are guest dependent. 

=item interactive =E<gt> $boolean

This is set to true if the client wants an interactive session in the guest.

=back

=cut

sub run_in_vm {
    my $self     = shift;
    my $vm_name  = shift;
    my %args = (
        username    => undef,
        password    => undef,
        interactive => 0,
        path        => undef,
        args        => '',
        dir         => undef,
        env         => [],
        @_,
    );

    for (qw{ username password path }) {
        croak "Missed required argument '$_'" unless defined $args{$_};
    }

    print STDERR "Run '$args{path} $args{args}' in $vm_name\n" if $self->debug;

    my $process_manager = $self->get_property('processManager',
        of   => 'GuestOperationsManager',
        moid => $self->{service}{guestOperationsManager},
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(vm => $self->get_moid($vm_name), type => 'VirtualMachine');
    $w->startTag('auth', 'xsi:type' => 'NamePasswordAuthentication');
    $w->dataElement(interactiveSession => $args{interactive} ? 'true':'false');
    $w->dataElement(username => $args{username});
    $w->dataElement(password => $args{password});
    $w->endTag('auth');
    $w->startTag('spec');
    $w->dataElement(programPath => $args{path});
    $w->dataElement(arguments => $args{args});
    $w->dataElement(workingDirectory => $args{dir}) if $args{dir};
    $w->dataElement(envVariables => $_) for @{$args{env}};
    $w->endTag('spec');
    $w->end;

    my $response = $self->request(
        GuestProcessManager => $process_manager,
        StartProgramInGuest => $spec,
    );
    if ($response =~ m|<returnval>(\d+)</returnval>|) {
        return $1;
    }
    croak "Invalid response: $response";
}
#-------------------------------------------------------------------------------

=head2 list_vm_processes

    $proc_info = $v->list_vm_processes(
        $vm_name,
        username => $username,
        password => $password,
        %options
    )

List the processes running in the guest operating system, plus those started by 
C<run_in_vm()> that have recently completed.

Required arguments:

=over

=item $vm_name

Name of the target virtual machine.

=item username =E<gt> $username

Login to authenticate in the guest operating system.

=item password =E<gt> $password

Password for this login.

=back

Optional parameters:

=over

=item pids =E<gt> $array_reference

Return information about processes specified by IDs only.

=item interactive =E<gt> $boolean

This is set to true if the client wants an interactive session in the guest.

=back

=cut

sub list_vm_processes {
    my $self    = shift;
    my $vm_name = shift;
    my %args = (
        username    => undef,
        password    => undef,
        interactive => undef,
        pids        => [],
        @_
    );

    for (qw{ username password }) {
        croak "Missed required argument '$_'" unless defined $args{$_};
    }

    my $process_manager = $self->get_property('processManager',
        of   => 'GuestOperationsManager',
        moid => $self->{service}{guestOperationsManager},
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(vm => $self->get_moid($vm_name), type => 'VirtualMachine');
    $w->startTag('auth', 'xsi:type' => 'NamePasswordAuthentication');
    $w->dataElement(interactiveSession => $args{interactive} ? 'true':'false');
    $w->dataElement(username => $args{username});
    $w->dataElement(password => $args{password});
    $w->endTag('auth');
    $w->dataElement(pids => $_) for @{$args{pids}};
    $w->end;

    my $response = $self->request(
        GuestProcessManager => $process_manager,
        ListProcessesInGuest => $spec,
    );
    my $xml = XMLin(
        $response,
        ForceArray => [qw{ returnval }],
        KeyAttr    => [qw{ pid }]
    );
    return $xml->{'soapenv:Body'}{ListProcessesInGuestResponse}{returnval};
}
#-------------------------------------------------------------------------------

=head2 add_portgroup

    $v->add_portgroup($host, $vswitch, $portgroup)
    $v->add_portgroup($host, $vswitch, $portgroup, $vlan)

Adds a port group to the virtual switch.

Required parameters:

=over

=item $host

Host name

=item $vswitch

Name of the virtual switch.

=item $portgroup

Name for the port group.

=back

Optional parameters:

=over

=item $vlan

The VLAN ID for ports using this port group. Possible values:

=over

=item *

A value of 0 specifies that you do not want the port group associated with a 
VLAN (by default).

=item *

A value from 1 to 4094 specifies a VLAN ID for the port group.

=item *

A value of 4095 specifies that the port group should use trunk mode, which 
allows the guest operating system to manage its own VLAN tags.

=back

=back

=cut

sub add_portgroup {
    my ($self, $host, $vswitch, $portgroup, $vlan) = @_;
    $vlan ||= 0;

    my $network_system = $self->get_property('configManager.networkSystem',
        of   => 'HostSystem',
        moid => $self->get_moid($host, 'HostSystem'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('portgrp');
    $w->dataElement(name => $portgroup);
    $w->dataElement(vlanId => $vlan);
    $w->dataElement(vswitchName => $vswitch);
    $w->emptyTag('policy');
    $w->endTag('portgrp');
    $w->end;

    $self->request(
        HostNetworkSystem => $network_system,
        AddPortGroup => $spec,
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 remove_portgroup

    $v->remove_portgroup($host, $portgroup)

Removes port group from the virtual switch.

Required parameters:

=over

=item $host

Host name

=item $portgroup

Name for the port group.

=back

=cut

sub remove_portgroup {
    my ($self, $host, $portgroup) = @_;

    my $network_system = $self->get_property('configManager.networkSystem',
        of   => 'HostSystem',
        moid => $self->get_moid($host, 'HostSystem'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(pgName => $portgroup);
    $w->end;

    $self->request(
        HostNetworkSystem => $network_system,
        RemovePortGroup => $spec,
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 change_esxi_settings

    $v->change_esxi_settings($host, %settings)

Updates advanced settings of the host.

Required parameters:

=over

=item $host

Host name

=item %settings

Pairs with key and value of settings.

=back

=cut

sub change_esxi_settings {
    my $self = shift;
    my $host = shift;
    my %settings = @_;

    my $option_manager = $self->get_property('configManager.advancedOption',
        of   => 'HostSystem',
        moid => $self->get_moid($host, 'HostSystem'),
    );

    my $supported = $self->get_property('supportedOption',
        of        => 'OptionManager',
        moid      => $option_manager,
        keep_type => 1,
        key_attr  => { OptionDef => 'key' },
    );
    $supported = $supported->{OptionDef};
    my %types;
    for (keys %settings) {
        croak "'$_' is unknown option" if not exists $supported->{$_};
        $types{$_} = $supported->{$_}{optionType}{'xsi:type'};
        $types{$_} =~ s/option//i;
    }

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    foreach my $key (keys %settings) {
        $w->startTag('changedValue');
        $w->dataElement(key => $key);
        $w->dataElement(value => $settings{$key}, 'xsi:type' => $types{$key});
        $w->endTag('changedValue');
    }
    $w->end;

    $self->request(
        OptionManager => $option_manager,
        UpdateOptions => $spec,
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 create_datacenter

    $v->create_datacenter($name)

Creates a new datacenter with the given name and returns its MOID.

=cut

sub create_datacenter {
    my ($self, $name) = @_;
    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(name => uri_escape($name));
    $w->end;

    my $response = $self->request(
        Folder => $self->{service}{rootFolder},
        CreateDatacenter => $spec,
    );
    croak "Wrong response from the server: $response"
        if $response !~ /<returnval type="Datacenter">([^<]+)<\/returnval>/;
    return $1;
}
#-------------------------------------------------------------------------------

=head2 create_cluster

    $v->create_cluster($cluster_name, %parameters)

Creates a new cluster returns its MOID.

Required parameters:

=over

=item datacenter =E<gt> $datacenter

Name of the target datacenter.

=back

Optional parameters:

=over

=item ha =E<gt> $boolean

Flag to indicate whether or not vSphere HA feature is enabled.

=item ha_vm_monitoring =E<gt> $ha_vm_monitoring

Level of HA Virtual Machine Health Monitoring Service. You can monitor both
guest and application heartbeats, guest heartbeats only, or you can disable
the service. Available values: C<vmAndAppMonitoring>, C<vmMonitoringOnly>,
C<vmMonitoringDisabled> (default).

=item ha_host_monitoring =E<gt> $boolean

Determines whether HA restarts virtual machines after a host fails.
The default value is true.

=item drs =E<gt> $boolean

Flag indicating whether or not the DRS service is enabled.

=item drs_default =E<gt> $drs_default

Specifies the cluster-wide default DRS behavior for virtual machines.
Available values: C<fullyAutomated> (default), C<manual>, C<partiallyAutomated>.

=item drs_rate =E<gt> $drs_rate

Threshold for generated ClusterRecommendations. DRS generates only those
recommendations that are above the specified vmotionRate. Ratings vary from 1
to 5 (3 by default). This setting applies to manual, partiallyAutomated, and
fullyAutomated DRS clusters.

=item dpm =E<gt> $boolean

Flag indicating whether or not the DPM service is enabled. This service can
not be enabled, unless DRS is enabled as well.

=item dpm_rate =E<gt> $dpm_rate

DPM generates only those recommendations that are above the specified rating.
Ratings vary from 1 to 5 (3 by default). This setting applies to both manual
and automated DPM clusters.

=back

=cut

sub create_cluster {
    my $self = shift;
    my $cluster_name = shift;
    my %args = (
        datacenter         => undef,
        ha                 => 0,
        ha_vm_monitoring   => 'vmMonitoringDisabled',
        ha_host_monitoring => 1,
        drs                => 0,
        drs_default        => 'fullyAutomated',
        drs_rate           => 3,
        dpm                => 0,
        dpm_rate           => 3,
        @_,
    );
    croak "Cluster name isn't defined" if not defined $cluster_name;
    for (qw{ datacenter }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    my $datacenter = $self->get_property('hostFolder',
        of   => 'Datacenter',
        moid => $self->get_moid($args{datacenter}, 'Datacenter'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(name => $cluster_name);
    $w->startTag('spec');
    $w->dataElement(vmSwapPlacement => 'vmDirectory');
    $w->startTag('dasConfig');
    $w->dataElement(enabled => $args{ha} ? 'true' : 'false');
    $w->dataElement(vmMonitoring => $args{ha_vm_monitoring});
    $w->dataElement(
        hostMonitoring => $args{ha_host_monitoring} ? 'enabled' : 'disabled'
    );
    $w->startTag(
        'admissionControlPolicy',
        'xsi:type' => 'ClusterFailoverLevelAdmissionControlPolicy'
    );
    $w->dataElement(failoverLevel => 1);
    $w->endTag('admissionControlPolicy');
    $w->dataElement(admissionControlEnabled => 'true');
    $w->startTag('defaultVmSettings');
    $w->dataElement(restartPriority => 'medium');
    $w->dataElement(isolationResponse => 'none');
    $w->startTag('vmToolsMonitoringSettings');
    $w->dataElement(enabled => 'true');
    $w->dataElement(failureInterval => 30);
    $w->dataElement(minUpTime => 120);
    $w->dataElement(maxFailures => 3);
    $w->dataElement(maxFailureWindow => 3600);
    $w->endTag('vmToolsMonitoringSettings');
    $w->endTag('defaultVmSettings');
    $w->endTag('dasConfig');
    $w->startTag('drsConfig');
    $w->dataElement(enabled => $args{drs} ? 'true' : 'false');
    $w->dataElement(defaultVmBehavior => $args{drs_default});
    $w->dataElement(vmotionRate => $args{drs_rate});
    $w->endTag('drsConfig');
    $w->startTag('dpmConfig');
    $w->dataElement(enabled => $args{dpm} ? 'true' : 'false');
    $w->dataElement(hostPowerActionRate => $args{dpm_rate});
    $w->endTag('dpmConfig');
    $w->endTag('spec');
    $w->end;

    my $response = $self->request(
        Folder => $datacenter,
        CreateClusterEx => $spec,
    );
    croak "Wrong response from the server: $response"
        if $response !~ /<returnval type="ClusterComputeResource">([^<]+)<\/returnval>/;
    return $1;
}
#-------------------------------------------------------------------------------

=head2 add_host

    $v->add_host(%parameters)

Adds a host to the cluster.

Required parameters:

=over

=item cluster =E<gt> $cluster_name

Name of the target cluster.

=item hostname =E<gt> $esxi_hostname

The DNS name or IP address of the host.

=item password =E<gt> $esxi_password

The password for the administration account.

=back

Optional parameters:

=over

=item port =E<gt> $port

The port number for the connection (443 by default).

=item username =E<gt> $username

The administration account on the host (root by default).

=back

=cut

sub add_host {
    my $self = shift;
    my %args = (
        cluster    => undef,
        hostname   => undef,
        port       => 443,
        username   => 'root',
        password   => undef,
        @_
    );
    for (qw{ cluster hostname password }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    my $host_cert = (get_https3($args{hostname}, $args{port}, '/'))[3]
        or croak "Can't get certificate from the host '$args{hostname}'";
    my $fingerprint = Net::SSLeay::X509_get_fingerprint($host_cert, "sha1");

    my $cluster = $self->get_moid($args{cluster}, 'ClusterComputeResource');

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->startTag('spec');
    $w->dataElement(hostName => $args{hostname});
    $w->dataElement(port => $args{port});
    $w->dataElement(sslThumbprint => $fingerprint);
    $w->dataElement(userName => $args{username});
    $w->dataElement(password => $args{password});
    $w->dataElement(force => 'true');
    $w->endTag('spec');
    $w->dataElement(asConnected => 'true');
    $w->end;
    return $self->run_task(
        ClusterComputeResource => $cluster,
        AddHost_Task => $spec,
    );
}
#-------------------------------------------------------------------------------

=head2 host_agent_vm_settings

    $v->host_agent_vm_settings($host, $datastore, $network)

Updates the host's ESX agent configuration.

=cut

sub host_agent_vm_settings {
    my ($self, $host, $datastore, $network) = @_;

    my $eam = $self->get_property('configManager.esxAgentHostManager',
        of   => 'HostSystem',
        moid => $self->get_moid($host, 'HostSystem'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->startTag('configInfo');
    $w->dataElement(
        agentVmDatastore => $self->get_moid($datastore, 'Datastore'),
        type => 'Datastore',
    );
    $w->dataElement(
        agentVmNetwork => $self->get_moid($network, 'Network'),
        type => 'Network',
    );
    $w->endTag('configInfo');
    $w->end;

    $self->request(
        HostEsxAgentHostManager => $eam,
        EsxAgentHostManagerUpdateConfig => $spec,
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 add_license

    $v->add_license($license_key)

Adds a license to the inventory of available licenses.

=cut

sub add_license {
    my ($self, $license) = @_;

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(licenseKey => $license);
    $w->end;
    my $response = $self->request(
        LicenseManager => $self->{service}{licenseManager},
        AddLicense => $spec,
    );
    my $xml = XMLin(
        $response,
        ForceArray => [qw{ labels properties }],
    );
    return $xml->{'soapenv:Body'}{AddLicenseResponse}{returnval};
}
#-------------------------------------------------------------------------------

=head2 assign_license

    $v->assign_license($entity, $license_key)

Update the license associated with an entity.

=cut

sub assign_license {
    my ($self, $entity, $license) = @_;

    my $lam = $self->get_property('licenseAssignmentManager',
        of => 'LicenseManager',
        moid => $self->{service}{licenseManager},
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(entity => $entity);
    $w->dataElement(licenseKey => $license);
    $w->end;
    my $response = $self->request(
        LicenseAssignmentManager => $lam,
        UpdateAssignedLicense => $spec,
    );
    my $xml = XMLin(
        $response,
        ForceArray => [qw{ labels properties }],
    );
    return $xml->{'soapenv:Body'}{UpdateAssignedLicenseResponse}{returnval};
}
#-------------------------------------------------------------------------------

=head2 assign_license_to_vc

    $v->assign_license_to_vc($license_key)

Update the license associated with the current vCenter.

=cut

sub assign_license_to_vc {
    my ($self, $license) = @_;
    return $self->assign_license(
        $self->{service}{about}{instanceUuid},
        $license,
    );
}
#-------------------------------------------------------------------------------

=head2 assign_license_to_host

    $v->assign_license_to_host($host, $license_key)

Update the license associated with the current vCenter.

=cut

sub assign_license_to_host {
    my ($self, $host, $license) = @_;
    return $self->assign_license(
        $self->get_moid($host, 'HostSystem'),
        $license,
    );
}
#-------------------------------------------------------------------------------

=head2 set_host_service_policy

    $v->set_host_service_policy($host, $service, $policy)

Updates the activation policy of the service.
Allowed values for the policy:

=over

=item automatic

Service should run if and only if it has open firewall ports. 

=item off

Service should not be started when the host starts up. 

=item on

Service should be started when the host starts up. 

=back

=cut

sub set_host_service_policy {
    my ($self, $host, $service, $policy) = @_;

    my $hss = $self->get_property('configManager.serviceSystem',
        of   => 'HostSystem',
        moid => $self->get_moid($host, 'HostSystem'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(id => $service);
    $w->dataElement(policy => $policy);
    $w->end;
    $self->request(
        HostServiceSystem   => $hss,
        UpdateServicePolicy => $spec,
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 enable_ruleset

    $v->enable_ruleset($host, $ruleset)

Opens the firewall ports belonging to the specified ruleset. If the ruleset has
a managed service with a policy of 'auto' that is not running, starts the
service.

=cut

sub enable_ruleset {
    my ($self, $host, $ruleset) = @_;

    my $hfs = $self->get_property('configManager.firewallSystem',
        of   => 'HostSystem',
        moid => $self->get_moid($host, 'HostSystem'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(id => $ruleset);
    $w->end;
    $self->request(
        HostFirewallSystem  => $hfs,
        EnableRuleset => $spec,
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 disable_ruleset

    $v->disable_ruleset($host, $ruleset)

Opens the firewall ports belonging to the specified ruleset. If the ruleset has
a managed service with a policy of 'auto' that is not running, starts the
service.

=cut

sub disable_ruleset {
    my ($self, $host, $ruleset) = @_;

    my $hfs = $self->get_property('configManager.firewallSystem',
        of   => 'HostSystem',
        moid => $self->get_moid($host, 'HostSystem'),
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(id => $ruleset);
    $w->end;
    $self->request(
        HostFirewallSystem  => $hfs,
        DisableRuleset => $spec,
    );
    return 1;
}
#-------------------------------------------------------------------------------

=head2 get_parent

    $v->get_parent($parent_type, of => $type, moid => $moid)

Returns a parent object with specified type of the managed object.

=cut

sub get_parent {
    my $self = shift;
    my $parent_type = shift or croak "Parent type isn't defined";
    my %args = (
        of   => 'VirtualMachine',
        moid => undef,
        @_,
    );
    my $type = $args{of} or croak "Required parameter 'of' isn't defined";
    my $moid = $args{moid} or croak "Required parameter 'moid' isn't defined";

    while (1) {
        my $parent = $self->get_property('parent',
            of        => $type,
            moid      => $moid,
            keep_type => 1,
        );
        croak "Can't get parent of $type with moid $moid"
            unless defined ref $parent and ref $parent eq 'HASH';
        return VMware::vSphere::MOID->new($parent->{content})
            if $parent->{type} eq $parent_type;
        $moid = $parent->{content};
        $type = $parent->{type};
    }
}
#-------------------------------------------------------------------------------

1;

__END__

=head1 SEE ALSO

=over

=item L<VMware::vSphere>

Raw interface to VMware vSphere Web Services.

=item L<IO::Socket::SSL>

Look it for additional SSL options.

=item L<vsphere>

Command line interface for L<VMware::vSphere::Simple>.

=item L<https://www.vmware.com/support/developer/vc-sdk/index.html>

Official VMware vSphere Web Services SDK Documentation.

=back

=head1 AUTHOR

Mikhail Telnov E<lt>Mikhail.Telnov@gmail.comE<gt>

=head1 COPYRIGHT

This software is copyright (c) 2016 by Mikhail Telnov.

This library is free software; you may redistribute and/or modify it
under the same terms as Perl itself.

=cut

package VMware::vSphere::Simple;

use strict;
use warnings;

use Carp;
use XML::Writer;
use VMware::vSphere;

our $VERSION = '1.00';
our @ISA = qw{ VMware::vSphere };

sub list {
    my ($self, $type) = @_;
    $type ||= 'VirtualMachine';
    my $p = $self->get_properties(of => $type, properties => ['name']);
    my @list = sort map { $p->{$_}{name} } keys %$p;
    return @list;
}

sub get_moid {
    my ($self, $name, $type) = @_;
    croak "Name of the managed object isn't defined" if not defined $name;
    $type ||= 'VirtualMachine';

    my $p = $self->get_properties(
        of         => $type,
        where      => { name => $name },
        properties => [ 'name' ],
    );
    return (keys %$p)[0];
}

sub get_vm_path {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    return $self->get_property('config.files.vmPathName',
        where => { name => $vm_name },
    );
}

sub get_vm_powerstate {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    return $self->get_property('runtime.powerState',
        where => { name => $vm_name },
    );
}

sub tools_is_running {
    my ($self, $vm_name) = @_;
    croak "VM name isn't defined" if not defined $vm_name;

    return $self->get_property('guest.toolsRunningStatus',
        where => { name => $vm_name },
    ) eq 'guestToolsRunning';
}

sub get_datastore_url {
    my ($self, $name) = @_;
    croak "Datastore name isn't defined" if not defined $name;

    return $self->get_property('info.url',
        of    => 'Datastore',
        where => { 'info.name' => $name },
    );
}

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

sub create_disk {
    my $self = shift;
    my $vm_name = shift;
    my %args = (
        size       => undef, # in KB
        thin       => 1,     # enable Thin Provisioning
        controller => 1000,  # controller ID
        unit       => 1,     # unit number
        @_,
    );
    croak "VM name isn't defined" if not defined $vm_name;
    for (qw{ size }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    print STDERR "Create virtual disk in VM '$vm_name' with size ".
                 "$args{size}KB\n" if $self->debug;

    my $w = XML::Writer->new(OUTPUT => \my $spec);
    $w->startTag('spec');
    $w->startTag('deviceChange');
    $w->dataElement(operation => 'add');
    $w->dataElement(fileOperation => 'create');
    $w->startTag('device', 'xsi:type' => 'VirtualDisk');
    $w->dataElement(key => '-100');
    $w->startTag(
        'backing', 'xsi:type' => 'VirtualDiskFlatVer2BackingInfo'
    );
    $w->dataElement(fileName => '');
    $w->dataElement(diskMode => 'persistent');
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
    $w->dataElement(controllerKey => $args{controller});
    $w->dataElement(unitNumber => $args{unit});
    $w->dataElement(capacityInKB => $args{size});
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

sub remove_disk {
    my ($self, $vm_name, $key) = @_;
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
    $w->dataElement(fileOperation => 'destroy');
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
        of    => 'HostSystem',
        where => { name => $args{host_name} },
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

sub find_files {
    my $self = shift;
    my %args = (
        datastore      => undef,    # name of the datastore
        pattern        => undef,    # pattern for filenames
        path           => undef,    # TODO
        case_sensitive => 0,        # TODO
        @_,
    );
    for (qw{ datastore pattern }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    my $datastore_path = "[$args{datastore}]";
    $datastore_path .= " $args{path}" if defined $args{path};

    # Get HostDatastoreBrowser
    my $browser = $self->get_property('browser',
        of => 'Datastore',
        where => { 'name' => $args{datastore} },
    );

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(datastorePath => $datastore_path);
    $w->startTag('searchSpec');
    $w->emptyTag('query', 'xsi:type' => 'FolderFileQuery');
    $w->emptyTag('query');
    $w->startTag('details');
    $w->dataElement($_ => 'false')
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
    my @pathes;
    push @pathes, $_->{folderPath}.$_->{file}{path}
        for @{$result->{HostDatastoreBrowserSearchResults}};
    return \@pathes;
}

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
    for (qw{ datacenter cluster host path }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
    }

    print STDERR "Register $args{path} as $vm_name at $args{host}\n"
        if $self->debug;

    my $datacenter = $self->get_property('vmFolder',
        of    => 'Datacenter',
        where => { name => $args{datacenter} },
    );

    # TODO allow to register outside a cluster
    my $cluster = $self->get_property('resourcePool',
        of    => 'ClusterComputeResource',
        where => { name => $args{cluster} },
    );

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

sub linked_clone {
    my ($self, $vm_name, $clone_name) = @_;

    print STDERR "Create linked clone with name '$clone_name' from VM $vm_name\n"
        if $self->debug;

    my $p = $self->get_properties(
        properties => [qw{
            parent parentVApp snapshot.currentSnapshot
        }],
        where => { name => $vm_name },
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

1;

__END__

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

This module inherits the constructor and methods from L<VMware::vSphere>.

=over

=item @mo_names = $v-E<gt>list()

=item @mo_names = $v-E<gt>list($type)

Returns a list with names of Managed Objects with specified C<$type>
('VirtualMachine' by default).

=item $moid = $v-E<gt>get_moid($name)

=item $moid = $v-E<gt>get_moid($mo_name, $mo_type)

Returns ID of the managed object by its name. C<$mo_type> is 'VirtualMachine' by
default.

=item $path = $v-E<gt>get_vm_path($vm_name)

Returns path to the VM configuration file.

=item $powerstate = $v-E<gt>get_vm_powerstate($vm_name)

Returns the string representation of VM powersate: poweredOff, poweredOn,
suspended.

=item $boolean = $v-E<gt>tools_is_running($vm_name)

Returns true if VMware Tools is running on the VM.

=item $datastore_url = $v-E<gt>get_datastore_url($datastore_name)

Returns unique locator for the datastore.

=item $v-E<gt>poweron_vm($vm_name)

Powers on the virtual machine. If the virtual machine is suspended, this method
resumes execution from the suspend point.

=item $v-E<gt>poweroff_vm($vm_name)

Powers off the virtual machine. If this virtual machine is a fault tolerant
primary virtual machine, this will result in the secondary virtual machine(s)
getting powered off as well.

=item $v-E<gt>shutdown_vm($vm_name)

Issues a command to the guest operating system asking it to perform a clean
shutdown of all services. Returns immediately and does not wait for the guest
operating system to complete the operation.

=item $v-E<gt>reboot_vm($vm_name)

Issues a command to the guest operating system asking it to perform a reboot.
Returns immediately and does not wait for the guest operating system to
complete the operation.

=item $v-E<gt>list_snapshots($vm_name)

Returns a plain list with snapshots of the virtual machine as a hash reference
with $snapshot_id =E<gt> $snapshot_name elements.

=item $v-E<gt>create_snapshot($vm_name, name =E<gt> $snapshot_name, %options)

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

=item $v-E<gt>revert_to_current_snapshot($vm_name)

Reverts the virtual machine to the current snapshot. If no snapshot exists, then
the operation does nothing, and the virtual machine state remains unchanged.

=item $v-E<gt>revert_to_snapshot($snapshot_id)

Reverts the virtual machine to the snapshot specified by ID.

=item $v-E<gt>remove_snapshot($snapshot_moid, %opts)

Removes this snapshot and deletes any associated storage.

Following options are available:

=over

=item removeChildren =E<gt> $boolean

Flag to specify removal of the entire snapshot subtree (enabled by default).

=item consolidate =E<gt> $boolean

If set to true, the virtual disk associated with this snapshot will be merged
with other disk if possible. Defaults to true.

=back

=item $v-E<gt>reconfigure_vm($vm_name, %options)

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

=item $v-E<gt>connect_cdrom($vm_name, $iso)

Mounts an ISO image to the virtual CD/DVD device.

=item $v-E<gt>disconnect_cdrom($vm_name)

Unmounts the virtual CD/DVD device.

=item $v-E<gt>connect_floppy($vm_name, $image)

Connects floppy image to the VM.

=item $v-E<gt>disconnect_floppy($vm_name)

Disconnects virtual floppy drive.

=item $v-E<gt>create_disk($vm_name, size =E<gt> $disk_size, %options)

Creates a new virtual disk in the virtual machine.

Required parameters:

=over

=item $vm_name

Name of the target virtual machine.

=item size =E<gt> $disk_size

Size of the disk in KB.

=back

Options:

=over

=item thin =E<gt> $boolean

Enables Thin Provisioning (enabled by default).

=item controller =E<gt> $controller_id

Controller ID (1000 by default).

=item unit =E<gt> $unit_number

Unit number (1 by default).

=back

=item $v-E<gt>remove_disk($vm_name, $key)

Removes a virtual disk from the virtual machine by its ID (C<$key>).

=item $v-E<gt>add_nas_storage(%parameters)

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

=item $v-E<gt>find_files(datastore =E<gt> $datastore, pattern =E<gt> $pattern, %options)

Searches files on the C<$datastore> by C<$pattern> and returns a reference to
the array with pathes.

The following options are available:

=over

=item path =E<gt> $path

Top level directory at the storage to start search (root of datastore by
default).

=item case_sensitive =E<gt> $boolean

This flag indicates whether or not to search using a case insensitive match on
type (disabled by default).

=back

=item $v-E<gt>register_vm($vm_name, %parameters)

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

=item $v-E<gt>mount_tools_installer($vm_name)

Mounts the VMware Tools CD installer as a CD-ROM for the guest operating system.

=item $v-E<gt>linked_clone($vm_name, $clone_name)

Creates a linked clone from the VM snapshot.

=back

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

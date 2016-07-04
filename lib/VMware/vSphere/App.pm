package VMware::vSphere::App;

our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Data::Dumper;
use File::Basename qw{ basename };
use List::Util qw{ first };
use Pod::Find qw{ pod_where };
use Pod::Usage;
use VMware::vSphere::Const;
use VMware::vSphere::Simple;
use VMware::vSphere;

sub new {
    my $class = shift;
    my %args = (
        stderr => \*STDERR,
        stdout => \*STDOUT,
        @_,
    );
    my $self = {
        stderr => $args{stderr},
        stdout => $args{stdout},
    };
    return bless $self, $class;
}

sub run {
    my $self = shift;

    return $self->show_usage() if not @_;
    my $first = shift;

    # Shell completion
    return $self->completion(@_) if $first eq 'comp';

    # Help
    return $self->help(@_) if $first eq 'help';

    # Create a VMware::vSphere::Simple object
    my $v = vsphere();

    if (not $v->can($first)) {
        print { $self->{stderr} } "Error: Method '$first' not found.\n";
        return $self->show_usage();
    }

    # Resolve complex arguments
    my @args;
    for (@_) {
        if (/^\{.*\}$/s or /^\[.*\]$/s) {
            no strict;
            no warnings;
            push @args, eval;
            use warnings;
            use strict;
            if ($@) {
                print { $self->{stderr} } "Error in argument '$_': $@\n";
                return;
            }
        } else {
            push @args, $_;
        }
    }

    # Invoke the method
    my @r = $v->$first(@args);
    if (defined first { ref } @r) {
        $Data::Dumper::Terse = 1;
        $Data::Dumper::Sortkeys = 1;
        print { $self->{stdout} } Dumper(\@r);
    } else {
        local $, = "\n";
        local $\ = "\n";
        print { $self->{stdout} } grep { defined } @r;
    }
    return 1;
}

sub completion {
    my $self = shift;
    my $i    = shift;

    my $cur = $_[$i];
    my $prev = $_[$i-1];
    my $m = $_[1];

    local $, = q{ };

    if ($i == 1) {
        print { $self->{stdout} } 'help', list_methods();
        return 1;
    }

    if ($i == 2 and $m eq 'help') {
        print { $self->{stdout} } list_methods();
        return 1;
    }

    if ($i == 2) {
        if ($m eq 'list') {
            print { $self->{stdout} } VMware::vSphere::Const::MO_TYPES;
            return 1;
        }

        if ($m eq 'get_moid' or $m eq 'delete') {
            my $type = defined $_[3] ? $_[3] : 'VirtualMachine';
            eval { print { $self->{stdout} } vsphere()->list($type); };
            return 1;
        }

        if ($m eq 'get_datastore_url') {
            eval { print { $self->{stdout} } vsphere()->list('Datastore'); };
            return 1;
        }

        if (defined first { $_ eq $m } qw{
            get_vm_path get_vm_powerstate tools_is_running poweron_vm
            poweroff_vm shutdown_vm reboot_vm list_snapshots create_snapshot
            revert_to_current_snapshot reconfigure_vm connect_cdrom
            disconnect_cdrom connect_floppy disconnect_floppy create_disk
            remove_disk mount_tools_installer linked_clone
            }
        ) {
            eval { print { $self->{stdout} } vsphere()->list; };
            return 1;
        }

    }

    if ($i == 3) {
        if ($m eq 'get_moid' or $m eq 'delete') {
            print { $self->{stdout} } VMware::vSphere::Const::MO_TYPES;
            return 1;
        }
    }

    return 1 if $i == 2 and $m eq 'remove_snapshot';

    if ($m eq 'add_nas_storage') {
        if ($prev eq 'access_mode') {
            print { $self->{stdout} } qw{ readWrite readOnly };
            return 1;
        }
        if ($prev eq 'type') {
            print { $self->{stdout} } qw{ NFS NFS41 CIFS };
            return 1;
        }
    }

    if ($m eq 'find_files') {
        if ($prev eq 'datastore') {
            eval { print { $self->{stdout} } vsphere()->list('Datastore'); };
            return 1;
        }
    }

    if ($m eq 'register_vm') {
        if ($prev eq 'datacenter') {
            eval { print { $self->{stdout} } vsphere()->list('Datacenter'); };
            return 1;
        }
        if ($prev eq 'cluster') {
            eval {
                print { $self->{stdout} }
                    vsphere()->list('ClusterComputeResource');
            };
            return 1;
        }
        if ($prev eq 'host') {
            eval { print { $self->{stdout} } vsphere()->list('HostSystem'); };
            return 1;
        }
    }

    my %proto = (
        create_snapshot => [qw{ name description memory quiesce }],
        remove_snapshot => [qw{ removeChildren consolidate }],
        create_disk => [qw{ size thin controller unit }],
        add_nas_storage => [qw{
            host_name remote_host remote_path local_path type access_mode
        }],
        find_files => [qw{ datastore pattern path case_sensitive }],
        register_vm => [qw{ datacenter cluster host path as_template }],
    );
    if (exists $proto{$m}) {
        print { $self->{stdout} } @{$proto{$m}}
            unless defined first { $prev eq $_ } @{$proto{$m}};
        return 1;
    }
}

sub help {
    my ($self, $method) = @_;
    return $self->show_usage() unless $method;

    my $module = list_methods($method);
    if (not $module) {
        print { $self->{stderr} } "Error: Method '$method' not found.\n";
        return $self->show_usage();
    }

    pod2usage(
        -verbose  => 99,
        -sections => ["METHODS/$method"],
        -input    => pod_where( { -inc => 1 }, $module ),
        -output   => $self->{stdout},
        -exitval  => 'NOEXIT',
    );
    return 1;
}

sub show_usage {
    my $self = shift;
    print { $self->{stderr} }
        "vsphere - CLI for VMware::vSphere::Simple perl module\n",
        "VMware::vSphere version is ", $VMware::vSphere::VERSION,
        "\n\nUsage: ", basename($0),
        " <METHOD> [[PARAMETER1] [PARAMETER2]...]\n\n",
        "Available methods:\n";
    print { $self->{stderr} } "$_\n" for list_methods();
    print { $self->{stderr} }
        "\nRun '", basename($0), " help <METHOD>' to see a method ",
        "description\nor open full documentation in perldoc ",
        "VMware::vSphere::Simple\n";
    return;
}

sub vsphere {
    for (qw{ VSPHERE_HOST VSPHERE_USER VSPHERE_PASS }) {
        croak "Error: Required environment variable '$_' isn't defined"
            if not defined $ENV{$_};
    }

    return VMware::vSphere::Simple->new(
        host => $ENV{VSPHERE_HOST},
        username => $ENV{VSPHERE_USER},
        password => $ENV{VSPHERE_PASS},
        debug => $ENV{VSPHERE_DEBUG},
    );
}

sub list_methods {
    my $method = shift;
    my %methods;
    no strict 'refs';
    for my $m (qw{ VMware::vSphere:: VMware::vSphere::Simple:: }) {
        for (keys %{$m}) {
            next unless defined &{"${m}$_"};
            if ($method and $method eq $_) {
                my $module = $m;
                $module =~ s/::$//;
                return $module;
            }
            next unless /^[a-z][a-z_]+/;
            next if /^(?:carp|croak|confess|new|debug)$/;

            $methods{$_} = 1;
        }
    }
    use strict 'refs';
    return sort keys %methods;
}

1;

__END__

=head1 NAME

VMware::vSphere::App - Command Line Interface for VMware::vSphere::Simple

=head1 SYNOPSIS

    use VMware::vSphere::App;
    my $app = VMware::vSphere::App->new(stdout => $fh_out, stderr => $fh_err);
    my $ret = $app->run(@ARGV);

=head1 DESCRIPTION

VMware::vSphere::App is the backbone implementation of L<vsphere> CLI utility.

=head1 ENVIRONMENT VARIABLES

=over

=item VSPHERE_HOST

Hostname or IP address of the VMware vSphere Web Service (vCenter or ESXi).

=item VSPHERE_USER

Username for login to the VMware vSphere Web Service.

=item VSPHERE_PASS

Password for login to the VMware vSphere Web Service.

=item VSPHERE_DEBUG

Enable verbose output for debugging.

=back

=head1 SEE ALSO

=over

=item L<vsphere>

Command line interface for L<VMware::vSphere::Simple>.

=item L<VMware::vSphere>

Raw interface to VMware vSphere Web Services.

=item L<VMware::vSphere::Simple>

Simplifies common vSphere methods and makes it more perlish.

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

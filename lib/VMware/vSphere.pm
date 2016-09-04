package VMware::vSphere;

our $VERSION = '1.01';

use strict;
use warnings;

use Carp;
use Data::Dumper;
use HTTP::Cookies;
use HTTP::Request::Common;
use IO::Socket::SSL;
use LWP::UserAgent;
use LWP::Protocol::https;
use XML::Simple;
use XML::Writer;

sub new {
    my $class = shift;
    my %args = (
        host       => undef,
        username   => undef,
        password   => undef,
        debug      => 0,
        ssl_opts   => undef,
        @_
    );
    my $self = {};
    for (qw{ host username password }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
        $self->{$_} = $args{$_};
    }
    # Enable debug messages
    $self->{debug} = $args{debug} || 0;

    # Prepare UserAgent
    my $cookies = HTTP::Cookies->new();
    my $ssl_opts = {};
    if (defined $args{ssl_opts}) {
        $ssl_opts = $args{ssl_opts};
    } else {
        $ssl_opts->{verify_hostname} = 0;
        $ssl_opts->{SSL_verify_mode} = SSL_VERIFY_NONE;
    }
    $self->{ua} = LWP::UserAgent->new(
        ssl_opts => $ssl_opts,
        cookie_jar => $cookies,
    ) or croak "Can't initialize LWP::UserAgent";

    if ($self->{debug}) {
        $self->{ua}->add_handler("request_send", sub {
            printf "\n%s\n%s\n%s\n", '='x80, shift->as_string, '='x80;
            return;
        });
        $self->{ua}->add_handler("response_done", sub {
            printf "\n%s\n%s\n%s\n", '='x80, shift->as_string, '='x80;
            return;
        });
    }

    bless $self, $class;
    $self->refresh_service;
    $self->login;
    return $self;
}

sub request {
    my ($self, $type, $id, $method, $spec, $do_not_try_login) = @_;
    $spec //= '';
    croak "Missed object type" if not defined $type;
    croak "Missed object id" if not defined $id;
    croak "Missed method name" if not defined $method;

    my $request = <<"EOF";
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:xsd="http://www.w3.org/2001/XMLSchema"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <soap:Body>
        <$method xmlns="urn:internalvim25">
            <_this type="$type">$id</_this>
            $spec
        </$method>
    </soap:Body>
</soap:Envelope>
EOF
    my $response = $self->{ua}->request(
        POST "https://$self->{host}/sdk/vimService",
        'Content-Type' => "text/xml; charset=utf-8",
        SOAPAction => "urn:vim25/5.0",
        content => $request,
    );
    croak "Invalid response from LWP" if not defined $response;

    return $response->content if $response->code eq '200';

    croak "Host returned an error: ".$response->status_line
        if not defined $response->content or $response->content !~ /<[?]xml/;

    my $xml = XMLin($response->content);

    if (
        $xml->{'soapenv:Body'}{'soapenv:Fault'}{detail}{NotAuthenticatedFault}
    ) {
        if ($do_not_try_login) {
            return if $do_not_try_login == 2;
        } else {
            $self->login;
            return $self->request($type, $id, $method, $spec, 1);
        }
    }

    my $faultstring = $xml->{'soapenv:Body'}{'soapenv:Fault'}{faultstring};
    croak "Request failed: $faultstring"
        if defined $faultstring and not ref $faultstring;
    croak "Host returned an error: $1"
        if $response->content =~ /<soapenv:Fault>(.*)<\/soapenv:Fault>/is;
    croak "Host returned an error: ".$response->content;
}

sub get_object_set {
    my $self = shift;
    my %args = (
        select_sets => undef,
        root        => $self->{service}{rootFolder},
        root_type   => 'Folder',
        @_
    );
    croak "Required parameter 'select_sets' isn't defined"
        if not defined $args{select_sets};

    my $w = XML::Writer->new(OUTPUT => \my $result, UNSAFE => 1);
    $w->dataElement(obj => $args{root}, type => $args{root_type});

    foreach my $ss (@{$args{select_sets}}) {
        carp "Specified select set isn't a hash reference"
            if not ref $ss or ref $ss ne 'HASH';
        foreach (qw{name path}) {
            carp "Missed required element $_ in select set"
                if not defined $ss->{$_};
        }
        my $type = defined $ss->{type} ? $ss->{type} : 'Folder';
        my $skip = $ss->{skip} ? 1 : 0;

        $w->startTag('selectSet', 'xsi:type' => 'TraversalSpec');
        $w->dataElement(name => $ss->{name});
        $w->dataElement(type => $type);
        $w->dataElement(path => $ss->{path});
        $w->dataElement(skip => $skip);

        if (ref $ss->{select_sets} and ref $ss->{select_sets} eq 'ARRAY') {
            foreach (@{$ss->{select_sets}}) {
                $w->startTag('selectSet');
                $w->dataElement(name => $_);
                $w->endTag('selectSet');
            }
        }

        $w->endTag('selectSet');
        $w->end;
    }
    return $result;
}

sub get_properties {
    my $self = shift;
    my %args = (
        of          => 'VirtualMachine',
        moid        => undef,
        where       => undef,
        object_set  => undef,
        properties  => undef,
        max_objects => undef,
        xml_params  => undef,
        @_
    );

    my $object_set = $args{moid} ? "<obj type=\"$args{of}\">$args{moid}</obj>":
                                   $args{object_set};
    if (not defined $object_set) {
        if ($args{of} eq 'VirtualMachine') {
            $object_set = $self->_get_object_set_for_vm;
        } elsif ($args{of} eq 'VirtualApp') {
            $object_set = $self->_get_object_set_for_vm;
        } elsif ($args{of} eq 'HostSystem') {
            $object_set = $self->_get_object_set_for_host;
        } elsif ($args{of} eq 'Datastore') {
            $object_set = $self->_get_object_set_for_datastore;
        } elsif ($args{of} eq 'ClusterComputeResource') {
            $object_set = $self->_get_object_set_for_cluster;
        } elsif ($args{of} eq 'Datacenter') {
            $object_set = $self->_get_object_set_for_datacenter;
        } elsif ($args{of} eq 'Network') {
            $object_set = $self->_get_object_set_for_network;
        } else {
            croak "Parameter 'object_set' should be set for this type";
        }
    }

    my %properties;
    if ($args{properties}) {
        @properties{@{$args{properties}}} = 1;
    }
    if ($args{where}) {
        @properties{keys %{$args{where}}} = 1;
    }

    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->startTag('specSet');
    $w->startTag('propSet');
    $w->dataElement(type => $args{of});
    if ($args{properties}) {
        $w->dataElement(all => 0);
        $w->dataElement(pathSet => $_) for sort keys %properties;
    } else {
        $w->dataElement(all => 1);
    }
    $w->endTag('propSet');
    $w->startTag('objectSet');
    $w->raw($object_set);
    $w->endTag('objectSet');
    $w->endTag('specSet');
    $w->startTag('options');
    $w->dataElement(maxObjects => $args{max_objects})
        if defined $args{max_objects};
    $w->endTag('options');
    $w->end;

    my $response = $self->request(
        PropertyCollector => $self->{service}{propertyCollector},
        RetrievePropertiesEx => $spec,
    );
    my %result;

    my @add_xml_params = $args{xml_params} ? @{$args{xml_params}} : ();
    my %xml_params = (
            ForceArray => [
                'objects', 'propSet', 'childSnapshotList',
                'HostDatastoreBrowserSearchResults'
            ],
            KeyAttr => {
                childSnapshotList => 'snapshot',
                propSet => 'name',
            },
            @add_xml_params,
    );
    while (1) {
        # Strip root tags
        $response =~ s/.*<soapenv:Body>\s*<\w+Response[^>]*>\s*//s;
        $response =~ s{\s*</\w+Response>\s*</soapenv:Body>.*}{}s;
        # Strip type attributes from tags
        $response =~ s/<(\w+)(?: (?:\w+\:)?type="[^"]+")+>/<$1>/gs;
        if ($response eq '') {
            print STDERR "Empty response\n" if $self->debug;
            last;
        }
        my $xml = XMLin($response, %xml_params);
        print Data::Dumper->Dump([$xml], ['xml']) if $self->debug;
        my $o = $xml->{objects};
        croak "Invalid response: $response"
            if not defined $o or not ref $o or ref $o ne 'ARRAY';
        my %r = map { $_->{obj} => $_->{propSet} } @$o;
        foreach my $obj (keys %r) {
            $result{$obj}{$_} = $r{$obj}{$_}{val} for keys %{$r{$obj}};
        }

        my $token = $xml->{token} // last;

        $response = $self->request(
            PropertyCollector => $self->{service}{propertyCollector},
            ContinueRetrievePropertiesEx => "<token>$token</token>",
        );
    };
    print Dumper(\%result) if $self->debug;

    if ($args{where}) {
        foreach my $moid (keys %result) {
            foreach my $property (keys %{$args{where}}) {
                if ($result{$moid}{$property} ne $args{where}{$property}) {
                    delete $result{$moid};
                    last;
                }
            }
        }
    }

    croak "Can't find a managed object" unless %result;
    return \%result;
}

sub get_property {
    my $self = shift;
    my $property = shift;
    my %args = (
        @_,
        properties => [ $property ],
    );

    my $objects = $self->get_properties(%args);
    return $objects->{(sort keys %{$objects})[0]}{$property};
}

sub run_task {
    my $self = shift;
    my ($obj_type, $moid, $task, $spec) = @_;

    my $response = $self->request($obj_type, $moid, $task, $spec);
    croak "Wrong response from the server: $response"
        if $response !~ m{<returnval\ type="Task">([^<]+)</returnval>};
    return $self->wait_for_task($1);
}

sub wait_for_task {
    my ($self, $task_id, $timeout) = @_;
    $timeout ||= 600;

    print STDERR "Waiting a task $task_id for $timeout seconds at $self->{host}\n"
        if $self->debug;

    my $start = time;
    while (time - $start < $timeout) {
        my $p = $self->get_properties(of => 'Task', moid => $task_id);
        my $state = lc $p->{$task_id}{info}{state};
        if ($state eq "queued" or $state eq "running") {
            sleep 1;
            next;
        }
        return $p->{$task_id}{info}{result} if $state eq "success";
        if ($state eq "error") {
            croak "Task completed with an error: $p->{localizedMessage}"
                if defined $p->{localizedMessage};
            croak "Task completed with an error: ".
                  $p->{$task_id}{info}{error}{localizedMessage}
                if defined $p->{$task_id}{info}{error}{localizedMessage};
            croak "Task completed with an error: ".Dumper($p);
        }
        croak "Returned invalid state for task '$task_id': ".$state;
    }
    croak "Task $task_id isn't finished in $timeout seconds";
}

sub refresh_service {
    my $self = shift;

    my $response = $self->request(
        ServiceInstance => 'ServiceInstance',
        'RetrieveServiceContent' => undef,
        1
    );
    # Strip type attributes from tags
    $response =~ s/<(\w+) (?:\w+\:)?type="[^"]+">/<$1>/gs;
    my $xml = XMLin($response);
    for (keys %$xml) {
        if (/body/si) {
            $xml = $xml->{$_}{RetrieveServiceContentResponse}{returnval};
            last;
        }
    }
    $self->{service} = $xml;
    return $self->{service};
}

sub login {
    my $self = shift;
    my $w = XML::Writer->new(OUTPUT => \my $spec, UNSAFE => 1);
    $w->dataElement(userName => $self->{username});
    $w->dataElement(password => $self->{password});
    $w->end;
    $self->{UserSession} = $self->request(
        SessionManager => $self->{service}{sessionManager},
        Login          => $spec,
        1
    );
    return $self->{UserSession};
}

sub debug {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{debug} = $value ? 1 : 0;
        return $self;
    }
    return $self->{debug};
}


sub DESTROY {
    my $self = shift;
    if (defined $self and defined $self->{UserSession}) {
        $self->request(
            SessionManager => $self->{service}{sessionManager},
            Logout         => undef,
            2
        );
    }
    return 1;
}

############################ PRIVATE METHODS ###################################

sub _get_object_set_for_vm {
    my $self = shift;
    return $self->get_object_set(
        select_sets => [
            {
                name => 'folders',
                path => 'childEntity',
                select_sets => [ 'folders', 'datacenter', 'vapp' ],
            },
            {
                name => 'datacenter',
                type => 'Datacenter',
                path => 'vmFolder',
                select_sets => [ 'folders', 'vapp' ],
            },
            {
                name => 'vapp',
                type => 'VirtualApp',
                path => 'vm',
            }
        ]);
}

sub _get_object_set_for_host {
    my $self = shift;
    return $self->get_object_set(
        select_sets => [
            {
                name => 'folders',
                path => 'childEntity',
                select_sets => [
                    'folders', 'datacenter', 'clusters', 'compres'
                ],
            },
            {
                name => 'datacenter',
                type => 'Datacenter',
                path => 'hostFolder',
                select_sets => [ 'folders' ],
            },
            {
                name => 'clusters',
                type => 'ClusterComputeResource',
                path => 'host',
            },
            {
                name => 'compres',
                type => 'ComputeResource',
                path => 'host',
            }
        ]);
}

sub _get_object_set_for_datastore {
    my $self = shift;
    return $self->get_object_set(
        select_sets => [
            {
                name => 'folders',
                path => 'childEntity',
                select_sets => [ 'folders', 'datacenter' ],
            },
            {
                name => 'datacenter',
                type => 'Datacenter',
                path => 'datastore',
            }
        ]);
}

sub _get_object_set_for_cluster {
    my $self = shift;
    return $self->get_object_set(
        select_sets => [
            {
                name => 'folders',
                path => 'childEntity',
                select_sets => [ 'folders', 'datacenter' ],
            },
            {
                name => 'datacenter',
                type => 'Datacenter',
                path => 'hostFolder',
                select_sets => [ 'folders' ],
            },
        ]);
}

sub _get_object_set_for_datacenter {
    my $self = shift;
    return $self->get_object_set(
        select_sets => [
            {
                name => 'folders',
                path => 'childEntity',
                select_sets => [ 'folders' ],
            },
        ]);
}

sub _get_object_set_for_network {
    my $self = shift;
    return $self->get_object_set(
        select_sets => [
            {
                name => 'folders',
                path => 'childEntity',
                select_sets => [ 'folders', 'datacenter' ],
            },
            {
                name => 'datacenter',
                type => 'Datacenter',
                path => 'network',
            },
        ]);
}

1;

__END__

=head1 NAME

VMware::vSphere - Raw interface for VMware vSphere Web Services

=head1 SYNOPSIS

    my $v = VMware::vSphere->new(
        host => $vcenter_host,
        username => $vcenter_username,
        password => $vcenter_password,
    );

    my $vm_path = $v->get_property(
        'config.files.vmPathName',
        where => { name => $name },
    );

=head1 DESCRIPTION

This module provides an interface to VMware vSphere Web Services (management
interface for VMware vCenter and VMware ESXi products). To use this module you
should be familiar with vSphere API 
(L<https://www.vmware.com/support/developer/vc-sdk/index.html>).
If not it's better to use L<VMware::vSphere::Simple> module.

It is not a full-featured replacement for VMware vSphere Perl SDK but this
module has following advantages:

=over

=item *

It's a pure perl module (VMware SDK has binaries and python (OMG!) in the
latest distributive).

=item *

It has minumal dependencies on non-core modules. Actually it needs L<LWP>,
L<IO::Socket::SSL>, L<XML::Simple> and L<XML::Writer> modules only.

=item *

High performance: it requests only what's actually needed.

=back

=head1 METHODS

=head2 new

    $v = VMware::vSphere->new(%args)

The constructor initiates connection with specified host and returns a
VMware::vSphere object. Connection will be logged out during object's
destruction.

The following arguments are required:

=over

=item host =E<gt> $host

Hostname or IP-address of the VMware vSphere host (ESXi or vCenter).

=item username =E<gt> $username

Login for the vSphere host.

=item password =E<gt> $password

Password for this login.

=back

The following arguments are optional:

=over

=item debug =E<gt> $boolean

Debug information will be printed to the C<STDERR> if this parameter is true.

=item ssl_opts =E<gt> \%ssl_opts

Pass additional SSL options to the L<IO::Socket::SSL> used for connection.
By default it disables any certificate checks:

{ verify_hostname =E<gt> 0, SSL_verify_mode =E<gt>SSL_VERIFY_NONE }

=back

=head2 request

    $response = $v->request($mo_type => $moid, $method)
    $response = $v->request(
        $mo_type => $moid,
        $method => $spec,
        $do_not_try_login,
    )

Calls specified method of the managed object. If C<$do_not_try_login> is true
it doesn't try to relogin on NotAuthenticatedFault. Also if C<$do_not_try_login>
is set to 2 it will not die on any error.

=head2 get_object_set

    $object_set = $v->get_object_set(select_sets => \@select_sets)
    $object_set = $v->get_object_set(
        select_sets => \@select_sets,
        root => $root,
        root_type => $root_type,
    )

Creates objectSet XML for C<get_properties> and C<get_property>.

=head2 get_properties

    $all_vm_properties = $v->get_properties
    $properties = $v->get_properties(%parameters)

Returns a hash reference ($moid =E<gt> \%properties) with all or specified
properties of managed objects.

The following optional parameters are available:

=over

=item of =E<gt> $mo_type

Managed object type. C<VirtualMachine> by default.

=item moid =E<gt> $moid

Retrieves properties for the managed object specified by its ID.

=item where =E<gt> { prop1 =E<gt> $value1, prop2 =E<gt> $value2, ... }

Reference to a hash with properties to filter objects.

=item object_set =E<gt> \@object_set

Set of specifications that determine the objects to filter. If this option
isn't defined it sets to default based on object type (C<of>).

=item properties =E<gt> \@properties

Array reference with properties names. If omitted it requests all properties.

=item max_objects =E<gt> $max_objects

How many objects retrieve per single request. It doesn't affect the method
result but allows to tune the network performance.
The maximum number of ObjectContent data objects that should be returned in a
single result from RetrievePropertiesEx. An unset value indicates that there
is no maximum. In this case PropertyCollector policy may still limit the number
of objects. Any remaining objects may be retrieved with
ContinueRetrievePropertiesEx. A positive value causes RetrievePropertiesEx to
suspend the retrieval when the count of objects reaches the specified maximum.
PropertyCollector policy may still limit the count to something less than
maxObjects. Any remaining objects may be retrieved with
ContinueRetrievePropertiesEx. A value less than or equal to 0 is illegal.

=item xml_params =E<gt> \%xml_params

Additional options for output XML parser (see L<XML::Simple/OPTIONS>).

=back

=head2 get_property

    $property = $v->get_property($property_name)
    $property = $v->get_property($property_name, %parameters)

Returns a value for the specified property of a single managed object.
Optional parameters are identical to C<get_properties> excepts
C<properties>.

=head2 run_task

    $result = $v->run_task($mo_type =E<gt> $moid, $task =E<gt> $spec);

Starts the task and waits until it's finished. On success it returns info.result
propety of the task.

=head2 wait_for_task

    $result = $v->wait_for_task($task_id)
    $result = $v->wait_for_task($task_id, $timeout)

Waits until the task is finished or dies after timeout (in seconds). Timeout is
10 minutes by default.

=head2 refresh_service

    $service_instance = $v->refresh_service

Retrieves the properties of the service instance.

=head2 login

    $v->login

Log on to the server. Ordinally you shouldn't call it: it called by the
constructor and if connection is lost during a C<request>. This method fails if
the user name and password are incorrect, or if the user is valid but has no
permissions granted.

=head2 debug

    $boolean = $v->debug
    $v->debug($boolean)

If enabled the module prints additional debug information to the C<STDERR>.

=head1 SEE ALSO

=over

=item L<VMware::vSphere::Simple>

Simplifies common vSphere methods and makes it more perlish.

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

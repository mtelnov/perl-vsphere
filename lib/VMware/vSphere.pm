package VMware::vSphere;

our $VERSION = '1.02';

use 5.012;
use warnings;

use Carp;
use Data::Dumper;
use WWW::Curl::Easy;
use XML::Simple;
use XML::Writer;

sub new {
    my $class = shift;
    my %args = (
        host           => undef,
        username       => undef,
        password       => undef,
        debug          => undef,
        ssl_verifyhost => 0,
        ssl_verifypeer => 0,
        cookies_file   => 'cookie.txt',
        save_cookies   => 0,
        ipv6           => 0,
        proxy          => undef,
        @_
    );
    my $self = {};
    for (qw{ host username password }) {
        croak "Required parameter '$_' isn't defined" if not defined $args{$_};
        $self->{$_} = $args{$_};
    }
    # Enable debug messages
    $self->{debug} = $args{debug} // $ENV{VSPHERE_DEBUG} // 0;
    $self->{save_cookies} = $args{save_cookies} ? 1 : 0;

    $self->{curl} = WWW::Curl::Easy->new()
        or croak "Can't initialize WWW::Curl::Easy.";

    $self->{curl}->setopt(CURLOPT_SSL_VERIFYHOST, $args{ssl_verifyhost} ? 2 : 0);
    $self->{curl}->setopt(CURLOPT_SSL_VERIFYPEER, $args{ssl_verifypeer} ? 1 : 0);
    $self->{curl}->setopt(CURLOPT_VERBOSE, $self->{debug});
    $self->{curl}->setopt(CURLOPT_USERAGENT, 'VMware VI Client/5.0.0');
    $self->{curl}->setopt(CURLOPT_COOKIEJAR, $args{cookies_file});
    $self->{curl}->setopt(CURLOPT_COOKIEFILE, $args{cookies_file});
    $self->{curl}->setopt(CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4)
        unless $args{ipv6};
    $self->{curl}->setopt(CURLOPT_PROXY, $args{proxy})
        if defined $args{proxy};

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

    # Reconnect if session timed out
    if (not $do_not_try_login and defined $self->{last_request_time}) {
        if (time - $self->{last_request_time} >= $self->timeout()) {
            print STDERR "Going to reconnect before $method of $id [$type]"
                if $self->{debug};
            $self->login;
        }
    }

    my $curl = $self->{curl};

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
    $curl->setopt(CURLOPT_POST, 1);
    $curl->setopt(CURLOPT_HTTPHEADER, [
        'Content-Type: text/xml; charset=utf-8',
        'SOAPAction: urn:vim25/5.0',
    ]);
    $curl->setopt(CURLOPT_POSTFIELDS, $request);
    $curl->setopt(CURLOPT_URL, "https://$self->{host}/sdk/vimService");

    my $response;
    $curl->setopt(CURLOPT_WRITEDATA, \$response);
    print STDERR "Send request:\n", '-'x80, "\n", $request, "\n", '-'x80, "\n"
        if $self->{debug};
    if (my $retcode = $curl->perform) {
        croak "Can't perform request: $retcode ".
            $curl->strerror($retcode)." ".$curl->errbuf;
    }
    $self->{last_request_time} = time;
    print STDERR "Got response:\n", '-'x80, "\n", $response, "\n", '-'x80, "\n"
        if $self->{debug} and defined $response;

    my $http_code = $curl->getinfo(CURLINFO_HTTP_CODE);
    return $response if $http_code == 200;

    croak "Host returned an error: $http_code" if not defined $response;
    croak "Host returned an error($http_code): $response"
        if $response !~ /<[?]xml/;

    my $xml = XMLin($response);

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
        if $response =~ /<soapenv:Fault>(.*)<\/soapenv:Fault>/is;
    croak "Host returned an error: ".$response;
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
        force_array => [],
        key_attr    => {},
        xml_params  => undef,
        keep_type   => 0,
        skip_login  => 0,
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
        } elsif ($args{of} eq 'ComputeResource') {
            $object_set = $self->_get_object_set_for_compute_resource;
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
        $args{skip_login}
    );
    my %result;

    my @add_xml_params = $args{xml_params} ? @{$args{xml_params}} : ();
    my %xml_params = (
            ForceArray => [
                'objects', 'propSet', 'childSnapshotList',
                'HostDatastoreBrowserSearchResults',
                @{$args{force_array}},
            ],
            KeyAttr => {
                VirtualDevice => 'key',
                childSnapshotList => 'snapshot',
                propSet => 'name',
                %{$args{key_attr}},
            },
            @add_xml_params,
    );
    while (1) {
        # Strip root tags
#        $response =~ s/.*<soapenv:Body>\s*<\w+Response[^>]*>\s*//s;
#        $response =~ s{\s*</\w+Response>\s*</soapenv:Body>.*}{}s;
        # Strip type attributes from tags
        if (not $args{keep_type}) {
            $response =~ s/<(\w+)(?: (?:\w+\:)?type="[^"]+")+>/<$1>/gs;
        }
        if ($response eq '') {
            print STDERR "Empty response\n" if $self->debug;
            last;
        }
        my $xml = XMLin($response, %xml_params);
        print Data::Dumper->Dump([$xml], ['xml']) if $self->debug;
        my $o = $xml;
        $o = $o->{(grep(/body/i, keys %$o))[0]};
        $o = $o->{(grep(/response/i, keys %$o))[0]};
        my $token = $o->{returnval}{token};
        $o = $o->{returnval}{objects};
        last if not defined $o;
        croak "Invalid response: $response"
            if not ref $o or ref $o ne 'ARRAY';
        my %r = map { $_->{obj} => $_->{propSet} } @$o;
        foreach my $obj (keys %r) {
            $result{$obj}{$_} = $r{$obj}{$_}{val} for keys %{$r{$obj}};
        }

        last if not defined $token;

        $response = $self->request(
            PropertyCollector => $self->{service}{propertyCollector},
            ContinueRetrievePropertiesEx => "<token>$token</token>",
            $args{skip_login}
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
    return unless defined ref $objects and ref $objects eq 'HASH' and %$objects;
    my $obj = $objects->{(sort keys %{$objects})[0]};
    return unless defined ref $obj and ref $obj eq 'HASH';
    return $obj->{$property};
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
    my $sm_moid = $self->{service}{sessionManager};
    my $sm = $self->get_properties(
        of => 'SessionManager', moid => $sm_moid, skip_login => 1,
    );
    if (defined $sm->{$sm_moid}{currentSession}) {
        return $sm->{$sm_moid}{currentSession};
    }
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

sub settings {
    my ($self, $key) = @_;
    return $self->{settings}{$key}
        if defined ref $self->{settings} and ref $self->{settings} eq 'HASH';
    my $om = $self->{service}{setting} or return;
    my $settings = $self->get_property('setting',
        of         => 'OptionManager',
        moid       => $om,
        key_attr   => { OptionValue => "key" },
        xml_params => [ ContentKey => "-value" ],
        skip_login => 1,
    );
    return unless defined ref $settings and ref $settings eq 'HASH';
    $self->{settings} = $settings->{OptionValue} // {};
    return $self->{settings}{$key};
}

sub timeout {
    my ($self) = @_;
    $self->{timeout} = $self->settings('vpxd.httpClientIdleTimeout') // 900
        if not defined $self->{timeout};
    return $self->{timeout};
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
    if (defined $self and defined $self->{UserSession}
            and not $self->{save_cookies}
    ) {
        $self->request(
            SessionManager => $self->{service}{sessionManager},
            Logout         => undef,
            2
        );
        $self->{curl}->setopt(CURLOPT_COOKIELIST, 'ALL');
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

sub _get_object_set_for_compute_resource {
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

It's small and easy to use.

=item *

It has minumal dependencies on non-core modules. Actually it needs 
L<WWW::Curl::Easy>, L<XML::Simple> and L<XML::Writer> modules only.

=item *

High performance: it uses libcurl and requests only what's actually needed.

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

=item ssl_verifyhost =E<gt> $boolean

This option determines whether libcurl verifies that the server cert is for the 
server it is known as. When negotiating TLS and SSL connections, the server 
sends a certificate indicating its identity. If enabled that certificate must 
indicate that the server is the server to which you meant to connect, or the 
connection fails. Simply put, it means it has to have the same name in the 
certificate as is in the URL you operate against. (disabled by default)

=item ssl_verifypeer =E<gt> $boolean

This option determines whether curl verifies the authenticity of the peer's
certificate. A value of 1 means curl verifies; 0 (zero) means it doesn't.

When negotiating a TLS or SSL connection, the server sends a certificate 
indicating its identity. Curl verifies whether the certificate is authentic, 
i.e. that you can trust that the server is who the certificate says it is. This
trust is based on a chain of digital signatures, rooted in certification 
authority (CA) certificates you supply. curl uses a default bundle of CA 
certificates (the path for that is determined at build time).

When enabled, and the verification fails to prove that the certificate is 
authentic, the connection fails. When the option is zero, the peer certificate
verification succeeds regardless.

Authenticating the certificate is not enough to be sure about the server. You 
typically also want to ensure that the server is the server you mean to be 
talking to. Use C<ssl_verifyhost> for that. The check that the host name in the 
certificate is valid for the host name you're connecting to is done 
independently of the C<ssl_verifyhost> option.

WARNING: disabling verification of the certificate allows bad guys to 
man-in-the-middle the communication without you knowing it. Disabling 
verification makes the communication insecure. Just having encryption on a 
transfer is not enough as you cannot be sure that you are communicating with 
the correct end-point.

(disabled by default)

=item ipv6 =E<gt> $boolean

Enables IPv6 DNS queries to allow resolve hostnames to IPv6 addresss too.
(disabled by default)

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

=item force_array =E<gt> \@tag_names

Allows you to specify a list of element names which should always be forced into
an array representation.

=item key_attr =E<gt> \%tags_and_keys

Specifies additional key properties.

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

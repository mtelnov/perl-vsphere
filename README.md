# VMware::vSphere

Perl API and command line utility to manage VMware ESXi/vCenter (VMware vSphere Web Services).
It is not a full-featured replacement for [VMware vSphere Perl SDK](https://www.vmware.com/support/developer/viperltoolkit/index.html) but this module has following advantages:

* It's small and easy to use.

* Easy to install: it has minumal dependencies on non-core modules. Actually it requires WWW::Curl::Easy, XML::Simple and XML::Writer modules only.

* High performance: it uses libcurl requests only what's actually needed.

* CLI with shell completion.

## Installation

### openSUSE/SLES/Fedore/RHEL/CentOS/ScientificLinux

It's better to use a prepared RPM rather than install from CPAN module:
http://software.opensuse.org/package/perl-VMware-vSphere

### Other \*nix/cygwin

```shell
git clone https://github.com/mtelnov/perl-vsphere.git
cd perl-vsphere
perl Makefile.PL
make test
make install
```

*Note:* if you use bash don't forget to install bash_completion to
/etc/bash_completion.d/.

## Getting Started

### vsphere utility

vsphere CLI utility requires three environment variables with vSphere
credentials: VSPHERE_HOST, VSPHERE_USER and VSPHERE_PASS.

```shell
export VSPHERE_HOST=vc.example.com VSPHERE_USER=root VSPHERE_PASS=vmware
```

Get list of virtual machines

    $ vsphere list
    test_vm1
    test_vm2
    test_vm3

Create a snapshot

    $ vsphere create_snapshot test_vm1 name snapshot1
    snapshot-1593

Reconfigure the VM

    $ vsphere reconfigure_vm test_vm1 memoryMB 2048
    1

Poweron the VM

    $ vsphere poweron_vm test_vm1
    1

Revert to the current snapshot

    $ vsphere revert_to_current_snapshot test_vm1
    1

Feel free to ask help

    $ vsphere help
    $ vsphere help linked_clone
    $ man VMware::vSphere::Simple


### Perl interface VMware::vSphere::Simple

```perl

use VMware::vSphere::Simple;

my $v = VMware::vSphere::Simple->new(
    host => 'vc.example.com',
    username => 'root',
    password => 'vmware',
);

my @list_vm = $v->list;
```

## License

This library is free software; you may redistribute and/or modify it under the
same terms as Perl itself.
See LICENSE for detailed information.

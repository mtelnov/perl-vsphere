#
# spec file for package perl-VMware-vSphere
#
# Copyright (c) 2016 Mikhail Telnov <Mikhail.Telnov@gmail.com>
#

Name:    perl-VMware-vSphere
Version: 1.00
Release: 0
%define  cpan_name VMware-vSphere
Summary:   Pure Perl API and CLI for VMware vSphere
License:   Artistic-1.0 or GPL-1.0+
Group:     Development/Libraries/Perl
Url:       https://github.com/mtelnov/perl-vsphere
Source0:   %{cpan_name}-%{version}.tar.gz
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-build
BuildRequires: perl
BuildRequires: perl(base)
BuildRequires: perl(Carp)
BuildRequires: perl(Data::Dumper)
BuildRequires: perl(ExtUtils::MakeMaker)
BuildRequires: perl(File::Basename)
BuildRequires: perl(HTTP::Cookies)
BuildRequires: perl(HTTP::Request::Common)
BuildRequires: perl(IO::Socket::SSL)
BuildRequires: perl(LWP::Protocol::https)
BuildRequires: perl(LWP::UserAgent)
BuildRequires: perl(List::Util)
BuildRequires: perl(Pod::Find)
BuildRequires: perl(Pod::Usage)
BuildRequires: perl(Test::More)
BuildRequires: perl(XML::Simple)
BuildRequires: perl(XML::Writer)
Requires: perl
Requires: perl(base)
Requires: perl(Carp)
Requires: perl(Data::Dumper)
Requires: perl(File::Basename)
Requires: perl(HTTP::Cookies)
Requires: perl(HTTP::Request::Common)
Requires: perl(IO::Socket::SSL)
Requires: perl(LWP::Protocol::https)
Requires: perl(LWP::UserAgent)
Requires: perl(List::Util)
Requires: perl(Pod::Find)
Requires: perl(Pod::Usage)
Requires: perl(XML::Simple)
Requires: perl(XML::Writer)

%description
Simple CLI utility and Perl interface for VMware vSphere Web Services
(management interface for VMware vCenter and VMware ESXi products).

%prep
%setup -q -n %{cpan_name}-%{version}
find . -type f -print0 | xargs -0 chmod 644

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
%{__make} %{?_smp_mflags}

%check
%{__make} test

%install
%{__make} DESTDIR=$RPM_BUILD_ROOT install_vendor
find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} ';'
find $RPM_BUILD_ROOT -type f -name perllocal.pod -exec rm -f {} ';'
%{__mkdir_p} ${RPM_BUILD_ROOT}/%{_sysconfdir}/bash_completion.d
%{__install} -m 644 bash_completion ${RPM_BUILD_ROOT}/%{_sysconfdir}/bash_completion.d/vsphere

%files
%{_bindir}/vsphere
%{perl_vendorlib}/VMware
%{perl_vendorlib}/VMware/vSphere.pm
%{perl_vendorlib}/VMware/vSphere
%{perl_vendorlib}/VMware/vSphere/*.pm
%{_mandir}/man1/vsphere.1* 
%{_mandir}/man3/VMware::vSphere.3pm* 
%{_mandir}/man3/VMware::vSphere::App.3pm* 
%{_mandir}/man3/VMware::vSphere::Const.3pm* 
%{_mandir}/man3/VMware::vSphere::Simple.3pm* 
%config %{_sysconfdir}/bash_completion.d/vsphere
%doc README LICENSE

%changelog
* Mon Jun 20 2016 Mikhail Telnov <mikhail.telnov@gmail.com> - 1.00-0
- Initial package

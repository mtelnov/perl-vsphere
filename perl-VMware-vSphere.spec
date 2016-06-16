#
# spec file for package perl-VMware-vSphere
#
# Copyright (c) 2016 Mikhail Telnov <Mikhail.Telnov@gmail.com>
#

Name:           perl-VMware-vSphere
Version:        1.00
Release:        0
#%define cpan_name VMware-vSphere
Summary:        Pure Perl API and CLI for VMware vSphere
License:        Artistic-1.0 or GPL-2.0+
Group:          Development/Libraries/Perl
Url:            https://github.com/mtelnov/perl-vsphere
Source0:        %{cpan_name}-%{version}.tar.gz
BuildArch:      noarch
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildRequires:  perl
BuildRequires:  perl-macros
BuildRequires:  perl(HTTP::Cookies)
BuildRequires:  perl(HTTP::Request::Common)
BuildRequires:  perl(IO::Socket::SSL)
BuildRequires:  perl(LWP::UserAgent)
BuildRequires:  perl(LWP::Protocol::https)
BuildRequires:  perl(XML::Simple)
BuildRequires:  perl(XML::Writer)
Requires:  perl(HTTP::Cookies)
Requires:  perl(HTTP::Request::Common)
Requires:  perl(IO::Socket::SSL)
Requires:  perl(LWP::UserAgent)
Requires:  perl(LWP::Protocol::https)
Requires:  perl(XML::Simple)
Requires:  perl(XML::Writer)
%{perl_requires}

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
%perl_make_install
%perl_process_packlist
%{__mkdir_p} ${RPM_BUILD_ROOT}/%{_sysconfdir}/bash_completion.d
%{__install} -m 755 bash_completion ${RPM_BUILD_ROOT}/%{_sysconfdir}/bash_completion.d/vsphere
%perl_gen_filelist

%files -f %{name}.files
%defattr(-,root,root,755)
%doc README LICENSE
%config  %{_sysconfdir}/bash_completion.d/vsphere

%changelog

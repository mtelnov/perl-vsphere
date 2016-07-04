package VMware::vSphere::Const;

use strict;
use warnings;

our $VERSION = 1.00;

use constant MO_TYPES => qw{
	Alarm
	AlarmManager
	AuthorizationManager
	CertificateManager
	ClusterComputeResource
	ClusterEVCManager
	ClusterProfile
	ClusterProfileManager
	ComputeResource
	ContainerView
	CustomFieldsManager
	CustomizationSpecManager
	Datacenter
	Datastore
	DatastoreNamespaceManager
	DiagnosticManager
	DistributedVirtualPortgroup
	DistributedVirtualSwitch
	DistributedVirtualSwitchManager
	EnvironmentBrowser
	EventHistoryCollector
	EventManager
	ExtensibleManagedObject
	ExtensionManager
	FileManager
	Folder
	GuestAliasManager
	GuestAuthManager
	GuestFileManager
	GuestOperationsManager
	GuestProcessManager
	GuestWindowsRegistryManager
	HistoryCollector
	HostAccessManager
	HostActiveDirectoryAuthentication
	HostAuthenticationManager
	HostAuthenticationStore
	HostAutoStartManager
	HostBootDeviceSystem
	HostCacheConfigurationManager
	HostCertificateManager
	HostCpuSchedulerSystem
	HostDatastoreBrowser
	HostDatastoreSystem
	HostDateTimeSystem
	HostDiagnosticSystem
	HostDirectoryStore
	HostEsxAgentHostManager
	HostFirewallSystem
	HostFirmwareSystem
	HostGraphicsManager
	HostHealthStatusSystem
	HostImageConfigManager
	HostKernelModuleSystem
	HostLocalAccountManager
	HostLocalAuthentication
	HostMemorySystem
	HostNetworkSystem
	HostPatchManager
	HostPciPassthruSystem
	HostPowerSystem
	HostProfile
	HostProfileManager
	HostServiceSystem
	HostSnmpSystem
	HostStorageSystem
	HostSystem
	HostVFlashManager
	HostVirtualNicManager
	HostVMotionSystem
	HostVsanInternalSystem
	HostVsanSystem
	HttpNfcLease
	InventoryView
	IoFilterManager
	IpPoolManager
	IscsiManager
	LicenseAssignmentManager
	LicenseManager
	ListView
	LocalizationManager
	ManagedEntity
	ManagedObjectView
	MessageBusProxy
	Network
	OpaqueNetwork
	OptionManager
	OverheadMemoryManager
	OvfManager
	PerformanceManager
	Profile
	ProfileComplianceManager
	ProfileManager
	PropertyCollector
	PropertyFilter
	ResourcePlanningManager
	ResourcePool
	ScheduledTask
	ScheduledTaskManager
	SearchIndex
	ServiceInstance
	ServiceManager
	SessionManager
	SimpleCommand
	StoragePod
	StorageResourceManager
	Task
	TaskHistoryCollector
	TaskManager
	UserDirectory
	View
	ViewManager
	VirtualApp
	VirtualDiskManager
	VirtualizationManager
	VirtualMachine
	VirtualMachineCompatibilityChecker
	VirtualMachineProvisioningChecker
	VirtualMachineSnapshot
	VmwareDistributedVirtualSwitch
	VRPResourceManager
	VsanUpgradeSystem
};

1;

__END__

=head1 NAME

VMware::vSphere::Const - constants for VMware::vSphere

=head1 SYNOPSIS

    use VMware::vSphere::Const;
    print join ', ', VMware::vSphere::Const::MO_TYPES;

=head1 DESCRIPTION

This module provides constants related to L<VMware::vSphere>.

=head1 CONSTANTS

=over

=item MO_TYPES

List with types of Managed Objects.

=back

=head1 SEE ALSO

=over

=item L<VMware::vSphere>

Raw interface to VMware vSphere Web Services.

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

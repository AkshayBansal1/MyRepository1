<#

.SYNOPSIS

TestVM Script



.DESCRIPTION

This script will fetch all Azure Test VM's



.PARAMETER Name

TestVM Script.



.INPUTS

None.



.OUTPUTS

The Test VM's report



.VERSION

1.0



.DEVELOPER

vRO Automation Team

#>



try

{

#install command to be run only the first time this scripts runs on a vm

#Install-Module -Name Az -AllowClobber

Import-Module -Name Az



#Inputs

$User = 'cec02054-9518-4366-8947-a0baed92c160'

$password='A-uBJ4RwkM@.B7BGvYAZC/8xjx5A3f'

$tenant='74b72ba8-5684-402c-98da-e38799398d7d'

$subscriptionId='c7e4f49b-8174-4f40-bd74-310d60dc6cb7'





$PWord = ConvertTo-SecureString -String $password -AsPlainText -Force



$pscredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord

#$pscredential = Get-Credential -UserName $sp.AppId

Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $tenant



# Create Report Array

$report = @()

# Record all the subscriptions in a Text file

#$reportName = "$env:userprofile\Desktop\Azure-VM-Details.csv"



# Select the subscription

Select-AzSubscription $subscriptionId



# Get all the VMs from the selected subscription

$vms = Get-AzVM



# Get all the Public IP Address

$publicIps = Get-AzPublicIpAddress



# Get all the Network Interfaces

$nics = Get-AzNetworkInterface | ?{ $_.VirtualMachine -NE $null}

foreach ($nic in $nics) {

# Creating the Report Header we have taken maxium 5 disks but you can extend it based on your need

$ReportDetails = "" | Select VmName, PrivateIpAddress, OsType

#Get VM IDs

$vm = $vms | ? -Property Id -eq $nic.VirtualMachine.id

$ReportDetails.OsType = $vm.StorageProfile.OsDisk.OsType

$ReportDetails.VMName = $vm.Name

$ReportDetails.PrivateIpAddress = $nic.IpConfigurations.PrivateIpAddress

$report+=$ReportDetails

}

$report | where {$_.VmName -like "zzc*"}


}

catch

{

"UNIQUEERRORCODE : Error occured in the scripts $($_.Exception)"

}
#$Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size (2250, 25)

Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue


$vmName = $args[0]
$vCenter = $args[1]
$vCenterUser = $args[2]
$vCenterPass = $args[3]
$csvTextFromGuest = $args[4]


Connect-VIServer -Server "$vCenter" -User "$vCenterUser" -Password "$vCenterPass" -WarningAction SilentlyContinue | Out-Null
$VM = Get-VM -Name $vmName

$VirtualDisks = @()
$GuestDiskCount = 0

$error.Clear()
if (! $error -and $csvTextFromGuest) 
{ 
	$WinDisks = $csvTextFromGuest | ConvertFrom-Csv

	#Determine SCSIPort offset 
    $portOffset = ($WinDisks | Where-Object {$_.SCSIPort} | Measure-Object -Property SCSIPort -Minimum).Minimum 
	
    #Can't find where this is used - Bobby
	#$scsi0pciSlotNumber = ($VM.Extensiondata.Config.ExtraConfig | Where-Object{ $_.key -like "scsi0.pciSlotNumber"}).value
	
	$scsiPciSlotNumbers = @()
    $VM.Extensiondata.Config.ExtraConfig | Where-Object {$_.key -like "scsi?.pciSlotNumber"} | ForEach-Object{ $scsiPciSlotNumbers += $_.value }

    #All entries that don't match any known pciSlotNumber are 
	#attached to scsi0.Change these entries to the pciSlotnumber 
	#of scsi0
    $WinDisks | Foreach-Object {
        #Increase GuestDiskCount
        $GuestDiskCount++

        if ($scsiPciSlotNumbers -notcontains $_.CtrlPCISlotNumber)
        {
            if ($scsiPciSlotNumbers -contains "1184" -and $_.CtrlPCISlotNumber -eq "161")
            {
                $_.CtrlPCISlotNumber = "1184"
            }
            elseif ($scsiPciSlotNumbers -contains "1216" -and $_.CtrlPCISlotNumber -eq "193")
            {
                $_.CtrlPCISlotNumber = "1216"
            }
            else
            {
                $_.CtrlPCISlotNumber = ($VM.ExtensionData.Config.Extraconfig | Where-Object{ $_.key -like "scsi0.pciSlotNumber"}).value
            }
        }
    }

	#Create DiskMapping table
	foreach ($VirtualSCSIController in ($VM.Extensiondata.Config.Hardware.Device | Where-Object {$_.DeviceInfo.Label -match "SCSI Controller"}))
	{ 
		foreach ($VirtualDiskDevice in ($VM.Extensiondata.Config.Hardware.Device | Where-Object {$_.ControllerKey -eq $VirtualSCSIController.Key})) 
		{ 
			$VirtualDisk = New-Object PSObject -Property @{
				#VMSCSIController = $VirtualSCSIController.DeviceInfo.Label
				#VMDiskName = $VirtualDiskDevice.DeviceInfo.Label
				#SCSI_Id = "{0}:{1}" -f $VirtualSCSIController.BusNumber, $VirtualDiskDevice.UnitNumber
				#VMDiskFile = $VirtualDiskDevice.Backing.FileName
				#VMDiskSizeGB = $VirtualDiskDevice.CapacityInKB * 1KB / 1GB
				#RawDeviceName = $VirtualDiskDevice.Backing.DeviceName
				#LunUuid = $VirtualDiskDevice.Backing.LunUuid
				#WindowsDisk = ""
				#WindowsDiskSizeGB = 0
                Index = [string] $VirtualDiskDevice.UnitNumber
                Bus = [string] $VirtualSCSIController.BusNumber
                Drive = ""
			}
			#Get VM Hardware Version
			$powerCliVersion = Get-PowerCLIVersion
			if ($powerCliVersion -eq $null) { Throw "Unable to get Power CLI Version." }

			if (($powerCliVersion.Major -eq 10 -and $powerCliVersion.Minor -eq 0) -or ($powerCliVersion.Major -lt 10))
			{
				[int] $vmVersion = $vm.version.ToString().Replace("v","")
			}
			else
			{
				[int] $vmVersion = $vm.HardwareVersion.Replace("vmx-","")
			}

			#Match disks
			if ($vmVersion -lt 7) 
			{ 
				# For hardware v4 match disks based on controller's SCSIPort an 
				# disk's SCSITargetId.
				# Not supported with mixed scsi adapter types.
				$DiskMatch = $WinDisks | Where-Object {( $_.SCSIPort - $portOffset) -eq $VirtualSCSIController.BusNumber -and $_.SCSITargetID -eq $VirtualDiskDevice.UnitNumber}
			} 
			else 
			{ 
				# For hardware v7 + match disks based on controller's pciSlotNumber 
				# and disk's SCSITargetId 
				$DiskMatch = $WinDisks | Where-Object {$_.CtrlPCISlotNumber -eq ($VM.Extensiondata.Config.Extraconfig | Where-Object {$_.key -match "scsi$($VirtualSCSIController.BusNumber).pcislotnumber"}).value -and $_.SCSITargetID -eq $VirtualDiskDevice.UnitNumber}
			}

			if ($DiskMatch) 
			{ 
				#$VirtualDisk.WindowsDisk = "Disk $( $DiskMatch.Index)"
				#$VirtualDisk.WindowsDiskSizeGB = $DiskMatch.Size / 1GB
                $VirtualDisk.Drive = $DiskMatch.DriveLetter
			} 
			else 
			{ 
				Write-Warning "No matching Windows disk found for SCSI id $( $virtualDisk.SCSI_Id)" 
			} 
			#$VirtualDisk
            $VirtualDisks += $VirtualDisk
		} 
	} 
} 
else 
{ 
	Write-Error "Error Retrieving Windows disk info from guest" 
}

Disconnect-VIServer * -Force -Confirm:$false


$ArrayVirtualDisks = New-Object PSObject -Property @{
    Disks = $VirtualDisks
    GuestDiskCount = $GuestDiskCount.ToString()
}


$ArrayVirtualDisks | ConvertTo-Json -Compress










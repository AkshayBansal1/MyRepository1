# ==============================================================================================
# 
# Microsoft PowerShell Source File -- Created with SAPIEN Technologies PrimalScript 2012
# 
# NAME: 
# 
# AUTHOR: Bobby Boyd (bobby_boyd@Dell.com) , Dell Computer Corporation
# DATE  : 2/06/2013
# MODIFY : 02/26/2019
# COMMENT: 
# 
# 05/31/2013 - Bobby - Removed 'active' from 2003 and 2008 diskpart script commands
# 08/07/2015 - Bobby - Modified to work with vCO Guest Script Manager package
# 01/14/2019 - Jorge - Added function to Get-AvailDrive which assigns next drive letter and initializes disk
# 02/19 /2019 -  Jorge - Replaced the use of functions Get-AvailDrive and Set-DiskConfiguration with PS cmdlets
# ==============================================================================================

Function Get-AvailDrive()
{
	$letters = 68..89 | ForEach-Object { [char]$_ }
    $count = 0
    $usedDrives = Get-PSDrive -PSProvider 'FileSystem' |Select Name
         do {    
            $drvLetter = $letters[$count].ToString()
            if ($usedDrives.Name -match $drvLetter) 
                {
                    Write-Host "drive letter $($drvLetter): already in use, skipping"
                }
            else 
                {
                    Write-Host "drive letter $($drvLetter): is available"
                    $found = $true
                    
                }
            $count++
         }while ($found -ne $true)
		return $drvLetter
}

Function Get-IsDiskUnconfiged($scsitargetid)
{
    #return Get-WmiObject -query "Select * from Win32_diskdrive Where Partitions = 0"
    return Get-WmiObject -query "Select * from Win32_diskdrive Where Partitions = 0 AND SCSITargetId = $scsitargetid"
}

#Below function is to support older Win OSs that have older PS versions
Function Set-DiskConfiguration($driveIndex, $letter)
{
    if ($driveIndex -eq 0)
    {
    	throw "ERROR: Disk Index 0 (OS Drive) cannot be configured!"
    }
    
    # @" ... "@ is a here-string - everything is intepreted as-is
    $DPcommands2K3 = @"
rescan
select disk $driveIndex
online noerr
clean
create partition primary noerr
assign letter $letter noerr
"@
    
    # @" ... "@ is a here-string - everything is intepreted as-is
    $DPcommands2K8 = @"
rescan
select disk $driveIndex
online disk noerr
attribute disk clear readonly noerr
clean
create partition primary noerr
format fs=ntfs label=Disk_$letter quick noerr
assign letter $letter noerr
"@

	switch ($osVersion) {
		"2003" {
			$DPcommands = $DPcommands2K3
		}
		"2008" {
			$DPcommands = $DPcommands2K8
		}
		default {
			throw "Error: Unable to determine OS version for: '$osVersion'"
		}
	}


	echo "Executing diskpart..."
	echo $DPcommands
	$DPcommands | diskpart | Out-Null
	
	if ($osVersion -eq "2003")
	{
		echo "Executing format for OS: '" $osVersion "'..."
		echo "ECHO Y | format $letter`: /fs:ntfs /v:Disk_$letter /q"
		Invoke-Expression "ECHO Y | format $letter`: /fs:ntfs /v:Disk_$letter /q"
	}
	
}


Function Get-OS()
{
	$os = $null
	#$osMajorVersion = (Get-WmiObject -class Win32_OperatingSystem).Version.Substring(0,1)
	
	#switch ($osMajorVersion) {
#		"5" {
#			$os = "2003"
#		}
#		"6" {
#			$os = "2008"	#Major version of 6 also applies to Windows 2012
#		}
#	}
    $os = "2008"
	return $os
}


Function Get-ArgsValid()
{
	$retVal = $true
	if ($scsiIndex -eq $null)
	{
		$retVal = $false
	}
	return $retVal
}


# -------------------------------------------------
# -------------------------------------------------

Write-Output "Add disk configuration starting..."

$scsiIndex = $args[0]
$driveLtr = $args[1]
$scriptname = $MyInvocation.MyCommand.Name
$argValidation = Get-ArgsValid

if ($argValidation -eq $false)
{
	throw "Error: Invalid arguments."
}

$osDriveIndex = $null
$osVersion = Get-OS
#to avoid prompts for formatting disk
Stop-Service -Name ShellHWDetection
#Initialize disks
#$disks = get-disk|where {$_.OperationalStatus -notcontains "Online" -and $_.PartitionStyle -eq "RAW"} 
$disks = get-disk|where {$_.PartitionStyle -eq "RAW"} 
foreach ($disk in $disks) 
                {
                    $disk | 
                    Initialize-Disk -PartitionStyle MBR -PassThru -Confirm:$false
                    # if using GPT no signature is returned - Initialize-Disk -PartitionStyle GPT -PassThru -Confirm:$false
                }
$newDisk = Get-IsDiskUnconfiged($scsiIndex)
#$driveLetter = Get-AvailDrive

if ($newDisk -eq $null)
    {
	    throw "Error: An unformatted disk on SCSITargetID $scsiIndex was not found."
    }
elseif ($newDisk.GetType().Name -eq "Object[]")
    {
	    throw "Error: More than 1 disk was returned."
    }
else
    {
	    $osDriveIndex = $newDisk.Index
	    Write-Host "Found unformatted disk - Index: '" $newDisk.Index "'  Size: "([Math]::Round($newDisk.Size/1GB, 2))"GB"
    }

if ($osDriveIndex -eq $null)
{
	throw	"Error: Unable to get disk Index."
}

#Set-DiskConfiguration -driveIndex $osDriveIndex -letter $driveLetter
Write-Host "Found unpartitioned disk on index $($osDriveIndex) with signature $($newDisk.Signature)"
if ($driveLtr -eq $null)
    {
        Write-Host "No drive letter provided during request, hence assigning drive letter"
        $newPart = get-disk |Where {$_.Signature -eq $newDisk.Signature} | New-Partition -AssignDriveLetter -UseMaximumSize 
    }
else
    {
        $newPart = get-disk |Where {$_.Signature -eq $newDisk.Signature} | New-Partition -DriveLetter $driveLtr -UseMaximumSize 
    }

$newPart | Format-Volume -FileSystem NTFS -Confirm:$false -Force | Select DriveLetter 
Write-Host "Add disk configuration complete for drive index $($osDriveIndex) with signature $($newDisk.Signature). "
Start-Service -Name ShellHWDetection
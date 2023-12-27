#!/bin/bash
# script to identify a new lun or any change in lun size and will use it to expand an existing file system
# =========================================================================
# written     : WK UNIX Team
# Created     : Dec 12 2012
# Last Update : June 28 2015
# -------------------------------------------------------------------------
PATH="/sbin:/usr/sbin:/usr/bin:/bin"

if echo ${1} | egrep ^/$ 1>/dev/null ; then MPOINT=/; SUFFIXLOGFILE=rootfs;
else
#Prefixing "/" and removing traling "/", if any
if echo ${1} | grep ^/ >/dev/null ; then MPOINT=`echo ${1}` ; else MPOINT=`echo "/${1}"` ; fi
if echo ${MPOINT} | grep /$ >/dev/null ; then MPOINT=$(echo ${MPOINT} | sed 's/\/$//') ; fi

##Removing any / from mountpoint name, just to use it as suffix for log file.
if echo ${MPOINT} | grep ^/ >/dev/null ; then SUFFIXLOGFILE=$(echo ${MPOINT} | sed 's/^\///') ; else SUFFIXLOGFILE=`echo ${1}` ; fi
SUFFIXLOGFILE=$(echo ${SUFFIXLOGFILE} | sed 's/\//_/')
fi

LOG_FILE="increasefilesystem_${SUFFIXLOGFILE}.out"
PASSEDNEWDISKID=${2}
STD_OUT=`readlink -f /proc/$$/fd/1`
STD_ERR=`readlink -f /proc/$$/fd/2`

stdtty() {
INPUT=${1}
[ -z "${INPUT}" ] && INPUT=BOTH
if [ "${INPUT}" == "ON" ] ; then
exec 1>${STD_OUT} 2>${STD_ERR}
elif [ "${INPUT}" == "OFF" ] ; then
exec >$LOG_FILE 2>&1
else
exec 1>${STD_OUT} 2>${STD_ERR}
exec &> >(tee -a "$LOG_FILE")
fi
}

stdtty BOTH

##Fetching release version
RELEASEVER=`rpm -qa --qf "%{release}\n" | grep el | head -1 | grep -o "el[0-9]" | grep -o "[0-9]"`

run_command() {
	$1
	RTN=$?
	if [ $RTN -eq 0 ]; then
		echo "Command $1 successful"
	else
		echo "Command $1 failed return code $RTN"
		exit 1
	fi
}

send_msg() {
	echo -e $1
}

diff() {
  awk 'BEGIN{RS=ORS=" "}
       {NR==FNR?a[$0]++:a[$0]--}
       END{for(k in a)if(a[k])print k}' <(echo -n "${!1}") <(echo -n "${!2}")
}
	
if [ "$USER" != "root" ]; then
	echo "  Please log in with root privileges and try again"
	exit 1
elif [ ${RELEASEVER} -lt 5 ]; then
	echo " This script is not compatible with OS releases prior to RHEL 5"
	exit 1
elif [ -z ${RELEASEVER} ] || [[ ! ${RELEASEVER} =~ ^-?[0-9]+$ ]]; then
	echo " Unable to determine OS RELEASE VERSION."
	exit 1
fi

if [ "$#" -gt 2 ]; then
	exec 1>${STD_OUT} 2>${STD_ERR}
	cat << EOT1
	This script will find the VG and LV for a mount point
	then will scan for new disks/expanded disk to expand the VG, LV and then file system.

  Usage: $0 mountpoint
EOT1
	exit 2
fi

#cat << EOT2
#	Please check the $LOG_FILE file contents to review the 	execution log.
#EOT2

#sleep 3
#echo "  Started processing"

#Make sure mountpoint does exist
if [ ! -d "${MPOINT}" ]; then
        echo "Mountpoint ${MPOINT} does not exist, aborting"
        exit 1
fi

send_msg "----Starting `date +'%Y-%b-%d %H:%M'`----"

#Find lv name from fstab
TLVNAME=$(awk -v MNT=${MPOINT} '$2 == MNT {print $1}' /etc/fstab | grep "^/")
if [ $? != 0 -o ! -n "$TLVNAME" -o $(echo $TLVNAME | wc -w) -ne 1 ]; then
        send_msg "Unable to find a logical volume or mount point doesn't exists in /etc/fstab file, aborting!"
        exit 1
else
        LVNAME=`lvdisplay ${TLVNAME} | awk '/LV Name/{print $NF}'`
        if [ $(echo ${LVNAME} | grep "/") ] ; then LVNAME=`echo ${LVNAME} | awk -F'/' '{print $NF}'` ; fi
        VGNAME=`lvdisplay ${TLVNAME} | awk '/VG Name/{print $NF}'`
        [ -z ${LVNAME} -o -z ${VGNAME} ] && send_msg "Either LV ${LVNAME} or VG ${VGNAME} not Found." && exit 1
        send_msg "Found LV ${LVNAME} in VG ${VGNAME} for mount point ${MPOINT}."
fi

#Scanning bus to make sure we have all the physical devices added
declare -a arrayA=(`ls -d /sys/block/sd* | awk -F/ '{print $NF}'`)
echo "arreyA=${arreyA[@]}"
for s in `ls /sys/class/scsi_host/` ; do echo "- - -" > /sys/class/scsi_host/$s/scan ; done ; sleep 4
declare -a arrayB=(`ls -d /sys/block/sd* | awk -F/ '{print $NF}'`)
echo "arreyB=${arreyB[@]}"
NEWDEVICES=`diff arrayB[@] arrayA[@]`
echo "NEWDEVICES=${NEWDEVICES}"

SUM=0
##Find all pvs in involved VG
INVOLVEDPV=`pvs | grep -w "${VGNAME}" | awk '{print $1}' | awk -F/ '{print $NF}' | grep -v [0-9]`
for i in ${INVOLVEDPV}
do
##Free PE before pvresize
arrayC[$SUM]=`pvdisplay /dev/$i | grep "Free PE" | awk '{print $NF}'`
arrayE[$SUM]=`cat /sys/block/${i}/size`
echo 1>/sys/block/${i}/device/rescan
arrayF[$SUM]=`cat /sys/block/${i}/size`
if [ ${arrayE[$SUM]} -ne ${arrayF[$SUM]} ] ; then
pvresize /dev/${i}
fi
##Free PE after pvresize
arrayD[$SUM]=`pvdisplay /dev/$i | grep "Free PE" | awk '{print $NF}'`
##Newly added Free PE to PV
NEW_FREEPE[$SUM]=`expr ${arrayD[$SUM]} - ${arrayC[$SUM]}`
##PV on which free Free PE found
[ ${NEW_FREEPE[$SUM]} -gt 0 ] && EXPANDEDPV[$SUM]="/dev/${i}"
(( SUM = $SUM + 1 ))
done
##Free PE Total found on all PVs
for i in ${NEW_FREEPE[@]} ; do FREEPET=$((${FREEPET}+${i})) ; done
[ -z "${FREEPET}" ] && FREEPET=0


if [ ! -z "${PASSEDNEWDISKID}" -a -z "${NEWDEVICES}" -a "${FREEPET}" -eq 0 ] ; then
echo "No new/expanded device found after scanning and recognized manually passed scsi id of newly added vm disk."
LASTDISK=`dmesg | egrep "GB.*GiB" | egrep -ow "\[sd.*\]" | sed 's/\[//g;s/\]//g' | tail -1`

##Mapping of OS SCSI id to VM SCSI ID
unset z ; unset OSSCID ; unset ; unset VMSCID ; unset MAPPING
for i in $( cd /sys/block/ ; for i in `ls -d sd*` ; do ls -lad /sys/block/${i}/device | awk -F'/' '{print $NF}' | awk -F':' '{print $1}' ; done | sort -g | uniq )
do
[ -z "${z}" ] && z=0
OSSCID[$z]=${i}
VMSCID[$z]=${z}
MAPPING[$z]="s/^${OSSCID[$z]}:/${VMSCID[$z]}:/;"
z=$((${z}+1))
done

echo "Mapping: ${MAPPING[*]}"
cd /sys/block/ ; for i in `ls -d sd*` ; do echo "`ls -lad /sys/block/${i}/device | awk -F'/' '{print $NF}' | awk -F':' '{print $1":"$3}'` ${i}"; done | sed "${MAPPING[*]}"

LASTDISKID=$(cd /sys/block/ ; for i in `ls -d sd*` ; do echo "`ls -lad /sys/block/${i}/device | awk -F'/' '{print $NF}' | awk -F':' '{print $1":"$3}'` ${i}"; done | sed "${MAPPING[*]}" | egrep "${LASTDISK}$" | awk '{print $1}')

if [ "${PASSEDNEWDISKID}" == "${LASTDISKID}" ] ; then
NEWDEVICES=${LASTDISK}
else
echo -e "LASTDISKID=${LASTDISKID} of disk ${LASTDISK} is not same as that of PASSEDNEWDISKID=${PASSEDNEWDISKID}."
fi
echo -e "LASTDISK=${LASTDISK}\nLASTDISKID=${LASTDISKID}\nPASSEDNEWDISKID=${PASSEDNEWDISKID}\nNEWDEVICESFORCED=${NEWDEVICES}"
else
echo -e "Neither find any new/expanded device nor any scsi id passed to the script."
fi


##Exit, if no new devices found or no expanded PV found
if [ -z "${NEWDEVICES}" ] && [ ${FREEPET} -eq 0 ] 2>/dev/null
then
send_msg "No new disks found. And none of the devices ( ${INVOLVEDPV} ) are expanded at vmware level."
exit 1
fi


for i in ${NEWDEVICES}; do
        echo "  Checking /dev/$i"
        if [ -b "/dev/$i" ]; then
                echo "  Physical device /dev/$i found"
                VGGRP=$(pvdisplay /dev/$i | awk '/VG Name/{print $3}')
                if [ -n "$VGGRP" ]; then
                        send_msg "  Device already in volume group $VGGRP, skipping"
                else
			send_msg " /dev/$i not in a volume group"
			send_msg "   Initializing disk"
			run_command "pvcreate /dev/$i"
				send_msg "   Adding disk to VG"
				run_command "vgextend $VGNAME /dev/$i"
			#Free available PE
            FREEPE=`pvdisplay /dev/$i | grep "Free PE" | awk '{print $NF}'`
			# extend lv on new disk
			send_msg "Extending $LVNAME and File system on new disk"
			lvextend -r -l +${FREEPE} $TLVNAME /dev/$i
			RTN=$?
			if [ $RTN -eq 0 ]; then
				echo "Command lvextend -r -l +${FREEPE} $TLVNAME /dev/$i successful"
			else
				echo "Command lvextend -r -l +${FREEPE} $TLVNAME /dev/$i is unsuccessful, Retrying with appending -n option to above command. [Now Forcing to ignore fsck, just before the FS expand.]"
				run_command "lvextend -r -n -l +${FREEPE} $TLVNAME /dev/$i"
			fi
			# extend file system
			#send_msg "Increasing file system"
			#run_command "resize2fs $TLVNAME"
			fi
		fi
done

##For Expanded PV
#if [ ! -z ${FREEPET} ] ; then
if [ ${FREEPET} -ne 0 ] ; then
	# extend lv on new disk
	send_msg "Extending $LVNAME and File system on existing disk `echo ${EXPANDEDPV[@]}`"
	
	lvextend -r -l +${FREEPET} $TLVNAME `echo ${EXPANDEDPV[@]}`
			RTN=$?
			if [ $RTN -eq 0 ]; then
				echo "Command lvextend -r -l +${FREEPET} $TLVNAME `echo ${EXPANDEDPV[@]}` successful"
			else
				echo "Command lvextend -r -l +${FREEPET} $TLVNAME `echo ${EXPANDEDPV[@]}` is unsuccessful, Retrying with appending -n option to above command. [Now Forcing to ignore fsck, just before the FS expand.]"
				run_command "lvextend -r -n -l +${FREEPET} $TLVNAME `echo ${EXPANDEDPV[@]}`"
			fi
	# extend file system
	#send_msg "Increasing file system"
	#run_command "resize2fs $TLVNAME"
fi
#fi

df -h ${MPOINT}
send_msg "----Finished `date +'%Y-%b-%d %H:%M'`----"
exit 0

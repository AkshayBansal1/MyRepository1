#!/bin/bash
# mountvm-fs: script to check for new storage devices and mount a new filesystem (as first agrgument) 
# and assign ownership to "users" group for the end users to be able to write to it.
# =========================================================================
# written     : Carlos Naranjo <carlos_naranjo@dell.com> || WK UNIX Team
# Created     : May 5 2011
# Last Update : May 30 2013
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

LOG_FILE="addfilesystem_${SUFFIXLOGFILE}.out"
VGNAME="vgapps"
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

##Setting file system type based on version
if [ $RELEASEVER -le 6 ]; then
	which mkfs.ext4 2>/dev/null 1>&2 ; [ $? -eq 0 ] && FSTYPE=`echo "ext4"` || FSTYPE=`echo "ext3"`
else
	FSTYPE="ext4"
fi

#Prefixing "/" and removing traling "/", if any
if echo ${1} | grep ^/ >/dev/null ; then MPOINT=`echo ${1}` ; else MPOINT=`echo "/${1}"` ; fi
if echo ${MPOINT} | grep /$ >/dev/null ; then MPOINT=$(echo ${MPOINT} | sed 's/\/$//') ; fi

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
        echo $1
}

do_mount() {
        DEVICE="$1"
        MOUNTNAME="$2"

        DIR_NAME=`dirname $MOUNTNAME`
        if [ -d "$DIR_NAME" ]; then
                send_msg "  Directory exists ($DIR_NAME)"
        else
                mkdir -p $DIR_NAME
        fi
        mkdir $MOUNTNAME
        send_msg "Following device $DEVICE was automatically added"
        cp -ip /etc/fstab /etc/fstab_`date +%Y-%b-%d_%H%M`
		echo "$DEVICE   $MOUNTNAME              ${FSTYPE}    defaults        1 2" >> /etc/fstab
        mount $MOUNTNAME
        df -k $MOUNTNAME 2>&1 > /dev/null
        if [ "$?" -eq 0 ]; then
                echo "  $MOUNTNAME was created and mounted"
                chmod 775 $MOUNTNAME
                chgrp users $MOUNTNAME
        fi
}

diff() {
  awk 'BEGIN{RS=ORS=" "}
       {NR==FNR?a[$0]++:a[$0]--}
       END{for(k in a)if(a[k])print k}' <(echo -n "${!1}") <(echo -n "${!2}")
}

if [ "$USER" != "root" ]; then
        echo "  Please log in with root privileges and try again"
        exit 1
fi

if [ "$#" -gt 2 ]; then
		exec 1>${STD_OUT} 2>${STD_ERR}
        cat << EOT1
        This script will create a VG, LV, filesystem and mount new
        physical devices.

  Usage: $0 mountpoint
EOT1
        exit 2
fi

cat << EOT2
        Please check the $LOG_FILE file contents to review the
        execution log.
EOT2
sleep 2

echo "  Started processing"

#Make sure mountpoint does not exist yet
if [ -d "$MPOINT" ]; then
      echo "Mountpoint $MPOINT already exists, Aborting"
      exit 1
fi
###Make sure mountpoint does not exist or else rename the mountpoint suffix it with a number.
##	MOUNTNAME=`echo "${MPOINT}"`
##while [ -d "${MOUNTNAME}" ]; do
##	X=$((${X}+1))
##	OLD_MOUNTNAME=`echo ${MOUNTNAME}`
##	MOUNTNAME=`echo ${MPOINT}${X}`
##	send_msg "  Given Mountpoint (${OLD_MOUNTNAME}) already exists. Automatically picked new mountpoint ${MOUNTNAME} "
##done
##unset X
##	MPOINT=`echo $MOUNTNAME`

send_msg "----Starting `date +'%Y-%b-%d %H:%M'`----"

#Scanning bus to make sure we have all the physical devices added

declare -a arreyA=(`ls -d /sys/block/sd* | awk -F/ '{print $NF}'`)
echo "arreyA=${arreyA[@]}"
for s in `ls /sys/class/scsi_host/` ; do echo "- - -" > /sys/class/scsi_host/$s/scan ; done ; sleep 4
declare -a arreyB=(`ls -d /sys/block/sd* | awk -F/ '{print $NF}'`)
echo "arreyB=${arreyB[@]}"
NEWDEVICES=`diff arreyB[@] arreyA[@]`
echo "NEWDEVICES=${NEWDEVICES}"

if [ ! -z "${PASSEDNEWDISKID}" -a -z "${NEWDEVICES}" ] ; then
echo "No new devices found after scanning and recognized manually passed scsi id of newly added vm disk."
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
echo -e "Neither find any new device nor any scsi id passed to the script."
fi

[ -z "${NEWDEVICES}" ] && echo -e "\n\e[41mNo new disks found!!\e[0m\n" && exit 1


#Check for 'physical' devices /dev/sdb through /dev/sdz
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
			timeout=0 ; while [ -f /tmp/vgcheck.lock -a ${timeout} -le 30 ]; do timeout=$((${timeout}+1)); sleep 2; done
			[ ! -f /tmp/vgcheck.lock ] && touch /tmp/vgcheck.lock ; [ ${timeout} -gt 30 ] && echo "Timeout occured for acquiring lock on file /tmp/vgcheck.lock" ; unset timeout
			#vgs 2>/dev/null | grep -v VSize | awk '{print $1}' | grep $VGNAME
                        #if [ $? -ne 0 ]; then
			if vgs | grep -w ${VGNAME} ; then
                                #VG does exist, extend
                                send_msg "  VG $VGNAME does exist, thus extending"
                                run_command "vgextend $VGNAME /dev/$i"
                        else
                                #VG does not exist, create
                                send_msg "  VG $VGNAME does not exist, creating"
                                run_command "vgcreate $VGNAME /dev/$i"
                        fi
			[ -f /tmp/vgcheck.lock ] && rm -f /tmp/vgcheck.lock
                        #Free available PE
                        FREEPE=`pvdisplay /dev/$i | grep "Free PE" | awk '{print $NF}'`
                        # generate lv name and create
                        LVNAME=lv$(echo ${MPOINT}|tr / _)
                        run_command "lvcreate -l $FREEPE -n $LVNAME $VGNAME /dev/$i"
                        # create file system
                        run_command "mkfs -t ${FSTYPE} /dev/$VGNAME/$LVNAME"
                        do_mount /dev/$VGNAME/$LVNAME $MPOINT
                        df -h | grep $MPOINT
                        send_msg "----Finished `date +'%Y-%b-%d %H:%M'`----"
                        exit 0
                fi
        fi
done
#send_msg "No disks found not currently in a volume group!"
exit 1

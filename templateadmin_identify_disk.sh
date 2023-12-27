#!/bin/bash
# script to identify SCSI ID and disk name, required to extend a LV
# =========================================================================
# written     : WK UNIX Team
# Created     : Dec 12 2012
# Last Update : June 28 2015
# -------------------------------------------------------------------------

if echo ${1} | egrep ^/$ 1>/dev/null ; then MPOINT=/; SUFFIXLOGFILE=rootfs;
else
#Prefixing "/" and removing traling "/", if any
if echo ${1} | grep ^/ >/dev/null ; then MPOINT=`echo ${1}` ; else MPOINT=`echo "/${1}"` ; fi
if echo ${MPOINT} | grep /$ >/dev/null ; then MPOINT=$(echo ${MPOINT} | sed 's/\/$//') ; fi

##Removing any / from mountpoint name, just to use it as suffix for log file.
if echo ${MPOINT} | grep ^/ >/dev/null ; then SUFFIXLOGFILE=$(echo ${MPOINT} | sed 's/^\///') ; else SUFFIXLOGFILE=`echo ${1}` ; fi
SUFFIXLOGFILE=$(echo ${SUFFIXLOGFILE} | sed 's/\//_/')
fi

LOG_FILE="identify_disk_${SUFFIXLOGFILE}.out"
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

stdtty OFF

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

if [ "$USER" != "root" ]; then
		stdtty BOTH
        echo "  Please log in with root privileges and try again"
        exit 1
fi

if [ "$#" -ne 1 ]; then
		stdtty BOTH
        cat << EOT1
        This script will identify SCSI ID and disk name, required to extend a LV.

  Usage: $0 mountpoint
EOT1
        exit 2
fi

stdtty OFF
send_msg "----Starting `date +'%Y-%b-%d %H:%M'`----"

stdtty BOTH
#Find lv name from fstab
TLVNAME=$(awk -v MNT=${MPOINT} '$2 == MNT {print $1}' /etc/fstab | grep "^/")
if [ $? != 0 -o ! -n "$TLVNAME" -o $(echo $TLVNAME | wc -w) -ne 1 ]; then
        send_msg "Unable to find a logical volume or mount point doesn't exists in /etc/fstab file, aborting!"
        exit 1
else
        LVNAME=`lvdisplay ${TLVNAME} | awk '/LV Name/{print $NF}'`
        if [ $(echo ${LVNAME} | grep "/") ] ; then LVNAME=`echo ${LVNAME} | awk -F'/' '{print $NF}'` ; fi
        VGNAME=`lvdisplay ${TLVNAME} | awk '/VG Name/{print $NF}'`
        [ -z "${LVNAME}" -o -z "${VGNAME}" ] && send_msg "Either LV ${LVNAME} or VG ${VGNAME} not Found." && exit 1
        send_msg "Found LV ${LVNAME} in VG ${VGNAME} for mount point ${MPOINT}."
fi


###Finding right PV to extend
INVOLVEDPVOFLV=`lvs -o +devices | grep -w ${VGNAME} | grep -w ${LVNAME} | awk '{print $NF}' | awk -F'(' '{print $1}' | awk -F'/' '{print $NF}' | grep -v [0-9]`
[ -z "${INVOLVEDPVOFLV}" ] 2>/dev/null && INVOLVEDPVOFLV=`pvs | grep -w "${VGNAME}" | awk '{print $1}' | awk -F/ '{print $NF}' | grep -v [0-9]`

if [ -z "${INVOLVEDPVOFLV}" ] 2>/dev/null
then
send_msg "NEWDISKREQUIRED: No PV (unpartioned) found for LV ${LVNAME}, Please get a new disk added to extend this LV."
exit 0
else
send_msg "Involved PVs are: ${INVOLVEDPVOFLV}"
fi

for i in ${INVOLVEDPVOFLV}; do
PEOFCURRPV=`pvdisplay /dev/${i} | grep "Total PE" | awk '{print $NF}'`

[ -z ${PEREF} ] && PEREF=${PEOFCURRPV}
[ -z ${SMALLESTPV} ] && SMALLESTPV=${i}

if [ ${PEOFCURRPV} -lt ${PEREF} ]
then
PEREF=${PEOFCURRPV}
SMALLESTPV=${i}
fi
done

##
send_msg "Smallest PV is $SMALLESTPV"

##Checking PV Size
SMALLESTPVSIZE=`pvdisplay --units G /dev/${SMALLESTPV} | awk '/PV Size/''{print $3}' | awk -F'.' '{print $1}'`
send_msg "Smallest PV $SMALLESTPV is of ${SMALLESTPVSIZE}GB"
if [ ${SMALLESTPVSIZE} -ge 500 ] ; then
send_msg "NEWDISKREQUIRED: The Smallest PV ${SMALLESTPV} is already of approx. 500GB or more. Please get a new disk added to expand this LV."
exit 0
fi

##Mapping of OS SCSI id to VM SCSI ID
unset z ; unset OSSCID ; unset ; unset VMSCID ; unset MAPPING
for i in $( cd /sys/block/ ; for i in `ls -d sd*` ; do ls -lad /sys/block/${i}/device | awk -F'/' '{print $NF}' | awk -F':' '{print $1}' ; done | sort -g | uniq )
do
[ -z ${z} ] && z=0
OSSCID[$z]=${i}
VMSCID[$z]=${z}
MAPPING[$z]="s/^${OSSCID[$z]}:/${VMSCID[$z]}:/;"
z=$((${z}+1))
done

##
send_msg "Mappings for OS SCSI id to VM SCSI ID: ${MAPPING[*]}"

##ALL devices without mapping
send_msg "Below are OS SCSI id and their respective device names"
cd /sys/block/ ; for i in `ls -d sd*` ; do echo "`ls -lad /sys/block/${i}/device | awk -F'/' '{print $NF}' | awk -F':' '{print $1":"$3}'` ${i}"; done

send_msg "Below are VM SCSI id and their respective device names"
cd /sys/block/ ; for i in `ls -d sd*` ; do echo "`ls -lad /sys/block/${i}/device | awk -F'/' '{print $NF}' | awk -F':' '{print $1":"$3}'` ${i}"; done | sed "${MAPPING[*]}"

##Final step
OUTPUT=$( cd /sys/block/ ; for i in `ls -d sd*` ; do echo "`ls -lad /sys/block/${i}/device | awk -F'/' '{print $NF}' | awk -F':' '{print $1":"$3}'` ${i}"; done | sed "${MAPPING[*]}" | grep "${SMALLESTPV}$" )

send_msg "VM SCSI ID and device name to extend: ${OUTPUT}"

stdtty OFF
send_msg "----Completed `date +'%Y-%b-%d %H:%M'`----"

stdtty BOTH
echo "${OUTPUT}"
echo "SCSI ID ${OUTPUT}(PV OS DEV NAME)`pvdisplay /dev/${SMALLESTPV} | awk -F'/' '/PV Size/''{print $1}'`"

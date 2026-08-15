#!/usr/bin/env bash 
# script to chroot LUKS/LVM installation
# ver 1.0
#touch /.autorelabel
chroot_dest="/mnt/fedora"
default_disk=''
default_LVroot='root'

#----------------------------------------------------------------------------------------------------------------------------
_EXIST() {
    local cmd
    cmd=$1
    command -v "${cmd}" &>/dev/null && return 0
    return 1
}
#----------------------------------------------------------------------------------------------------------------------------
_HAS_LVM() {
    local device="$1"
    # shellcheck disable=SC2312
    lsblk -nrpo FSTYPE "${device}" 2>/dev/null | grep -iqx 'lvm2_member'
}
#----------------------------------------------------------------------------------------------------------------------------
# shellcheck disable=SC2312
_IS_MOUNTED() {
    local device="${1:-}"
    local path
    local mountpoints

    [[ -n "${device}" ]] || return 2
    [[ -b "${device}" ]] || return 2

    while IFS= read -r path; do
        mountpoints="$(
            lsblk -nrpo MOUNTPOINTS "${path}" 2>/dev/null
        )"

        if [[ -n "${mountpoints}" ]]; then
            return 0
        fi
    done < <(
        lsblk -nrpo PATH "${device}" 2>/dev/null
    )

    return 1
}
#----------------------------------------------------------------------------------------------------------------------------



if [[ "${EUID}" -eq 0 ]]; then
	echo "1) Gathering data..."
# disk
	echo "Disk detected:"
	if _EXIST lsblk; then
		lsblk -dnpo NAME,TYPE,SIZE,MODEL | awk '$2 == "disk" { print "device: " $1 ", model: " $4 $5 $6 $7 $8 $9 $10 $11", size: " $3 }' || true
	else
		echo "lsblk not installed!"
		exit 1
	fi
	echo
	default_disk=$(lsblk -dnp -o NAME)
	if [[ ! -e "${default_disk}" ]]; then
		default_disk=''
	fi	
	str=''
	[[ -n "${default_disk}" ]] && str="[${default_disk}]"
	read -r -p "Disk to be mounted ${str}: " disk
	disk="${disk:-${default_disk}}"
	echo "Selected disk: ${disk}"
	if [[ ! -e "${disk}" ]]; then
		echo "'${disk}' is not a disk device!"
		exit 1
	fi

# LVM	
	if _HAS_LVM "${disk}"; then
		echo
		echo "LVM detected:"
		if _EXIST vgscan; then
			vgscan --mknodes
		else
			echo "vgscan (lvm2) not installed!"
			exit 1
		fi
		if _EXIST vgchange; then
			vgchange -ay			
		else
			echo "vgchange (lvm2) not installed!"
			exit 1
		fi
		if _EXIST udevadm; then
			udevadm settle
		else
			sleep 2
		fi		
		if _EXIST vgs; then
			vgs 
			default_VG=$(vgs -o vg_name --noheadings | xargs || true)
		else
			echo "vgs (lvm2) not installed!"
			exit 1
		fi
		echo
		read -r -p "Volume Group (VG) to be mounted [${default_VG:-VG0}]: " VG
		VG="${VG:-${default_VG:-VG0}}"
		if vgs "${VG}" >/dev/null 2>&1; then
		    echo "Selected VG: ${VG}"
		else
		    echo "'${VG}' is not a Volume Group!"
		    exit 1
		fi
		if _EXIST lvs; then
			lvs "${VG}" -o lv_name,vg_name,lv_size
		else
			echo "lvs (lvm2) not installed!"
			exit 1
		fi
		echo
		read -r -p "Logical Volume (LV) to be mounted as root filesystem [${default_LVroot}]: " LVroot
		LVroot="${LVroot:-${default_LVroot:-root}}"
		if [[ -e /dev/mapper/"${VG}-${LVroot}" ]]; then 
			echo "Selected root LV: /dev/mapper/${VG}-${LVroot}"
		else
			echo "'${LVroot}' is not a Logical Volume!"
			exit 1
		fi		
	fi

	echo; echo "2) Mount point..."
	mkdir -pv "${chroot_dest}"
	
	echo ; echo "3) Decrypt LUKS parts..."
	cryptsetup luksOpen /dev/mapper/"${VG}-${LVroot}" "${LVroot}decrypt"
	if [[ ! -e /dev/mapper/"${LVroot}decrypt" ]]; then 
		echo "Missing /dev/mapper/${LVroot}decrypt, LUKS issue ?"
		exit 1
	fi
	cryptsetup luksOpen /dev/mapper/"${VG}"-varlog varlogdecrypt
	if [[ ! -e /dev/mapper/varlogdecrypt ]]; then
		echo 'Missing /dev/mapper/varlogdecrypt, LUKS issue ?'
		exit 2
	fi
	
	echo ; echo "4) Check parts..."
	if _IS_MOUNTED /dev/mapper/"${LVroot}decrypt"; then 
		echo "/dev/mapper/${LVroot}decrypt is already mounted, cannot check filesystem!"
		exit 1
	else
		echo "Press ENTER to check & fix /dev/mapper/${LVroot}decrypt or CTRL+C to abort..." ; read -r 
		fsck -f -y /dev/mapper/"${LVroot}decrypt"
	fi
	if _IS_MOUNTED /dev/mapper/varlogdecrypt; then 
		echo "/dev/mapper/varlogdecrypt is already mounted, cannot check filesystem!"
		exit 1
	else
		echo "Press ENTER to check & fix /dev/mapper/varlogdecrypt or CTRL+C to abort..." ; read -r 
		fsck -f -y /dev/mapper/varlogdecrypt
	fi
	if _IS_MOUNTED /dev/nvme0n1p2; then 
		echo "/dev/nvme0n1p2 is already mounted, cannot check filesystem!"
		exit 1
	else
		echo "Press ENTER to check & fix /dev/nvme0n1p2 or CTRL+C to abort..." ; read -r 
		fsck -f -y /dev/nvme0n1p2
	fi
	if _IS_MOUNTED /dev/nvme0n1p1; then 
		echo "/dev/nvme0n1p1 is already mounted, cannot check filesystem!"
		exit 1
	else
		echo "Press ENTER to check & fix /dev/nvme0n1p1 or CTRL+C to abort..." ; read -r 
		fsck -f -y /dev/nvme0n1p1
	fi

	echo ; echo "5) Mount parts..."
	mkdir -p "${chroot_dest}"/var/log "${chroot_dest}"/boot/efi
	mount -v /dev/mapper/"${LVroot}decrypt" "${chroot_dest}"
	mount -v /dev/mapper/varlogdecrypt "${chroot_dest}"/var/log
	mount -v /dev/nvme0n1p2 "${chroot_dest}"/boot
	mount -v /dev/nvme0n1p1 "${chroot_dest}"/boot/efi

	echo ; echo "6) Bindmount pseudoFS..."
	mkdir -p "${chroot_dest}"/dev "${chroot_dest}"/proc "${chroot_dest}"/sys "${chroot_dest}"/run 

	mount -v --rbind /dev "${chroot_dest}"/dev
	mount --make-rslave "${chroot_dest}"/dev

	mount -v --rbind /proc "${chroot_dest}"/proc
	mount --make-rslave "${chroot_dest}"/proc

	mount -v --rbind /sys "${chroot_dest}"/sys
	mount --make-rslave "${chroot_dest}"/sys

	mount -v --rbind /run "${chroot_dest}"/run
	mount --make-rslave "${chroot_dest}"/run

	echo ; echo "7) Listing ${chroot_dest}..."
	/usr/bin/ls -alh "${chroot_dest}"
	
	echo ; echo "8) Press ENTER to chroot in ${chroot_dest} or CTRL+C to abort..." ; read -r 
	chroot "${chroot_dest}"

else

	echo "This script must be run as root!"

fi

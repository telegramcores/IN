echo "--- start LVM-service ---"
/etc/init.d/lvm start

disk="/dev/sda"
lvm_group_name = "vg01"
echo "--- clean disk /dev/sda ---"
wipefs -af $disk
echo "--- clear LVM group ---" 
existing_lvm_groups=$(vgs | sed -n 2,\$p | awk '{print $1}')
vgremove -y $existing_lvm_groups

echo "---create sda1 bios_grub ---"
parted -a optimal --script $disk mklabel gpt
parted -a optimal --script $disk mkpart primary 1MiB 3MiB
parted -a optimal --script $disk name 1 grub
parted -a optimal --script $disk set 1 bios_grub on

echo "---create sda2 boot ---"
parted -a optimal --script $disk mkpart primary 3MiB 259MiB
parted -a optimal --script $disk name 2 boot
parted -a optimal --script $disk set 2 boot on

echo "---create sda3 LVM ---"
parted -s -- $disk mkpart primary 259MiB -1MiB
parted -a optimal --script $disk name 3 lvm01
parted -a optimal --script $disk set 3 lvm on


pvcreate -ff /dev/sda3
vgcreate vg01 /dev/sda3

lvcreate -y -L 4096M -n swap vg01
lvcreate -y -l 100%VG -n rootfs vg01

mkfs.fat -F 32 /dev/sda2
mkfs.ext4 /dev/vg01/rootfs
mkswap /dev/vg01/swap
swapon /dev/vg01/swap

mount /dev/vg01/rootfs /mnt/gentoo
mkdir /mnt/gentoo/home

ntpd -q -g

echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

URL='https://mirror.yandex.ru/gentoo-distfiles/releases/amd64/autobuilds'
STAGE3=$(wget $URL/latest-stage3-amd64.txt -qO - | grep -v '#')
wget $URL/$STAGE3
tar xpf stage3-*.tar.* --xattrs-include='*.*' --numeric-owner






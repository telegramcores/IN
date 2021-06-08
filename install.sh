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
parted -s -- $disk unit MB mkpart primary 259 -1
parted -a optimal --script $disk name 3 lvm01
parted -a optimal --script $disk set 3 lvm on


pvcreate -ff /dev/sda3
vgcreate $lvm_group_name /dev/sda3

lvcreate -y -L 4096M -n swap $lvm_group_name
lvcreate -y -l 100%VG -n rootfs $lvm_group_name





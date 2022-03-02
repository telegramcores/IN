echo "--- start LVM-service ---"
/etc/init.d/lvm start

disk="/dev/sda"

swapon /dev/vg01/swap
mount /dev/vg01/rootfs /mnt/gentoo
mount /dev/vg02/devhdd /mnt/gentoo/mnt/HDD

echo -e "\e[31m--- inside chroot ---\e[0m"
chroot_dir=/mnt/gentoo
chroot $chroot_dir /bin/bash << "CHROOT"
env-update && source /etc/profile
export PS1="(chroot) $PS1" 
mount /dev/sda2 /boot
mount -t tmpfs tmpfs -o size=2G,nr_inodes=1M /var/tmp/portage
CHROOT

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
cd /mnt/gentoo
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

echo -e "\e[31m--- Disk System ---\e[0m"
df -h

echo -e "\e[31m--- load Stage3 ---\e[0m"
URL='https://mirror.yandex.ru/gentoo-distfiles/releases/amd64/autobuilds'
STAGE3=$(wget $URL/latest-stage3-amd64.txt -qO - | grep -v '#' | awk '{print $1;}')
wget $URL/$STAGE3
echo -e "\e[31m--- extract Stage3 ---\e[0m"
tar xpf stage3-*.tar.* --xattrs-include='*.*' --numeric-owner


sed -i '/COMMON_FLAGS=/ s/\("[^"]*\)"/\1 -march=native"/' etc/portage/make.conf

mkdir --parents etc/portage/repos.conf
cp usr/share/portage/config/repos.conf etc/portage/repos.conf/gentoo.conf

cp --dereference /etc/resolv.conf etc/

    # mounting livecd folders
mount --types proc  /proc proc
mount --rbind       /sys  sys
mount --make-rslave       sys
mount --rbind       /dev  dev
mount --make-rslave       dev

echo -e "\e[31m--- inside chroot ---\e[0m"
chroot_dir=/mnt/gentoo
chroot $chroot_dir /bin/bash << "CHROOT"
env-update && source /etc/profile
export PS1="(chroot) $PS1" 
mount /dev/sda2 /boot
echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y"' >> /etc/portage/make.conf
echo -e "\e[31m--- emerge-webrsync ---\e[0m"
emerge-webrsync
emerge --oneshot sys-apps/portage
emerge app-portage/gentoolkit
emerge app-portage/cpuid2cpuflags
cpuid2cpuflags | sed 's/: /="/' | sed -e '$s/$/"/' >> /etc/portage/make.conf
#http://lego.arbh.ru/posts/gentoo_upd.html - про обновление toolchain
echo -e "\e[31m--- update @world ---\e[0m"
emerge --update --deep --newuse @world

echo "/dev/sda2 /boot fat32 defaults 0 2" >> /etc/fstab
echo 'ACCEPT_LICENSE="*"'     >> /etc/portage/make.conf
echo 'USE="abi_x86_64"' >> /etc/portage/make.conf
#echo "tmpfs /var/tmp/portage tmpfs size=12G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0" >> /etc/fstab

echo -e "\e[31m--- add soft and settings ---\e[0m"rd.lvm.vg=vg01 rd.lvm.lv=vg01/rootfs rd.lvm.lv=vg01/swap ro rootfstype=ext4 
echo hostname="gentoo" > /etc/conf.d/hostname
blkid | grep 'boot' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t /boot \t swap \t sw \t 0 \t 0@'
blkid | grep 'swap' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t none \t swap \t sw \t 0 \t 0@' >> /etc/fstab
blkid | grep 'ext4' | grep 'rootfs' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t / \t ext4 \t noatime \t 0 \t 1@'>> /etc/fstab
pushd /etc/init.d && ln -s net.lo net.eth0 && rc-update add net.eth0 default && popd
#--- службы ---
emerge app-admin/sysklogd
rc-update add sysklogd default
emerge sys-process/cronie
rc-update add cronie default
emerge net-misc/dhcpcd
rc-update add dhcpcd default
emerge sys-fs/lvm2
rc-update add lvmetad boot
rc-update add udev boot

#--- софт ---
emerge sys-apps/mlocate sys-fs/e2fsprogs tmux htop app-misc/mc

echo 'GRUB_PLATFORMS="emu efi-32 efi-64 pc"' >> /etc/portage/make.conf
echo 'sys-boot/grub:2 device-mapper' >> /etc/portage/package.use/package.use
emerge sys-boot/grub:2
echo 'GRUB_CMDLINE_LINUX_DEFAULT="dolvm"' >> /etc/default/grub

echo -e "\e[31m--- set kernel ---\e[0m"
#emerge sys-kernel/gentoo-kernel-bin
emerge sys-kernel/gentoo-sources
emerge sys-kernel/linux-firmware
emerge --autounmask-write sys-kernel/genkernel
echo -5 | etc-update
emerge sys-kernel/genkernel
eselect kernel set 1

echo -e "\e[31m--- create kernel ---\e[0m"
genkernel --lvm --mountboot --iscsi --busybox all

grub-install --target=$(lscpu | head -n1 | sed 's/^[^:]*:[[:space:]]*//')-efi --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg

CHROOT


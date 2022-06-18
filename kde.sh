echo "--- start LVM-service ---"
/etc/init.d/lvm start

disk="/dev/sda"
# lvm_group_name = "vg01"
echo "--- clean disk /dev/sda ---"
wipefs -af $disk
echo "--- clear LVM group ---" 
existing_lvm_groups=$(vgs | sed -n 2,\$p | awk '{print $1}')
if [ "$existing_lvm_groups" != "" ]
then
vgremove -y $existing_lvm_groups
fi

echo "---create sda1 boot ---"
parted -a optimal --script $disk mklabel gpt
parted -a optimal --script $disk mkpart primary 1MiB 256MiB
parted -a optimal --script $disk name 1 boot
parted -a optimal --script $disk set 1 boot on

echo "---create sda2 LVM (ssd) ---"
parted -s -- $disk mkpart primary 256MiB 90%
parted -a optimal --script $disk name 2 lvm01
parted -a optimal --script $disk set 2 lvm on

echo "---create sda3 LVM (hdd) ---"
parted -s -- $disk mkpart primary 90% -1MiB
parted -a optimal --script $disk name 3 lvm02
parted -a optimal --script $disk set 3 lvm on


pvcreate -ff /dev/sda2
vgcreate vg01 /dev/sda2

pvcreate -ff /dev/sda3
vgcreate vg02 /dev/sda3

lvcreate -y -L 16384M -n swap vg01
lvcreate -y -l 100%VG -n rootfs vg01

lvcreate -y -l 100%VG -n devhdd vg02

mkfs.fat -F 32 /dev/sda1
mkfs.ext4 /dev/vg01/rootfs

mkfs.ext4 /dev/vg02/devhdd

mkswap /dev/vg01/swap
swapon /dev/vg01/swap

mkdir /mnt/gentoo
mount /dev/vg01/rootfs /mnt/gentoo
mkdir /mnt/gentoo/mnt
mkdir /mnt/gentoo/mnt/HDD
mount /dev/vg02/devhdd /mnt/gentoo/mnt/HDD

mkdir /mnt/gentoo/home

ntpd -q -g

echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

echo -e "\e[31m--- Disk System ---\e[0m"
df -h

echo -e "\e[31m--- Copy the DVD to your new filesystem ---\e[0m"
eval `grep '^ROOT_' /usr/share/genkernel/defaults/initrd.defaults`
cd /
cp -avx /$ROOT_LINKS /mnt/gentoo
cp -avx /$ROOT_TREES /mnt/gentoo
mkdir /mnt/gentoo/proc
mkdir /mnt/gentoo/dev
mkdir /mnt/gentoo/sys
mkdir -p /mnt/gentoo/run/udev
tar cvf - -C /dev/ . | tar xvf - -C /mnt/gentoo/dev/
tar cvf - -C /etc/ . | tar xvf - -C /mnt/gentoo/etc/

cd /mnt/gentoo
sed -i '/COMMON_FLAGS=/ s/\("[^"]*\)"/\1 -march=native"/' etc/portage/make.conf

mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

    # mounting livecd folders
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo -e "\e[31m--- inside chroot ---\e[0m"
chroot_dir=/mnt/gentoo
chroot $chroot_dir /bin/bash << "CHROOT"
env-update && source /etc/profile
export PS1="(chroot) $PS1" 
mount /dev/sda1 /boot

cd /dev
rm null 
mknod console c 5 1 
chmod 600 console 
mknod null c 1 3 
chmod 666 null 
mknod zero c 1 5 
chmod 666 zero 
rc-update del autoconfig default
rc-update del fixinittab



# создаем tmpfs
echo "tmpfs /var/tmp/portage tmpfs size=10G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0" >> /etc/fstab
mkdir /var/tmp/portage
mount -t tmpfs tmpfs -o size=10G,nr_inodes=1M /var/tmp/portage
echo -e "\e[31m--- Disk System after tmpfs ---\e[0m"
df -h

############ бинарные пакеты https://www.linux.org.ru/news/gentoo/16547411 ##########################
cat << EOF >> /etc/portage/binrepos.conf
[binhost]
priority = 9999
sync-uri = https://gentoo.osuosl.org/experimental/amd64/binpkg/default/linux/17.1/x86-64/
EOF
# прописываем параметры для бинарных пакетов
echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y --binpkg-respect-use=y --getbinpkg=y"' >> /etc/portage/make.conf
#######################################################
# отключить бинарные пакеты
# echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y"' >> /etc/portage/make.conf
#######################################################
# Московское время
echo "Europe/Moscow" > /etc/timezone
emerge --config sys-libs/timezone-data

echo -e "\e[31m--- emerge-webrsync ---\e[0m"
emerge-webrsync
#eselect news read
emerge --oneshot sys-apps/portage
emerge app-portage/gentoolkit
emerge app-portage/cpuid2cpuflags
cpuid2cpuflags | sed 's/: /="/' | sed -e '$s/$/"/' >> /etc/portage/make.conf
#http://lego.arbh.ru/posts/gentoo_upd.html - про обновление toolchain
#echo -e "\e[31m--- update @world ---\e[0m"
#emerge --update --deep --newuse @world

echo "/dev/sda1 /boot vfat defaults 0 2" >> /etc/fstab
echo 'ACCEPT_LICENSE="*"'     >> /etc/portage/make.conf
echo 'USE="ABI_x86_64"' >> /etc/portage/make.conf


echo -e "\e[31m--- add soft and settings ---\e[0m"
echo hostname="gentoo_kde" > /etc/conf.d/hostname
# blkid | grep 'boot' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t /boot \t swap \t sw \t 0 \t 0@'
blkid | grep 'swap' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t none \t swap \t sw \t 0 \t 0@' >> /etc/fstab
blkid | grep 'ext4' | grep 'rootfs' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t / \t ext4 \t noatime \t 0 \t 1@'>> /etc/fstab
blkid | grep 'ext4' | grep 'devhdd' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t /mnt/HDD \t ext4 \t noatime \t 0 \t 1@'>> /etc/fstab

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
emerge ntp
rc-update add ntpd default

#--- пароль root и запуск ssh ---
echo -e "\e[31m--- root&sshd ---\e[0m"
rc-update add sshd default
#Дополнительные настройки для доступа
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
# sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

#--- софт ---
emerge sys-apps/mlocate sys-fs/e2fsprogs tmux htop app-misc/mc sys-apps/lm-sensors sys-apps/smartmontools app-portage/eix app-misc/colordiff
emerge app-admin/sudo app-admin/eclean-kernel


echo 'GRUB_PLATFORMS="emu efi-32 efi-64 pc"' >> /etc/portage/make.conf
echo 'sys-boot/grub:2 device-mapper' >> /etc/portage/package.use/package.use
emerge sys-boot/grub:2
echo 'GRUB_CMDLINE_LINUX_DEFAULT="dolvm"' >> /etc/default/grub
echo 'GRUB_CMDLINE_LINUX="iommu=pt intel_iommu=on pcie_acs_override=downstream,multifunction nofb"' >> /etc/default/grub



echo -e "\e[31m--- set kernel ---\e[0m"
emerge sys-kernel/linux-firmware
emerge sys-kernel/gentoo-kernel-bin
eselect kernel set 1


echo -e "\e[31m--- create EFI boot ---\e[0m"
#Параметр для EFI
grub-install --target=$(lscpu | head -n1 | sed 's/^[^:]*:[[:space:]]*//')-efi --efi-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg

echo -e "\e[31m--- Check EFI boot ---\e[0m"
################ https://wiki.gentoo.org/wiki/Efibootmgr/ru
efibootmgr -v

CHROOT

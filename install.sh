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

echo "---create sda3 LVM (ssd) ---"
parted -s -- $disk mkpart primary 259MiB 90%
parted -a optimal --script $disk name 3 lvm01
parted -a optimal --script $disk set 3 lvm on

echo "---create sda4 LVM (hdd) ---"
parted -s -- $disk mkpart primary 90% -1MiB
parted -a optimal --script $disk name 4 lvm02
parted -a optimal --script $disk set 4 lvm on


pvcreate -ff /dev/sda3
vgcreate vg01 /dev/sda3

pvcreate -ff /dev/sda4
vgcreate vg02 /dev/sda4

lvcreate -y -L 16384M -n swap vg01
lvcreate -y -l 100%VG -n rootfs vg01

lvcreate -y -l 100%VG -n devhdd vg02

mkfs.fat -F 32 /dev/sda2
mkfs.ext4 /dev/vg01/rootfs

mkfs.ext4 /dev/vg02/devhdd

mkswap /dev/vg01/swap
swapon /dev/vg01/swap

mount /dev/vg01/rootfs /mnt/gentoo

mount /dev/vg02/devhdd /mnt/gentoo/mnt/HDD

mkdir /mnt/gentoo/home

ntpd -q -g
cd /mnt/gentoo
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

echo -e "\e[31m--- Disk System ---\e[0m"
df -h

echo -e "\e[31m--- load Stage3 ---\e[0m"
URL='https://mirror.yandex.ru/gentoo-distfiles/releases/amd64/autobuilds'
STAGE3=$(wget $URL/latest-stage3-amd64-openrc.txt -qO - | grep -v '#' | awk '{print $1;}')
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
# создаем tmpfs
echo "tmpfs /var/tmp/portage tmpfs size=2G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0" >> /etc/fstab
mount -t tmpfs tmpfs -o size=1024M,nr_inodes=1M /var/tmp/portage

############ бинарные пакеты https://www.linux.org.ru/news/gentoo/16547411 ##########################
# cat << EOF >> /etc/portage/binrepos.conf
# [binhost]
# priority = 9999
# sync-uri = https://gentoo.osuosl.org/experimental/amd64/binpkg/default/linux/17.1/x86-64/
# EOF
# прописываем параметры для бинарных пакетов
#echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y --binpkg-respect-use=y --getbinpkg=y"' >> /etc/portage/make.conf
#######################################################
# отключить бинарные пакеты
echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y"' >> /etc/portage/make.conf
#######################################################

echo -e "\e[31m--- emerge-webrsync ---\e[0m"
emerge-webrsync
emerge --oneshot sys-apps/portage
emerge app-portage/gentoolkit
emerge app-portage/cpuid2cpuflags
cpuid2cpuflags | sed 's/: /="/' | sed -e '$s/$/"/' >> /etc/portage/make.conf
#http://lego.arbh.ru/posts/gentoo_upd.html - про обновление toolchain
echo -e "\e[31m--- update @world ---\e[0m"
emerge --update --deep --newuse @world

echo "/dev/sda2 /boot vfat defaults 0 2" >> /etc/fstab
echo 'ACCEPT_LICENSE="*"'     >> /etc/portage/make.conf
echo 'USE="abi_x86_64"' >> /etc/portage/make.conf


echo -e "\e[31m--- add soft and settings ---\e[0m"
echo hostname="gentoo_server" > /etc/conf.d/hostname
blkid | grep 'boot' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t /boot \t swap \t sw \t 0 \t 0@'
blkid | grep 'swap' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t none \t swap \t sw \t 0 \t 0@' >> /etc/fstab
blkid | grep 'ext4' | grep 'rootfs' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t / \t ext4 \t noatime \t 0 \t 1@'>> /etc/fstab

blkid | grep 'ext4' | grep 'devhdd' | sed 's@.*UUID="\([^"]*\)".*@UUID=\1 \t / \t ext4 \t noatime \t 0 \t 1@'>> /etc/fstab

#pushd /etc/init.d && ln -s net.lo net.eth0 && rc-update add net.eth0 default && popd
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

#--- пароль root и запуск ssh ---
echo -e "\e[31m--- root&sshd ---\e[0m"
sed -i 's/everyone/none/' /etc/security/passwdqc.conf
echo -e "1\n1" | passwd root
rc-update add sshd default
#Дополнительные настройки для доступа
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config


################# Настройка bridge ##############################
echo -e "\e[31m--- bridge ---\e[0m"
netcard1=`ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}'| awk 'NR==1'`
netcard2=`ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}'| awk 'NR==2'`
touch /etc/conf.d/net
# если есть вторая сетевая карта
if [ "$netcard2" != "" ]; then
cat << EOF >> /etc/conf.d/net
config_$netcard1="null"
config_$netcard2="null"
bridge_br0="$netcard1 $netcard2"
EOF
rm -f /etc/init.d/net.$netcard1
rm -f /etc/init.d/net.$netcard2
rc-update delete net.$netcard1
rc-update delete net.$netcard2
else
# если только одна сетевая карта
cat << EOF >> /etc/conf.d/net
config_$netcard1="null"
bridge_br0="$netcard1"
config_br0="192.168.1.50/24"
EOF
rm -f /etc/init.d/net.$netcard1
rc-update delete net.$netcard1
fi
cat << EOF >> /etc/conf.d/net
bridge_forward_delay_br0=0
bridge_hello_time_br0=200
bridge_stp_state_br0=0
routes_br0="default gw 192.168.1.1"
EOF
ln -s /etc/init.d/net.lo /etc/init.d/net.br0
rc-update add net.br0


#-- samba ---
emerge net-fs/samba
touch /etc/samba/smb.conf

cat << EOF >> /etc/samba/smb.conf
[GLOBAL]
workgroup = WORKGROUP
server role = standalone server
security = user
browseable = yes
map to guest = Bad User

[share]
path = /mnt/HDD
read only = No
browseable = yes
guest ok = yes
create mask = 0777
directory mask = 0777
EOF

rc-update add samba default


#--- софт ---
emerge sys-apps/mlocate sys-fs/e2fsprogs tmux htop app-misc/mc sys-apps/lm-sensors sys-apps/smartmontools

echo 'GRUB_PLATFORMS="emu efi-32 efi-64 pc"' >> /etc/portage/make.conf
echo 'sys-boot/grub:2 device-mapper' >> /etc/portage/package.use/package.use
emerge sys-boot/grub:2
echo 'GRUB_CMDLINE_LINUX_DEFAULT="dolvm"' >> /etc/default/grub
echo 'GRUB_CMDLINE_LINUX="iommu=pt intel_iommu=on pcie_acs_override=downstream,multifunction nofb"' >> /etc/default/grub

echo -e "\e[31m--- set kernel ---\e[0m"
emerge sys-kernel/linux-firmware
emerge sys-kernel/gentoo-kernel-bin
#emerge sys-kernel/gentoo-sources
emerge --autounmask-write sys-kernel/genkernel
echo -5 | etc-update
emerge sys-kernel/genkernel
eselect kernel set 1

echo -e "\e[31m--- create kernel ---\e[0m"
#genkernel --lvm --mountboot --busybox all

#Параметр для EFI
grub-install --target=$(lscpu | head -n1 | sed 's/^[^:]*:[[:space:]]*//')-efi --efi-directory=/boot
#Параметр для Leagacy
#grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

CHROOT

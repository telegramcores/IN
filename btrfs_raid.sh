#https://github.com/ccie18643/Arch-Linux-install-on-RAID-BTRFS
#https://wiki.polaire.nl/doku.php?id=install_gentoo
#https://btrfs.wiki.kernel.org/index.php/Using_Btrfs_with_Multiple_Devices

disk="/dev/sda"
echo "---create sda1 bios_grub ---"
parted -a optimal --script $disk mklabel gpt
parted -a optimal --script $disk mkpart primary 1MiB 3MiB
parted -a optimal --script $disk name 1 grub
parted -a optimal --script $disk set 1 bios_grub on

echo "---create sda2 boot ---"
parted -a optimal --script $disk mkpart primary 3MiB 259MiB
parted -a optimal --script $disk name 2 boot
parted -a optimal --script $disk set 2 boot on

echo "---create sda3 swap ---"
parted -a optimal --script $disk mkpart primary 259MiB 16GiB
parted -a optimal --script $disk name 3 swap

echo "---create sda4 raid1 ---"
parted -s -- $disk mkpart primary 16GiB 100%
parted -a optimal --script $disk name 4 raid1
parted -a optimal --script $disk set 4 raid on

disk="/dev/sdb"
echo "---create sdb1 bios_grub ---"
parted -a optimal --script $disk mklabel gpt
parted -a optimal --script $disk mkpart primary 1MiB 3MiB
parted -a optimal --script $disk name 1 grub
parted -a optimal --script $disk set 1 bios_grub on

echo "---create sdb2 boot ---"
parted -a optimal --script $disk mkpart primary 3MiB 259MiB
parted -a optimal --script $disk name 2 boot
parted -a optimal --script $disk set 2 boot on

echo "---create sdb3 swap ---"
parted -a optimal --script $disk mkpart primary 259MiB 16GiB
parted -a optimal --script $disk name 3 swap

echo "---create sdb4 raid1 ---"
parted -s -- $disk mkpart primary 16GiB 100%
parted -a optimal --script $disk name 4 raid1
parted -a optimal --script $disk set 4 raid on

mkfs.fat -F32 /dev/sda2
mkfs.fat -F32 /dev/sdb2
mkswap /dev/sda3
swapon /dev/sda3
mkfs.btrfs -L btrfsmirror -m raid1 -d raid1 /dev/sda4 /dev/sdb4

echo "LABEL=btrfsmirror	/mnt/gentoo		btrfs	defaults,noatime	0 0" >> /etc/fstab
mount /mnt/gentoo
btrfs subvolume create /mnt/gentoo/home

ntpd -q -g
cd /mnt/gentoo
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

echo -e "\e[31m--- load Stage3 ---\e[0m"
URL='https://mirror.yandex.ru/gentoo-distfiles/releases/amd64/autobuilds'
STAGE3=$(wget $URL/latest-stage3-amd64-openrc.txt -qO - | grep -v '#' | awk '{print $1;}')
wget $URL/$STAGE3
echo -e "\e[31m--- extract Stage3 ---\e[0m"
tar xpf stage3-*.tar.* --xattrs-include='*.*' --numeric-owner
sed -i '/COMMON_FLAGS=/ s/\("[^"]*\)"/\1 -march=native"/' etc/portage/make.conf

mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# mounting livecd folders
mount --types proc /proc /mnt/gentoo/proc && mount --rbind /sys /mnt/gentoo/sys && mount --make-rslave /mnt/gentoo/sys && mount --rbind /dev /mnt/gentoo/dev && mount --make-rslave /mnt/gentoo/dev && mount --bind /run /mnt/gentoo/run && mount --make-slave /mnt/gentoo/run

echo -e "\e[31m--- inside chroot ---\e[0m"
chroot_dir=/mnt/gentoo
chroot $chroot_dir /bin/bash << "CHROOT"
env-update && source /etc/profile
export PS1="(chroot) $PS1" 
mount /dev/sda2 /boot
# создаем tmpfs
echo "tmpfs /var/tmp/portage tmpfs size=20G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0" >> /etc/fstab
mkdir /var/tmp/portage
mount -t tmpfs tmpfs -o size=20G,nr_inodes=1M /var/tmp/portage

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

echo -e "\e[31m--- emerge-webrsync ---\e[0m"
emerge-webrsync
eselect news read && eselect news purge

# Московское время
echo "Europe/Moscow" > /etc/timezone
emerge --config sys-libs/timezone-data

emerge --oneshot sys-apps/portage
emerge app-portage/gentoolkit
emerge app-portage/cpuid2cpuflags
cpuid2cpuflags | sed 's/: /="/' | sed -e '$s/$/"/' >> /etc/portage/make.conf

echo "/dev/sda2 /boot vfat defaults 0 2" >> /etc/fstab
echo 'ACCEPT_LICENSE="*"'     >> /etc/portage/make.conf
echo 'USE="abi_x86_64"' >> /etc/portage/make.conf

echo -e "\e[31m--- add soft and settings ---\e[0m"
echo hostname="gentoo_s" > /etc/conf.d/hostname
echo "/dev/sda3 none swap sw 0 0" >> /etc/fstab
echo "LABEL=btrfsmirror / btrfs defaults,noatime,compress=lzo,autodefrag,subvol=@  0 0" >> /etc/fstab

#--- службы ---
emerge app-admin/sysklogd && rc-update add sysklogd default
emerge sys-process/cronie && rc-update add cronie default
#emerge net-misc/dhcpcd && rc-update add dhcpcd default
emerge net-misc/ntp && rc-update add ntpd default
emerge sys-fs/btrfs-progs
rc-update add sshd default
#Дополнительные настройки для доступа
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
# sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

################# Настройка bridge ##############################
echo -e "\e[31m--- bridge ---\e[0m"
netcard1=`ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}'| awk 'NR==1'| sed -r 's/^ *//'`
netcard2=`ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}'| awk 'NR==2'| sed -r 's/^ *//'`
touch /etc/conf.d/net
# если есть вторая сетевая карта
if [ "$netcard2" != "" ]
then
cat << EOF >> /etc/conf.d/net
config_$netcard1="null"
config_$netcard2="null"
bridge_br0="$netcard1 $netcard2"
EOF
rm -f /etc/init.d/net.$netcard1
rm -f /etc/init.d/net.$netcard2
else
# если только одна сетевая карта
cat << EOF >> /etc/conf.d/net
config_$netcard1="null"
bridge_br0="$netcard1"
EOF
rm -f /etc/init.d/net.$netcard1
fi
cat << EOF >> /etc/conf.d/net
config_br0="192.168.1.52/24"
bridge_forward_delay_br0=0
bridge_hello_time_br0=200
bridge_stp_state_br0=0
routes_br0="default gw 192.168.1.1"
EOF
ln -s /etc/init.d/net.lo /etc/init.d/net.br0
rc-update add net.br0

touch /etc/resolv.conf
cat << EOF >> /etc/resolv.conf
nameserver 192.168.1.1
EOF

###########################
#-- samba ---

############################


#--- софт ---
emerge sys-apps/mlocate sys-fs/e2fsprogs app-misc/tmux sys-process/htop app-misc/mc sys-apps/lm-sensors sys-apps/smartmontools app-admin/sudo

echo 'GRUB_PLATFORMS="emu efi-32 efi-64 pc"' >> /etc/portage/make.conf
echo 'sys-boot/grub:2 device-mapper' >> /etc/portage/package.use/grub2
emerge sys-boot/grub:2

echo -e "\e[31m--- set kernel ---\e[0m"
emerge sys-kernel/linux-firmware
emerge sys-kernel/gentoo-kernel-bin
dracut -f --kver 5.15.88-gentoo-dist

eselect kernel set 1

echo -e "\e[31m--- create legacy boot ---\e[0m"
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

echo -e "\e[31m--- Последний этап установки! ---\e[0m"
echo -e "\e[31m--- Сделай вход в chroot: chroot /mnt/gentoo ---\e[0m"
echo -e "\e[31m--- Создай пароль root: passwd ---\e[0m"
echo -e "\e[33m--- Создать пользователя: useradd <name> ---\e[0m"
echo -e "\e[33m--- Создать пароль пользователя: passwd <name> ---\e[0m"
echo -e "\e[33m--- Добавить права суперпользователя аналогично root: visudo ---\e[0m"
echo -e "\e[31m--- После ввода пароля наберите exit ---\e[0m"

CHROOT

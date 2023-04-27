#https://btrfs.wiki.kernel.org/index.php/Main_Page
#https://help.ubuntu.ru/wiki/btrfs
#https://github.com/ccie18643/Arch-Linux-install-on-RAID-BTRFS
#https://wiki.polaire.nl/doku.php?id=install_gentoo
#https://btrfs.wiki.kernel.org/index.php/Using_Btrfs_with_Multiple_Devices
#https://wiki.calculate-linux.org/ru/btrfs
#https://linuxhint.com/how-to-use-btrfs-scrub/
#https://ru.phen375questions.com/article/how-to-use-btrfs-balance
#https://pikabu.ru/story/archlinux_ustanovka_sistemyi_na_subvolume_btrfs_8052240
#http://www.bog.pp.ru/work/btrfs.html
#https://dzen.ru/a/XpHXdzePaVeSMFW5
#https://yamadharma.github.io/ru/post/2021/08/27/btrfs-subvolumes/
#BTRFS TOPIC https://github.com/topics/btrfs


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

echo "---create sda4 raid ---"
parted -s -- $disk mkpart primary 16GiB 100%
parted -a optimal --script $disk name 4 btrfsraid
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

echo "---create sdb4 raid ---"
parted -s -- $disk mkpart primary 16GiB 100%
parted -a optimal --script $disk name 4 btrfsraid
parted -a optimal --script $disk set 4 raid on

mkfs.fat -F32 /dev/sda2
mkfs.fat -F32 /dev/sdb2
mkswap /dev/sda3
swapon /dev/sda3
mkfs.btrfs -f -L btrfsraid -m raid10 -d raid10 /dev/sda4 /dev/sdb4

echo "LABEL=btrfsraid /mnt/gentoo btrfs defaults,noatime  0 0" >> /etc/fstab
mount /mnt/gentoo 
btrfs subvolume create /mnt/gentoo/@ 
btrfs subvolume create /mnt/gentoo/@home 
btrfs subvolume create /mnt/gentoo/@var
btrfs subvolume create /mnt/gentoo/@snapshots
btrfs subvolume create /mnt/gentoo/@share
umount /mnt/gentoo

mount -o defaults,noatime,autodefrag,compress=zstd:3,subvol=@ /dev/sda4 /mnt/gentoo
mkdir -p /mnt/gentoo/{home,.snapshots,var,share}
mount -o autodefrag,relatime,space_cache,compress=zstd:3,subvol=@home /dev/sda4 /mnt/gentoo/home
mount -o autodefrag,relatime,space_cache,compress=zstd:3,subvol=@var  /dev/sda4 /mnt/gentoo/var
mount -o autodefrag,relatime,space_cache,compress=zstd:3,subvol=@snapshots  /dev/sda4 /mnt/gentoo/.snapshots
mount -o autodefrag,relatime,space_cache,compress=zstd:3,subvol=@share /dev/sda4 /mnt/gentoo/share

cd /mnt/gentoo
ntpd -q -g
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

echo -e "\e[32m--- load Stage3 ---\e[0m"
URL='https://mirror.yandex.ru/gentoo-distfiles/releases/amd64/autobuilds'
STAGE3=$(wget $URL/latest-stage3-amd64-openrc.txt -qO - | grep -v '#' | awk '{print $1;}')
wget $URL/$STAGE3
echo -e "\e[32m--- extract Stage3 ---\e[0m"
tar xpf stage3-*.tar.* --xattrs-include='*.*' --numeric-owner
sed -i '/COMMON_FLAGS=/ s/\("[^"]*\)"/\1 -march=native"/' etc/portage/make.conf

mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# mounting livecd folders
mount --types proc /proc /mnt/gentoo/proc && mount --rbind /sys /mnt/gentoo/sys && mount --make-rslave /mnt/gentoo/sys && mount --rbind /dev /mnt/gentoo/dev && mount --make-rslave /mnt/gentoo/dev && mount --bind /run /mnt/gentoo/run && mount --make-slave /mnt/gentoo/run

echo -e "\e[32m--- inside chroot ---\e[0m"
chroot_dir=/mnt/gentoo
chroot $chroot_dir /bin/bash << "CHROOT"
env-update && source /etc/profile
export PS1="(chroot) $PS1" 
mount /dev/sda2 /boot

# создаем tmpfs
mkdir /var/tmp/portage
mount -t tmpfs tmpfs -o size=20G,nr_inodes=1M /var/tmp/portage

echo -e "\e[32m--- emerge-webrsync ---\e[0m"
emerge-webrsync 
eselect news read && eselect news purge

echo '############ бинарные пакеты ##########################'
cat << EOF >> /etc/portage/binrepos.conf
[calculate]
priority = 9999
sync-uri = https://mirror.yandex.ru/calculate/grp/x86_64/
[official_test]
priority = 9998
sync-uri = https://gentoo.osuosl.org/experimental/amd64/binpkg/default/linux/17.1/x86-64/
EOF
# прописываем параметры для бинарных пакетов
echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y --binpkg-respect-use=y --getbinpkg=y"' >> /etc/portage/make.conf
#######################################################
# отключить бинарные пакеты
# echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y"' >> /etc/portage/make.conf
#######################################################

# правильный тип процессора в make.conf
emerge app-misc/resolve-march-native
march=`resolve-march-native | head -n1 | awk '{print $1;}'`
sed -i 's/COMMON_FLAGS="-O2 -pipe -march=native"/COMMON_FLAGS="-O2 -pipe '$march'"/g' /etc/portage/make.conf

# Московское время
echo "Europe/Moscow" > /etc/timezone
emerge --config sys-libs/timezone-data

############ руссификация ############################
emerge terminus-font freefonts cronyx-fonts corefonts
rm -f /etc/locale.gen
touch /etc/locale.gen
cat << EOF >> /etc/locale.gen
ru_RU.UTF-8 UTF-8
EOF
locale-gen
rm -f /etc/env.d/02locale
touch /etc/env.d/02locale
cat << EOF >> /etc/env.d/02locale
LC_ALL=""
LANG="ru_RU.UTF-8"
EOF
env-update && source /etc/profile
rm -f /etc/conf.d/consolefont
touch /etc/conf.d/consolefont
cat << EOF >> /etc/conf.d/consolefont
CONSOLEFONT="cyr-sun16"
EOF
rm -f /etc/conf.d/keymaps
touch /etc/conf.d/keymaps
cat << EOF >> /etc/conf.d/keymaps
KEYMAP="ru-ms"
WINDOWKEYS="yes"
DUMPKEYS_CHARSET="koi8-r"
EOF
/etc/init.d/keymaps restart && /etc/init.d/consolefont restart
rc-update add keymaps default
rc-update add consolefont default

emerge --oneshot sys-apps/portage
emerge app-portage/gentoolkit
emerge app-portage/cpuid2cpuflags
cpuid2cpuflags | sed 's/: /="/' | sed -e '$s/$/"/' >> /etc/portage/make.conf
emerge app-shells/bash-completion app-shells/gentoo-bashcomp

echo "/dev/sda2 /boot vfat defaults 0 2" >> /etc/fstab
echo 'ACCEPT_LICENSE="*"'     >> /etc/portage/make.conf
echo 'USE="abi_x86_64 bash-completion unicode"' >> /etc/portage/make.conf

echo -e "\e[32m--- add soft and settings ---\e[0m"
echo hostname="home_s" > /etc/conf.d/hostname
echo "/dev/sda3 none swap sw 0 0" >> /etc/fstab
blkid /dev/sda4 | awk '{print $3" / btrfs defaults,noatime,autodefrag,compress=zstd:3,subvol=@  0 0"}' >> /etc/fstab
blkid /dev/sda4 | awk '{print $3" /home btrfs autodefrag,relatime,space_cache,compress=zstd:3,subvol=@home  0 0"}' >> /etc/fstab
blkid /dev/sda4 | awk '{print $3" /var btrfs autodefrag,relatime,space_cache,compress=zstd:3,subvol=@var  0 0"}' >> /etc/fstab
blkid /dev/sda4 | awk '{print $3" /.snapshots btrfs autodefrag,relatime,space_cache,compress=zstd:3,subvol=@snapshots 0 0"}' >> /etc/fstab
blkid /dev/sda4 | awk '{print $3" /share btrfs autodefrag,relatime,space_cache,compress=zstd:3,subvol=@share  0 0"}' >> /etc/fstab
echo "tmpfs /var/tmp/portage tmpfs size=20G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0" >> /etc/fstab

#--- службы ---
emerge app-admin/sysklogd && rc-update add sysklogd default
emerge sys-process/cronie && rc-update add cronie default
emerge net-misc/dhcpcd && rc-update add dhcpcd default
emerge net-misc/ntp && rc-update add ntpd default
rc-update add udev sysinit
emerge sys-fs/btrfs-progs
rc-update add sshd default
#Дополнительные настройки для доступа
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
# sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

################# Настройка bridge ##############################
echo -e "\e[32m--- bridge ---\e[0m"
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
rc_net_$netcard1_need="udev-settle"
rc_net_$netcard2_need="udev-settle"
EOF
rm -f /etc/init.d/net.$netcard1
rm -f /etc/init.d/net.$netcard2
else
# если только одна сетевая карта
cat << EOF >> /etc/conf.d/net
config_$netcard1="null"
bridge_br0="$netcard1"
rc_net_$netcard1_need="udev-settle"
EOF
rm -f /etc/init.d/net.$netcard1
fi
cat << EOF >> /etc/conf.d/net
config_br0="192.168.1.150/24"
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
chmod 777 /share
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
path = /share
read only = No
browseable = yes
guest ok = yes
create mask = 0777
directory mask = 0777
EOF
rc-update add samba default
############################

#--- софт ---
emerge sys-apps/mlocate sys-fs/e2fsprogs app-misc/tmux sys-process/htop app-misc/mc sys-apps/lm-sensors sys-apps/smartmontools app-admin/sudo sys-fs/ntfs3g app-misc/screen app-portage/eix sys-block/parted
emerge app-eselect/eselect-repository app-portage/layman
emerge sys-fs/duperemove

echo 'GRUB_PLATFORMS="emu efi-32 efi-64 pc"' >> /etc/portage/make.conf
echo 'sys-boot/grub:2 device-mapper' >> /etc/portage/package.use/grub2
emerge sys-boot/grub:2
echo 'GRUB_CMDLINE_LINUX="iommu=pt intel_iommu=on pcie_acs_override=downstream,multifunction nofb"' >> /etc/default/grub

echo -e "\e[32m--- set kernel ---\e[0m"
emerge sys-kernel/linux-firmware
emerge sys-kernel/gentoo-kernel-bin
dracut -f --kver 6.1.22-gentoo-dist
eselect kernel set 1

echo -e "\e[32m--- create EFI boot ---\e[0m"
grub-install --target=$(lscpu | head -n1 | sed 's/^[^:]*:[[:space:]]*//')-efi --efi-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg

echo -e "\e[31m--- Последний этап установки! ---\e[0m"
echo -e "\e[31m--- Сделай вход в chroot: chroot /mnt/gentoo ---\e[0m"
echo -e "\e[31m--- Создай пароль root: passwd ---\e[0m"
echo -e "\e[33m--- Создать пользователя: useradd <name> ---\e[0m"
echo -e "\e[33m--- Создать пароль пользователя: passwd <name> ---\e[0m"
echo -e "\e[33m--- Добавить права суперпользователя аналогично root: visudo ---\e[0m"
echo -e "\e[31m--- После ввода пароля наберите exit ---\e[0m"

CHROOT

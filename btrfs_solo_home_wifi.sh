disk="/dev/nvme0n1"
diskpref=$disk"p"
echo "---create disk1 bios_grub ---"
parted -a optimal --script $disk mklabel gpt
parted -a optimal --script $disk mkpart primary 1MiB 3MiB
parted -a optimal --script $disk name 1 grub
parted -a optimal --script $disk set 1 bios_grub on

echo "---create disk2 boot ---"
parted -a optimal --script $disk mkpart primary 3MiB 259MiB
parted -a optimal --script $disk name 2 boot
parted -a optimal --script $disk set 2 boot on

echo "---create disk3 swap ---"
parted -a optimal --script $disk mkpart primary 259MiB 16GiB
parted -a optimal --script $disk name 3 swap

echo "---create disk4 btrfs ---"
parted -s -- $disk mkpart primary 16GiB 100%
parted -a optimal --script $disk name 4 btrfs
#parted -a optimal --script $disk set 4 raid on

mkfs.fat -F32 $diskpref"2"
mkswap $diskpref"3"
swapon $diskpref"3"
mkfs.btrfs -f $diskpref"4" -L btrfs

echo "LABEL=btrfs /mnt/gentoo btrfs defaults,noatime  0 0" >> /etc/fstab
mount /mnt/gentoo 
btrfs subvolume create /mnt/gentoo/@ 
btrfs subvolume create /mnt/gentoo/@home 
btrfs subvolume create /mnt/gentoo/@var
btrfs subvolume create /mnt/gentoo/@share
btrfs subvolume create /mnt/gentoo/@admman
umount /mnt/gentoo

mount -o defaults,noatime,autodefrag,subvol=@ $diskpref"4" /mnt/gentoo
mkdir -p /mnt/gentoo/{home,var,share,admman}
mount -o autodefrag,noatime,space_cache=v2,compress=zstd:3,subvol=@home $diskpref"4" /mnt/gentoo/home
mount -o autodefrag,noatime,space_cache=v2,compress=zstd:3,subvol=@var  $diskpref"4" /mnt/gentoo/var
mount -o autodefrag,noatime,space_cache=v2,compress=zstd:3,subvol=@share $diskpref"4" /mnt/gentoo/share
mount -o autodefrag,noatime,space_cache=v2,compress=zstd:3,subvol=@admman $diskpref"4" /mnt/gentoo/admman

cd /mnt/gentoo
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

echo -e "\e[31m--- load Stage3 ---\e[0m"
URL='https://mirror.yandex.ru/gentoo-distfiles/releases/amd64/autobuilds'
STAGE3=$(wget $URL/latest-stage3-amd64-openrc.txt -qO - | grep -v '#' | awk '{print $1;}')
wget $URL/$STAGE3
echo -e "\e[31m--- extract Stage3 ---\e[0m"у
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
disk="/dev/nvme0n1"
diskpref=$disk"p"
mount $diskpref"2" /boot

# создаем tmpfs
mkdir /var/tmp/portage
mount -t tmpfs tmpfs -o size=100G,nr_inodes=1M /var/tmp/portage

echo -e "\e[31m--- Обновление emerge-webrsync ---\e[0m"
emerge-webrsync
eselect news read && eselect news purge

echo '############ бинарные пакеты ##########################'
rm /etc/portage/binrepos.conf
cat << EOF >> /etc/portage/binrepos.conf
[calculate]
priority = 9999
sync-uri = https://mirror.calculate-linux.org/grp/x86_64/
EOF
# прописываем параметры для бинарных пакетов
echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y --binpkg-respect-use=y --getbinpkg=y "' >> /etc/portage/make.conf
# echo 'BINPKG_FORMAT="xpak"' >> /etc/portage/make.conf
#######################################################
# отключить бинарные пакеты
# echo 'EMERGE_DEFAULT_OPTS="-j --quiet-build=y --with-bdeps=y"' >> /etc/portage/make.conf
#######################################################


# правильный тип процессора в make.conf
# emerge app-misc/resolve-march-native
# march=`resolve-march-native | head -n1 | awk '{print $1;}'`
# sed -i 's/COMMON_FLAGS="-O2 -pipe -march=native"/COMMON_FLAGS="-O2 -pipe '$march'"/g' /etc/portage/make.conf

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
rc-update add keymaps
rc-update add consolefont

emerge --oneshot sys-apps/portage
emerge app-portage/gentoolkit
emerge app-portage/cpuid2cpuflags
cpuid2cpuflags | sed 's/: /="/' | sed -e '$s/$/"/' >> /etc/portage/make.conf
emerge app-shells/bash-completion app-shells/gentoo-bashcomp

echo '/dev/nvme0n1p2 /boot vfat defaults 0 2' >> /etc/fstab
echo 'ACCEPT_LICENSE="*"'     >> /etc/portage/make.conf
echo 'USE="abi_x86_64 bash-completion unicode"' >> /etc/portage/make.conf

echo -e "\e[31m--- Установка soft and settings ---\e[0m"
echo hostname="gentoo_serv" > /etc/conf.d/hostname
echo '/dev/nvme0n1p3 none swap sw 0 0' >> /etc/fstab
blkid $diskpref'4' | awk '{print $3" / btrfs defaults,noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@  0 0"}' >> /etc/fstab
blkid $diskpref'4' | awk '{print $3" /home btrfs noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@home  0 0"}' >> /etc/fstab
blkid $diskpref'4' | awk '{print $3" /var btrfs noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@var  0 0"}' >> /etc/fstab
blkid $diskpref'4' | awk '{print $3" /share btrfs noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@share  0 0"}' >> /etc/fstab
blkid $diskpref'4' | awk '{print $3" /admman btrfs noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@admman  0 0"}' >> /etc/fstab
echo "tmpfs /var/tmp/portage tmpfs size=100G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0" >> /etc/fstab

#--- службы ---
emerge app-admin/sysklogd && rc-update add sysklogd default
emerge sys-process/cronie && rc-update add cronie default
#emerge net-misc/dhcpcd && rc-update add dhcpcd default
emerge net-misc/ntp && rc-update add ntpd default
rc-update add udev sysinit
emerge sys-fs/btrfs-progs
rc-update add sshd default
#Дополнительные настройки для доступа
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
# sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

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
[admman]
path = /admman
read only = No
browseable = yes
guest ok = yes
create mask = 0777
directory mask = 0777
EOF
rc-update add samba default
############################

#--- софт ---
emerge sys-apps/mlocate sys-fs/e2fsprogs app-misc/tmux sys-process/htop app-misc/mc sys-process/iotop sys-apps/lm-sensors sys-apps/smartmontools app-admin/sudo sys-fs/ntfs3g app-misc/screen app-portage/eix sys-block/parted
emerge app-eselect/eselect-repository sys-process/btop sys-fs/bees sys-fs/compsize app-admin/eclean-kernel net-wireless/wpa_supplicant app-backup/snapper
rc-update add dbus

#настройка wifi
touch /etc/wpa_supplicant/wpa_supplicant.conf
wpa_passphrase Keenetic-4742 zamochek >> /etc/wpa_supplicant/wpa_supplicant.conf
rc-update add wpa_supplicant

echo 'GRUB_PLATFORMS="emu efi-32 efi-64 pc"' >> /etc/portage/make.conf
echo 'sys-boot/grub:2 device-mapper' >> /etc/portage/package.use/grub2
emerge sys-boot/grub:2
echo 'GRUB_CMDLINE_LINUX="iommu=pt intel_iommu=on pcie_acs_override=downstream,multifunction nofb"' >> /etc/default/grub

echo -e "\e[31m--- set kernel ---\e[0m"
emerge sys-kernel/linux-firmware
emerge sys-kernel/gentoo-kernel-bin
dracut -f --kver 6.1.55-gentoo-dist

eselect kernel set 1

echo -e "\e[31m--- create EFI boot ---\e[0m"
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

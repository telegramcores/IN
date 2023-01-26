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

echo "LABEL=btrfsmirror /mnt/gentoo btrfs defaults,noatime  0 0" >> /etc/fstab
mount /mnt/gentoo
cd /mnt/gentoo

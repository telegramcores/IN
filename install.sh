disk="/dev/sda"
lvm_group_name = "vg01"
echo "--- очищаем диск ---"
wipefs -af $disk
echo "--- удаляем LVM группы ---" 
existing_lvm_groups=vgs | sed -n 2,\$p | awk '{print $1}'
vgremove -y $existing_lvm_groups

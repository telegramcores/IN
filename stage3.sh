pushd /mnt/gentoo

    URL='http://mirror.yandex.ru/gentoo-distfiles/releases/amd64/autobuilds' | STAGE3=$(wget $URL/latest-stage3-amd64.txt -qO - | grep -v '#') | wget $URL/$STAGE3 -O -
    tar xpf stage3-*.tar.* --xattrs-include='*.*' --numeric-owner

    # adding -march=native flag
    sed -i '/COMMON_FLAGS=/ s/\("[^"]*\)"/\1 -march=native"/' etc/portage/make.conf
    
    #removing -pipe flag, because we will use tmpfs
    #sed -i '/COMMON_FLAGS=/ s/-pipe//' etc/portage/make.conf


    # selecting mirror interactively
    #mirrorselect -4 -D -s5

    mkdir --parents etc/portage/repos.conf
    cp usr/share/portage/config/repos.conf etc/portage/repos.conf/gentoo.conf

    cp --dereference /etc/resolv.conf etc/

    # mounting livecd folders
    mount --types proc  /proc proc
    mount --rbind       /sys  sys
    mount --make-rslave       sys
    mount --rbind       /dev  dev
    mount --make-rslave       dev

popd

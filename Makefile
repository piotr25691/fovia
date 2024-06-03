# Dependencies required on Arch Linux:
# sudo pacman -S upx musl kernel-headers-musl git make gcc syslinux dosfstools cpio bc
#
# Dependencies required on Ubuntu or Debian:
# sudo apt install upx musl git make syslinux dosfstools cpio bc
#
# sstrip is obtained from https://pts.50.hu/files/sstrip/sstrip-3.0a
# Warning: The certificate for the site given has expired, if you're uncomfortable with it, skip it by removing lines 25-26, 59.

.RECIPEPREFIX := $(.RECIPEPREFIX) 

all:
    make normal || make error

normal: init fetch compile initrd image

init:
    @rm -rf work
    @echo -e "\033[7mChecking dependencies...\033[0m"

    @printf "git... "
    @command -v git || echo "not found"; false
    @printf "musl-gcc (gcc)... "
    @command -v musl-gcc || echo "not found"; false
    @printf "sstrip (from elfkickers)... "
    @command -v sstrip || echo "not found"; false
    @printf "upx... "
    @command -v upx || echo "not found"; false
    @printf "cpio... "
    @command -v cpio || echo "not found"; false
    @printf "extlinux (from syslinux)... "
    @command -v extlinux || echo "not found"; false
    @printf "dosfslabel (from dosfstools)... "
    @command -v dosfslabel || echo "not found"; false
    @printf "bc (a kernel dependency)... "
    @command -v bc || echo "not found"; false

    @echo -e "\033[7mCreating work paths...\033[0m"
    mkdir -pv work work/linux work/busybox work/initrd

fetch:
    @echo -e "\033[7mFetching sources...\033[0m"
    git clone --depth=1 -b v6.9.3 https://github.com/gregkh/linux work/linux
    git clone --depth=1 -b 1_36_0 https://github.com/mirror/busybox work/busybox

compile:
    @echo -e "\033[7mCompiling sources...\033[0m"
    cp -v configs/linux/.config work/linux/.config
    cp -v configs/busybox/.config work/busybox/.config

    @echo -e "\033[7mCompiling Linux...\033[0m"
    yes "n" | make -C work/linux oldconfig
    make KCFLAGS="-Oz" KBUILD_BUILD_HOST="fovia" -C work/linux -j$$(nproc) all

    @echo -e "\033[7mCompiling BusyBox...\033[0m"
    yes "n" | make -C work/busybox oldconfig
    make CC="musl-gcc" -C work/busybox -j$$(nproc) all install

    sstrip work/busybox/_install/bin/busybox
    upx --ultra-brute work/busybox/_install/bin/busybox

initrd:
    @echo -e "\033[7mBuilding initrd...\033[0m"
    tar -xvzf skeleton.tar.gz -C work/initrd

    cp -rv work/busybox/_install/bin work/initrd/bin
    cp -rv work/busybox/_install/sbin work/initrd/sbin
    chmod -Rc 755 work/initrd/bin work/initrd/sbin work/initrd/init

image:
    @echo -e "\033[7mBuilding image...\033[0m"
    dd bs=512 count=5760 if=/dev/zero of=work/fovia.img conv=sparse
    
    mkfs.fat work/fovia.img
    dosfslabel work/fovia.img FOVIA
    mount work/fovia.img /mnt
    
    extlinux --install /mnt

    ( cd work/initrd; find . | cpio -oH newc | xz -9 --check=crc32 > /mnt/initrd )
    cp -v work/linux/arch/x86/boot/bzImage /mnt/vmlinuz
    printf "default fovia\n\nlabel fovia\nlinux /vmlinuz\ninitrd /initrd\n\ntimeout 1" > /mnt/syslinux.cfg

    umount -R /mnt
    mkdir -v out
    mv -v work/fovia.img out/fovia.img

error:
    @echo
    @printf "\033[31mI am scared of building any further, because an error occurred.\nMake sure you've installed the dependencies listed and try again.\n\033[0m"
    @echo
    @exit 1

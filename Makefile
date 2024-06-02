# Dependencies required on Arch Linux:
# sudo pacman -S upx musl kernel-headers-musl git make gcc syslinux dosfstools cpio bc
#
# Dependencies required on Ubuntu or Debian:
# sudo apt install upx musl git make syslinux dosfstools cpio bc
#
# sstrip is obtained from https://pts.50.hu/files/sstrip/sstrip-3.0a
# Warning: The certificate for the site given is expired, if you are uncomfortable, skip it by removing line 51.

.RECIPEPREFIX := $(.RECIPEPREFIX) 
all: init fetch compile initrd image

init:
    @rm -rf work
    @echo "Checking dependencies..."

    @printf "git... "
    @command -v git  # https://github.com/git/git
    @printf "musl-gcc (gcc)... "
    @command -v musl-gcc  # https://github.com/kvinwang/musl-gcc
    @printf "sstrip (from elfkickers)... "
    @command -v sstrip  # https://pts.50.hu/files/sstrip/sstrip-3.0a
    @printf "upx... "
    @command -v upx  # https://github.com/upx/upx
    @printf "cpio... "
    @command -v cpio  # https://mirror.lyrahosting.com/gnu/cpio/cpio-latest.tar.bz2
    @printf "extlinux (from syslinux)... "
    @command -v extlinux  # https://github.com/geneC/syslinux

    @echo "Creating work paths..."
    mkdir -pv work work/linux work/busybox work/initrd

fetch:
    @echo "Fetching sources..."
    git clone --depth=1 -b v6.9.3 https://github.com/gregkh/linux work/linux
    git clone --depth=1 -b 1_36_0 https://github.com/mirror/busybox work/busybox

compile:
    @echo "Compiling sources..."
    cp -v configs/linux/.config work/linux/.config
    cp -v configs/busybox/.config work/busybox/.config

    @echo "Compiling linux..."
    yes "n" | make -C work/linux oldconfig
    make KCFLAGS="-Oz" KBUILD_BUILD_HOST="fovia" -C work/linux -j$$(nproc) all

    @echo "Compiling busybox..."
    yes "n" | make -C work/busybox oldconfig
    make CC="musl-gcc" -C work/busybox -j$$(nproc) all install

    sstrip work/busybox/_install/bin/busybox
    upx --ultra-brute work/busybox/_install/bin/busybox

initrd:
    @echo "Building initrd..."
    tar -xvzf skeleton.tar.gz -C work/initrd

    cp -rv work/busybox/_install/bin work/initrd/bin
    cp -rv work/busybox/_install/sbin work/initrd/sbin
    chmod -Rc 755 work/initrd/bin work/initrd/sbin work/initrd/init

image:
    @echo "Building image..."
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

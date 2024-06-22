# Dependencies required on Arch Linux:
# sudo pacman -S upx musl kernel-headers-musl git make gcc syslinux dosfstools cpio bc pahole
#
# Dependencies required on Ubuntu or Debian:
# sudo apt install upx musl musl-tools git make syslinux dosfstools cpio bc pahole
#
# sstrip is obtained from https://pts.50.hu/files/sstrip/sstrip-3.0a
# Warning: The certificate for the site given has expired, if you're uncomfortable with it, skip it by editing related lines.

.PHONY: all full clean init fetch compile initrd image error
.RECIPEPREFIX := $(.RECIPEPREFIX) 
THREADS := $(shell nproc)

all:
    $(MAKE) full || make error

full: clean init fetch compile initrd image

clean:
    @rm -rf work

init:
    @echo -e "\033[7mChecking dependencies...\033[0m"

    @for dependency in git musl-gcc sstrip upx cpio extlinux dosfslabel bc pahole; do \
        printf "$$dependency... "; \
        command -v $$dependency || ( echo "not found"; false ); \
    done

    @echo -e "\033[7mCreating work paths...\033[0m"
    mkdir -pv work

fetch:
    @echo -e "\033[7mFetching sources...\033[0m"
    git clone --depth=1 -b v6.9.3 https://github.com/gregkh/linux work/linux
    git clone --depth=1 -b 1_36_0 https://github.com/mirror/busybox work/busybox

compile:
    @echo -e "\033[7mCompiling sources...\033[0m"
    cp -v configs/linux/.config work/linux/.config
    cp -v configs/busybox/.config work/busybox/.config

    @echo -e "\033[7mCompiling Linux...\033[0m"
    $(MAKE) -C work/linux oldconfig
    $(MAKE) KCFLAGS="-Oz" KBUILD_BUILD_HOST="fovia" -C work/linux -j$(THREADS) all

    @echo -e "\033[7mCompiling BusyBox...\033[0m"
    $(MAKE) -C work/busybox oldconfig
    $(MAKE) CC="musl-gcc" -C work/busybox -j$(THREADS) all
    $(MAKE) CC="musl-gcc" -C work/busybox -j$(THREADS) all install

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
    # uncomment for serial output
    # printf "default fovia\n\nlabel fovia\nlinux /vmlinuz\ninitrd /initrd\nappend console=ttyS0\n\ntimeout 1" > /mnt/syslinux.cfg

    umount -R /mnt
    mkdir -v out
    mv -v work/fovia.img out/fovia.img

error:
    @echo
    @printf "\033[31mI am scared of building any further, because an error occurred.\nCheck the above error output.\nMake sure you've installed the dependencies listed and try again.\n\033[0m"
    @echo
    @false

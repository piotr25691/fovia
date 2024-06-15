.PHONY: all full fast init fetch compile initrd verify image error
.RECIPEPREFIX := $(.RECIPEPREFIX) 

THREADS := $(shell nproc)

all: 
    $(MAKE) full || $(MAKE) error

# build and do not compile, needs one full make
fast:
    $(MAKE) init initrd verify image || $(MAKE) error

# build and compile
full: clean init fetch compile initrd verify image

# delete work paths
clean:
    rm -rf work

# dependency resolution and build init
init:
    @echo -e "\033[7mChecking dependencies...\033[0m"

    for dependency in git musl-gcc sstrip upx cpio syslinux xorrisofs bc; do \
       printf "$$dependency... "; \
       command -v $$dependency || ( echo "not found"; false ); \
    done

    @echo -e "\033[7mCreating work paths...\033[0m"
    mkdir -pv work

# download sources
fetch:
    @echo -e "\033[7mFetching sources...\033[0m"
    git clone --depth=1 -b v6.9.4 https://github.com/gregkh/linux work/linux
    git clone --depth=1 -b 1_36_stable https://git.busybox.net/busybox work/busybox

# compile sources
compile:
    @echo -e "\033[7mCompiling sources...\033[0m"
    @cp -v configs/linux/.config work/linux/.config
    @cp -v configs/busybox/.config work/busybox/.config

    @echo -e "\033[7mCompiling Linux...\033[0m"
    $(MAKE) -C work/linux oldconfig
    $(MAKE) KCFLAGS="-Oz -pipe" KBUILD_BUILD_HOST="fovia" -C work/linux -j$(THREADS) all

    @echo -e "\033[7mCompiling BusyBox...\033[0m"
    ( cp patches/busybox.patch work/busybox && cd work/busybox && patch -Nup1 -i busybox.patch )
    $(MAKE) -C work/busybox oldconfig
    # determines COMMON_BUFSIZE
    $(MAKE) CC="musl-gcc" -C work/busybox -j$(THREADS) all
    # uses new COMMON_BUFSIZE
    $(MAKE) CC="musl-gcc" -C work/busybox -j$(THREADS) all install
    
    sstrip work/busybox/_install/bin/busybox
    upx --ultra-brute work/busybox/_install/bin/busybox
    
# create initrd fs
initrd:
    @echo -e "\033[7mBuilding initrd...\033[0m"
    @rm -rvf work/initrd && mkdir -pv work/initrd
    tar -xvzf skeleton.tar.gz -C work/initrd

    cp -rv work/busybox/_install/bin work/initrd/bin
    cp -rv work/busybox/_install/sbin work/initrd/sbin
    
    cp -rv rootfs.tar.xz work/initrd/var/rootfs.tar.xz

    # comment to skip modules, might break some features
    $(MAKE) INSTALL_MOD_PATH=../initrd -C work/linux modules_install

    chmod -Rc 755 work/initrd/bin work/initrd/sbin work/initrd/init
    find work/initrd | xargs touch --date=@0
    touch --date=@0 work/linux/arch/x86/boot/bzImage
        
# verify all files
verify:
    @echo -e "\033[7mVerifying files...\033[0m"
    @ls -la work/initrd/bin/busybox
    @ls -la work/linux/arch/x86/boot/bzImage
    @ls -la work/initrd/var/rootfs.tar.xz

# create iso image
image:
    @echo -e "\033[7mBuilding image...\033[0m"
    @rm -rvf work/iso && mkdir -pv work/iso work/iso/boot work/iso/isolinux
        
    ( cd work/initrd; find . | cpio --reproducible -oH newc | xz -9 --check=crc32 > ../iso/boot/initrd )
    
    @cp -pv work/linux/arch/x86/boot/bzImage work/iso/boot/vmlinuz

    @cp -pv /usr/lib/syslinux/bios/isolinux.bin work/iso/isolinux
    @cp -pv /usr/lib/syslinux/bios/ldlinux.c32 work/iso/isolinux
    printf "default fovia\n\nlabel fovia\nlinux /boot/vmlinuz\ninitrd /boot/initrd\nappend rw panic=10\n\ntimeout 1" > work/iso/isolinux/isolinux.cfg

    find work/iso | xargs touch --date=@0
    SOURCE_DATE_EPOCH=0 xorrisofs -U -V FOVIA_BOOTSTRAPPER -o work/fovia.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table work/iso

    @mkdir -pv out
    @mv -v work/fovia.iso out/fovia.iso

error:
    @echo
    @printf "\033[31mI am scared of building any further, because an error occurred.\nCheck the error output above.\nMake sure you have installed the required dependencies, and try again.\n\033[0m"
    @echo
    @false

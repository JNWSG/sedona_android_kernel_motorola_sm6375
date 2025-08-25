#!/bin/bash

# Env & Paths
export KBUILD_BUILD_USER=Moto
export KBUILD_BUILD_HOST=Sedona
export PATH=$PWD/toolchain/bin:$PATH
export LLVM=1 LLVM_IAS=1
export AnyKernel3=AnyKernel3
export modpath=${AnyKernel3}/modules/vendor/lib/modules

# Device & Defconfig
DEVICE="$1"
DEVICES=("bangkk" "corfur" "fogo" "fogos" "penang" "rhodep")

[[ -z "$DEVICE" ]] && { echo "Specify a device: $0 fogos [c]"; exit 1; }
[[ ! " ${DEVICES[*]} " =~ " $DEVICE " ]] && { echo "Device not supported: ${DEVICES[*]}"; exit 1; }

DEFCONFIG="vendor/ext_config/moto-holi-${DEVICE}.config"
ZIPNAME="SEDONA-$DEVICE-$(date '+%Y%m%d-%H%M').zip"

# Toolchain
[ ! -d toolchain ] && git clone --depth=1 https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone toolchain
# Clean build
[[ "$2" == "-c" || "$2" == "--clean" ]] && make O=out clean && rm -rf out/*

# Build Kernel
START=$(date +%s)
make O=out vendor/sedona_defconfig $DEFCONFIG -j$(nproc)
make O=out -j$(nproc)

[[ ! -f "out/arch/arm64/boot/Image" ]] && { echo "ERROR: Image not found!"; exit 1; }

make O=out -j$(nproc) INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install
END=$(date +%s)
ELAPSED=$((END-START))
printf "Kernel built in %02dh %02dm %02ds\n" $((ELAPSED/3600)) $(((ELAPSED%3600)/60)) $((ELAPSED%60))

# AnyKernel3 Setup
[ -d AnyKernel3 ] && git -C AnyKernel3 checkout common &>/dev/null || \
git clone -q https://github.com/Moto-Sedona/AnyKernel3 -b common || { echo "Cannot clone AnyKernel3"; exit 1; }

rm -rf ${modpath}/* ${AnyKernel3}/{Image,dtb,dtbo.img} ${AnyKernel3}/*.zip
mkdir -p ${modpath}

kver=$(make kernelversion)
cp out/arch/arm64/boot/{Image,dtb.img,dtbo.img} ${AnyKernel3}/
cp $(find out/modules/lib/modules/${kver}* -name '*.ko') ${modpath}/
cp out/modules/lib/modules/${kver}*/modules.{alias,dep,softdep} ${modpath}/
cp out/modules/lib/modules/${kver}*/modules.order ${modpath}/modules.load

sed -i 's@\(\S*/\)\([^: ]*\.ko\)@/vendor/lib/modules/\2@g' ${modpath}/modules.dep
sed -i 's/.*\///; s/\.ko$//' ${modpath}/modules.load

# Create Prebuilt Kernel repo
PKR=out/${DEVICE}-kernel
[ -d "${PKR}" ] && rm -rf "${PKR}"
mkdir -p ${PKR}/modules
cp out/arch/arm64/boot/Image ${PKR}/kernel
chmod 775 "$PKR/kernel"
cp out/arch/arm64/boot/dtb.img ${PKR}/dtb.img
cp out/arch/arm64/boot/dtbo.img ${PKR}/dtbo.img
cp $(find out/modules/lib/modules/5.4* -name '*.ko') ${PKR}/modules/

# Zip Kernel
cd ${AnyKernel3}
zip -r9 $ZIPNAME * -x .git README.md *placeholder
cp $ZIPNAME ../out
cd ..
rm -rf ${AnyKernel3}

echo "Kernel successfully built! Find it in out/..."

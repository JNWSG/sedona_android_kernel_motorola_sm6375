#!/bin/bash
export KBUILD_BUILD_USER=Moto
export KBUILD_BUILD_HOST=Sedona
PATH=$PWD/toolchain/bin:$PATH
export LLVM_DIR=$PWD/toolchain/bin
export LLVM=1
export LLVM_IAS=1
export AnyKernel3=AnyKernel3
export TIME="$(date "+%Y%m%d")"
export modpath=${AnyKernel3}/modules/vendor/lib/modules

if [ -z "$1" ]; then
    echo "Error: You should specify the device. Example: $0 fogos [c]"
    exit 1
fi

DEVICE="$1"

case $DEVICE in
    bangkk)
        DEFCONFIG="vendor/bangkk_defconfig"
        ;;
    corfur)
        DEFCONFIG="vendor/corfur_defconfig"
        ;;
    fogos)
        DEFCONFIG="vendor/fogos_defconfig"
        ;;
    penang)
        DEFCONFIG="vendor/penang_defconfig"
        ;;
    rhodep)
        DEFCONFIG="vendor/rhodep_defconfig"
        ;;
    miami)
        DEFCONFIG="vendor/miami_defconfig"
        ;;
    *)
        echo "Error: Device not supported, use one of these: bangkk, corfur, fogos, penang, rhodep, miami."
        exit 1
        ;;
esac

ZIPNAME="SEDONA-$DEVICE-$(date '+%Y%m%d-%H%M').zip"

# Check if there toolchain
if [ ! -d "toolchain" ]; then
    echo "installing toolchain..."
    git clone --depth=1 https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone toolchain
fi

# Clean build option
if [[ "$2" == "-c" || "$2" == "--clean" ]]; then
    echo "Cleaning previous build..."
    make O=out clean
    rm -rf out/*
fi

# Record the start time
START_TIME=$(date +%s)
echo "Starting kernel build for $DEVICE..."

make O=out $DEFCONFIG -j$(nproc --all)
make O=out LLVM=1 LLVM_IAS=1 -j$(nproc --all)

[ ! -e "out/arch/arm64/boot/Image" ] && \
echo "  ERROR : image binary not found in any of the specified locations , fix compile!" && \
exit 1

make O=out LLVM=1 LLVM_IAS=1 -j$(nproc --all) INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

# Record the end time
END_TIME=$(date +%s)

# Calculate elapsed time
ELAPSED_TIME=$((END_TIME - START_TIME))

# Convert seconds to hours, minutes, and seconds
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(((ELAPSED_TIME % 3600) / 60))
SECONDS=$((ELAPSED_TIME % 60))

echo "Kernel build for $DEVICE completed in ${HOURS}h ${MINUTES}m ${SECONDS}s"

echo -e "\nKernel compiled succesfully! Zipping up...\n"

if [ -d "AnyKernel3" ]; then
  git -C AnyKernel3 checkout common &> /dev/null
elif ! git clone -q https://github.com/Moto-Sedona/AnyKernel3 -b common; then
  echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
  exit 1
fi

# Clean Up
rm -rf ${modpath}/*
rm -rf ${AnyKernel3}/{Image, dtb, dtbo.img}
rm -rf ${AnyKernel3}/*.zip

# Setup
mkdir -p ${modpath}
kver=$(make kernelversion)
kmod=$(echo ${kver} | awk -F'.' '{print $3}')

# Copy stuff
cp out/arch/arm64/boot/Image ${AnyKernel3}/Image
cp out/arch/arm64/boot/dtb.img ${AnyKernel3}/dtb
cp out/arch/arm64/boot/dtbo.img ${AnyKernel3}/dtbo.img
cp $(find out/modules/lib/modules/5.4* -name '*.ko') ${modpath}/
cp out/modules/lib/modules/5.4*/modules.{alias,dep,softdep} ${modpath}/
cp out/modules/lib/modules/5.4*/modules.order ${modpath}/modules.load

# Edit
sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' ${modpath}/modules.dep
sed -i 's/.*\///; s/\.ko$//' ${modpath}/modules.load

# Zip
cd ${AnyKernel3}
zip -r9 $ZIPNAME * -x .git README.md *placeholder
cp -r $ZIPNAME ../out
cd ..
rm -rf ${AnyKernel3}
echo -e "\nKernel successfully built! You can find it in out/..."


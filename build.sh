#!/usr/bin/env bash

export BUILDER="Moto"
export HOST="Sedona"
export KDIR=$(pwd)
export OUT_DIR="${KDIR}/out"
export COMPILER="clang"
export TOOLCHAIN_DIR="${KDIR}/${COMPILER}"

msg() { echo -e "\n\e[1;34m[*] $1 \e[0m"; }
success() { echo -e "\n\e[1;32m[✓] $1 \e[0m"; }
warn() { echo -e "\e[1;33m[!] $1 \e[0m"; }
abort() { echo -e "\n\e[1;31m[✗] $1 \e[0m" >&2; exit 1; }

trap 'abort "Operation cancelled by user."' SIGINT

DEVICE="$1"
DEVICES=("bangkk" "corfur" "fogos" "penang" "rhodep")

if [[ -z "$DEVICE" || "$DEVICE" == -* ]]; then
    abort "Usage: $0 <device> [-c|--clean] [-p|--push] [--repo=User/Repo]\nSupported devices: ${DEVICES[*]}"
fi

if [[ ! " ${DEVICES[*]} " =~ " $DEVICE " ]]; then
    abort "Unsupported device: $DEVICE"
fi

shift

CLEAN_BUILD=0
PUSH_BUILD=0
REPO_URL=""

for arg in "$@"; do
    case $arg in
        -c|--clean) CLEAN_BUILD=1 ;;
        -p|--push) PUSH_BUILD=1 ;;
        --repo=*) REPO_URL="${arg#*=}" ;;
    esac
done

if [[ $PUSH_BUILD -eq 1 && -z "$REPO_URL" ]]; then
    REPO_URL="Moto-Sedona/platform_device_motorola_${DEVICE}-kernel"
fi

export DEFCONFIG="vendor/holi-qgki_defconfig vendor/ext_config/sedona.config vendor/ext_config/moto-holi-${DEVICE}.config"

setup_toolchain() {
    if [ ! -f "${TOOLCHAIN_DIR}/bin/${COMPILER}" ]; then
        msg "Downloading LLVM Toolchain..."
        mkdir -p "${TOOLCHAIN_DIR}" || abort "LLVM toolchain directory creation failed!"
        curl -sL https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b/archive/refs/heads/lineage-20.0.tar.gz | \
            tar -xzf - -C "${TOOLCHAIN_DIR}" --strip-components=1 || abort "Failed to download LLVM toolchain!"
    fi

    export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"
    export LLVM=1
    export LLVM_IAS=1
    
    export CC="ccache clang"
    
    KBUILD_COMPILER_STRING=$("${TOOLCHAIN_DIR}/bin/${COMPILER}" -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
    success "Using compiler: ${KBUILD_COMPILER_STRING} (with ccache)"
}

build_kernel() {
    if [[ $CLEAN_BUILD -eq 1 ]]; then
        msg "Cleaning output directory..."
        make O="${OUT_DIR}" clean >/dev/null 2>&1
        rm -rf "${OUT_DIR}"/*
    fi

    msg "Generating defconfig for ${DEVICE}..."
    make O="${OUT_DIR}" CC="${CC}" -j$(nproc --all) $DEFCONFIG || abort "Failed to generate defconfig."

    msg "Building kernel and images..."
    BUILD_START=$(date +"%s")
    
    make O="${OUT_DIR}" CC="${CC}" -j$(nproc --all) || abort "Kernel compilation failed."

    msg "Installing modules..."
    rm -rf "${OUT_DIR}/modules" 
    
    make O="${OUT_DIR}" CC="${CC}" -j$(nproc --all) INSTALL_MOD_PATH="${OUT_DIR}/modules" INSTALL_MOD_STRIP=1 modules_install || abort "Module compilation failed."

    msg "Exporting UAPI headers..."
    make O="${OUT_DIR}" CC="${CC}" -j$(nproc --all) INSTALL_HDR_PATH="${OUT_DIR}/usr" headers_install || abort "Failed to export headers."

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
    success "Kernel built in $((DIFF / 60)) min and $((DIFF % 60)) sec."
}

export_prebuilts() {
    local PREBUILT_DIR="${OUT_DIR}/${DEVICE}-kernel-prebuilts"
    
    if [[ -n "$REPO_URL" ]]; then
        msg "Cloning remote prebuilts repository: ${REPO_URL}..."
        rm -rf "${PREBUILT_DIR}"
        git clone "https://github.com/${REPO_URL}.git" "${PREBUILT_DIR}" || abort "Failed to download prebuilt kernel tree!"
        
        cd "${PREBUILT_DIR}" || abort "Failed to enter cloned repo."
        rm -rf dtb kernel-headers modules Image dtbo.img
        cd "${KDIR}"
    else
        msg "Structuring local prebuilts repository..."
        rm -rf "${PREBUILT_DIR}"
    fi

    mkdir -p "${PREBUILT_DIR}/"{dtb,kernel-headers/usr,modules}

    cp "${OUT_DIR}/arch/arm64/boot/Image" "${PREBUILT_DIR}/Image" || abort "Failed to copy Image."
    cp "${OUT_DIR}/arch/arm64/boot/dtbo.img" "${PREBUILT_DIR}/dtbo.img" 2>/dev/null || warn "dtbo.img not found."
    chmod 775 "${PREBUILT_DIR}/Image"

    find "${OUT_DIR}/arch/arm64/boot/dts" -type f -name "*${DEVICE}*.dtb" -exec cp {} "${PREBUILT_DIR}/dtb/" \;
    find "${OUT_DIR}/modules" -type f -name "*.ko" -exec cp {} "${PREBUILT_DIR}/modules/" \;
    cp -r "${OUT_DIR}/usr/include" "${PREBUILT_DIR}/kernel-headers/usr/"

    find "${PREBUILT_DIR}/kernel-headers" -type f -name ".*.cmd" -delete

    local K_SUBLEVEL=$(grep '^SUBLEVEL =' "${KDIR}/Makefile" | awk '{print $3}')
    [[ -z "$K_SUBLEVEL" ]] && K_SUBLEVEL="0"
    printf "VERSION = 5\nPATCHLEVEL = 4\nSUBLEVEL = %s\n\nheaders_install:\n\t@mkdir -p \$(O)/usr\n\t@rsync -mrq \$(shell pwd)/* \$(O)/\n\nall:\n\t@true\n" "$K_SUBLEVEL" > "${PREBUILT_DIR}/kernel-headers/Makefile"

    if [[ -n "$REPO_URL" ]]; then
        msg "Committing and pushing changes to GitHub..."
        cd "${PREBUILT_DIR}" || abort "Failed to enter prebuilt directory."
        
        git add dtb kernel-headers modules Image dtbo.img || abort "Failed to add files to git."
        
        if ! git diff-index --quiet HEAD --; then
            git commit -s -m "${DEVICE}-kernel: Update prebuilts $(date +'%Y%m%d%H%M')" -m "- Auto-generated by Sedona Builder." || abort "Commit failed."
            git push || abort "Failed to push to remote repository."
            success "Prebuilts successfully updated and pushed!"
        else
            warn "No changes detected, skipping commit and push."
        fi
        
        cd "${KDIR}"
        rm -rf "${PREBUILT_DIR}"
    else
        success "Local prebuilts successfully generated at: ${PREBUILT_DIR}"
    fi
}

setup_toolchain
build_kernel
export_prebuilts

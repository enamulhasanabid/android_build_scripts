#!/bin/bash
#
# Compile script for Stone Kernel
# Copyright (C) 2025 @enamulhasanabid
#

set -e

# =============================================
# CONFIGURATION
# =============================================
KERNEL_REPO="https://github.com/kamikaonashi/private_kernel_stone.git"
KERNEL_BRANCH="16"
KERNEL_DIR="private_kernel_stone"

ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3.git"
ANYKERNEL_DIR="$(pwd)/AnyKernel3"

DEVICE="stone"
OUTPUT_DIR="$(pwd)/out"
ZIP_NAME="stone-kernel-$(date +%Y%m%d-%H%M).zip"

# Toolchain (AOSP Clang 21+ for Android 15)
CLANG_URL="https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379/-/archive/15.0/android_prebuilts_clang_host_linux-x86_clang-r547379-15.0.tar.gz"
CLANG_DIR="$(pwd)/clang"

# Configuration
export KBUILD_BUILD_USER="android-build"
export KBUILD_BUILD_HOST="localhost"
export SOURCE_DATE_EPOCH=$(date +%s)
export BUILD_REPRODUCIBLE=1
JOBS=$(nproc --all)

# AnyKernel3 Configuration Variables
AK3_KERNEL_STRING="Darkmoon"
AK3_DO_DEVICECHECK=1
AK3_DEVICE_NAME1="moonstone"
AK3_DEVICE_NAME2="sunstone"
AK3_DEVICE_NAME3="gemstone"
AK3_DEVICE_NAME4="stone"
AK3_DO_CLEANUP=1

# =============================================
# PRE-BUILD SETUP
# =============================================
echo "=== Kernel Build Script ==="
echo "Device: $DEVICE"
echo "CPU Cores: $JOBS"
echo "Build User: $KBUILD_BUILD_USER"
echo "Build Host: $KBUILD_BUILD_HOST"

# libxml2 workaround
if ! ldconfig -p | grep -q "libxml2.so.2"; then
    echo "Applying libxml2 workaround..."
    sudo ln -sf /usr/lib/libxml2.so.16 /usr/lib/libxml2.so.2
    sudo ldconfig
fi

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf "$OUTPUT_DIR" "$ANYKERNEL_DIR"
mkdir -p "$OUTPUT_DIR"

# =============================================
# TOOLCHAIN
# =============================================
if [ ! -d "$CLANG_DIR" ]; then
    echo "Downloading and extracting Clang toolchain..."
    mkdir -p "$CLANG_DIR"
    curl -L "$CLANG_URL" | tar xz -C "$CLANG_DIR" --strip-components=1
fi

export PATH="$CLANG_DIR/bin:$PATH"
echo "Toolchain path: $CLANG_DIR"

# =============================================
# KERNEL SOURCE
# =============================================
if [ ! -d "$KERNEL_DIR" ]; then
    echo "Cloning kernel source..."
    git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
else
    echo "Updating kernel source..."
    cd "$KERNEL_DIR"
    git reset --hard
    git clean -fdx
    git pull
    cd ..
fi

# =============================================
# ANYKERNEL3 SETUP
# =============================================
echo "Setting up AnyKernel3..."
[ ! -d "$ANYKERNEL_DIR" ] && rm -rf "$ANYKERNEL_DIR"
git clone --depth=1 "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"

# Configure AnyKernel3 script
echo "Rewriting anykernel.sh with custom configuration..."
cat > "$ANYKERNEL_DIR/anykernel.sh" <<EOF
#!/bin/bash

### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=$AK3_KERNEL_STRING
do.devicecheck=$AK3_DO_DEVICECHECK
device.name1=$AK3_DEVICE_NAME1
device.name2=$AK3_DEVICE_NAME2
device.name3=$AK3_DEVICE_NAME3
device.name4=$AK3_DEVICE_NAME4
do.cleanup=$AK3_DO_CLEANUP
'; }
# end properties

### AnyKernel install
# boot shell variables
block=boot;
is_slot_device=auto;
no_block_display=1;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
split_boot;
flash_boot;
## end boot install
EOF

# Make the script executable
chmod +x "$ANYKERNEL_DIR/anykernel.sh"

# =============================================
# BUILD CONFIGURATION
# =============================================
cd "$KERNEL_DIR"
echo "Configuring kernel..."

# Clean thoroughly
make ARCH=arm64 distclean
make ARCH=arm64 mrproper
git clean -fdx
git reset --hard

# Environment hardening
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CC="clang"
export LD="ld.lld"
export AR="llvm-ar"
export NM="llvm-nm"
export STRIP="llvm-strip"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export CLANG_TRIPLE="aarch64-linux-gnu-"
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"

# Force stealth config
echo "CONFIG_LOCALVERSION=\"-secure\"" > "$OUTPUT_DIR/.config"
make O="$OUTPUT_DIR" stone_defconfig

# =============================================
# COMPILATION
# =============================================
echo "Starting compilation..."
echo "Using jobs: $JOBS"
make O="$OUTPUT_DIR" -j"$JOBS" \
    LOCALVERSION= \
    KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
    KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST"

# Verify build
if [ ! -f "$OUTPUT_DIR/arch/arm64/boot/Image" ]; then
    echo "Error: Kernel Image not found!"
    exit 1
fi

# Identity leaks validation
#echo "Checking for identity leaks in binary..."
#if strings "$OUTPUT_DIR/arch/arm64/boot/Image" | grep -i "$(whoami)\|$(hostname)"; then
#    echo "WARNING: Personal identifiers detected in binary!"
#    exit 1
#else
#    echo "Binary clean - no personal identifiers found"
#fi

# =============================================
# PACKAGE
# =============================================
echo "Preparing AnyKernel3 package..."

# Validate AnyKernel3 directory
if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo "Error: AnyKernel3 directory missing!"
    exit 1
fi

echo "Copying build artifacts..."
cp -v "$OUTPUT_DIR/arch/arm64/boot/Image" "$ANYKERNEL_DIR/"
[ -f "$OUTPUT_DIR/arch/arm64/boot/dtbo.img" ] && cp -v "$OUTPUT_DIR/arch/arm64/boot/dtbo.img" "$ANYKERNEL_DIR/"

echo "Creating flashable zip..."
cd "$ANYKERNEL_DIR"
zip -r9 "../$ZIP_NAME" * -x '*.git*' '*.md' '*.placeholder'
cd ..

echo "=== Build Complete ==="
echo "Flashable zip: $ZIP_NAME"
echo "Build User: $KBUILD_BUILD_USER"
echo "Build Host: $KBUILD_BUILD_HOST"

#!/bin/bash
#
# Compile script for Stone Kernel
# Copyright (C) 2025 @enamulhasanabid
#

set -e

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================
# DIRECTORY STRUCTURE SETUP
# =============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
SOURCE_DIR="${BUILD_DIR}/source"
OUTPUT_DIR="${BUILD_DIR}/out"
RELEASE_DIR="${SCRIPT_DIR}/release"

# Create directories if they don't exist
mkdir -p "${SOURCE_DIR}" "${OUTPUT_DIR}" "${RELEASE_DIR}"

# =============================================
# CONFIGURATION
# =============================================
echo -e "${BLUE}================================================================================${NC}"
echo "                  Kernel Build Script by @enamulhasanabid for Stone"
echo -e "${BLUE}================================================================================${NC}"
echo
echo -e "${RED}Note: This script is configured for building the 'stone' kernel.${NC}"
echo "  If building for a different device, you'll need to modify:"
echo "          1. The make commands (stone_defconfig, etc.)"
echo "          2. AnyKernel3 device names and configurations"
echo
echo
echo -e "${RED}Note:To modify AnyKernel3 variables, please edit this script directly${NC}"
echo
echo -e "${YELLOW}Current AnyKernel3 settings:${NC}"
echo "Kernel String: Darkmoon"
echo "Devices: moonstone, sunstone, stone"
echo "Cleanup: enabled"
echo "Device Check: enabled"
echo -e ${BLUE}"================================================================================${NC}"
echo

# Start build timer
START_TIME=$(date +%s)

# Prompt user for kernel repository and branch
read -p "Enter Kernel Repository URL [default: https://github.com/kamikaonashi/private_kernel_stone.git]: " KERNEL_REPO
KERNEL_REPO=${KERNEL_REPO:-"https://github.com/kamikaonashi/private_kernel_stone.git"}

read -p "Enter Kernel Branch [default: 16]: " KERNEL_BRANCH
KERNEL_BRANCH=${KERNEL_BRANCH:-"16"}

# Prompt for Clang URL and ZIP Name
read -p "Enter Clang Toolchain URL [default: https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379/-/archive/15.0/android_prebuilts_clang_host_linux-x86_clang-r547379-15.0.tar.gz]: " CLANG_URL
CLANG_URL=${CLANG_URL:-"https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379/-/archive/15.0/android_prebuilts_clang_host_linux-x86_clang-r547379-15.0.tar.gz"}

read -p "Enter Output ZIP Name [default: stone-kernel]: " ZIP_BASE_NAME
ZIP_BASE_NAME=${ZIP_BASE_NAME:-"stone-kernel"}
ZIP_NAME="${ZIP_BASE_NAME}-$(date +%Y%m%d-%H%M).zip"

KERNEL_DIR="${SOURCE_DIR}/private_kernel_stone"
ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3.git"
ANYKERNEL_DIR="${SOURCE_DIR}/AnyKernel3"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
CLANG_DIR="${SOURCE_DIR}/clang"

# Configuration
export KBUILD_BUILD_USER="android-build"
export KBUILD_BUILD_HOST="localhost"
export SOURCE_DATE_EPOCH=$(date +%s)
export BUILD_REPRODUCIBLE=1
JOBS=$(nproc --all)

# AnyKernel3 Configuration Variables
AK3_KERNEL_STRING="Darkmoon"
AK3_DEVICE_NAME1="moonstone"
AK3_DEVICE_NAME2="sunstone"
AK3_DEVICE_NAME3="stone"
AK3_DEVICE_NAME4=
AK3_DO_CLEANUP=1
AK3_DO_CLEANUP_UPON_ABORT=0
AK3_DO_DEVICECHECK=1
AK3_DO_MODULES=0
AK3_DO_SYSTEMLESS=1
AK3_SUPPORTED_VERSION=
AK3_SUPPORTED_PATCHLEVELS=

# =============================================
# PRE-BUILD SETUP
# =============================================
echo
echo -e "${GREEN}=== Kernel Build Information ===${NC}"
echo
echo "Device: stone"
echo "CPU Cores: $JOBS"
echo "Build User: $KBUILD_BUILD_USER"
echo "Build Host: $KBUILD_BUILD_HOST"
echo "Kernel Repo: $KERNEL_REPO"
echo "Kernel Branch: $KERNEL_BRANCH"
echo "Build Directory: $BUILD_DIR"
echo "Source Directory: $SOURCE_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Release Directory: $RELEASE_DIR"
echo
echo -e "${GREEN}================================${NC}"

# Check for required commands
for cmd in git curl tar unzip ldconfig make find strings; do
    if ! command -v "$cmd" &> /dev/null; then
        if [ "$cmd" != "strings" ]; then
            echo -e "${RED}Error: Required command '$cmd' not found.${NC}"
            exit 1
        else
            echo -e "${YELLOW}Warning: 'strings' command not found (leak checks disabled)${NC}"
        fi
    fi
done

# Verify disk space (minimum 10GB free)
REQ_SPACE=10000000
AVAIL_SPACE=$(df "$BUILD_DIR" | awk 'NR==2 {print $4}')
if [ "$AVAIL_SPACE" -lt "$REQ_SPACE" ]; then
    echo -e "${YELLOW}Warning: Low disk space (${AVAIL_SPACE}KB available, ${REQ_SPACE}KB recommended)${NC}"
fi

# libxml2 workaround - dynamic version detection
if ! ldconfig -p | grep -q "libxml2.so.2"; then
    echo
    echo -e "${YELLOW}Applying libxml2 workaround...${NC}"
    echo
    latest_libxml=$(find /usr/lib -name "libxml2.so.*" 2>/dev/null | grep -E 'libxml2\.so\.[0-9]+$' | sort -V | tail -1)
    if [ -n "$latest_libxml" ]; then
        if command -v sudo &> /dev/null; then
            sudo ln -sf "$latest_libxml" /usr/lib/libxml2.so.2
            sudo ldconfig
        else
            echo -e "${YELLOW}Warning: sudo not available, libxml2 workaround skipped${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: No libxml2.so found in /usr/lib${NC}"
    fi
fi

# Clean previous builds
echo
echo -e "${YELLOW}Cleaning previous builds...${NC}"
echo
rm -rf "${OUTPUT_DIR}" "${ANYKERNEL_DIR}"
mkdir -p "${OUTPUT_DIR}"

# =============================================
# TOOLCHAIN
# =============================================
if [ ! -d "$CLANG_DIR" ]; then
    echo
    echo -e "${YELLOW}Downloading and extracting Clang toolchain...${NC}"
    echo
    mkdir -p "$CLANG_DIR"
    if [[ "$CLANG_URL" == *.tar.gz ]]; then
        if ! curl -L "$CLANG_URL" | tar xz -C "$CLANG_DIR" --strip-components=1; then
            echo -e "${RED}Error: Clang extraction failed${NC}"
            exit 1
        fi
    elif [[ "$CLANG_URL" == *.zip ]]; then
        temp_zip="${CLANG_DIR}/clang.zip"
        if ! curl -L "$CLANG_URL" -o "$temp_zip"; then
            echo -e "${RED}Error: Failed to download Clang zip${NC}"
            exit 1
        fi
        if ! unzip "$temp_zip" -d "$CLANG_DIR/temp"; then
            echo -e "${RED}Error: Failed to unzip Clang${NC}"
            exit 1
        fi
        mv "$CLANG_DIR"/temp/*/* "$CLANG_DIR/" 2>/dev/null || true
        rm -rf "$temp_zip" "$CLANG_DIR/temp"
    fi

    # Verify Clang extraction
    if [ ! -f "$CLANG_DIR/bin/clang" ]; then
        echo -e "${RED}Error: Clang extraction failed or is corrupted${NC}"
        exit 1
    fi
fi

export PATH="$CLANG_DIR/bin:$PATH"
echo "Toolchain path: $CLANG_DIR"

# =============================================
# KERNEL SOURCE
# =============================================
if [ ! -d "$KERNEL_DIR" ]; then
    echo
    echo -e "${YELLOW}Cloning kernel source...${NC}"
    echo
    if ! git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"; then
        echo -e "${RED}Error: Failed to clone kernel source${NC}"
        exit 1
    fi
else
    echo
    echo -e "${YELLOW}Updating kernel source...${NC}"
    echo
    cd "$KERNEL_DIR"
    if ! git fetch origin "$KERNEL_BRANCH"; then
        echo -e "${RED}Error: Failed to fetch kernel updates${NC}"
        exit 1
    fi
    git reset --hard origin/"$KERNEL_BRANCH"
    git clean -fdx
    cd ..
fi

# =============================================
# ANYKERNEL3 SETUP
# =============================================
echo
echo -e "${YELLOW}Setting up AnyKernel3...${NC}"
echo
rm -rf "$ANYKERNEL_DIR"
if ! git clone --depth=1 "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"; then
    echo -e "${RED}Error: Failed to clone AnyKernel3${NC}"
    exit 1
fi

# Configure AnyKernel3 script
echo
echo -e "${YELLOW}Rewriting anykernel.sh with custom configuration...${NC}"
echo
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
do.cleanuponabort=$AK3_DO_CLEANUP_UPON_ABORT
supported.versions=$AK3_SUPPORTED_VERSION
supported.patchlevels=$AK3_SUPPORTED_PATCHLEVELS
do.modules=$AK3_DO_MODULES
do.systemless=$AK3_DO_SYSTEMLESS
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
echo
echo -e "${YELLOW}Configuring kernel...${NC}"
echo

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

# Make Config
echo "CONFIG_LOCALVERSION=\"-secure\"" > "$OUTPUT_DIR/.config"
if ! make O="$OUTPUT_DIR" stone_defconfig; then
    echo -e "${RED}Error: Failed to configure kernel${NC}"
    exit 1
fi

# =============================================
# COMPILATION
# =============================================
echo
echo
echo -e "${YELLOW}Starting compilation...${NC}"
echo -e "${YELLOW}Using nproc: $JOBS${NC}"
echo
echo
if ! make O="$OUTPUT_DIR" -j"$JOBS" \
    LOCALVERSION= \
    KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
    KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST"; then
    echo -e "${RED}Error: Kernel compilation failed${NC}"
    exit 1
fi

# Verify build
if [ ! -f "$OUTPUT_DIR/arch/arm64/boot/Image" ]; then
    echo
    echo -e "${RED}Error: Kernel Image not found!${NC}"
    echo
    exit 1
fi

# Show build artifacts
echo
echo -e "${YELLOW}Build artifacts:${NC}"
ls -lh "$OUTPUT_DIR/arch/arm64/boot/"Image*

# Identity leaks validation
echo
echo -e "${YELLOW}Checking for identity leaks in binary...${NC}"
echo
if command -v strings &> /dev/null; then
    if leaks=$(strings "$OUTPUT_DIR/arch/arm64/boot/Image" | grep -i "$(whoami)\|$(hostname)"); then
        echo -e "${YELLOW}Warning: Potential personal identifiers in binary:${NC}"
        echo
        echo "$leaks"
        echo
        echo -e "${YELLOW}Consider rebuilding with clean environment.${NC}"
    else
        echo -e "${GREEN}Binary clean - no personal identifiers found${NC}"
    fi
fi
# =============================================
# PACKAGE
# =============================================
echo
echo -e "${YELLOW}Preparing AnyKernel3 package...${NC}"
echo
# Validate AnyKernel3 directory
if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo
    echo -e "${RED}Error: AnyKernel3 directory missing!${NC}"
    echo
    exit 1
fi
echo
echo -e "${YELLOW}Copying build artifacts...${NC}"
echo
cp -v "$OUTPUT_DIR/arch/arm64/boot/Image" "$ANYKERNEL_DIR/"
[ -f "$OUTPUT_DIR/arch/arm64/boot/dtbo.img" ] && cp -v "$OUTPUT_DIR/arch/arm64/boot/dtbo.img" "$ANYKERNEL_DIR/"
[ -f "$OUTPUT_DIR/arch/arm64/boot/dtb.img" ] && cp -v "$OUTPUT_DIR/arch/arm64/boot/dtb.img" "$ANYKERNEL_DIR/"

echo
echo -e "${YELLOW}Creating flashable zip...${NC}"
echo
cd "$ANYKERNEL_DIR"
if ! zip -r9 "${ZIP_PATH}" * -x '*.git*' '*.md' '*.placeholder'; then
    echo -e "${RED}Error: Failed to create zip file${NC}"
    exit 1
fi
cd ..

# =============================================
# FINAL OUTPUT
# =============================================
echo
echo -e "${GREEN}=== Build Complete ===${NC}"
echo "Flashable zip created at: ${ZIP_PATH}"
echo "File size: $(du -h "${ZIP_PATH}" | cut -f1)"
echo "Build User: $KBUILD_BUILD_USER"
echo "Build Host: $KBUILD_BUILD_HOST"
echo "Build duration: $(($(date +%s) - START_TIME)) seconds"
echo

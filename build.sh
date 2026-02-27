#!/bin/bash

set -euo pipefail

ROOT_DIR="$(pwd)"
OUT_DIR="$ROOT_DIR/out"
DEFCONFIG="${2:-begonia_user_defconfig}"
TOOLCHAIN_DIR="$ROOT_DIR/toolchain/clang"
LOG_FILE="$ROOT_DIR/build_log.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

msg() { echo -e "${GREEN}[+] $1${NC}"; }
err() { echo -e "${RED}[!] $1${NC}"; exit 1; }

setup_env() {
    export ARCH=arm64
    export SUBARCH=arm64
    export KBUILD_BUILD_USER="opencode"
    export KBUILD_BUILD_HOST="archlinux"
    export PATH="$PATH:$TOOLCHAIN_DIR/bin"
    export CC=clang
    export HOSTCC=gcc
    export HOSTCXX=g++
    export HOSTLD=ld.bfd
    export LLVM=1
    export LLVM_IAS=1
    export CROSS_COMPILE=aarch64-linux-gnu-
    export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
}

clean_build() {
    msg "Cleaning output and build log"
    rm -rf "$OUT_DIR" "$LOG_FILE"
}

build_kernel() {
    [ -x "$TOOLCHAIN_DIR/bin/clang" ] || err "Missing clang toolchain at $TOOLCHAIN_DIR"

    setup_env
    mkdir -p "$OUT_DIR"

    msg "Generating config: $DEFCONFIG"
    make O="$OUT_DIR" "$DEFCONFIG"

    if [ -f "$ROOT_DIR/scripts/config" ]; then
        "$ROOT_DIR/scripts/config" --file "$OUT_DIR/.config" -d LLVM_POLLY
        make O="$OUT_DIR" olddefconfig
    fi

    msg "Compiling kernel with clang"
    make -j"$(nproc)" O="$OUT_DIR" \
        CC=clang LLVM=1 LLVM_IAS=1 \
        AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump STRIP=llvm-strip LD=ld.lld \
        2>&1 | tee "$LOG_FILE"

    if [ -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]; then
        msg "Build successful"
        msg "Kernel image: $OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    else
        err "Build failed, check $LOG_FILE"
    fi
}

case "${1:-}" in
    -b|--build)
        build_kernel
        ;;
    -c|--clean)
        clean_build
        ;;
    -cb|--clean-build)
        clean_build
        build_kernel
        ;;
    *)
        echo "Usage: $0 [option] [defconfig]"
        echo "  -b,  --build        Build kernel"
        echo "  -c,  --clean        Remove out/ and build_log.txt"
        echo "  -cb, --clean-build  Clean then build"
        exit 1
        ;;
esac

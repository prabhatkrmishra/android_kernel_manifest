#!/bin/bash
# msm-4.19 kernel build with config fragments.
# Merges a base defconfig with config fragments, then builds the kernel
# out-of-tree. The source tree is only read from, never written to.
# All output goes to ./out/.
#
# After syncing, the tree root holds root-level shortcuts (created by the
# manifest): ./build runs this script, and plain `make` runs its Makefile.
#   ./build kernel
#   ./build kernel @X00TD/FRAGMENTS
#   make kernel
# TREE_TOP is detected automatically (parent of this script's directory);
# export it only to build against a different tree.
# Paths you pass (@file, --config) are read from where you invoke.
# The bundled X00TD/FRAGMENTS default needs no path at all.
#
# Usage:
#   ./build config [base_defconfig] [fragment...]
#   ./build config @fragments-file
#   ./build kernel [base_defconfig] [fragment...]
#   ./build kernel @fragments-file
#   ./build kernel --config path/to/.config
#   ./build menuconfig
#   ./build clean
#   ./build mrproper
#
# Fragments:
#   Passed on the command line when given, otherwise taken from FRAGMENTS
#   in the environment, otherwise read from X00TD/FRAGMENTS next to this
#   script. The first entry is the base defconfig, every following
#   *.config entry is merged in order via merge_config.sh -m, each followed
#   by olddefconfig. @path/to/file reads the list from a file instead
#   (one fragment per line, # comments allowed).
#
# Full config:
#   With --config <file>, the given file is used as the complete .config
#   (copied to the output dir, then olddefconfig). No merging happens.
#
# Examples (run from the synced tree root):
#   ./build config vendor/my_defconfig vendor/my.config
#   ./build kernel @tools/kernel-build/X00TD/FRAGMENTS
#   ./build kernel --config ~/my-full.config
#   ./build kernel   # bundled default list
set -e
INVOKED_DIR=$PWD
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]:-$0}")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
cd "$SCRIPT_DIR"
STANDALONE_TOP=$(pwd)

# Paths you pass (@file, --config) resolve from where you invoke the script.
# Paths bundled with the script (X00TD/FRAGMENTS default) resolve next to it.
resolve_invoked() {
  case "$1" in /*) printf '%s' "$1";; *) printf '%s' "$INVOKED_DIR/$1";; esac
}

# --- settings: everything derives from the environment ---
# TREE_TOP points at the synced tree root (kernel source + prebuilts).
# An explicit TREE_TOP (or legacy LINEAGE_TOP) always wins; otherwise the
# parent of this script's directory is used when it looks like a tree root.
TREE_TOP=${TREE_TOP:-${LINEAGE_TOP:-}}
if [ -z "$TREE_TOP" ]; then
  D=$SCRIPT_DIR
  for _ in 1 2 3; do
    if [ -d "$D/kernel" ] && [ -d "$D/prebuilts" ]; then TREE_TOP=$D; break; fi
    D=$(dirname "$D")
  done
  if [ -z "$TREE_TOP" ]; then
    echo "ERROR: TREE_TOP not set and no tree root detected." >&2
    echo "Export it explicitly: export TREE_TOP=<synced tree root>" >&2
    exit 1
  fi
fi
[ -d "$TREE_TOP" ] || { echo "ERROR: TREE_TOP not found: $TREE_TOP" >&2; exit 1; }

KERNEL_SRC=${KERNEL_SRC:-$TREE_TOP/kernel/asus/sdm660}
KERNEL_OUT=${KERNEL_OUT:-$STANDALONE_TOP/out/KERNEL_OBJ}
MODULES_OUT=${MODULES_OUT:-$STANDALONE_TOP/out/modules}

KERNEL_ARCH=${KERNEL_ARCH:-arm64}
DEFCONFIG_ARCH=${DEFCONFIG_ARCH:-arm64}
BOARD_KERNEL_IMAGE_NAME=${BOARD_KERNEL_IMAGE_NAME:-Image.gz-dtb}
BOARD_KERNEL_BASE=${BOARD_KERNEL_BASE:-0x00000000}
BOARD_KERNEL_PAGESIZE=${BOARD_KERNEL_PAGESIZE:-4096}
BOARD_KERNEL_CMDLINE=${BOARD_KERNEL_CMDLINE:-"androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x37 ehci-hcd.park=3 sched_enable_hmp=1 sched_enable_power_aware=1 service_locator.enable=1 loop.max_part=7 printk.devkmsg=on"}

CLANG_VERSION=${CLANG_VERSION:-clang-r596125}
CLANG_PATH=$TREE_TOP/prebuilts/clang/host/linux-x86/$CLANG_VERSION
MAKE_BIN=$TREE_TOP/prebuilts/build-tools/linux-x86/bin/make
LZ4_BIN=$TREE_TOP/prebuilts/kernel-build-tools/linux-x86/bin/lz4
PAHOLE_BIN=$TREE_TOP/prebuilts/kernel-build-tools/linux-x86/bin/pahole
FLEX_BIN=$TREE_TOP/prebuilts/build-tools/linux-x86/bin/flex
BISON_BIN=$TREE_TOP/prebuilts/build-tools/linux-x86/bin/bison
M4_BIN=$TREE_TOP/prebuilts/build-tools/linux-x86/bin/m4
BISON_PKGDATADIR=$TREE_TOP/prebuilts/build-tools/common/bison
KBUILD_TOOLS_INC=$TREE_TOP/prebuilts/kernel-build-tools/linux-x86/include
KBUILD_TOOLS_LIB=$TREE_TOP/prebuilts/kernel-build-tools/linux-x86/lib64
GLIBC_SYSROOT=$TREE_TOP/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot
TOOLS_LINEAGE_BIN=$TREE_TOP/prebuilts/tools-lineage/linux-x86/bin
BUILDTOOLS_BIN=$TREE_TOP/prebuilts/build-tools/linux-x86/bin
CLANGTOOLS_BIN=$TREE_TOP/prebuilts/clang-tools/linux-x86/bin
LIBCLANG_PATH=$CLANG_PATH/lib
JOBS=${JOBS:-$(nproc)}

# the staging helper called by `make bacon` reads these from the environment
export TREE_TOP KERNEL_SRC KERNEL_OUT MODULES_OUT KERNEL_ARCH
export BOARD_KERNEL_IMAGE_NAME BOARD_KERNEL_BASE BOARD_KERNEL_PAGESIZE BOARD_KERNEL_CMDLINE
export FRAGMENTS

read_fragments_file() {
  grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' | tr '\n' ' '
}

# --- argument parsing: command, optional --config, optional fragment list ---
cmd="${1:-}"; shift || true
FULL_CONFIG=""
if [ "$cmd" = "config" ] || [ "$cmd" = "kernel" ]; then
  if [ "${1:-}" = "--config" ]; then
    [ -n "${2:-}" ] || { echo "ERROR: --config needs a file path" >&2; exit 1; }
    FULL_CONFIG=$(resolve_invoked "$2")
    shift 2 || true
  fi
  if [ "$#" -eq 1 ] && [ "${1#@}" != "$1" ]; then
    fragfile=$(resolve_invoked "${1#@}")
    [ -f "$fragfile" ] || { echo "ERROR: fragments file not found: $fragfile" >&2; exit 1; }
    FRAGMENTS=$(read_fragments_file "$fragfile")
    [ -n "$FRAGMENTS" ] || { echo "ERROR: no fragments listed in: $fragfile" >&2; exit 1; }
  elif [ "$#" -gt 0 ]; then
    FRAGMENTS="$*"
  elif [ -z "${FRAGMENTS:-}" ] && [ -f ./X00TD/FRAGMENTS ]; then
    FRAGMENTS=$(read_fragments_file ./X00TD/FRAGMENTS)
  fi
fi

KERNEL_SRC_ABS=$(readlink -f "$KERNEL_SRC")
OUT_ABS=$(readlink -m "$KERNEL_OUT")
DEFCONFIG_DIR_ABS="$KERNEL_SRC_ABS/arch/$DEFCONFIG_ARCH/configs"
MERGE_SCRIPT="$KERNEL_SRC_ABS/scripts/kconfig/merge_config.sh"

echo "== msm-4.19 kernel build =="
echo "TREE_TOP (ro): $TREE_TOP"
echo "KERNEL_SRC  (ro): $KERNEL_SRC_ABS"
echo "KERNEL_OUT  (rw): $OUT_ABS"
echo "ARCH: $KERNEL_ARCH  IMAGE: $BOARD_KERNEL_IMAGE_NAME  CLANG: $CLANG_VERSION"
if [ -n "$FULL_CONFIG" ]; then
  echo "FULL_CONFIG: $FULL_CONFIG"
else
  echo "FRAGMENTS: $FRAGMENTS"
fi
echo ""

if [ -z "$FULL_CONFIG" ] && [ -z "${FRAGMENTS:-}" ]; then
  echo "ERROR: no fragments given and no X00TD/FRAGMENTS found." >&2
  echo "Pass fragments, @file, --config, or set FRAGMENTS." >&2
  exit 1
fi
if [ -n "$FULL_CONFIG" ]; then
  [ -f "$FULL_CONFIG" ] || { echo "ERROR: config file not found: $FULL_CONFIG" >&2; exit 1; }
else
  for f in $FRAGMENTS; do
    if [ ! -f "$DEFCONFIG_DIR_ABS/$f" ]; then
      echo "ERROR: fragment not found: $DEFCONFIG_DIR_ABS/$f" >&2
      exit 1
    fi
  done
fi
[ -x "$MERGE_SCRIPT" ] || { echo "ERROR: $MERGE_SCRIPT not executable/found" >&2; exit 1; }
[ -x "$MAKE_BIN" ] || { echo "ERROR: make not found: $MAKE_BIN" >&2; exit 1; }
[ -x "$CLANG_PATH/bin/clang" ] || { echo "ERROR: clang not found: $CLANG_PATH/bin/clang" >&2; exit 1; }

# --- build environment (prebuilt toolchain from the synced tree) ---
export HIP_PATH=none
export PERL5LIB="$TREE_TOP/prebuilts/tools-lineage/common/perl-base"
export BISON_PKGDATADIR="$BISON_PKGDATADIR"
export PATH="$TOOLS_LINEAGE_BIN:$BUILDTOOLS_BIN:$CLANG_PATH/bin:$CLANGTOOLS_BIN:$PATH"
export LD_LIBRARY_PATH="$CLANG_PATH/lib64:${LD_LIBRARY_PATH:-}"

HOST_SYSROOT_FLAG="--sysroot=$GLIBC_SYSROOT"
HOSTCFLAGS="$HOST_SYSROOT_FLAG -I$KBUILD_TOOLS_INC"
HOSTLDFLAGS="$HOST_SYSROOT_FLAG -Wl,-rpath,$KBUILD_TOOLS_LIB -L $KBUILD_TOOLS_LIB -fuse-ld=lld --rtlib=compiler-rt"

KBUILD_FLAGS="-j$JOBS LLVM=1 LLVM_IAS=1"
KBUILD_FLAGS="$KBUILD_FLAGS LZ4=$LZ4_BIN PAHOLE=$PAHOLE_BIN"
KBUILD_FLAGS="$KBUILD_FLAGS LEX=$FLEX_BIN YACC=$BISON_BIN M4=$M4_BIN"
KBUILD_FLAGS="$KBUILD_FLAGS LIBCLANG_PATH=$LIBCLANG_PATH"
KBUILD_FLAGS="$KBUILD_FLAGS HOSTCFLAGS=\"$HOSTCFLAGS\" HOSTLDFLAGS=\"$HOSTLDFLAGS\""
KBUILD_BASE="ARCH=$KERNEL_ARCH CLANG_TRIPLE=aarch64-linux-gnu- CC=\"clang\" LD=ld.lld"

do_config() {
  mkdir -p "$OUT_ABS"
  if [ -n "$FULL_CONFIG" ]; then
    echo "[1/2] cp full config $FULL_CONFIG -> \$OUT/.config"
    cp "$FULL_CONFIG" "$OUT_ABS/.config"
    echo "[2/2] olddefconfig"
    # shellcheck disable=SC2086
    eval "$MAKE_BIN $KBUILD_FLAGS -C \"$KERNEL_SRC_ABS\" O=\"$OUT_ABS\" $KBUILD_BASE olddefconfig"
  else
    # 1) base defconfig = first word
    set -- $FRAGMENTS
    BASE="$DEFCONFIG_DIR_ABS/$1"; shift
    echo "[1/3] cp base $BASE -> \$OUT/.config"
    cp "$BASE" "$OUT_ABS/.config"
    echo "[2/3] olddefconfig (base)"
    # shellcheck disable=SC2086
    eval "$MAKE_BIN $KBUILD_FLAGS -C \"$KERNEL_SRC_ABS\" O=\"$OUT_ABS\" $KBUILD_BASE olddefconfig"
    # 2) merge each *.config fragment one-by-one + olddefconfig
    for frag in "$@"; do
      case "$frag" in *.config)
        echo "[merge] $frag"
        ( cd "$OUT_ABS" && "$MERGE_SCRIPT" -m -O "$OUT_ABS" "$OUT_ABS/.config" "$DEFCONFIG_DIR_ABS/$frag" )
        # shellcheck disable=SC2086
        eval "$MAKE_BIN $KBUILD_FLAGS -C \"$KERNEL_SRC_ABS\" O=\"$OUT_ABS\" $KBUILD_BASE olddefconfig"
        ;;
      *) echo "skip non-fragment $frag (base already handled)";;
      esac
    done
  fi
  echo "[done] .config ready: $OUT_ABS/.config"
  grep -E "^CONFIG_LOCALVERSION=|.*Kernel Configuration" "$OUT_ABS/.config" | head -n 5
}

case "$cmd" in
  config)
    do_config
    ;;
  kernel)
    # re-pass fragments/config: the child process starts fresh, so CLI
    # overrides must be forwarded explicitly (unquoted: word-split).
    if [ -n "$FULL_CONFIG" ]; then
      "$0" config --config "$FULL_CONFIG"
    else
      # shellcheck disable=SC2086
      "$0" config $FRAGMENTS
    fi
    echo "[build] $BOARD_KERNEL_IMAGE_NAME"
    # shellcheck disable=SC2086
    eval "$MAKE_BIN $KBUILD_FLAGS -C \"$KERNEL_SRC_ABS\" O=\"$OUT_ABS\" $KBUILD_BASE $BOARD_KERNEL_IMAGE_NAME"
    if [ -d "$KERNEL_SRC_ABS/arch/$KERNEL_ARCH/boot/dts" ]; then
      echo "[build] dtbs"
      # shellcheck disable=SC2086
      eval "$MAKE_BIN $KBUILD_FLAGS -C \"$KERNEL_SRC_ABS\" O=\"$OUT_ABS\" $KBUILD_BASE dtbs"
    fi
    if grep -q '=m' "$OUT_ABS/.config"; then
      echo "[build] modules"
      # shellcheck disable=SC2086
      eval "$MAKE_BIN $KBUILD_FLAGS -C \"$KERNEL_SRC_ABS\" O=\"$OUT_ABS\" $KBUILD_BASE modules"
      mkdir -p "$MODULES_OUT"
      echo "[install] modules -> $MODULES_OUT (INSTALL_MOD_STRIP=1)"
      # shellcheck disable=SC2086
      eval "$MAKE_BIN $KBUILD_FLAGS -C \"$KERNEL_SRC_ABS\" O=\"$OUT_ABS\" $KBUILD_BASE INSTALL_MOD_PATH=\"$MODULES_OUT\" INSTALL_MOD_STRIP=1 modules_install"
    fi
    echo "DONE:"
    ls -lh "$OUT_ABS/arch/$KERNEL_ARCH/boot/$BOARD_KERNEL_IMAGE_NAME"
    cat "$OUT_ABS/include/config/kernel.release"
    ;;
  menuconfig)
    mkdir -p "$OUT_ABS"
    # shellcheck disable=SC2086
    eval "$MAKE_BIN $KBUILD_FLAGS -C \"$KERNEL_SRC_ABS\" O=\"$OUT_ABS\" $KBUILD_BASE menuconfig"
    ;;
  clean)
    echo "rm -rf $OUT_ABS"
    rm -rf "$OUT_ABS"
    ;;
  mrproper)
    echo "rm -rf $STANDALONE_TOP/out"
    rm -rf "$STANDALONE_TOP/out"
    ;;
  *)
    echo "usage: $0 {config|kernel|menuconfig|clean|mrproper} [--config file] [base_defconfig] [fragment...] | @fragments-file" >&2
    exit 1
    ;;
esac

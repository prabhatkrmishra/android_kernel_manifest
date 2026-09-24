#!/bin/bash
# Stage a built kernel into a flashable dir.
# KERNEL_OUT and friends come from the environment when chained after
# build-kernel.sh; defaults below let it run standalone too.
set -e
cd "$(dirname "$0")/.."
KERNEL_OUT=${KERNEL_OUT:-$PWD/out/KERNEL_OBJ}
BOARD_KERNEL_IMAGE_NAME=${BOARD_KERNEL_IMAGE_NAME:-Image.gz-dtb}
KERNEL_ARCH=${KERNEL_ARCH:-arm64}
KERNEL_SRC=${KERNEL_SRC:-${TREE_TOP:-.}/kernel/asus/sdm660}
FRAGMENTS=${FRAGMENTS:-"(see X00TD/FRAGMENTS)"}
OUT_ABS=$(readlink -m "$KERNEL_OUT")
KIMG="$OUT_ABS/arch/$KERNEL_ARCH/boot/$BOARD_KERNEL_IMAGE_NAME"
STAGE="./out/build"
mkdir -p "$STAGE"
cp -v "$KIMG" "$STAGE/"
if [ -f "$OUT_ABS/.config" ]; then cp -v "$OUT_ABS/.config" "$STAGE/kernel_config"; fi
if [ -f "$OUT_ABS/include/config/kernel.release" ]; then cp -v "$OUT_ABS/include/config/kernel.release" "$STAGE/kernel.release"; fi
MODULES_OUT=${MODULES_OUT:-$PWD/out/modules}
if [ -d "$MODULES_OUT" ]; then
  mods=$(find "$MODULES_OUT" -type f -name '*.ko' 2>/dev/null)
  if [ -n "$mods" ]; then
    mkdir -p "$STAGE/modules"
    echo "$mods" | while read -r m; do cp -v "$m" "$STAGE/modules/"; done
  else
    echo "no modules built; skipping modules copy"
  fi
else
  echo "no modules dir; skipping modules copy"
fi
cat > "$STAGE/README.txt" <<EOF2
msm-4.19 kernel (fragment build)
Fragments: $FRAGMENTS
Source (ro): $KERNEL_SRC @ $(git -C "$KERNEL_SRC" log --oneline -1 2>/dev/null || echo unknown)
Image: Image.gz-dtb (appended dtb, no separate dtbo)
Copy it into an AnyKernel3 zip to flash it.
EOF2
ls -lh "$STAGE"

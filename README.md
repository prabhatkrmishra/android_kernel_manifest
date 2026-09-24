# Android kernel manifest — msm-5.4-holi (fogos)

Manifest for the Motorola fogos (Holi) msm-5.4 kernel. Includes the device
kernel, KernelSU-Next, and the latest AOSP toolchain so a fresh
`repo init && repo sync` gives a build-ready tree.

## Toolchain

* Clang: **clang-r547379** (Clang 20.0.0, current AOSP stable)
* Binutils: GNU `aarch64-linux-android-4.9` prebuilts (host tools only).

Clang is intentionally not a manifest project — the full
`prebuilts/clang/host/linux-x86` clone is ~20 GB and repo v2 no longer
supports sparse `#branch/path` projects. Fetch only what the kernel build
needs (~1.1 GB; a plain sparse clone of the toolchain is ~4.6 GB), once,
after `repo sync`:
```bash
git clone --filter=blob:none --no-checkout --depth 1 -b master \
  https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
  prebuilts-master/clang/host/linux-x86
cd prebuilts-master/clang/host/linux-x86
git sparse-checkout set --no-cone 'clang-r547379/bin' \
  'clang-r547379/lib/clang/20/include' 'clang-r547379/lib/clang/20/share'
git checkout master
```

## Repo Init
```bash
repo init -u https://github.com/prabhatKrMishra/android_kernel_manifest.git -b msm-5.4-holi
```
## Sync Source
```bash
repo sync --force-sync --no-clone-bundle --current-branch --no-tags -j$(nproc --all)
```
`kernel/msm-5.4` (branch `15.0-302`) is synced as a project. Its
KernelSU-Next submodule (branch `upgraded`) then needs:
```bash
git -C kernel/msm-5.4 submodule update --init --depth 1 KernelSU-Next
```

## Build
Clang build (LTO thin, qgki):
```bash
BUILD_CONFIG=kernel/msm-5.4/build.config.msm.holi VARIANT=qgki LTO=thin TARGET_PRODUCT=fogos BUILD_KERNEL=1 TARGET_BUILD_VARIANT=user build/build.sh
```
Outputs land in `out/msm-5.4-holi-qgki/dist/` (`Image.gz`, `vmlinux`, DTB/DTBO).

KernelSU-Next uses manual hooks (`CONFIG_KSU_MANUAL_HOOK=y`); the hook check
in its `Kbuild` is skipped during configless clean/mrproper passes so
`build.sh`'s initial `mrproper` works.

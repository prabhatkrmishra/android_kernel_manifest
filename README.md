## msm-4.19 kernel build

Fragment-based out-of-tree kernel build. You give it a base defconfig plus
config fragments (or one complete `.config`), and it produces a kernel image.
The kernel source tree is only read from, never written to.

Fragment paths are relative to the kernel's `arch/arm64/configs/` directory,
for example `vendor/base_defconfig` means
`arch/arm64/configs/vendor/base_defconfig` inside the kernel source.

## Repo Init ##
```bash
repo init -u https://github.com/prabhatkrmishra/android_kernel_manifest.git -b msm-4.19-sdm660
```
## Sync Source ##
```bash
repo sync --force-sync --no-clone-bundle --current-branch --no-tags -j$(nproc --all)
```

Syncing gives you this layout at the tree root:

```bash
kernel/                # kernel sources
prebuilts/             # toolchain and build tools
tools/kernel-build/    # this repo: build script, Makefile, X00TD/, scripts/
build                  # shortcut to tools/kernel-build/build-kernel.sh
Makefile               # shortcut to tools/kernel-build/Makefile
```

The `build` and `Makefile` shortcuts are created by the manifest at sync
time. If yours are missing, recreate them once from the tree root:

```bash
ln -s tools/kernel-build/build-kernel.sh build
ln -s tools/kernel-build/Makefile Makefile
```

Build output lands in `tools/kernel-build/out/`.

## Setup ##

Source the environment once per shell, from anywhere inside the tree:

```bash
source tools/kernel-build/envsetup.sh
```

That exports `TREE_TOP` (auto-detected, override it only to build against a
different tree) and gives you two commands that work from any directory:

- `build ...` — runs the kernel build script
- `kmake ...` — runs its Makefile targets

To skip even that one line, run it automatically in every new shell by
appending it to `~/.bashrc` (guarded, so shells still work if the tree
moves or is absent):

```bash
[ -f ~/kernel/tools/kernel-build/envsetup.sh ] && source ~/kernel/tools/kernel-build/envsetup.sh
```

(Replace `~/kernel` with wherever you synced the tree.)

The examples below use the short `build` form; `./build` from the tree root
means the same thing.

## Commands: build ##

Every build command accepts an optional fragment list. The first entry is
the base defconfig, each following `*.config` entry is merged on top of it
in order (`merge_config.sh -m`, each merge followed by `olddefconfig`),
so later fragments win on conflicts. A `@path/to/file` argument reads the
list from a file instead (one fragment per line, `#` comments allowed;
relative `@` paths resolve from where you invoke). With no fragment
arguments, the `FRAGMENTS` variable from the environment is used, falling
back to the bundled `X00TD/FRAGMENTS`.
Device-specific lists live in `tools/kernel-build/X00TD/`.

### config — merge and validate only

```bash
build config
```

Copies the base defconfig into the output dir, runs `olddefconfig`, then
merges each fragment one by one. Finishes quickly and tells you immediately
if a fragment path is wrong. Use it to iterate on config changes without
compiling anything. The resulting `.config` stays in the output dir for the
`kernel` step to reuse. Pass fragments to override the default, e.g.
`build config vendor/my_defconfig vendor/my.config`.

### kernel — full kernel build

```bash
build kernel
```

Runs the `config` step first, then compiles:

1. the kernel image into the output `arch/arm64/boot/` dir,
2. the device trees (`dtbs`) next to it,
3. loadable modules plus `modules_install` into the modules dir — only when
   the merged config actually enables modules (`=m` entries exist).

This is the long step.

### kernel with a full config file — skip merging

```bash
build kernel --config path/to/.config
```

Copies your complete `.config` straight into the output dir and runs
`olddefconfig` on it. No fragment merging happens. Use it when you already
have a generated config (for example one saved from a previous build) and
want to rebuild exactly that. The `--config` path resolves from where you
invoke.

### menuconfig — interactive configuration

```bash
build menuconfig
```

Opens the kernel's interactive config editor against the out-of-tree
directory. Reads and writes only the output `.config`; the source tree is
untouched. Save, exit, then rebuild with `--config` pointing at the saved
file to build exactly what you configured.

### clean — drop the kernel output

```bash
build clean
```

Deletes the kernel output dir (objects and merged config). Next build
starts from merging again.

### mrproper — drop everything built

```bash
build mrproper
```

Deletes the whole output directory (kernel objects, modules staging, build
staging). Use it when switching to unrelated fragments or when disk space
matters.

## Commands: make ##

`kmake <target>`, `make <target>` (tree root), and `build <target>` are
the same thing: every Makefile target just forwards to the matching script
command, so use whichever form you prefer. Fragments go in `FRAGMENTS="..."`:

```bash
kmake config
kmake kernel
kmake kernel FRAGMENTS="@tools/kernel-build/X00TD/FRAGMENTS"
kmake bacon
kmake menuconfig
```

The one target with no script equivalent is `bacon`: it builds the kernel,
then collects the kernel image, the used `.config`, the kernel release
string, and any built modules into `out/build/` (under the script
directory). That directory is meant to be dropped into a flashable zip
template. It is staging only — no signed package is produced here.

## Configuration ##

Everything derives from the environment; there is no config file:

```bash
source tools/kernel-build/envsetup.sh
build kernel @tools/kernel-build/X00TD/FRAGMENTS
```

| Variable | Meaning | Default |
|---|---|---|
| `TREE_TOP` | Root of the synced tree holding kernel source and prebuilts (read-only) | auto-detected, override to use another tree |
| `KERNEL_SRC` | Kernel source directory | `$TREE_TOP/kernel/asus/sdm660` |
| `KERNEL_OUT` | Directory receiving objects and `.config` | `<script-dir>/out/KERNEL_OBJ` |
| `MODULES_OUT` | Directory receiving installed modules | `<script-dir>/out/modules` |
| `FRAGMENTS` | Default base defconfig plus fragments | bundled `X00TD/FRAGMENTS` |
| `JOBS` | Parallel build jobs | CPU count |

## Verify ##

```bash
grep -E "^CONFIG_LOCALVERSION=" tools/kernel-build/out/KERNEL_OBJ/.config
cat tools/kernel-build/out/KERNEL_OBJ/include/config/kernel.release
ls -lh tools/kernel-build/out/KERNEL_OBJ/arch/arm64/boot/
```

You should see your merged options in `.config`, the kernel release string,
and the built image plus device trees under `arch/arm64/boot/`.

# msm-4.19 kernel build environment. Source once per shell, from anywhere:
#   source tools/kernel-build/envsetup.sh        # inside the synced tree
#
# Provides:
#   build ...   run the kernel build script from any directory
#               (build config | build kernel [@file] [--config f] | build menuconfig | ...)
#   kmake ...   run its Makefile targets from any directory
#               (kmake kernel | kmake bacon | kmake menuconfig | ...)
#   $TREE_TOP   exported, pointing at the synced tree root
#   $KB         the tools/kernel-build directory holding the scripts
#
# Plain `make` is intentionally left alone: shadowing the system make would
# break everything else in your shell. From the tree root the symlinked
# root Makefile already makes bare `make <target>` work.

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  echo "ERROR: source this file instead of executing it:" >&2
  echo "  source tools/kernel-build/envsetup.sh" >&2
  exit 1
fi

# Resolve our own real location, following any symlinks.
_KB_SRC="${BASH_SOURCE[0]}"
while [ -L "$_KB_SRC" ]; do
  _KB_DIR=$(cd -P "$(dirname "$_KB_SRC")" && pwd)
  _KB_LINK=$(readlink "$_KB_DIR/$(basename "$_KB_SRC")")
  case "$_KB_LINK" in
    /*) _KB_SRC="$_KB_LINK" ;;
    *) _KB_SRC="$_KB_DIR/$_KB_LINK" ;;
  esac
done
KB=$(cd -P "$(dirname "$_KB_SRC")" && pwd)
unset _KB_SRC _KB_DIR _KB_LINK

# The synced tree root sits two levels above this directory
# (tools/kernel-build). An explicit TREE_TOP always wins.
_CANDIDATE=$(dirname "$(dirname "$KB")")
if [ -z "${TREE_TOP:-}" ]; then
  if [ -d "$_CANDIDATE/kernel" ] && [ -d "$_CANDIDATE/prebuilts" ]; then
    export TREE_TOP="$_CANDIDATE"
  else
    echo "envsetup: warning: no kernel/prebuilts above $KB" >&2
    echo "envsetup: set TREE_TOP manually: export TREE_TOP=<synced tree root>" >&2
  fi
fi
unset _CANDIDATE

build() {
  "$KB/build-kernel.sh" "$@"
}

kmake() {
  make -C "$KB" "$@"
}

echo "tree: ${TREE_TOP:-<unset>}  |  build ... | kmake ..."

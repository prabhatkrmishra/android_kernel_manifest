## X00TD device files

Everything in this folder is specific to the X00TD build. The scripts at
the repo root stay generic and work with any fragments you pass them.

- `FRAGMENTS` — base defconfig plus fragments in merge order. From the
  synced tree root, build with:
  `./build kernel`
  (the bundled list is the default; `@tools/kernel-build/X00TD/FRAGMENTS`
  names it explicitly).

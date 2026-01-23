# Hylyx e2fs Tool-chain

This directory contains the make-based build that produces the fully-static **e2fsprogs** utilities (primarily `mke2fs`) required by Hylyx Install (Create.swift)

Key goals
----------
1. Produce `mke2fs` that can **populate an ext4 image directly from compressed tarballs** (xz, zstd, …) without needing runtime `libarchive`.
2. Link everything **statically** (no `.dylib` or `dlopen()` at run-time) so the binary works inside the macOS app bundle / sandbox.
3. Keep the final executables as small as reasonably possible (symbols are stripped automatically during `make`).

What gets built
--------------
• `mke2fs` (+ symlink `mkfs.ext4`)
• `resize2fs` • `fsck` • `e2fsck`

Output:
* `e2fs/bin/` – prebuilt binaries used by build.sh

Build flow (targets in **Makefile**)
------------------------------------
```
make               # default → deps + libarchive + e2fsprogs + install (stripped)
make deps          # zstd + xz/liblzma static helper libs
make libarchive    # static libarchive compiled against those helper libs
make e2fsprogs     # patched, statically linked e2fsprogs tree
make install       # copies binaries to install/bin
make clean         # wipe build tree (binaries already copied remain)
```

Important implementation notes
------------------------------
* **Static helper libs** – `e2fs/deps/` builds zstd 1.5.5 and xz/liblzma 5.4.5 with `--enable-static --disable-shared`.
* **Static libarchive (3.8.1)** – compiled with `--enable-static --disable-shared --with-zstd --with-lzma` and all command-line utilities disabled.  A stray convenience `libzstd.a` member is removed from `libarchive.a` to keep the macOS linker happy.
* **e2fsprogs (1.47.0)** – configured with `CPPFLAGS="-DHAVE_ARCHIVE_H -UHAVE_DLOPEN"` so the tar-import feature is always enabled and the dlopen path is compiled out.
* **Symbol stripping** – the install rule runs `strip -x` on everything before mirroring, shrinking `mke2fs` from ≈1.3 MB to ≈460 KB while retaining full functionality.
* **Custom binary set** – override `BINSET` on the make command line if you need a different subset, e.g. `make BINSET="mke2fs resize2fs"`.



Clean rebuild example
---------------------
```bash
make clean
make -j$(sysctl -n hw.ncpu)
```
This performs a full build and strips the binaries.

License
-------
All patches are derived from upstream GPL-compatible sources.  The build scripts themselves are released under MIT – see the root `LICENSE` of this repo. 
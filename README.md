# rh-utils — header-only utilities, one Debian package per header

Small, dependency-free C headers shared across the DB platform repos. Each
header is packaged as its **own** Debian package shipping a single `.h`, plus
one `rh-utils-devtools` package for the shared build tooling.

## Headers → packages

| Header (`header_only/`)   | Package                        | Installs to                              | Consumed as                        |
|---------------------------|--------------------------------|------------------------------------------|------------------------------------|
| `string_view.h`           | `rh-util-string-view`          | `/usr/local/include/utils/string_view.h` | `#include <utils/string_view.h>`   |
| `memory_macros.h`         | `rh-util-memory-macros`        | `/usr/local/include/utils/memory_macros.h` | `#include <utils/memory_macros.h>` |
| `time_macros.h`           | `rh-util-time-macros`          | `/usr/local/include/utils/time_macros.h` | `#include <utils/time_macros.h>`   |
| `preprocessor_macros.h`   | `rh-util-preprocessor-macros`  | `/usr/local/include/utils/preprocessor_macros.h` | `#include <utils/preprocessor_macros.h>` |
| — (build tooling)         | `rh-utils-devtools`            | `/usr/local/share/rh-utils/{gcc_build_profiles.sh,.clang-format,testkit/}` | tooling, not `#include`d |

The include path is **flat**: every header lands directly in
`/usr/local/include/utils/`, so `#include <utils/<name>.h>` works unchanged.
The package split is purely about *distribution* — a consumer depends only on
the headers it actually includes, and each header can version independently.

## Why one package per header

- **Minimal dependencies.** DB_http includes only `<utils/memory_macros.h>`
  and `<utils/string_view.h>`; its deb depends on just those two packages, not
  on a monolith carrying headers it never uses.
- **Independent versioning.** Bumping `string_view.h` is a version bump of
  `rh-util-string-view` alone; unrelated consumers are untouched.
- **Clear ownership.** `dpkg -S /usr/local/include/utils/time_macros.h`
  names exactly one package.

## Build

```bash
bash compilation/build_deb.sh          # → build/debs/*.deb (5 packages)
```

The script discovers `header_only/*.h` automatically — **adding a header needs
no script edit**; it becomes `rh-util-<name>` (underscores → hyphens) on the
next build. Version comes from `VERSION` (currently `1.0.0`) and applies to
every package it emits. Output lands in `build/debs/`.

Each package declares `Replaces:`/`Conflicts: rh-utils` (the retired
monolithic package), so on a machine that still has the old `rh-utils`, `apt`
removes it and the split packages take over its files with no conflict.

## Install

Installed as part of the platform bootstrap (`sudo ./DB_install.sh` at the
superproject root), which builds and installs each repo's debs in dependency
order. To install just these by hand:

```bash
sudo apt-get install --yes ./build/debs/rh-util-*_1.0.0_all.deb \
                           ./build/debs/rh-utils-devtools_1.0.0_all.deb
```

Verify:

```bash
dpkg -L rh-util-memory-macros            # → /usr/local/include/utils/memory_macros.h
echo '#include <utils/memory_macros.h>' | gcc -fsyntax-only -x c -   # compiles
```

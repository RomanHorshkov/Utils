# fsutil

Small POSIX/Linux filesystem helper built around directory file descriptors as
capabilities.

It avoids string-built absolute paths. Open a trusted directory once, then
operate relative to it with `*at()`-style helpers.

## Goals

- dirfd-based traversal
- single-component file/dir operations
- relative path walking
- symlink rejection during acquisition
- explicit metadata verification
- explicit crash-consistency barriers
- predictable fd ownership

## Layout

- `fsutil.h` - public API
- `fsutil.c` - implementation
- `utils/` - build and test scripts
- `tests/ITs/` - cmocka integration tests
- `tests/results/ITs/` - test and coverage outputs
- `build/` - generated objects, libraries, and test binaries

## Platform

POSIX.1-2008 / Linux-like systems.

Not a Windows abstraction.

## Return convention

All functions return:

```c
0       // success
-errno  // failure
```

## Build

Builds are driven by scripts under `utils/`.

Build static and shared libraries:

```sh
./utils/make_libs.sh
```

Artifacts:

- `build/libfsutil.a`
- `build/libfsutil.so`

## Testing

The integration suite uses `cmocka` and produces coverage reports with
`gcovr`.

Requirements on Debian/Ubuntu:

```sh
sudo apt install libcmocka-dev gcovr
```

Run:

```sh
./utils/make_ITs.sh
```

Outputs:

- `tests/results/ITs/integration_result.txt`
- `tests/results/ITs/ITs_all_coverage.html`
- `tests/results/ITs/ITs_all_coverage.xml`
- `tests/results/ITs/coverage-summary.json`

## API notes

- single-component helpers accept exactly one component: no `/`, no `.`, no `..`
- walk helpers accept relative paths only
- symlinks are rejected during capability acquisition
- durability stays explicit: create, rename, and unlink helpers do not fsync
  parent directories implicitly

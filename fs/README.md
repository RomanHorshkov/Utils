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

## Platform

POSIX.1-2008 / Linux-like systems.

Not a Windows abstraction.

## Return convention

All functions return:

```c
0       // success
-errno  // failure
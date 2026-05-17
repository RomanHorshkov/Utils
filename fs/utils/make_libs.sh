#!/usr/bin/env bash
set -euo pipefail

START_DIR="$(pwd -P)"
cleanup() { cd -- "$START_DIR"; }
trap cleanup EXIT

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$ROOT_DIR"

BUILD_DIR="${ROOT_DIR}/build"
mkdir -p "${BUILD_DIR}"

WARN_FLAGS=(
  -Werror
  -Wall
  -Wextra
  -Wpedantic
  -Wshadow
  -Wformat=2
  -Wconversion
  -Wnull-dereference
  -Wdouble-promotion
  -Wduplicated-cond
  -Wduplicated-branches
  -Wlogical-op
)

CFLAGS=(
  -std=c11
  -D_GNU_SOURCE
  -O2
  -g
  -I.
  "${WARN_FLAGS[@]}"
)

printf 'building fsutil libraries in %s\n' "${BUILD_DIR}"

gcc "${CFLAGS[@]}" -fPIC -c fsutil.c -o "${BUILD_DIR}/fsutil.pic.o"
gcc "${CFLAGS[@]}"       -c fsutil.c -o "${BUILD_DIR}/fsutil.o"

gcc -shared -o "${BUILD_DIR}/libfsutil.so" "${BUILD_DIR}/fsutil.pic.o"
ar rcs "${BUILD_DIR}/libfsutil.a" "${BUILD_DIR}/fsutil.o"

printf 'artifacts:\n'
printf '  %s\n' "${BUILD_DIR}/libfsutil.a"
printf '  %s\n' "${BUILD_DIR}/libfsutil.so"

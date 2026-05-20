#!/usr/bin/env bash


# Build static and shared libraries.


# -e: stop immediately if a command fails.
# -u: stop if an unset variable is used.
# -o pipefail: fail a pipeline if any command in the pipeline fails.
set -euo pipefail

# Remember where the user launched the script.
START_DIR="$(pwd -P)"
# Return to the user's launch directory.
cleanup() { cd -- "$START_DIR"; }
# Always return to START_DIR on script exit.
trap cleanup EXIT

# Determine the root directory of the project (the parent of the script's directory).
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$ROOT_DIR"

# Create the build directory if it doesn't exist.
BUILD_DIR="${ROOT_DIR}/build"
mkdir -p "${BUILD_DIR}"

# Compiler warning flags to enforce code quality.
WARN_FLAGS=(
  # Treat all warnings as errors.
  -Werror
  # Enable common warnings about code quality and potential issues.
  -Wall
  # Enable extra warnings that are not included in -Wall.
  -Wextra
  # Enable warnings about language extensions and non-standard code.
  -Wpedantic
  # Enable warnings about shadowing variables, which can lead to confusing code.
  -Wshadow
  # Enable warnings about format string vulnerabilities and mismatches, 2 to treat them as errors.
  -Wformat=2
  # Enable warnings about implicit conversions that may change the value, such as signed to unsigned.
  -Wconversion
  # Enable warnings about null pointer dereferences, which can lead to crashes.
  -Wnull-dereference
  # Enable warnings about implicit fallthrough in switch statements, which can lead to bugs.
  -Wimplicit-fallthrough=5
  # Enable warnings about double promotion of float to double, which can lead to performance issues.
  -Wdouble-promotion
  # Enable warnings about duplicated conditions in if statements, which can indicate logic errors.
  -Wduplicated-cond
  # Enable warnings about duplicated branches in if statements, which can indicate logic errors.
  -Wduplicated-branches
  # Enable warnings about logical operations that are always true or false, which can indicate logic errors.
  -Wlogical-op
  # Enable warnings about missing field initializers in struct initialization, which can lead to uninitialized fields.
  -Wmissing-field-initializers
  # Enable warnings about missing prototypes for functions, which can lead to implicit declarations and potential bugs.
  -Wmissing-prototypes
  # Enable warnings about missing declarations for functions, which can lead to implicit declarations and potential bugs.
  -Wmissing-declarations
)

CFLAGS=(
  # Use the C11 standard and enable GNU extensions.
  -std=c11
  # Define _GNU_SOURCE to enable GNU extensions in the C library.
  -D_GNU_SOURCE
  # Optimization level 2 for better performance without sacrificing too much compile time.
  -O2
  # Include debug symbols for easier debugging and profiling.
  -g
  # Include the current directory for header files.
  -I.
  # Include the warning flags defined above.
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

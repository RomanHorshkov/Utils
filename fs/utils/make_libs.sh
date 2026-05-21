#!/usr/bin/env bash


# Build static and shared libraries.


# -e: stop immediately if a command fails.
# -u: stop if an unset variable is used.
# -o pipefail: fail a pipeline if any command in the pipeline fails.
set -euo pipefail

# Print a short, human-meaningful description of a produced artifact.
print_artifact_report() {
    local artifact_path="$1"

    printf '    artifact: %s\n' "${artifact_path}"
    printf '      size:   %s bytes\n' "$(wc -c < "${artifact_path}")"
    printf '      type:   %s\n' "$(file -b "${artifact_path}")"
}

# Remember where the user launched the script.
START_DIR="$(pwd -P)"
# Return to the user's launch directory.
cleanup() { cd -- "$START_DIR"; }
# Always return to START_DIR on script exit.
trap cleanup EXIT

# Determine the directory that contains this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load the shared GCC build-profile definitions from the same directory as this
# script, so execution does not depend on the user's current working directory.
source "${SCRIPT_DIR}/gcc_build_profiles.sh"

# Determine the root directory of the project (the parent of the script's directory).
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd -- "$ROOT_DIR"

# Create the build directory if it doesn't exist.
BUILD_DIR="${ROOT_DIR}/build"
mkdir -p "${BUILD_DIR}"

printf 'building fsutil libraries in %s\n' "${BUILD_DIR}"


# Build both library variants for every profile exported by the shared GCC
# profile configuration.
#
# The profile file gives us names such as:
#   - debug
#   - release
#   - native
#
# For each profile we create:
#   - build/<profile>/libfsutil.a
#   - build/<profile>/libfsutil.so
#
# The profile arrays follow a predictable naming convention:
#   CPPFLAGS_DEBUG   CFLAGS_DEBUG   LDFLAGS_DEBUG
#   CPPFLAGS_RELEASE CFLAGS_RELEASE LDFLAGS_RELEASE
#   ...
#
# The loop below converts the lowercase profile name into uppercase, rebuilds
# those array names as strings, and then uses Bash namerefs so gcc receives the
# correct arrays for the current profile.

for profile in "${GCC_BUILD_PROFILES[@]}"; do
    profile_upper="${profile^^}"
    profile_build_dir="${BUILD_DIR}/${profile}"

    cppflags_var="CPPFLAGS_${profile_upper}"
    cflags_var="CFLAGS_${profile_upper}"
    ldflags_var="LDFLAGS_${profile_upper}"

    declare -n cppflags_ref="${cppflags_var}"
    declare -n cflags_ref="${cflags_var}"
    declare -n ldflags_ref="${ldflags_var}"

    # Keep each profile's artifacts in its own directory so builds do not
    # overwrite one another and inspection stays simple.
    mkdir -p "${profile_build_dir}"

    printf '\n[%s]\n' "${profile}"
    printf '  compiling PIC object:    %s\n' "${profile_build_dir}/fsutil.pic.o"

    # Position-independent object for the shared library.
    gcc "${cppflags_ref[@]}" "${cflags_ref[@]}" -fPIC -c fsutil.c \
        -o "${profile_build_dir}/fsutil.pic.o"

    printf '  compiling static object: %s\n' "${profile_build_dir}/fsutil.o"

    # Normal object for the static library.
    gcc "${cppflags_ref[@]}" "${cflags_ref[@]}" -c fsutil.c \
        -o "${profile_build_dir}/fsutil.o"

    printf '  linking shared library:  %s\n' "${profile_build_dir}/libfsutil.so"

    # Shared library (.so): link the PIC object and apply the profile's link
    # flags, which matters for profiles such as sanitize, native, and tsan.
    gcc -shared "${ldflags_ref[@]}" \
        -o "${profile_build_dir}/libfsutil.so" \
        "${profile_build_dir}/fsutil.pic.o"

    printf '  creating static library: %s\n' "${profile_build_dir}/libfsutil.a"

    # Static library (.a): archive the non-PIC object.
    ar rcs "${profile_build_dir}/libfsutil.a" \
        "${profile_build_dir}/fsutil.o"

    # Report what was actually produced, not just that the commands ran.
    printf '  output summary:\n'
    print_artifact_report "${profile_build_dir}/libfsutil.so"
    print_artifact_report "${profile_build_dir}/libfsutil.a"
done

printf 'artifacts:\n'
for profile in "${GCC_BUILD_PROFILES[@]}"; do
    printf '  %s\n' "${BUILD_DIR}/${profile}/libfsutil.a"
    printf '  %s\n' "${BUILD_DIR}/${profile}/libfsutil.so"
done

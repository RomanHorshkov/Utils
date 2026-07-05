#!/usr/bin/env bash
# =============================================================================
# build_deb.sh — package the rh-utils foundation deb (Architecture: all)
#
# author  Roman Horshkov <github.com/RomanHorshkov>
#
# Payload (see superproject IMPLEMENTATION_PROCEDURE.md §4.3, order 1):
#   /usr/local/include/utils/*.h            header-only libraries
#   /usr/local/include/utils/VERSION        version marker for humans/tools
#   /usr/local/share/rh-utils/gcc_build_profiles.sh
#   /usr/local/share/rh-utils/.clang-format
#   /usr/local/share/rh-utils/VERSION
#   /usr/local/share/rh-utils/testkit/**    superproject tests/ toolkit,
#                                           staged only when present (§4.5)
#
# After install every repo consumes:  #include <utils/string_view.h>  etc.
# and syncs its gcc_build_profiles.sh from /usr/local/share/rh-utils/.
# =============================================================================

set -euo pipefail

START_DIR="$(pwd -P)"
cleanup() { cd -- "${START_DIR}"; }
trap cleanup EXIT

die() { printf 'build_deb: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd -- "${ROOT_DIR}"

command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found in PATH"
command -v fakeroot >/dev/null 2>&1 || die "fakeroot not found in PATH"

PKG_NAME="rh-utils"
VER="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
[[ -n "${VER}" ]] || die "VERSION is empty"
ARCH="all"

HEADERS_DIR="${ROOT_DIR}/header_only"
PROFILES_SH="${ROOT_DIR}/compilation/gcc_build_profiles.sh"
CLANG_FMT="${ROOT_DIR}/.clang-format"
# Superproject tests/ toolkit (§4.5) — optional until it exists.
TESTKIT_DIR="${TESTKIT_DIR:-$(cd "${ROOT_DIR}/.." 2>/dev/null && pwd)/tests}"

[[ -d "${HEADERS_DIR}" ]] || die "missing ${HEADERS_DIR}"
[[ -f "${PROFILES_SH}" ]] || die "missing ${PROFILES_SH}"
[[ -f "${CLANG_FMT}"   ]] || die "missing ${CLANG_FMT}"

STAGE="${ROOT_DIR}/build/pkgroot"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/build/debs}"
DEB="${OUT_DIR}/${PKG_NAME}_${VER}_${ARCH}.deb"

rm -rf -- "${STAGE}"
mkdir -p -- "${STAGE}/DEBIAN" \
            "${STAGE}/usr/local/include/utils" \
            "${STAGE}/usr/local/share/rh-utils"

# --- headers -----------------------------------------------------------------
shopt -s nullglob
headers=("${HEADERS_DIR}"/*.h)
shopt -u nullglob
(( ${#headers[@]} > 0 )) || die "no headers found in ${HEADERS_DIR}"
for h in "${headers[@]}"
do
    install -m 0644 -- "${h}" "${STAGE}/usr/local/include/utils/$(basename "${h}")"
    printf '  header  %s\n' "$(basename "${h}")"
done
printf '%s\n' "${VER}" > "${STAGE}/usr/local/include/utils/VERSION"
chmod 0644 "${STAGE}/usr/local/include/utils/VERSION"

# --- shared assets -------------------------------------------------------------
install -m 0644 -- "${PROFILES_SH}" "${STAGE}/usr/local/share/rh-utils/gcc_build_profiles.sh"
install -m 0644 -- "${CLANG_FMT}"   "${STAGE}/usr/local/share/rh-utils/.clang-format"
printf '%s\n' "${VER}" > "${STAGE}/usr/local/share/rh-utils/VERSION"
chmod 0644 "${STAGE}/usr/local/share/rh-utils/VERSION"

# --- testkit (optional until superproject tests/ lands, §4.5) -----------------
if [[ -d "${TESTKIT_DIR}" ]]
then
    printf '  testkit %s -> /usr/local/share/rh-utils/testkit/\n' "${TESTKIT_DIR}"
    mkdir -p -- "${STAGE}/usr/local/share/rh-utils/testkit"
    cp -a -- "${TESTKIT_DIR}/." "${STAGE}/usr/local/share/rh-utils/testkit/"
    find "${STAGE}/usr/local/share/rh-utils/testkit" -type d -exec chmod 0755 {} +
    find "${STAGE}/usr/local/share/rh-utils/testkit" -type f -name '*.sh' -exec chmod 0755 {} +
    find "${STAGE}/usr/local/share/rh-utils/testkit" -type f ! -name '*.sh' -exec chmod 0644 {} +
else
    printf 'build_deb: NOTE superproject testkit not found at %s — packaging without it\n' "${TESTKIT_DIR}"
fi

# --- control -------------------------------------------------------------------
cat > "${STAGE}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: Roman Horshkov <https://github.com/RomanHorshkov>
Description: rh header-only C utilities and canonical build tooling
 Header-only libraries (string_view, memory/time/preprocessor macros)
 installed under /usr/local/include/utils, plus the canonical
 gcc_build_profiles.sh, .clang-format and shared test toolkit under
 /usr/local/share/rh-utils.
EOF

# Header-only + assets: no ldconfig hooks needed.

mkdir -p -- "${OUT_DIR}"
fakeroot dpkg-deb --build "${STAGE}" "${DEB}"

printf '\nbuilt: %s\n' "${DEB}"
dpkg-deb -I "${DEB}"
dpkg-deb -c "${DEB}"

#!/usr/bin/env bash
set -euo pipefail

START_DIR="$(pwd -P)"
cleanup() { cd -- "$START_DIR"; }
trap cleanup EXIT

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$ROOT_DIR"

BUILD_DIR="${ROOT_DIR}/build/ITs"
RESULT_DIR="${ROOT_DIR}/tests/results/ITs"
RESULT_FILE="${RESULT_DIR}/integration_result.txt"

mkdir -p "${BUILD_DIR}"
mkdir -p "${RESULT_DIR}"
find "${BUILD_DIR}" -mindepth 1 -maxdepth 1 -type f -delete

if ! pkg-config --exists cmocka; then
  echo "cmocka not found (pkg-config --exists cmocka failed)"
  exit 1
fi

if ! command -v gcovr >/dev/null 2>&1; then
  echo "gcovr not found"
  exit 1
fi

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
  -O0
  -g
  --coverage
  -I.
  -Itests/ITs
  "${WARN_FLAGS[@]}"
)

read -r -a CMOCKA_CFLAGS <<< "$(pkg-config --cflags cmocka)"
read -r -a CMOCKA_LIBS <<< "$(pkg-config --libs cmocka)"

gcc "${CFLAGS[@]}" -c fsutil.c -o "${BUILD_DIR}/fsutil.o"
gcc "${CFLAGS[@]}" "${CMOCKA_CFLAGS[@]}" -c tests/ITs/integration_test.c -o "${BUILD_DIR}/integration_test.o"
gcc --coverage -O0 -g \
  "${BUILD_DIR}/fsutil.o" \
  "${BUILD_DIR}/integration_test.o" \
  -o "${BUILD_DIR}/integration_test" \
  "${CMOCKA_LIBS[@]}"

TEST_RC=0
"${BUILD_DIR}/integration_test" | tee "${RESULT_FILE}" || TEST_RC=$?

printf '[coverage] generating reports via gcovr...\n'
gcovr -r "${ROOT_DIR}" \
  --object-directory "${BUILD_DIR}" \
  --exclude 'tests/' \
  --gcov-ignore-parse-errors negative_hits.warn_once_per_file \
  --html --html-details \
  -o "${RESULT_DIR}/ITs_all_coverage.html"

gcovr -r "${ROOT_DIR}" \
  --object-directory "${BUILD_DIR}" \
  --exclude 'tests/' \
  --gcov-ignore-parse-errors negative_hits.warn_once_per_file \
  --xml \
  -o "${RESULT_DIR}/ITs_all_coverage.xml"

gcovr -r "${ROOT_DIR}" \
  --object-directory "${BUILD_DIR}" \
  --exclude 'tests/' \
  --gcov-ignore-parse-errors negative_hits.warn_once_per_file \
  --json-summary \
  -o "${RESULT_DIR}/coverage-summary.json"

printf '[coverage] report ready: %s\n' "${RESULT_DIR}/ITs_all_coverage.html"

exit "${TEST_RC}"

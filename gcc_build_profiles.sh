#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# gcc_build_profiles.sh
# =============================================================================
#
# Purpose
# -------
# Repo-ready GCC flag profiles for a serious C project.
#
# The file is intentionally verbose. It is both:
#
#   1. a reusable Bash fragment containing arrays of GCC flags; and
#   2. documentation explaining why each flag exists, what it costs, and where
#      it should or should not be used.
#
# Intended usage
# --------------
# Source this file from your build script:
#
#   source ./gcc_build_profiles.sh
#
# Then select one profile:
#
#   gcc "${CFLAGS_TEST[@]}"    src/*.c -o app_test    "${LDFLAGS_TEST[@]}"
#   gcc "${CFLAGS_RELEASE[@]}" src/*.c -o app_release "${LDFLAGS_RELEASE[@]}"
#   gcc "${CFLAGS_EXTREME[@]}" src/*.c -o app_extreme "${LDFLAGS_EXTREME[@]}"
#
# Or print flags for command substitution:
#
#   gcc $(./gcc_build_profiles.sh print-cflags test) src/*.c -o app_test \
#       $(./gcc_build_profiles.sh print-ldflags test)
#
# Or inspect a profile:
#
#   ./gcc_build_profiles.sh explain
#   ./gcc_build_profiles.sh print-cflags release
#
# Philosophy
# ----------
# There are three different ideas that people often mix together:
#
#   1. warnings
#      Compile-time diagnostics. They do not make the final binary slower.
#      They can make compilation noisier. They may reject ugly code if -Werror
#      is used, but this file deliberately does NOT use -Werror.
#
#   2. instrumentation / hardening
#      Runtime checks inserted into the binary. Examples: sanitizers, stack
#      protectors, _FORTIFY_SOURCE. These can make the binary larger/slower.
#
#   3. optimization
#      Code-generation strategy. Examples: -O1, -O2, -O3, -flto,
#      -march=native. These affect runtime speed, binary size, debug quality,
#      and sometimes the visibility of undefined behavior.
#
# The three build profiles below separate these ideas:
#
#   test
#       Maximum practical diagnostics and runtime checking. Heavy. Slow.
#       Use before trusting the code.
#
#   release
#       Fast optimized build with sane hardening. This is the default serious
#       release profile for software that should be fast but not reckless.
#
#   extreme
#       Maximum-speed local-machine build. This intentionally removes some
#       safety/debug features. It is for benchmarks and controlled deployment,
#       not for portable distribution.
#
# Recommended workflow
# --------------------
#
#   1. Build and run tests with: test
#   2. Build and run tests with: release
#   3. Build and run benchmarks with: release
#   4. Build and run benchmarks with: extreme, if you really want to have fun
#
# Important warning
# -----------------
# Passing the test build does NOT mathematically prove that the release or
# extreme build is correct. Optimized builds can expose undefined behavior that
# sanitizer/debug builds did not trigger. Therefore run the same tests under the
# optimized profiles too.
#
# Compatibility note
# ------------------
# This file is written for GCC on Linux/glibc. Some flags are GCC-specific and
# may not exist in Clang, TinyCC, embedded cross-compilers, or old GCC versions.
# If targeting multiple compilers, add a small feature-detection layer.
#
# =============================================================================
# Usage helper
# =============================================================================

_print_array() {
    local -n arr="$1"
    printf '%q ' "${arr[@]}"
    printf '\n'
}

# =============================================================================
# Language / platform policy
# =============================================================================
#
# COMMON_CFLAGS
# -------------
# Flags that define the basic compilation contract of the project.
#
# -std=c11
#     Compile as ISO C11.
#
#     Compile-time cost: none/minimal.
#     Runtime cost: none.
#     Risk: if you use GNU-only syntax, GCC may reject it unless the extension is
#           still accepted as an extension. With -Wpedantic, it will complain.
#
# -D_GNU_SOURCE
#     Expose GNU/glibc extensions in system headers.
#
#     This is useful for Linux systems programming: accept4, pipe2, O_TMPFILE,
#     memfd_create, pthread_setname_np, asprintf, etc.
#
#     Compile-time cost: none.
#     Runtime cost: none.
#     Portability: Linux/glibc-specific behavior becomes easier to depend on.
#
#     Alternative for stricter POSIX code:
#
#       -D_POSIX_C_SOURCE=200809L
#
#     Alternative if you knowingly want GNU C dialect:
#
#       -std=gnu11
#
# -I.
#     Add current directory as an include root. For serious projects, may
#     prefer -Iinclude or -Iapp/include.
#
COMMON_CFLAGS=(
  -std=c11
  -D_POSIX_C_SOURCE=200809L
#  -D_GNU_SOURCE
  -I.
)

# =============================================================================
# Warning group 1: baseline warnings
# =============================================================================
#
# WARN_BASE
# ---------
# These are warnings that are almost always sane for a serious C codebase.
# They are not perfectly silent, but they catch real mistakes frequently.
#
# Runtime cost of all warning flags: none.
# Binary-size cost of all warning flags: none.
# Compile-time cost: usually tiny, except where explicitly noted.
#
WARN_BASE=(
  # -Wall
  #   Enables GCC's common warning set. Despite the name, it does NOT enable all
  #   warnings. It catches many basic mistakes: suspicious control flow,
  #   unused variables, missing returns in many cases, bad printf usage, etc.
  -Wall

  # -Wextra
  #   Adds more useful warnings not included in -Wall. Examples: unused
  #   parameters in some contexts, missing field initializers in some cases,
  #   sign comparisons, etc.
  -Wextra

  # -Wpedantic
  #   Warn when using code that violates the selected ISO C standard.
  #   With -std=c11, this helps detect non-standard constructs.
  #
  #   Important: because this file also defines _GNU_SOURCE, system headers and
  #   your code may intentionally use GNU/POSIX APIs. That is fine. This warning
  #   mainly helps keep your own language syntax honest.
  -Wpedantic

  # -Wformat=2
  #   Strong printf/scanf format checking. This includes extra checks beyond the
  #   default format warnings.
  #
  #   Catches wrong format specifiers, dangerous nonliteral formats in some
  #   cases, and security-sensitive formatting mistakes.
  -Wformat=2

  # -Wshadow
  #   Warn when a local declaration shadows another variable, parameter, global,
  #   or type depending on context.
  #
  #   Value: excellent for maintainability.
  #   Cost: no runtime cost; can be noisy in legacy code.
  -Wshadow

  # -Wundef
  #   Warn if an undefined macro is used in an #if expression.
  #
  #   Example caught:
  #       #if FEATURE_X
  #   when FEATURE_X was never defined.
  #
  #   Safer style:
  #       #if defined(FEATURE_X) && FEATURE_X
  -Wundef

  # -Wmissing-prototypes
  #   Warn if a global function is defined without a previous prototype.
  #
  #   This is extremely useful in C. It catches accidental external functions
  #   that should have been static, and public functions missing from headers.
  -Wmissing-prototypes

  # -Wstrict-prototypes
  #   Warn about old-style prototypes like:
  #       int f();
  #   In C, that does NOT mean "function with no parameters". It means
  #   "function with unspecified parameters".
  #
  #   Proper C prototype:
  #       int f(void);
  -Wstrict-prototypes

  # -Wold-style-definition
  #   Warn about K&R-style function definitions.
  #
  #   Modern C code should use prototype-style definitions only.
  -Wold-style-definition

  # -Wmissing-declarations
  #   Warn if a global function has no previous declaration.
  #
  #   This overlaps somewhat with -Wmissing-prototypes, but it is still useful
  #   when trying to keep external symbols intentional.
  -Wmissing-declarations

  # -Wreturn-type
  #   Warn about functions that should return a value but may not.
  #   Usually included by -Wall, but kept explicit here because it is critical.
  -Wreturn-type

  # -Wimplicit-fallthrough=5
  #   Warn about switch cases that fall through without an explicit recognized
  #   annotation.
  #
  #   Level 5 is strict. Prefer the C attribute when available:
  #       __attribute__((fallthrough));
  #   or a project macro around it.
  -Wimplicit-fallthrough=5

  # -Wswitch-enum
  #   Warn when a switch over an enum does not handle all enum values.
  #
  #   Very useful for finite-state machines and typed status enums.
  #   Can be noisy if you intentionally use default for many enums.
  -Wswitch-enum

  # -Wswitch-default
  #   Warn when a switch does not have a default case.
  #
  #   Note: there is a style tension with -Wswitch-enum. For safety-critical-ish
  #   code, one common pattern is:
  #       - explicitly list all enum cases;
  #       - still have default for corrupted/out-of-range values.
  -Wswitch-default
)

# =============================================================================
# Warning group 2: strict value/type/memory warnings
# =============================================================================
#
# WARN_STRICT
# -----------
# These warnings are very valuable, but they force discipline. They may require
# explicit casts, better type choices, and better API design.
#
WARN_STRICT=(
  # -Wconversion
  #   Warn for implicit conversions that may change a value.
  #
  #   Examples:
  #       uint32_t x = some_uint64;
  #       int i = some_size_t;
  #       uint8_t b = 300;
  #
  #   Value: excellent for serialization, binary formats, UUIDs, file sizes,
  #   indexes, wire protocols, endian code, and embedded targets.
  #
  #   Pain: high. You will need explicit casts at intentional boundaries.
  -Wconversion

  # -Wsign-conversion
  #   Warn for implicit conversions that change signedness.
  #
  #   This is extremely useful in C because size_t/int mixing is a bug factory.
  #   It is also noisy until the codebase is disciplined.
  -Wsign-conversion

  # -Wdouble-promotion
  #   Warn when float is implicitly promoted to double.
  #
  #   Useful in embedded/FP-heavy code. Less relevant for integer-only systems
  #   code. Can be noisy around printf because float arguments are promoted to
  #   double by the C calling convention for variadic functions.
  -Wdouble-promotion

  # -Wfloat-equal
  #   Warn when comparing floating-point values with == or !=.
  #
  #   Useful for numerical code, control code, simulation, and filters, where
  #   exact equality is often suspicious.
  #
  #   May be annoying if you intentionally compare against 0.0, NaN-handling
  #   patterns, or exact encoded values.
  -Wfloat-equal

  # -Wcast-qual
  #   Warn when a cast removes const or volatile qualifiers.
  #
  #   Very useful for API hygiene. Removing const is often a design smell.
  #   Removing volatile can be disastrous for MMIO/concurrency-ish code.
  -Wcast-qual

  # -Wcast-align=strict
  #   Warn when a cast may increase alignment requirements.
  #
  #   Example danger:
  #       uint8_t *p = ...;
  #       uint64_t *q = (uint64_t *)p;
  #
  #   On x86 this may merely be slower. On other architectures it may fault.
  #   Very relevant for portable C and embedded targets.
  -Wcast-align=strict

  # -Wwrite-strings
  #   Give string literals type "const char[N]" for warning purposes.
  #
  #   This catches code that tries to modify string literals or stores them in
  #   mutable char * pointers.
  -Wwrite-strings

  # -Wpointer-arith
  #   Warn about pointer arithmetic on void* or function pointers.
  #
  #   GNU C allows void* arithmetic as an extension. ISO C does not.
  #   Prefer uint8_t* / char* when doing byte addressing.
  -Wpointer-arith

  # -Wbad-function-cast
  #   Warn when a function call result is cast to an incompatible type.
  #
  #   Useful in C code with factory functions, integer/pointer conversion
  #   mistakes, or old-style APIs.
  -Wbad-function-cast

  # -Wstrict-aliasing=3
  #   Warn about code that may violate strict aliasing rules.
  #
  #   Important when using -O2/-O3 because GCC optimizes assuming strict
  #   aliasing by default. Many ugly type-punning tricks are undefined behavior.
  #
  #   Safer type-punning tools:
  #       memcpy
  #       unions only when used with care and compiler support
  #       explicit byte buffers
  -Wstrict-aliasing=3

  # -Wvla
  #   Warn on variable-length arrays.
  #
  #   VLAs can create unpredictable stack usage. For robust systems code, avoid
  #   them unless you have a very explicit reason.
  -Wvla

  # -Walloca
  #   Warn on alloca().
  #
  #   alloca() consumes stack dynamically and is hard to reason about. Avoid in
  #   robust systems code.
  -Walloca

  # -Wmissing-field-initializers
  #   Warn when aggregate initialization does not initialize every field.
  #
  #   Note: this can be annoying with idioms like {0}. GCC usually treats {0}
  #   specially, but designated initializers are often clearer:
  #       struct cfg c = { .mode = MODE_X, .size = 42 };
  -Wmissing-field-initializers
)

# =============================================================================
# Warning group 3: paranoid / GCC-specific diagnostics
# =============================================================================
#
# WARN_PARANOID
# -------------
# These are useful for serious test builds, but more compiler-version-sensitive
# and sometimes noisy. They are intentionally kept separate.
#
WARN_PARANOID=(
  # -Wduplicated-cond
  #   Warn about duplicated conditions in if/else chains.
  #
  #   Example:
  #       if (x == 1) { ... }
  #       else if (x == 1) { ... }
  -Wduplicated-cond

  # -Wduplicated-branches
  #   Warn when two branches contain identical code.
  #
  #   Sometimes catches copy/paste bugs. Sometimes complains about deliberate
  #   symmetry. Good for test builds.
  -Wduplicated-branches

  # -Wlogical-op
  #   Warn about suspicious logical expressions.
  #
  #   Example classes: self-comparisons, always-true/false logic, duplicated
  #   operands. GCC-specific and occasionally noisy.
  -Wlogical-op

  # -Wnull-dereference
  #   Warn when GCC can prove a null pointer is dereferenced.
  #
  #   More effective with optimization enabled. No runtime cost.
  -Wnull-dereference

  # -Warray-bounds=2
  #   Stronger array bounds diagnostics.
  #
  #   More effective with optimization. Can find real bugs in fixed-size array
  #   code, serialization code, and manual buffers.
  -Warray-bounds=2

  # -Wstringop-overflow=4
  #   Aggressive warnings for overflowing string/memory builtins like memcpy,
  #   strcpy, memset, etc., when GCC can reason about object sizes.
  #
  #   Very useful with _FORTIFY_SOURCE and optimization.
  -Wstringop-overflow=4

  # -Wformat-overflow=2
  #   Warn when sprintf-like formatting may overflow the destination buffer.
  -Wformat-overflow=2

  # -Wformat-truncation=2
  #   Warn when snprintf-like formatting may truncate output.
  #
  #   Note: truncation is not always a bug if you intentionally handle it.
  -Wformat-truncation=2

  # -Walloc-zero
  #   Warn about allocations of size zero.
  #
  #   malloc(0) is implementation-defined-ish in practical behavior and often
  #   indicates a missing validation path.
  -Walloc-zero

  # -Wsizeof-pointer-memaccess
  #   Warn about suspicious sizeof(pointer) used in memory operations.
  #
  #   Example:
  #       memset(ptr, 0, sizeof(ptr));    // probably wrong
  -Wsizeof-pointer-memaccess

  # -Wsizeof-array-div
  #   Warn about suspicious sizeof(array) / sizeof(pointer-or-wrong-type)
  #   element-count calculations.
  -Wsizeof-array-div

  # -Wmemset-elt-size
  #   Warn when memset appears to use element count instead of byte count.
  -Wmemset-elt-size

  # -Wmemset-transposed-args
  #   Warn about suspicious memset argument order.
  #
  #   Example:
  #       memset(buf, sizeof(buf), 0);    // probably meant memset(buf, 0, sizeof buf)
  -Wmemset-transposed-args

  # -Wtrampolines
  #   Warn when GCC must generate trampolines, often caused by nested functions
  #   whose addresses escape.
  #
  #   Trampolines can require executable stack. Avoid in hardened/portable C.
  -Wtrampolines

  # -Wdate-time
  #   Warn on __DATE__, __TIME__, __TIMESTAMP__.
  #
  #   These macros make builds non-reproducible.
  -Wdate-time

  # -Wredundant-decls
  #   Warn about redundant declarations.
  #
  #   Useful for header hygiene, but can be noisy if system headers or legacy
  #   patterns repeat declarations.
  -Wredundant-decls

  # -Wstrict-overflow=5
  #   Warn about optimizations based on the assumption that signed overflow is
  #   undefined behavior.
  #
  #   This can be very noisy. It is useful when auditing integer-heavy code.
  #   Do not blindly panic at every warning; inspect the expression.
  -Wstrict-overflow=5
)

# =============================================================================
# Static analyzer group
# =============================================================================
#
# GCC_ANALYZER_FLAGS
# ------------------
# -fanalyzer enables GCC's path-sensitive static analyzer.
#
# It tries to find problems such as:
#   - double free;
#   - use after free;
#   - file descriptor leaks;
#   - memory leaks;
#   - null dereferences;
#   - use of uninitialized values;
#   - impossible paths.
#
# Compile-time cost: can be very high.
# Runtime cost: none.
# Binary-size cost: none.
# False positives: possible.
# Recommended: use in the test/audit build, not necessarily on every edit.
#
GCC_ANALYZER_FLAGS=(
  -fanalyzer
)

# =============================================================================
# Sanitizer groups
# =============================================================================
#
# Sanitizers insert runtime instrumentation into the binary. They are among the
# best tools available for C testing, but they are NOT release flags.
#
# Important sanitizer rule
# ------------------------
# AddressSanitizer and ThreadSanitizer should not be mixed in the same build.
# Use separate profiles.
#
# This file's main "test" profile uses ASan + UBSan + LSan.
# If you need TSAN, use CFLAGS_TSAN / LDFLAGS_TSAN below.
#
SANITIZER_ADDRESS_UNDEFINED_LEAK=(
  # -fsanitize=address
  #   Detects many memory bugs:
  #       heap buffer overflow
  #       stack buffer overflow
  #       global buffer overflow
  #       use after free
  #       use after scope in some cases
  #
  #   Runtime cost: high, commonly ~1.5x-3x slower.
  #   Memory cost: high, often ~2x or more.
  #   Release use: no.
  -fsanitize=address

  # -fsanitize=undefined
  #   Detects many forms of undefined behavior at runtime:
  #       signed integer overflow
  #       invalid shifts
  #       misaligned access
  #       null passed where nonnull is required
  #       out-of-bounds in some cases
  #       invalid enum values in some cases
  #
  #   Runtime cost: moderate.
  #   Release use: generally no, except special hardened diagnostic builds.
  -fsanitize=undefined

  # -fsanitize=leak
  #   Detects memory leaks at process exit.
  #
  #   Note: often included with AddressSanitizer on Linux, but explicit is fine.
  #   Runtime cost: mostly at shutdown/reporting.
  -fsanitize=leak
)

SANITIZER_THREAD=(
  # -fsanitize=thread
  #   Detects data races and some threading misuse.
  #
  #   Runtime cost: very high, commonly 5x-15x slower.
  #   Memory cost: high.
  #   Cannot be combined with AddressSanitizer.
  #   Use for concurrent code: worker threads, queues, reactors, caches, etc.
  -fsanitize=thread
)

# =============================================================================
# Instrumentation / hardening flags
# =============================================================================
#
# These affect generated code. Use in test and release-safe profiles. Remove in
# extreme only if you deliberately want maximum speed/minimum overhead.
#
HARDENING_FLAGS=(
  # -fstack-protector-strong
  #   Adds stack canary checks to functions that are more likely to suffer stack
  #   smashing: local arrays, address-taken locals, etc.
  #
  #   Runtime cost: usually small.
  #   Binary-size cost: small.
  #   Security value: good.
  #   Extreme-speed choice: may remove with -fno-stack-protector.
  -fstack-protector-strong

  # -D_FORTIFY_SOURCE=3
  #   Enables extra glibc checks for certain libc calls when optimization is on.
  #
  #   Examples: memcpy, strcpy, sprintf, etc., may get compile-time or runtime
  #   object-size checks.
  #
  #   Requires optimization to be useful: -O1 or higher.
  #   Runtime cost: usually small, sometimes none, occasionally measurable.
  #   Portability: glibc-specific. Level 3 requires sufficiently recent glibc/GCC.
  #
  #   If your toolchain rejects level 3, use:
  #       -D_FORTIFY_SOURCE=2
  -D_FORTIFY_SOURCE=3

  # -fno-common
  #   Make tentative global definitions behave strictly.
  #
  #   Catches accidental multiple global definitions at link time.
  #   Modern GCC defaults to -fno-common already, but keeping it explicit makes
  #   the policy visible.
  #
  #   Runtime cost: none.
  -fno-common
)

# =============================================================================
# Debuggability flags
# =============================================================================
#
DEBUGGABILITY_FLAGS=(
  # -g3
  #   Emit maximum debug information, including macro definitions.
  #
  #   Runtime cost: normally none.
  #   Binary/object/debug file size: much larger.
  #   Compile/link cost: somewhat higher.
  -g3

  # -fno-omit-frame-pointer
  #   Keep frame pointers.
  #
  #   Runtime cost: small on some architectures/workloads.
  #   Debug/profiling value: excellent. Stack traces become more reliable.
  -fno-omit-frame-pointer
)

# =============================================================================
# Optimization groups
# =============================================================================
#
OPT_TEST=(
  # -O1
  #   Light optimization.
  #
  #   Why not -O0 for sanitizer testing?
  #   Because some compiler diagnostics and sanitizer checks work better when
  #   the compiler performs at least basic analysis. -O1 is a good sanitizer
  #   default.
  #
  #   Runtime: much faster than -O0, slower than -O2/-O3.
  #   Debuggability: still decent with -g3 and frame pointers.
  -O1
)

OPT_DEBUG=(
  # -Og
  #   Optimize for debugging experience.
  #
  #   Good for stepping in GDB. Not the strongest sanitizer choice, not the
  #   fastest runtime choice.
  -Og
)

OPT_RELEASE=(
  # -O3
  #   Aggressive optimization.
  #
  #   Enables more inlining, vectorization, loop transformations, and other
  #   optimizations beyond -O2.
  #
  #   Runtime: often fastest, but not always. Sometimes -O2 is smaller/faster.
  #   Compile time: higher than -O2.
  #   Binary size: may increase due to inlining/unrolling.
  #   Risk: exposes undefined behavior more brutally.
  -O3

  # -DNDEBUG
  #   Disables assert() from <assert.h>.
  #
  #   Runtime: removes assertion checks.
  #   Risk: if your program relies on assert side effects, the program is wrong.
  #   Never write:
  #       assert(init_thing() == 0);
  #   if init_thing() must run in release.
  -DNDEBUG

  # -flto
  #   Link Time Optimization.
  #
  #   Allows optimization across translation units.
  #
  #   Runtime: can improve speed and/or reduce size.
  #   Compile/link time: higher, sometimes much higher.
  #   Tooling risk: needs compatible compiler, linker plugin, and archive tools.
  #   Use gcc-ar/gcc-ranlib for static libraries when needed.
  -flto
)

OPT_EXTREME=(
  # -O3
  #   Same aggressive optimization as release.
  -O3

  # -DNDEBUG
  #   Remove assert() checks.
  -DNDEBUG

  # -flto
  #   Whole-program-ish optimization at link time.
  -flto

  # -march=native
  #   Generate instructions for the CPU of the build machine.
  #
  #   Runtime: can improve performance significantly for CPU-heavy code.
  #   Portability: bad for distributing binaries. The program may crash with
  #   illegal instruction on older/different CPUs.
  #
  #   Excellent for local benchmarks and deployment to identical machines.
  -march=native

  # -fomit-frame-pointer
  #   Allow compiler to use the frame pointer register for general optimization.
  #
  #   Runtime: sometimes small speed gain.
  #   Debug/profiling: worse stack traces on some platforms/tools.
  -fomit-frame-pointer

  # -fno-stack-protector
  #   Explicitly remove stack canaries.
  #
  #   Runtime: tiny speed/size gain in affected functions.
  #   Security/safety: worse.
  #
  #   Use only for the "I want the lightest fastest local binary" profile.
  -fno-stack-protector

  # -U_FORTIFY_SOURCE
  #   Undefine _FORTIFY_SOURCE if inherited from environment or distro flags.
  #
  #   Runtime: may remove some libc object-size checks.
  #   Safety: worse.
  #   Use only when you explicitly want no fortify overhead/checking.
  -U_FORTIFY_SOURCE
)

# =============================================================================
# Optional dangerous optimization: -Ofast
# =============================================================================
#
# This file deliberately does NOT use -Ofast by default.
#
# -Ofast enables -O3 plus optimizations that may violate strict standards
# semantics, especially floating-point behavior. It may imply flags such as
# -ffast-math depending on compiler version.
#
# For robotics, simulation, filters, control, orbital math, geometry, and any
# code where NaN/Inf/rounding/IEEE behavior matters: do not casually use -Ofast.
#
# For pure integer-heavy systems code, it may be worth benchmarking, but still
# test carefully.
#
# If you want an experimental profile, add -Ofast manually and compare against
# -O3 with tests and benchmarks.
#

# =============================================================================
# Build profiles
# =============================================================================

# TEST PROFILE
# ------------
# Maximum practical diagnostics.
#
# Use for:
#   - unit tests;
#   - fuzz tests;
#   - integration tests;
#   - filesystem/path/database stress tests;
#   - pre-release bug hunting.
#
# Properties:
#   Compile time: high.
#   Runtime speed: slow.
#   Memory usage: high.
#   Debuggability: good.
#   Release suitability: no.
#
CFLAGS_TEST=(
  "${COMMON_CFLAGS[@]}"
  "${WARN_BASE[@]}"
  "${WARN_STRICT[@]}"
  "${WARN_PARANOID[@]}"
  "${GCC_ANALYZER_FLAGS[@]}"
  "${OPT_TEST[@]}"
  "${DEBUGGABILITY_FLAGS[@]}"
  "${SANITIZER_ADDRESS_UNDEFINED_LEAK[@]}"
  "${HARDENING_FLAGS[@]}"
)

LDFLAGS_TEST=(
  "${SANITIZER_ADDRESS_UNDEFINED_LEAK[@]}"
)

# TSAN PROFILE
# ------------
# Separate thread-sanitizer profile. Use this when auditing concurrent code.
#
# Properties:
#   Compile time: high.
#   Runtime speed: very slow.
#   Memory usage: very high.
#   Release suitability: no.
#
CFLAGS_TSAN=(
  "${COMMON_CFLAGS[@]}"
  "${WARN_BASE[@]}"
  "${WARN_STRICT[@]}"
  "${WARN_PARANOID[@]}"
  "${OPT_TEST[@]}"
  "${DEBUGGABILITY_FLAGS[@]}"
  "${SANITIZER_THREAD[@]}"
  -fno-common
)

LDFLAGS_TSAN=(
  "${SANITIZER_THREAD[@]}"
)

# RELEASE PROFILE
# ---------------
# Fast optimized build with sane hardening.
#
# Use for:
#   - normal release;
#   - realistic performance testing;
#   - deployed binaries where safety still matters.
#
# Properties:
#   Compile time: medium/high because of -O3 and -flto.
#   Runtime speed: high.
#   Memory usage: normal.
#   Debuggability: lower than test/debug.
#   Safety: still keeps stack protector and fortify.
#
CFLAGS_RELEASE=(
  "${COMMON_CFLAGS[@]}"
  "${WARN_BASE[@]}"
  "${WARN_STRICT[@]}"
  "${OPT_RELEASE[@]}"
  "${HARDENING_FLAGS[@]}"
)

LDFLAGS_RELEASE=(
  -flto
)

# EXTREME PROFILE
# ---------------
# Maximum-speed local-machine build.
#
# Use for:
#   - benchmark experiments;
#   - local-only binaries;
#   - controlled deployment to known identical CPUs;
#   - cases where you explicitly accept less hardening/debuggability.
#
# Properties:
#   Compile time: high.
#   Runtime speed: potentially highest.
#   Memory usage: normal.
#   Debuggability: low.
#   Portability: low because of -march=native.
#   Safety/hardening: intentionally reduced.
#
# This is the "fastest in the world, fuck it" profile, but do not confuse it
# with the safest release profile.
#
CFLAGS_EXTREME=(
  "${COMMON_CFLAGS[@]}"

  # Keep baseline warnings because they have no runtime cost.
  # Remove even these only if a third-party dependency makes your build noisy.
  "${WARN_BASE[@]}"

  "${OPT_EXTREME[@]}"
)

LDFLAGS_EXTREME=(
  -flto
)

# DEBUG PROFILE
# -------------
# Not part of the requested test/release/extreme trio, but useful in practice.
#
# Use when you want easy GDB stepping rather than maximum bug detection.
#
CFLAGS_DEBUG=(
  "${COMMON_CFLAGS[@]}"
  "${WARN_BASE[@]}"
  "${WARN_STRICT[@]}"
  "${OPT_DEBUG[@]}"
  "${DEBUGGABILITY_FLAGS[@]}"
  -fno-inline
  -fstack-protector-strong
)

LDFLAGS_DEBUG=()

# =============================================================================
# Build-time / runtime cost summary
# =============================================================================
#
# Rough qualitative costs:
#
#   warnings only
#       Compile time: low to medium
#       Runtime cost: none
#       Binary size: none
#
#   -fanalyzer
#       Compile time: high to very high
#       Runtime cost: none
#       Binary size: none
#
#   -fsanitize=address
#       Compile time: medium
#       Runtime cost: high
#       Memory cost: high
#       Binary size: higher
#
#   -fsanitize=undefined
#       Compile time: medium
#       Runtime cost: low to medium
#       Binary size: higher
#
#   -fsanitize=thread
#       Compile time: high
#       Runtime cost: very high
#       Memory cost: very high
#
#   -fstack-protector-strong
#       Compile time: tiny
#       Runtime cost: usually tiny
#       Binary size: slightly higher
#
#   -D_FORTIFY_SOURCE=3
#       Compile time: low
#       Runtime cost: usually low/tiny
#       Binary size: maybe slightly higher
#
#   -O3
#       Compile time: medium/high
#       Runtime speed: usually high, sometimes not better than -O2
#       Binary size: can increase
#
#   -flto
#       Compile/link time: high
#       Runtime speed: can improve
#       Binary size: can improve or worsen
#       Tooling: needs compatible build pipeline
#
#   -march=native
#       Compile time: normal
#       Runtime speed: can improve
#       Portability: bad outside the build machine class
#
# =============================================================================
# Suggested make/build-script policy
# =============================================================================
#
# Suggested default:
#
#   during development:
#       debug or test
#
#   before merging:
#       test + tsan if threaded + release
#
#   before performance claims:
#       release benchmark
#       extreme benchmark only after release passes tests
#
#   for CI:
#       test
#       tsan where relevant
#       release
#
# Optional CI strictness:
#   Add -Werror in CI only after the warning set is stable.
#   Do not put -Werror into this file by default; it makes compiler upgrades
#   and third-party headers unnecessarily painful.
#
# =============================================================================
# Command-line interface
# =============================================================================

_explain() {
    cat <<'TXT'
Available profiles:

  test
      Heavy diagnostics: all warning groups, GCC static analyzer,
      ASan + UBSan + LSan, debug info, frame pointers, hardening.

  tsan
      ThreadSanitizer profile. Use separately from address sanitizer.

  release
      Normal serious optimized release: -O3, -flto, -DNDEBUG,
      warnings, stack protector, fortify.

  extreme
      Fastest local-machine profile: -O3, -flto, -march=native,
      no frame pointer, no stack protector, no fortify.

  debug
      GDB-friendly profile: -Og, -g3, frame pointers, no forced inlining.

Examples:

  gcc $(./gcc_build_profiles.sh print-cflags test) src/*.c -o app_test \
      $(./gcc_build_profiles.sh print-ldflags test)

  gcc $(./gcc_build_profiles.sh print-cflags release) src/*.c -o app_release \
      $(./gcc_build_profiles.sh print-ldflags release)

  source ./gcc_build_profiles.sh
  gcc "${CFLAGS_TEST[@]}" src/*.c -o app_test "${LDFLAGS_TEST[@]}"
TXT
}

_profile_to_array_name() {
    case "$1" in
        test)    printf 'CFLAGS_TEST\n' ;;
        tsan)    printf 'CFLAGS_TSAN\n' ;;
        release) printf 'CFLAGS_RELEASE\n' ;;
        extreme) printf 'CFLAGS_EXTREME\n' ;;
        debug)   printf 'CFLAGS_DEBUG\n' ;;
        *)
            printf 'unknown profile: %s\n' "$1" >&2
            return 1
            ;;
    esac
}

_profile_to_ldarray_name() {
    case "$1" in
        test)    printf 'LDFLAGS_TEST\n' ;;
        tsan)    printf 'LDFLAGS_TSAN\n' ;;
        release) printf 'LDFLAGS_RELEASE\n' ;;
        extreme) printf 'LDFLAGS_EXTREME\n' ;;
        debug)   printf 'LDFLAGS_DEBUG\n' ;;
        *)
            printf 'unknown profile: %s\n' "$1" >&2
            return 1
            ;;
    esac
}

_main() {
    local cmd="${1:-}"
    local profile="${2:-}"
    local arr_name

    case "$cmd" in
        explain|'')
            _explain
            ;;

        print-cflags)
            if [[ -z "$profile" ]]; then
                printf 'usage: %s print-cflags {test|tsan|release|extreme|debug}\n' "$0" >&2
                return 2
            fi
            arr_name="$(_profile_to_array_name "$profile")" || return 2
            _print_array "$arr_name"
            ;;

        print-ldflags)
            if [[ -z "$profile" ]]; then
                printf 'usage: %s print-ldflags {test|tsan|release|extreme|debug}\n' "$0" >&2
                return 2
            fi
            arr_name="$(_profile_to_ldarray_name "$profile")" || return 2
            _print_array "$arr_name"
            ;;

        *)
            printf 'unknown command: %s\n' "$cmd" >&2
            printf 'usage: %s {explain|print-cflags|print-ldflags} [profile]\n' "$0" >&2
            return 2
            ;;
    esac
}

# Only execute the helper CLI when run as a script, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _main "$@"
fi

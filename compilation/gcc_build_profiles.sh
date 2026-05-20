#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# MARK: File Overview
# gcc_build_profiles.sh
# =============================================================================
#
# Purpose
# -------
# Repository-ready GCC build profiles for a production-quality C project.
#
# This file is intentionally detailed. It serves two roles:
#
#   1. a reusable Bash fragment that exposes GCC flag arrays; and
#   2. a reference document describing why each flag is present, what trade-offs
#      it introduces, and where it should or should not be used.
#
# Intended usage
# --------------
# Source this file from your build script:
#
#   source ./gcc_build_profiles.sh
#
# Then select one profile:
#
#   gcc "${CFLAGS_DEBUG[@]}"   src/*.c -o app_debug   "${LDFLAGS_DEBUG[@]}"
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
# Design Principles
# -----------------
# Build configuration discussions often blur together concerns that should be
# evaluated independently. This file keeps them separate:
#
#   1. warnings
#      Compile-time diagnostics. They do not make the final binary slower.
#      They can increase build noise and, if paired with -Werror, can make the
#      build more brittle across compiler versions. This file deliberately does
#      not enable -Werror by default.
#
#   2. instrumentation / hardening
#      Runtime checks or safety mechanisms inserted into the generated binary.
#      Examples include sanitizers, stack protectors, and _FORTIFY_SOURCE.
#      These may increase runtime cost and binary size.
#
#   3. optimization
#      Code-generation policy. Examples include -O1, -O2, -O3, -flto, and
#      -march=native. These affect runtime performance, binary size, debugging
#      quality, and sometimes whether latent undefined behavior becomes visible.
#
# The profiles below keep those concerns explicit:
#
#   debug
#       GDB-oriented development profile. Prioritizes inspectability and
#       predictable stepping behavior.
#
#   test
#       High-diagnostic validation profile with extensive warnings, runtime
#       checks, and debugging support.
#
#   release
#       Optimized production profile with sensible hardening. This is the
#       default release configuration for software that must be fast without
#       abandoning baseline defensive measures.
#
#   extreme
#       Maximum-performance local-machine profile. It intentionally removes some
#       safety and debugging features and is intended for benchmarking or tightly
#       controlled deployment, not for general distribution.
#
#   tsan
#       Optional dedicated ThreadSanitizer profile for concurrency analysis.
#
# Recommended workflow
# --------------------
#
#   1. Develop with: debug
#   2. Validate with: test
#   3. Re-run the same tests with: release
#   4. Benchmark with: release
#   5. Use: extreme only when there is a concrete need to pursue the final
#      increment of performance
#   6. Use: tsan when auditing concurrent code
#
# Important Note
# --------------
# Passing the test profile does not prove that the release or extreme profiles
# are correct. Optimized builds can expose undefined behavior that did not
# manifest under sanitizer-heavy or debug-oriented builds. The same test suite
# should therefore be exercised under the optimized profiles as well.
#
# Compatibility Note
# ------------------
# This file targets GCC on Linux/glibc. Several flags are GCC-specific and may
# be unavailable in Clang, TinyCC, embedded cross-compilers, or older GCC
# releases. If the project must support multiple toolchains, add a small
# feature-detection or compatibility layer rather than weakening the policy
# globally.
#
# =============================================================================
# MARK: Helpers
# Usage helper
# =============================================================================

_print_array() {
    local -n arr="$1"
    printf '%q ' "${arr[@]}"
    printf '\n'
}

# =============================================================================
# MARK: Language And Platform Policy
# Language / platform policy
# =============================================================================
#
# CFLAGS_BASE
# -------------
# Flags that define the project's baseline compilation contract.
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
#     Add the current directory as an include root. In larger projects, a more
#     explicit include layout such as -Iinclude or -Iapp/include is often
#     preferable.
#

CFLAGS_LANGUAGE=(
  -std=c11
)

CPPFLAGS_FEATURES=(
  # -D_GNU_SOURCE
  -D_POSIX_C_SOURCE=200809L
)

CPPFLAGS_INCLUDES=(
  -I.
)

CFLAGS_BASE=(
  "${CFLAGS_LANGUAGE[@]}"
  "${CPPFLAGS_FEATURES[@]}"
  "${CPPFLAGS_INCLUDES[@]}"
)

# =============================================================================
# MARK: Baseline Warnings
# Warning group 1: baseline warnings
# =============================================================================
#
# CFLAGS_WARN_BASE
# ---------
# These are warnings that are almost always sane for a serious C codebase.
# They are not perfectly silent, but they catch real mistakes frequently.
#
# Runtime cost of all warning flags: none.
# Binary-size cost of all warning flags: none.
# Compile-time cost: usually tiny, except where explicitly noted.
#
CFLAGS_WARN_BASE=(
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
  #   the code may intentionally use GNU/POSIX APIs. That is fine. This warning
  #   mainly helps keep the code language syntax honest.
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
  #   Cost: no runtime cost;
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
  #   That does NOT mean "function with no parameters".
  #   It means "function with unspecified parameters".
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
  #   Usually included by -Wall, kept explicit because it is critical.
  -Wreturn-type

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
  #   Pain: high. Always need explicit casts at intentional boundaries.
  -Wconversion

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
  #   Sometimes catches copy/paste bugs.
  #   Sometimes complains about deliberate symmetry.
  #   Good for test builds.
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

  # -Wsign-conversion
  #   Warn for implicit conversions that change signedness.
  #
  #   This is extremely useful in C because size_t/int mixing is a bug factory.
  #   It is also noisy until the codebase is disciplined.
  -Wsign-conversion

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
  #   Can be noisy if default is intentionally used for many enums.
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
# MARK: Strict Warnings
# Warning group 2: strict value/type/memory warnings
# =============================================================================
#
# CFLAGS_WARN_STRICT
# -----------
# These warnings are very valuable, but they force discipline.
# May require explicit casts, better type choices, and better API design.
#
CFLAGS_WARN_STRICT=(
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
  #   GNU C allows void* arithmetic as an extension.
  #   ISO C does not.
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
  #   aliasing by default.
  #   Many ugly type-punning tricks are undefined behavior.
  #
  #   Safer type-punning tools:
  #       memcpy
  #       unions only when used with care and compiler support
  #       explicit byte buffers
  -Wstrict-aliasing=3

  # -Wvla
  #   Warn on variable-length arrays.
  #
  #   VLAs can create unpredictable stack usage.
  #   For robust systems code, avoid
  #   them unless you have a very explicit reason.
  -Wvla

  # -Walloca
  #   Warn on alloca().
  #
  #   alloca() consumes stack dynamically and is hard to reason about.
  #   Avoid in robust systems code.
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
# MARK: Paranoid Warnings
# Warning group 3: paranoid / GCC-specific diagnostics
# =============================================================================
#
# CFLAGS_WARN_PARANOID
# -------------
# These are useful for serious test builds, but more compiler-version-sensitive
# and sometimes noisy.
# They are intentionally kept separate.
#
CFLAGS_WARN_PARANOID=(
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
  #   malloc(0) is implementation-defined-ish in practical behavior.
  #   Often indicates a missing validation path.
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
# MARK: GCC Analyzer
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
# MARK: Sanitizers
# Sanitizer groups
# =============================================================================
#
# Sanitizers insert runtime instrumentation into the binary.
# They are among the best tools available for C testing,
# but they are NOT for release.
#
# Important sanitizer rule
# ------------------------
# AddressSanitizer and ThreadSanitizer should not be mixed in the same build.
# Use separate profiles.
#
# This file's main "test" profile uses ASan + UBSan + LSan.
# If you need TSAN, use CFLAGS_TSAN / LDFLAGS_TSAN below.
#
CFLAGS_SANITIZER_ADDRESS=(
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

CFLAGS_SANITIZER_THREAD=(
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
# MARK: Hardening
# Instrumentation / hardening flags
# =============================================================================
#
# These flags alter generated code. They belong in validation and production
# profiles by default, and should only be removed in the extreme profile when
# lower overhead is explicitly more important than defensive hardening.
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
# MARK: Debuggability
# Debuggability flags
# =============================================================================
#
CFLAGS_DEBUG=(
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
# MARK: Optimization Groups
# Optimization groups
# =============================================================================
#
CFLAGS_OPT_TEST=(
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

CFLAGS_OPT_DEBUG=(
  # -Og
  #   Optimize for debugging experience.
  #
  #   Good for stepping in GDB. Not the strongest sanitizer choice, not the
  #   fastest runtime choice.
  -Og
)

CFLAGS_OPT_RELEASE=(
  # -O3
  #   Aggressive optimization.
  #
  #   Enables more inlining, vectorization, loop transformations, and other
  #   optimizations beyond -O2.
  #
  #   Runtime: often fastest, but not always. Sometimes -O2 is smaller/faster.
  #   Compile time: higher than -O2.
  #   Binary size: may increase due to inlining/unrolling.
#   Risk: can make latent undefined behavior surface more aggressively.
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

CFLAGS_OPT_EXTREME=(
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
# MARK: Ofast Policy
# Optional dangerous optimization: -Ofast
# =============================================================================
#
# This file deliberately does not use -Ofast by default.
#
# -Ofast enables -O3 plus optimizations that may violate strict standards
# semantics, especially floating-point behavior. It may imply flags such as
# -ffast-math depending on compiler version.
#
# For robotics, simulation, filtering, control, orbital math, geometry, and any
# code where NaN/Inf handling, rounding, or IEEE semantics matter, -Ofast
# should not be adopted casually.
#
# For pure integer-heavy systems code, it may be worth benchmarking, but still
# test carefully.
#
# If you want an experimental profile, add -Ofast manually and compare against
# -O3 with tests and benchmarks.
#

# =============================================================================
# MARK: Build Profiles
# Build profiles
# =============================================================================

# MARK: Debug Profile
# DEBUG PROFILE
# -------------
# GDB-oriented development profile.
#
# Use for:
#   - day-to-day development;
#   - interactive debugging;
#   - stepping through control flow;
#   - investigation of logic issues where minimal optimization helps.
#
# Properties:
#   Compile time: low to medium.
#   Runtime speed: moderate.
#   Memory usage: normal.
#   Debuggability: excellent.
#   Release suitability: not suitable.
#
# Not part of the main validation/release path, but extremely useful in
# practice.
#
CFLAGS_DEBUG=(
  "${CFLAGS_BASE[@]}"
  "${CFLAGS_WARN_BASE[@]}"
  "${CFLAGS_WARN_STRICT[@]}"
  "${CFLAGS_OPT_DEBUG[@]}"
  "${CFLAGS_DEBUG[@]}"
  -fno-inline
  -fstack-protector-strong
)

LDFLAGS_DEBUG=()

# MARK: Test Profile
# TEST PROFILE
# ------------
# High-diagnostic validation profile.
#
# Use for:
#   - unit tests;
#   - fuzz tests;
#   - integration tests;
#   - filesystem, path, and database stress tests;
#   - pre-release defect hunting.
#
# Properties:
#   Compile time: high.
#   Runtime speed: slow.
#   Memory usage: high.
#   Debuggability: good.
#   Release suitability: not suitable.
#
CFLAGS_TEST=(
  "${CFLAGS_BASE[@]}"
  "${CFLAGS_WARN_BASE[@]}"
  "${CFLAGS_WARN_STRICT[@]}"
  "${CFLAGS_WARN_PARANOID[@]}"
  "${CFLAGS_OPT_TEST[@]}"
  "${CFLAGS_DEBUG[@]}"
  "${CFLAGS_SANITIZER_ADDRESS[@]}"
  "${GCC_ANALYZER_FLAGS[@]}"
  "${HARDENING_FLAGS[@]}"
)

LDFLAGS_TEST=(
  "${CFLAGS_SANITIZER_ADDRESS[@]}"
)

# MARK: Release Profile
# RELEASE PROFILE
# ---------------
# Optimized production profile with baseline hardening.
#
# Use for:
#   - standard release builds;
#   - representative performance testing;
#   - deployed binaries where baseline hardening still matters.
#
# Properties:
#   Compile time: medium/high because of -O3 and -flto.
#   Runtime speed: high.
#   Memory usage: normal.
#   Debuggability: lower than test/debug.
#   Safety: still keeps stack protector and fortify.
#
CFLAGS_RELEASE=(
  "${CFLAGS_BASE[@]}"
  "${CFLAGS_WARN_BASE[@]}"
  "${CFLAGS_WARN_STRICT[@]}"
  "${CFLAGS_OPT_RELEASE[@]}"
  "${HARDENING_FLAGS[@]}"
)

LDFLAGS_RELEASE=(
  -flto
)

# MARK: Extreme Profile
# EXTREME PROFILE
# ---------------
# Maximum-performance local-machine profile.
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
# This profile exists for narrowly scoped performance work. It should not be
# confused with the default release configuration.
#
CFLAGS_EXTREME=(
  "${CFLAGS_BASE[@]}"

  # Keep baseline warnings because they have no runtime cost.
  # Remove even these only if a third-party dependency makes your build noisy.
  "${CFLAGS_WARN_BASE[@]}"

  "${CFLAGS_OPT_EXTREME[@]}"
)

LDFLAGS_EXTREME=(
  -flto
)

# MARK: TSAN Profile
# TSAN PROFILE
# ------------
# Optional dedicated ThreadSanitizer profile.
#
# Use for:
#   - auditing concurrent code;
#   - race detection;
#   - validation of thread coordination paths.
#
# Properties:
#   Compile time: high.
#   Runtime speed: very slow.
#   Memory usage: very high.
#   Release suitability: not suitable.
#
CFLAGS_TSAN=(
  "${CFLAGS_BASE[@]}"
  "${CFLAGS_WARN_BASE[@]}"
  "${CFLAGS_WARN_STRICT[@]}"
  "${CFLAGS_WARN_PARANOID[@]}"
  "${CFLAGS_OPT_TEST[@]}"
  "${CFLAGS_DEBUG[@]}"
  "${CFLAGS_SANITIZER_THREAD[@]}"
  -fno-common
)

LDFLAGS_TSAN=(
  "${CFLAGS_SANITIZER_THREAD[@]}"
)

# =============================================================================
# MARK: Cost Summary
# Build-time / runtime cost summary
# =============================================================================
#
# Approximate qualitative cost summary:
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
# MARK: Build Policy
# Suggested make/build-script policy
# =============================================================================
#
# Suggested default policy:
#
#   during development:
#       debug
#
#   before merging:
#       test + release
#       tsan if the code is threaded
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
#   Add -Werror in CI only after the warning set has proven stable.
#   Do not enable -Werror in this file by default; doing so makes compiler
#   upgrades and third-party headers unnecessarily painful.
#
# =============================================================================
# MARK: CLI
# Command-line interface
# =============================================================================

_explain() {
    cat <<'TXT'
Available profiles:

  debug
      GDB-oriented profile: -Og, -g3, frame pointers, and no forced inlining.

  test
      High-diagnostic validation profile: warning groups, GCC static analyzer,
      ASan + UBSan + LSan, debug information, frame pointers, and hardening.

  release
      Optimized production profile: -O3, -flto, -DNDEBUG,
      warnings, stack protector, and fortify.

  extreme
      Maximum-performance local-machine profile: -O3, -flto, -march=native,
      no frame pointer, no stack protector, and no fortify.

  tsan
      Optional ThreadSanitizer profile. Use separately from AddressSanitizer.

Examples:

  gcc $(./gcc_build_profiles.sh print-cflags debug) src/*.c -o app_debug \
      $(./gcc_build_profiles.sh print-ldflags debug)

  gcc $(./gcc_build_profiles.sh print-cflags test) src/*.c -o app_test \
      $(./gcc_build_profiles.sh print-ldflags test)

  gcc $(./gcc_build_profiles.sh print-cflags release) src/*.c -o app_release \
      $(./gcc_build_profiles.sh print-ldflags release)

  source ./gcc_build_profiles.sh
  gcc "${CFLAGS_DEBUG[@]}" src/*.c -o app_debug "${LDFLAGS_DEBUG[@]}"
TXT
}

_profile_to_array_name() {
    case "$1" in
        debug)   printf 'CFLAGS_DEBUG\n' ;;
        test)    printf 'CFLAGS_TEST\n' ;;
        release) printf 'CFLAGS_RELEASE\n' ;;
        extreme) printf 'CFLAGS_EXTREME\n' ;;
        tsan)    printf 'CFLAGS_TSAN\n' ;;
        *)
            printf 'unknown profile: %s\n' "$1" >&2
            return 1
            ;;
    esac
}

_profile_to_ldarray_name() {
    case "$1" in
        debug)   printf 'LDFLAGS_DEBUG\n' ;;
        test)    printf 'LDFLAGS_TEST\n' ;;
        release) printf 'LDFLAGS_RELEASE\n' ;;
        extreme) printf 'LDFLAGS_EXTREME\n' ;;
        tsan)    printf 'LDFLAGS_TSAN\n' ;;
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
                printf 'usage: %s print-cflags {debug|test|release|extreme|tsan}\n' "$0" >&2
                return 2
            fi
            arr_name="$(_profile_to_array_name "$profile")" || return 2
            _print_array "$arr_name"
            ;;

        print-ldflags)
            if [[ -z "$profile" ]]; then
                printf 'usage: %s print-ldflags {debug|test|release|extreme|tsan}\n' "$0" >&2
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

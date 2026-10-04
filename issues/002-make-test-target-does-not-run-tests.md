# 002 — Make test target does not run tests

**Status**: Open
**Priority**: P2 (Medium)
**Severity**: Moderate
**Category**: Infrastructure
**Related**: `Makefile`, `.github/workflows/build-test.yml`

---

## 1. Problem & Motivation

The `Makefile` advertises `make test` as the way to run all tests, but its recipe contains only a TODO comment. Make therefore returns success without running a test command. This can mislead local contributors into treating an empty check as verification.

## 2. Technical Specification / Findings

CI runs `meson test --print-errorlogs` in its Debian and Ubuntu container jobs and `dub test` in the compiler matrix. The local `test-q1` target delegates to the empty `make test` target, so it does not provide those checks locally.

## 3. Implementation & Verification Plan

Wire `make test` to the supported project test command(s), or make it fail clearly until a local test workflow is available. Ensure `make test-q1` invokes the same meaningful checks. Verify that the command runs tests and returns a failure status when a test fails.

**Status**: Draft
**Priority**: P2 (Medium)
**Severity**: Minor
**Category**: Bug
**Related**:

---

## 1. Problem & Motivation
Describe the problem and why it matters.

## 2. Technical Specification / Findings
Record relevant technical details and findings.

## 3. Implementation & Verification Plan
Describe the implementation and how it will be verified.

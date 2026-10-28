---
name: tdd
description: Test-driven development, the red → green loop. Fire this before writing production code, when a reported bug needs a failing test to reproduce it, when the user says red-green-refactor, or when a feature needs integration tests.
---

You [YOU] are the implementer at the keyboard. This skill is the reference that makes the loop produce tests worth keeping: what a good test is, where it goes, the anti-patterns, and the rules of the loop. Every section applies on every cycle; consult them before the cycle, not after it.

Invocation: `/skill:tdd`, or the user naming it. No arguments. Invoking it authorises writing the failing test first and holding the implementation to it.

When exploring the codebase, read `GLOSSARY.md` if it exists, so test names and interface vocabulary match the project's domain language, and respect ADRs in the area you touch.

## What a good test is

Tests verify behaviour through public interfaces, never implementation details. Code can be rewritten entirely; the tests should not notice. A good test reads like a specification — "user can checkout with valid cart" names the capability that exists — and it survives refactors because it does not care about internal structure. One logical assertion per test, describing WHAT, not HOW.

The expected value must come from a source independent of the code under test: a known-good literal, a worked example, the spec. Otherwise the test cannot disagree with the code.

Mock at system boundaries only: external APIs, the database (prefer a real test DB), time and randomness, sometimes the file system. Your own modules and internal collaborators stay real.

Two references carry the detail, and each is read once per cycle at most: `skill://tdd/tests.md` for worked good and bad tests, `skill://tdd/mocking.md` for where to mock and how to shape an interface so a mock stays trivial.

## Seams: where tests go

A **seam** is the public boundary you test at: the interface where you observe behaviour without reaching inside. Tests live at seams, never against internals.

## [YOU] Phase 1: Agree the seams

Before writing any test, write down the seams under test and confirm them with the user: "What's the public interface, and which seams should we test?" No test is written at an unconfirmed seam. You cannot test everything, so agreeing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case. Prefer an existing seam to a new one, and the highest one available.

When the shape of that interface is itself in question — how deep the module is, where the seam belongs, what it should expose — read `skill://codebase-design` for the shared vocabulary. It is a reference to consult, not a session to run.

**Done**: the confirmed seams are written down, one line each, and the user has agreed to them.

## [YOU] Phase 2: Red

Write the test for one behaviour at the agreed seam and watch it fail. It must fail because the behaviour is missing: a test that passes on the first run, or fails on a typo or a missing import, has verified nothing yet and gets fixed before you move on.

Two anti-patterns to refuse here:

- **Implementation-coupled**: mocks internal collaborators, tests private methods, asserts on call counts or call order, or verifies through a side channel (querying the database instead of using the interface). The tell: the test breaks when you refactor but the behaviour has not changed.
- **Tautological**: the assertion recomputes the expected value the way the code does (`expect(add(a, b)).toBe(a + b)`, a snapshot derived by hand the same way, a constant asserted equal to itself), so it passes by construction and can never disagree with the code.

**Done**: the new test fails, and the failure message names the missing behaviour.

## [YOU] Phase 3: Green

Write only enough code to pass that one test. Do not anticipate future tests and do not add speculative features.

Work in **vertical slices**, one at a time: one test → one implementation → repeat, each test a **tracer bullet** that responds to what the last cycle taught you. The alternative — all tests first, then all implementation — is **horizontal slicing**: bulk tests verify _imagined_ behaviour, they pin the _shape_ of things rather than user-facing behaviour, they go insensitive to real change, and you commit to test structure before understanding the implementation.

**Done**: the whole suite is green, and the diff holds nothing the failing test did not demand.

## [YOU] Phase 4: Hand the cycle to review

Refactoring is not part of this loop. It belongs to the review stage: `skill://code-review` owns the cleanup pass, run with the suite green and behaviour unchanged. Skipping it is how a cycle ends on green with the design worse than it started, and the next cycle inherits the mess — so the hand-off is part of the job, not an optional extra.

**Done**: the suite is green and the cycle is handed to `skill://code-review`, which sets what the refactor changes.

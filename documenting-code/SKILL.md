---
name: documenting-code
description: Standardizes code comments and docstrings, focusing on intent, business rules, and constraints while removing redundant syntax noise. Use when writing docstrings, refactoring comments, adding inline explanations, or reviewing code documentation.
---

# Code Documentation and Commenting Standards

## Core Principles

### 1. Refactor Code Before Adding Comments
* If an inline comment merely explains *what* confusing syntax is doing, first consider renaming variables or extracting a helper method.
* Code demonstrates the **WHAT**; comments must explain the **WHY** (business logic, upstream constraints, security edge cases, or non-obvious workarounds).

### 2. Zero-Clutter Parameter & Return Documentation
* **Never** restate primitive variable names, obvious types, or tautological descriptions (e.g., avoid `@param userId - The user ID`).
* **Only** document parameters or return values to specify:
  * **Units of measurement** (e.g., milliseconds, base currency subunits, percentages).
  * **Domain constraints & invariants** (e.g., "Must be pre-sanitized", "Non-empty string", "Allowed range 1-100").
  * **Nullability and error conditions** (e.g., "Returns null if upstream cache expires").

### 3. Idiomatic Formatting by Ecosystem
* **JavaScript / TypeScript:** TSDoc / JSDoc blocks (`/** ... */`).
* **Python:** PEP 257 docstrings (`"""..."""`) with concise summaries and specific raises/yields only when non-obvious.
* **C# / .NET:** Formal XML documentation (`/// <summary>`, `/// <param>`).
* **Go / Rust:** Idiomatic sentence-style comments directly above the identifier (`// FunctionName ...` or `/// ...`).

### 4. Architectural & Context Preservation
* Never delete or simplify existing comments referencing architectural decisions, bug trackers, regulatory requirements, or complex system loops (e.g., "sync loop", "provenance tracking", "idempotency key").

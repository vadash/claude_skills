---
name: domain-modeling
description: Build and sharpen a project's domain model — challenge fuzzy terms, keep GLOSSARY.md small and current, and record only the decisions that earn an ADR.
disable-model-invocation: true
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline: challenging terms, inventing edge-case scenarios, and writing down a real term or a decision that passes the tests the moment it crystallises. (Merely *reading* `GLOSSARY.md` for vocabulary is not this skill: that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

Invocation is `/skill:domain-modeling`, or the user naming it. It runs alongside the design work it is sharpening, not as a separate pass after it: a real term gets written down when it resolves, while the rest stays in the design.

The names you settle here are the names the architecture takes. When the question turns to where a module's interface sits, how deep it is, or which dependencies cross its seam, read `skill://codebase-design` for that vocabulary: domain language names the seams, and the two references are consulted together.

## File structure

Most repos have a single context:

```
/
├── GLOSSARY.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `GLOSSARY-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── GLOSSARY-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── GLOSSARY.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── GLOSSARY.md
│       └── docs/adr/
```

Create files lazily: only when you have something to write. If no `GLOSSARY.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `GLOSSARY.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account': do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?"

### Update GLOSSARY.md inline

When a term is resolved, update `GLOSSARY.md` right there, but only when the term passes the test in `GLOSSARY-FORMAT.md`: two maintainers could disagree about the word, or the entry names a synonym to avoid. Most features add zero terms. Do not add code identifiers, UI states, config keys, build steps, or lane mechanics; those belong in code or the owning agent doc. Do not batch a real term; capture it when it resolves.

`GLOSSARY.md` is product language, not a spec, scratch pad, or implementation record.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If any is missing, skip it. A feature may add zero ADRs. One file is one decision family, not one decision: if two decisions share the same future reader and the same rejected alternative, they are one family. If the content is a layout, size, copy, step list, field list, enum, or test procedure, it is spec, not an ADR; put it in the spec, `DESIGN.md`, code, or the lane doc. Keep the active set under 12k tokens; combine or retire before adding past that. The ceiling, measuring command, and family format live in `skill://domain-modeling/ADR-FORMAT.md`.

## Reference files

Both are read on demand, never up front:

- A term is resolved and the glossary needs the entry → `skill://domain-modeling/GLOSSARY-FORMAT.md` for the entry shape, the `_Avoid_` rule, which terms belong, and the single-versus-multi-context `GLOSSARY-MAP.md` structure.
- All three ADR conditions hold and a decision is being recorded → `skill://domain-modeling/ADR-FORMAT.md` for the family template, active-set budget, optional sections, numbering, and retirement.

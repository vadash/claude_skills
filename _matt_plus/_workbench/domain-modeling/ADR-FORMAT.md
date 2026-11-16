# ADR Format

Reached from `skill://domain-modeling` when a decision passes the three tests and is recorded.

ADRs live in `docs/adr/` and use sequential numbering: `0001-slug.md`, `0002-slug.md`, etc. Create the folder lazily: only when the first ADR is needed.

## One file per decision family

A decision is the smallest unit a future reader would re-litigate, not the smallest unit you decided. If two decisions share the same future reader and the same rejected alternative, they are one family. A feature may add zero records.

The active set is a current-state reading surface, not a history. The 12k cap is a ceiling, not a target: there is no minimum, and a new project may have one record. Measure the numbered records only, not the README:

```sh
find docs/adr -maxdepth 1 -name '[0-9]*.md' -exec cat {} + | wc -m
```

```powershell
(Get-ChildItem docs/adr -File | Where-Object Name -match '^\d' | Get-Content -Raw | Measure-Object -Character).Characters
```

A rough token count is characters / 4, so 12k tokens is about 48k characters. Run the command in the set you are editing. Over 48k characters is over budget: combine or retire before adding.

A big project gets more reading surfaces, not a bigger one. Keep `docs/adr/` for system-wide decisions and put context decisions under `src/<context>/docs/adr/`; `GLOSSARY-MAP.md` routes to them. Keep the total an agent reads for one task — the root set plus the one context set it needs — under 12k; if that total is over, shrink the root set first because it should hold only decisions every context depends on. If one context set still exceeds 12k, cut spec content, merge families that share a reader and alternative, retire decisions that are no longer active, or split the context. A single context that genuinely needs more than 12k is too broad to be one context; split it rather than raising the ceiling.

The folder README maps the active families and retired numbers; keep it a map, not a policy essay. The rules live in this skill.

## Template

```md
# {Family title}

{1-2 sentences: the family's shared context and decision.}

**{Decision one}.** {1-3 sentences: what, why, and the rejected alternative only if non-obvious.}
**{Decision two}.** ...
```

No frontmatter; git history is the date. A record can be a few paragraphs.

Before writing, search the active set: each fact lives in exactly one family. If it already lives there, extend that record. If it lives elsewhere, cite it instead of restating it.

Names only: the module, seam, or term. Signatures, field lists, file inventories, layout sizes, step lists, and test procedures belong in code, the spec, `DESIGN.md`, or the lane doc.

Default is no sections. `Considered Options` only if a future reader would plausibly re-propose the rejected option; one line per alternative, name plus why rejected. `Consequences` only if the record does not already state the effect; one line per effect.

## Numbering and retirement

New families take the next number after the highest in use. Numbers are never reused.

A minor change to one decision edits the family record in place; git history is the old state.

A major change, or a change to half the family, writes a new family record that restates the current family, deletes the old file, and lists the old number under Retired in the README. Do not keep a `superseded by` stub in the active folder; git history holds the old text.

If a family is too broad or changes often, split it into two families. If two families are one decision, merge them.

## When to offer an ADR

All three of these must be true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If a decision is easy to reverse, skip it: you'll just reverse it. If it's not surprising, nobody will wonder why. If there was no real alternative, there's nothing to record beyond "we did the obvious thing."

### What qualifies

- **Architectural shape.** "We're using a monorepo." "The write model is event-sourced, the read model is projected into Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target. Not every library: just the ones that would take a quarter to swap out.
- **Boundary and scope decisions.** "Customer data is owned by the Customer context; other contexts reference it by ID only." The explicit no-s are as valuable as the yes-s.
- **Deliberate deviations from the obvious path.** "We're using manual SQL instead of an ORM because X." Anything where a reasonable reader would assume the opposite. These stop the next engineer from "fixing" something that was deliberate.
- **Constraints not visible in the code.** "We can't use AWS because of compliance requirements." "Response times must be under 200ms because of the partner API contract."
- **Rejected alternatives when the rejection is non-obvious.** If you considered GraphQL and picked REST for subtle reasons, record it; otherwise someone will suggest GraphQL again in six months.

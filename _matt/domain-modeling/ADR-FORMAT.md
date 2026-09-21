# ADR Format

ADRs live in `docs/adr/` and use sequential numbering: `0001-slug.md`, `0002-slug.md`, etc.

Create the `docs/adr/` directory lazily: only when the first ADR is needed.

## Template

```md
# {Short title of the decision}

{1-3 sentences: what's the context, what did we decide, and why.}
```

That's it. An ADR can be a single paragraph. The value is in recording *that* a decision was made and *why*, not in filling out sections.

## Optional sections

Only include these when they add genuine value. Most ADRs won't need them.

- **Status** frontmatter (`proposed | accepted | deprecated | superseded by ADR-NNNN`): useful when decisions are revisited
- **Considered Options**: only when the rejected alternatives are worth remembering
- **Consequences**: only when non-obvious downstream effects need to be called out

## Numbering

The next number is one past the highest ever used — counting a number as used even when its file is gone. Scan `docs/adr/` for the highest `NNNN` among the files, and check the retired table in `docs/adr/README.md` for retired numbers above it; take the highest of the two and increment.

Never fill a gap in the sequence. A missing number usually means its ADR was retired (see below), and reusing it would silently re-point every older `ADR-NNNN` citation to the wrong decision. If a number is missing and the ledger doesn't explain it, treat it as used anyway and move on: a skipped number costs nothing, a reused one lies.

## Superseding a decision

Two cases:

- **The new ADR restates the old decision whole** — retire the old one. Delete its file and add a row to the retired table in `docs/adr/README.md` (create the file lazily on the first retirement): the number, the title, and the superseding ADR. The title is the only record left of what the decision was, so keep it descriptive. The retired number is spent for good. On first retirement, seed the README so a future reader understands the table without archaeology:

  ```md
  # ADRs

  Decisions live here as `NNNN-slug.md`, one paragraph each.

  A superseded decision that keeps its file states its successor in `status:` frontmatter. A superseded decision whose successor restates it whole is **retired**: the file is deleted and its number moves to the table below.

  ## Retired numbers

  Numbers listed here were used and are spent — nothing may reuse them. The file is gone because its successor restates the decision whole, so the title is the only remaining record of what it decided, and the successor is the authority in force.

  | Number | Title | Superseded by |
  | ------ | ----- | ------------- |
  | {NNNN} | {original title, descriptive} | {NNNN} |
  ```
- **The new ADR only partially replaces it** — keep the file and set `status: superseded by ADR-NNNN` frontmatter.

Retiring beats leaving a tombstone: a file whose only content is "superseded by X" is noise in every future directory listing, but deleting outright loses the number's history and invites reuse. The ledger avoids both. In the successor's paragraph, name what it replaces — the ledger row carries only the old title, so the link between old and new lives in the successor's prose.

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

## Optional: pin the shape with a test

If the repo has a test suite, consider a small test that pins the mechanical half of this format, so drift gets caught by CI instead of by a reader:

- every file in `docs/adr/` matches `NNNN-slug.md` and has a `# ` title
- sections are limited to the optional set above
- `status:` frontmatter parses, and a `superseded by ADR-NNNN` target exists and isn't the file itself
- every `ADR-NNNN` citation across the repo resolves to a live file or a retired row
- no live file uses a retired number, and every retired row names a live successor

Keep prose and length unasserted — the test's job is catching broken references and layout drift, not grading writing. Search the repo for an existing test before writing a new one; if the pattern is already pinned, extend rather than duplicate.

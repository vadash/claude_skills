# The Out-of-Scope Knowledge Base

The `.out-of-scope/` directory in a repo holds persistent records of rejected feature requests. Two jobs:

1. **Institutional memory**: why a feature was rejected, so the reasoning survives the issue closing.
2. **Deduplication**: when a new request matches a prior rejection, surface the decision instead of re-litigating it.

## Layout

```
.out-of-scope/
├── dark-mode.md
├── plugin-system.md
└── graphql-api.md
```

One file per **concept**, never per issue. Several issues asking for the same thing group under one file.

### Naming

Short, descriptive, kebab-case: `dark-mode.md`, `plugin-system.md`, `graphql-api.md`. Someone browsing the directory should recognise what was rejected without opening the file.

## File format

Write it relaxed and readable — a short design document, not a database row. Paragraphs, code samples, and examples carry the reasoning to someone meeting it for the first time.

```markdown
# Dark Mode

This project does not support dark mode or user-facing theming.

## Why this is out of scope

The rendering pipeline assumes a single color palette defined in
`ThemeConfig`. Supporting multiple themes would require:

- A theme context provider wrapping the entire component tree
- Per-component theme-aware style resolution
- A persistence layer for user theme preferences

This is a significant architectural change that doesn't align with the
project's focus on content authoring. Theming is a concern for downstream
consumers who embed or redistribute the output.

```ts
// The current ThemeConfig interface is not designed for runtime switching:
interface ThemeConfig {
  colors: ColorPalette; // single palette, resolved at build time
  fonts: FontStack;
}
```

## Prior requests

- #42: "Add dark mode support"
- #87: "Night theme for accessibility"
- #134: "Dark theme option"
```

### Writing the reason

The reason is substantive: why, not "we don't want this". Good reasons cite:

- **Scope or philosophy**: "This project focuses on X; theming is a downstream concern."
- **Technical constraint**: "Supporting this would require Y, which conflicts with our Z architecture."
- **Strategic choice**: "We chose A over B because…"

Durability matters: a reason that names a temporary circumstance ("we're too busy right now") is a deferral, not a rejection, and it makes the file a lie within weeks.

## When to check

Read every file in `.out-of-scope/` during Phase 2 (Gather context). For a new item:

- Match by **concept similarity**, not keywords: "night theme" matches `dark-mode.md`.
- On a match, surface it: "This is similar to `.out-of-scope/dark-mode.md`. We rejected it because [reason]. Do you still feel the same way?"

The maintainer answers one of three ways:

- **Confirm**: append the new item to that file's "Prior requests" list, then close it.
- **Reconsider**: delete or update the out-of-scope file, and let the item run through normal triage.
- **Disagree**: related but distinct, so the item runs through normal triage.

## When to write

Only when an **enhancement** — never a bug — is *rejected* as `wontfix`. An enhancement PR counts exactly as an issue: record a rejected PR here so the same request does not return as fresh code.

Write nothing when an item closes as `wontfix` for being **already implemented**. That is a built feature, not a rejected one; filing it poisons every later dedup check with a false rejection. The closing comment points at where the feature already lives.

The flow:

1. The maintainer decides the request is out of scope.
2. Check for a matching `.out-of-scope/` file.
3. Exists: append the item to "Prior requests".
4. Missing: create the file with the concept name, the decision, the reason, and this first prior request.
5. Comment on the item with the decision and a pointer to the file.
6. Close it with `wontfix`.

## Changing your mind

The maintainer reverses a rejection:

- Delete the `.out-of-scope/` file.
- Leave the old issues closed; they are historical records, and reopening them would bury the new request in a stale thread.
- Run the item that triggered the reconsideration through normal triage.

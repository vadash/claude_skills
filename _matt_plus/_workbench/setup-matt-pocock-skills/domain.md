# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root. It is product language; read it so you do not invent synonyms. Build and lane vocabulary lives in the owning agent doc.
- **The active ADR set** in `docs/adr/` when the task touches architecture. The folder README maps the families; old per-decision records are removed and git history holds them.
- **`GLOSSARY-MAP.md`** at the repo root if it exists: it points at one `GLOSSARY.md` and ADR set per context. Read the ones relevant to the topic.

If a file does not exist, proceed silently. Never suggest creating one upfront; `/skill:domain-modeling` creates terms and decisions lazily when they resolve.

## Use the glossary's vocabulary

When your output names a domain concept (issue title, proposal, hypothesis, test name), use the term defined in `GLOSSARY.md`; do not drift to a synonym it avoids. If the concept is missing, reconsider the wording or note a gap for `/skill:domain-modeling`; do not invent a term.

## Decisions

Read the active ADR families for the area. A feature may add zero records; `skill://domain-modeling` owns the bar and format. Do not write an ADR for feature behavior, layout, sizes, steps, fields, or test procedures; those live in the spec, `DESIGN.md`, code, or the lane doc. Surface a conflict with an active ADR by naming it and why it should be reopened.

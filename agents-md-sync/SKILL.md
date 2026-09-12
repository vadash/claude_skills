---
name: agents-md-sync
description: Manually sync session learnings into AGENTS.md routers and agent_docs leaves before a commit or session wrap-up
disable-model-invocation: true  
---

# AGENTS.md Sync

Write durable contracts, not chronicles. Output tokens are precious; reader time more so.

## Apply the rules
Read `references/rules.md` and apply it to every edit. Summary: ASD-STE100, one fact per bullet, ≤ 2 lines / 25 words, no history, strip code identifiers.

## When to run
- After implementation and verification fully complete.
- Not on casual mentions of "commit" or "docs".
- If the tree needs a full rewrite, stop and recommend `agents-md-init`.

## Place narrowly
| Content | Target |
|---|---|
| Global boundary | Root `AGENTS.md` |
| Domain routing | Nearest nested `AGENTS.md` |
| Gotchas, runbooks | `agent_docs/<domain>_gotchas.md` |
| New domain | New dir, `<domain>.md` index, leaf |

## Edit, prune, validate
- Replace contradictions. Merge duplicates.
- Keep routers lean: move details to a leaf, leave a pointer.
- Strip any code refs that slipped in (see `references/rules.md`).
- Prune dead paths, obsolete workarounds, finished TODOs.
- Re-glob to confirm links resolve.
- Report adds, removes, and rejections in one line each.

Edit at the end-of-session moment for inclusion in the same authorized commit. Never mutate external state tools or trigger deployments.

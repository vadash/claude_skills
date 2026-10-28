---
name: wayfinder
description: Plan a huge chunk of work (more than one agent session can hold) as a shared map of decision tickets on your issue tracker, and resolve them one at a time until the way to the destination is clear.
disable-model-invocation: true
---

A loose idea has arrived, too big for one agent session, and wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding is about finding that way, not charging at the destination. This skill charts the way as a **shared map** on the repo's issue tracker, then works its **decision tickets** (questions whose resolution is a decision, not slices of a build to execute) one at a time until the route is clear.

[YOU] is this thread: it names the destination, charts the map, and resolves one ticket per session.

Invocation: `/skill:wayfinder <a loose idea>` to chart a new map, or `/skill:wayfinder <map URL | map number> [ticket]` to work one. Invoking authorises writing to the tracker — map, tickets, labels, blocking edges, comments, closes.

The destination varies per effort, and naming it is the first act of charting: it shapes every ticket. It might be a spec to hand off and iterate on, a decision to lock before planning starts, or a change made in place like a data-structure migration. The map is domain-agnostic: engineering work, course content, whatever fits the shape.

## Plan, don't do

Wayfinder is **planning** by default: each ticket resolves a decision, and the map is done when the way is clear, with nothing left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you've reached the edge of the map and it's time to hand off. An effort can override this in its **Notes**, carrying execution into the map itself, but absent that, produce decisions, not deliverables.

## Refer by name

Every map and ticket is an issue, so it has a **name**: its title. In everything the human reads (narration, the map's Decisions-so-far), refer to it by that name, never by a bare id, number, or slug. A wall of `#42, #43, #44` is illegible; names read at a glance. The id and URL don't vanish; a name wraps its link, but they ride _inside_ the name, never stand in for it.

## The Map

The map is a single issue on this repo's issue tracker, labelled `wayfinder:map`, the canonical artifact. Its tickets are child issues of the map.

The map is an **index**, not a store. It lists the decisions made and points at the tickets that hold their detail; a decision lives in exactly one place, its ticket, so the map never restates it, only gists it and links.

**Where the map, its child tickets, blocking, and frontier queries physically live is tracker-specific.** The issue tracker should have been provided to you in `docs/agents/issue-tracker.md`. If not, tell the user to run `/skill:setup-matt-pocock-skills`. Consult the tracker doc's **Wayfinding operations** section for how _this_ repo expresses them.

**No tracker provided? Default to the local-markdown tracker, don't block.** Wayfinding is reached for at the foggy start of an effort, exactly when a repo has no tracker config yet; refusing to chart until setup runs stalls the effort at the moment it most needs the map. Read `skill://setup-matt-pocock-skills/issue-tracker-local.md` and use its **Wayfinding operations** section — map at `.scratch/<effort>/map.md`, one child file per ticket. Say which tracker you fell back to, once, in the map's **Notes**, and carry on.

### The map body

The whole map at low resolution, loaded once per session. Open tickets are **not** listed: they are open child issues, found by query.

```markdown
## Destination

<what reaching the end of this map looks like: the spec, decision, or change this effort is finding its way to. One or two lines; every session orients to it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the index: one line per closed ticket, enough to judge relevance, then zoom the link for the detail the ticket holds -->

- [<closed ticket title>](link): <one-line gist of the answer>

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination; closed, never graduates -->
```

### Tickets

Each ticket is a **child issue** of the map; the tracker's issue id is its identity. Its body is the question, sized to one 100K token agent session:

```markdown
## Question

<the decision or investigation this ticket resolves>
```

Each ticket carries a `wayfinder:<type>` label, one of `research`, `prototype`, `grilling`, `task` (see [Ticket Types](#ticket-types)). `wayfinder:` labels are the only labels a map and its tickets carry, never a triage label like `ready-for-agent`: they are decisions, not implementation work.

A session **claims** a ticket by assigning it to the dev driving the map, **first**, before any work, so concurrent sessions skip it. That assignee _is_ the claim: an open, unassigned ticket is unclaimed.

Blocking uses the tracker's **native** dependency relationship: essential because it renders the frontier _visually_ in the tracker's own UI, so the human sees what's takeable without opening the map. Only a tracker that lacks native blocking falls back to a body convention. A ticket is **unblocked** when every ticket blocking it is closed; the **frontier** is the open, unblocked, unclaimed children, the edge of the known.

The answer isn't part of the body; it's recorded on resolution (see [Working through the map](#working-through-the-map)). Assets created while resolving a ticket are linked from the issue, not pasted in.

## Ticket Types

Every ticket is either **HITL** (human in the loop, worked _with_ a human who speaks for themselves) or **AFK**, driven by the agent alone. A HITL ticket only resolves through that live exchange; the agent never stands in for the human's side of it (a grilling agent that answers its own questions has broken this).

- **Research** (AFK): Reading documentation, third-party APIs, or local resources like knowledge bases to surface a fact a decision waits on. Resolved by a subagent that runs `read skill://research`. Use when knowledge outside the current working directory is required.
- **Prototype** (HITL): Raise the fidelity of the discussion by making a cheap, rough, concrete artifact to react to (an outline, a rough take, a stub, or UI/logic code) by running `read skill://prototype`. Links the prototype as an asset. Use when "how should it look" or "how should it behave" is the key question.
- **Grilling** (HITL): Conversation. The default case. Always `read skill://grilling` and `read skill://domain-modeling`.
- **Task** (HITL or AFK): Manual work that must happen before a _decision_ can be made: nothing to decide, prototype, or research, but the discussion is blocked until it's done. Signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. This is the one type that _does_ rather than decides, and it earns its place by unblocking a decision, not by delivering the destination. The agent drives it alone where it can (AFK); otherwise it hands the human a precise checklist (HITL). Resolved when the work is done; the answer records what was done and any resulting facts (credentials location, new URLs, row counts) later tickets depend on.

## Fog of war

The map is _deliberately_ incomplete: don't chart what you can't yet see. Beyond the live tickets lies the **fog of war**: the dim view of decisions and investigations you can tell are coming but can't yet pin down, because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever's now specifiable into fresh tickets, one at a time, until the way to the destination is clear and no tickets remain.

The map's **Not yet specified** section is where that dim view is written down: the suspected question, the area to revisit later. It's the undiscovered **frontier** _toward_ the destination: everything here is in scope, just not sharp enough to ticket. Write as loosely or as fully as the view allows; it doubles as a signpost for collaborators reading where the effort is headed.

**Fog or ticket?** The test is whether you can state the question precisely now, _not_ whether you can answer it now.

- **Ticket when** the question is already sharp, even if it's blocked and you can't act on it yet.
- **Not yet specified when** you can't yet phrase it that sharply. Don't pre-slice the fog into ticket-sized pieces: it's coarser than a ticket, and one patch may graduate into several tickets, or none, once the frontier reaches it.

**Not yet specified** excludes what's already decided (Decisions so far), what's already a live ticket, and what's out of scope (the next section).

## Out of scope

Fog only ever gathers _toward_ the destination. The destination fixes the scope, so work beyond it is **out of scope**: it isn't fog, and it doesn't belong in **Not yet specified**. It gets its own **Out of scope** section on the map: work you've consciously ruled out of _this_ effort. Scope, not sharpness, lands it here.

Out-of-scope work never graduates (the frontier stops at the destination), so it returns only if the destination is redrawn, and then as a fresh effort, not a resumption.

Ruling something out of scope is a scoping act, not a step on the route. When a ticket that already exists turns out to sit past the destination (mis-scoped in while charting, or exposed by a resolution), **close it** (a closed ticket is unambiguously off the frontier) and leave one line in the **Out of scope** section: the gist plus why it's out of scope, linking the closed ticket. It stays out of **Decisions so far**, which records the route actually walked; a scope boundary isn't a step on it.

## Charting the map

Phases 1 to 5 chart a new map from a loose idea. **Charting is one session's work and hand-resolves nothing**: it stops at Phase 5.

## [YOU] Phase 1: Name the destination

`read skill://grilling` and `read skill://domain-modeling` to pin down what this map is finding its way to: the spec, decision, or change. The destination fixes the scope, so it's settled first.

**Done**: the destination is written in one or two lines, and every later ticket can be judged as inside or beyond it.

## [YOU] Phase 2: Map the frontier

Grill again, **breadth-first** this time: fan out across the whole space rather than deep on any one thread, surfacing the open decisions and the first steps takeable now.

**If this surfaces no fog** (the way to the destination is already clear, the whole journey small enough for one session), you don't need a map. Stop and ask the user how they'd like to proceed.

**Done**: the space has been fanned across rather than drilled into, and you can say either that the journey needs a map — with the open decisions and takeable first steps in hand — or that it doesn't, and the user has been asked rather than left with half a map.

## [YOU] Phase 3: Create the map

Create the map issue, labelled `wayfinder:map`: Destination and Notes filled in, Decisions-so-far empty, the fog sketched into **Not yet specified**.

**Done**: the map issue exists with all five sections, and no ticket is listed in it.

## [YOU] Phase 4: Create the tickets you can specify now

Create them as child issues of the map, then wire blocking edges in a **second pass** (issues need ids before they can reference each other). Write cross-references in that pass too, with real ids: a placeholder `#<n>` auto-links to an unrelated issue. Wiring sorts them into the frontier and the blocked; everything you can't yet specify stays in the fog: the **Not yet specified** section.

**Done**: every ticket sharp enough to state is a child issue carrying one `wayfinder:<type>` label; every blocking edge is a real link to a real id; and everything you couldn't state sharply is in **Not yet specified** as fog, in no ticket body.

## [YOU] Phase 5: Fire the research subagents

For each `research` ticket you just created, spin up a subagent that runs `read skill://research` to resolve it in parallel, capturing its findings on a throwaway `research/<name>` branch with a context pointer from the ticket. Push the branch but open no PR: it is never merged.

Then stop: charting is one session's work; it hand-resolves nothing. A research ticket is the one ticket a charting session may resolve, because the subagent does it.

**Done**: every research ticket has its subagent, its `research/<name>` branch pushed, no PR opened, and the session ends with the map charted and no other ticket resolved.

## Working through the map

Phases 6 to 10 work an existing map. **Never resolve more than one ticket per session**, with the exception of research tickets.

## [YOU] Phase 6: Load the map

Load the **map**: the low-res view, not every ticket body.

**Done**: Destination, Notes, Decisions so far, Not yet specified, and Out of scope are all in hand, and no ticket body has been fetched except the one Phase 7 picks.

## [YOU] Phase 7: Choose and claim the ticket

If the user named one, use it. Otherwise take the first frontier ticket in order. **Claim it**: assign it to yourself before any work.

**Done**: exactly one ticket is chosen, its claim is visible on the tracker, and no other ticket carries an assignee you set.

## [YOU] Phase 8: Resolve it as its type

Resolve it as the type its `wayfinder:<type>` label names (see [Ticket Types](#ticket-types)). Read the label, not just the body: the body never states the type. **Zoom as needed**: fetch the full body of any related or closed ticket on demand; reach whichever skills the `## Notes` block names. If in doubt, `read skill://grilling` and `read skill://domain-modeling`.

**Done**: the ticket's question is answered in the form its type demands — research surfaced the fact, the prototype was built and seen, the human's side of the grilling came from the human, the task work is actually done — with the answer material in hand.

## [YOU] Phase 9: Record the resolution

Post the answer as a **resolution comment**, **close** the issue, and **append a context pointer** to the map's Decisions-so-far.

**Done**: the answer lives on the ticket as a comment, the ticket is closed, and the map's Decisions-so-far carries one gist line wrapping a link to it — with the detail left on the ticket, not restated in the map.

## [YOU] Phase 10: Move the map

Add newly-surfaced tickets (create-then-wire); graduate any fog the answer has made specifiable, clearing each graduated patch from **Not yet specified** so it lives only as its new ticket. If the answer reveals that a ticket (this one or another) sits beyond the destination, **rule it out of scope** rather than resolving it on the route. If the decision invalidates other parts of the map, update or delete those tickets.

**Done**: every newly specifiable question is a wired child ticket, every graduated patch has left **Not yet specified**, every ticket the answer invalidated is updated or deleted, and any ticket past the destination is closed with one line in **Out of scope** — or you can say the map needed no change, and why.

The user may run unblocked tickets in parallel, so expect other sessions to be editing the tracker concurrently.

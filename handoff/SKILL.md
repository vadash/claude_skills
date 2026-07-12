---
name: handoff
description: Create one compact, validated session handoff for a Beads-tracked workstream when context is running low or work is pausing. Captures current deltas, verified state, and the next action without duplicating durable project documentation.
user_invocable: true
triggers:
  - do a handoff
  - create a handoff
  - run handoff
  - save session context
  - session handoff
  - save session progress
  - running out of context
argument-hint: [optional reason, e.g. "context low", "end of day"]
---

# Session Handoff

Create one compact, evidence-backed delta handoff for a Beads-tracked workstream.
The next session should be able to resume without re-reading the whole project or
mistaking duplicated handoff text for an authoritative source.

**Arguments:** $ARGUMENTS

## Guards

- Run only when the user explicitly asks to create or update a handoff now.
- Require an active Beads workspace. If `bd` is unavailable or `bd where` cannot
  resolve the repository, stop and explain that this skill supports Beads-backed
  repositories only.
- Read applicable repository and user policy before any write or state mutation.
- Treat the handoff request as authority to write the handoff and update its
  active Beads issue notes. Do not infer authority to commit, push, sync, deploy,
  archive, close issues, or move files.
- Create exactly one handoff file. Never split it by size.

## Step 1: Policy and Beads Preflight

Before gathering or writing:

1. Read the active repository instruction files and current user/system
   instructions.
2. Identify ownership boundaries for task state, durable documentation,
   generated artifacts, secrets, commits, and session closure.
3. Run `bd prime`, then confirm the workspace with `bd where` if needed.
4. Inspect in-progress work with `bd list --status=in_progress` and read every
   candidate issue with `bd show <id>`.
5. If no issue represents the active work, create and claim one before writing
   the handoff. Do not invent a standalone/non-Beads chain.

Repository instructions and durable project documentation are inputs to the
handoff process, not handoff content. Do not include links to `AGENTS.md`, any
variant of `AGENT.md`, or files under `agent_docs/` in the generated handoff.
Do not copy their stable rules into the handoff. Record only a policy change or
conflict that directly affects resumption.

## Step 2: Gather Current State

Use the tools and shell available in the environment. Do not assume Bash,
PowerShell, a particular agent product, or named editing tools. Prefer parallel
read-only calls when supported.

Gather:

- Git branch, HEAD, recent commits, staged/unstaged/untracked state, and diff
  summary when the workspace uses Git.
- Active Beads issue details, dependencies, blockers, acceptance criteria, and
  current status.
- Existing handoffs under the configured handoff directory, including archived
  subdirectories.
- Files actually changed, tests actually run, measurements actually observed,
  and unresolved failures from this session.
- User directions that were introduced, changed, or revoked this session.

Never paste secrets, ignored configuration contents, deployment credentials,
real infrastructure identifiers, or unfiltered command output into a handoff.

## Step 3: Resolve the Chain

Determine the parent in this order:

1. An explicit handoff path supplied by the user or session-opening prompt.
2. The latest handoff whose Beads chain and planned next action directly match
   the active work.
3. No parent when this is a genuinely new Beads workstream.

Read the full parent when one exists. A shared bead or epic is only a candidate;
the current work must be a direct continuation of its next action.

Use the parent chain tag for a continuation. For a new chain, use the active
epic ID when one exists; otherwise use the primary Beads issue ID. Set sequence
to the parent sequence plus one, or one for a new chain. Store the exact parent
path; do not emit a growing ancestor breadcrumb.

## Step 4: Mine Session Deltas

The conversation is the source for intent and chronology; the filesystem, Git,
test output, and Beads are the source for current facts.

For a short or focused session, make one structured pass. For a long,
multi-topic, or tool-heavy session, read `references/mining-deep-chunked.md` and
use its multi-pass procedure.

Extract only information that helps resume this work:

- What changed since the parent or since the session began.
- Non-obvious decisions and rejected alternatives.
- Expensive failed approaches and why they failed.
- Current worktree state and incomplete edits.
- Verification performed this session, emphasizing failures, changed results,
  acceptance-relevant gates, and measurements that affected a decision.
- New or changed user direction.
- Current risks, blockers, and unanswered questions.
- The single next action and a small number of ordered follow-ons.

Do not repeat stable architecture, product scope, operating procedures, old
user preferences, complete task history, or evidence already owned by durable
project documentation or Beads. Link task-specific raw evidence only when the
next session needs it.

## Step 5: Write One Handoff

Choose the first existing handoff directory, creating `plans/handoffs/` only
when no configured location exists:

1. `plans/handoffs/`
2. `.claude/handoffs/`

Name the file:

`HANDOFF_{chain_tag}_{2-4-word-slug}_{YYYY-MM-DD}.md`

Append `_2`, `_3`, and so on only on collision.

Read `references/output-template.md` and follow its compact section structure.
Write the complete handoff in one file. Add an appendix inside that file only
when raw chronology or evidence is genuinely necessary for resumption.

After the initial write, read the file back and remove duplication. Expand only
when a concrete resumption fact is missing; never expand to meet a length target.

## Step 6: Validate Information Quality

Read `references/validation.md` and run every applicable check. Validate claims
against current Git, Beads, files, and observed command results. Fix stale,
duplicated, unsupported, or policy-conflicting content before continuing.

## Step 7: Update Beads

Update the active issue notes with only the handoff path, chain sequence,
session outcome, and next action. Do not duplicate the handoff body in Beads.
Do not close the issue unless its actual acceptance criteria are complete and
repository policy permits closure.

Use `bd remember` only when repository policy uses Beads memories for handoff
discovery. Store a compact pointer, not another summary.

## Step 8: Report

Tell the user:

- The handoff path.
- Chain tag and sequence.
- Active Beads issue(s).
- Whether validation passed.
- The exact next action.
- Any uncommitted state or action requiring separate authorization.

If the user asks to close the session, read `references/close-session.md`.
Never default to committing or archiving.

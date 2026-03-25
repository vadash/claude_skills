---
name: repo-eval
description: Structured evaluation of GitHub repositories. Use this skill whenever the user drops a GitHub repo URL, mentions evaluating/reviewing/auditing a repo, asks "what do you think of this repo", says "check this out" with a GitHub link, or asks you to look over a codebase. Also trigger when the user references a repo they want to vet before adopting, contribute to, or integrate into their stack. This skill applies to any public GitHub repository regardless of language or framework. Even if the user phrases it casually ("take a look at this"), if there's a GitHub URL involved and they want your assessment, use this skill.
---

# Repo Eval

Structured two-phase evaluation of GitHub repositories. Phase 1 is a quick triage that surfaces initial findings and a recommendation on whether a deeper dive is worthwhile. Phase 2 (triggered by the user) is the full deep dive with automated scans, code review, and a formal report.

This two-phase structure exists because thorough repo evaluation requires many tool calls — cloning, reading files, running scripts, fetching GitHub metadata. Splitting into phases avoids hitting tool call limits and gives the user a natural decision point: not every repo deserves the full treatment.

---

## Phase 1: Triage

Phase 1 runs automatically when a repo URL lands. It should use **no more than 8-10 tool calls** to answer one question: "Is this worth looking at more closely?"

### Step 1: Acquire

Clone the repo:

```bash
git clone --depth 1 <repo-url> /home/claude/repo-eval-workspace/<repo-name>
```

Use `--depth 1` always. If the clone fails, tell the user and stop.

### Step 2: Quick orientation (aim for 4-5 tool calls)

Gather just enough to form a first impression:

1. **View the directory tree** (1 call). Get the structural shape, file count, and size distribution.
2. **Read the README** (1 call). Note what it claims, who it's for, and what stage it's at.
3. **Check the package manifest** (1 call) — `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc. Note dependency count and license.
4. **Fetch the GitHub page** (1 call). Get stars, forks, contributor count, commit activity, open issues. This gives social proof and maintenance signals that the code alone can't tell you.
5. **Spot-check one or two key files** (1-2 calls). Pick the entry point or the largest source file — just enough to gauge code quality at a glance.

### Step 3: Deliver the triage

Present findings conversationally. Cover these points in whatever order makes sense for what you found:

- **What it is**: One-sentence summary of what the project does.
- **Vital signs**: Stars, forks, contributors, last commit, commit frequency, open issues. Is anyone actually using or maintaining this?
- **First impressions**: What jumped out — good or bad? Big files, tiny dependency list, missing license, hardcoded secrets in config, stale dependencies, impressive test suite, whatever caught your eye.
- **Maturity read**: Does this feel like a production tool, a solid side project, a proof-of-concept, or a generated dump?
- **Anything alarming**: If you spotted a clear security concern, broken build config, or obvious red flag, surface it now — the user shouldn't have to wait for Phase 2 for deal-breakers.

End with a clear recommendation:

- **"Worth a deep dive"** — interesting enough or risky enough to warrant Phase 2.
- **"Skip it"** — obviously dead, broken, dangerous, or not what it claims.
- **"Your call"** — mixed signals; explain the tradeoff and let the user decide.

If the user flagged a specific concern with the repo, make sure the triage addresses that concern directly, even if it means an extra tool call.

---

## Phase 2: Deep Dive

Phase 2 runs only when the user says to proceed (e.g., "yes", "dig in", "let's go deeper", "do the full eval"). The repo is already cloned from Phase 1.

### Step 1: Run automated scans

Run both helper scripts against the cloned repo:

```bash
python3 <skill-directory>/scripts/security_scan.py /home/claude/repo-eval-workspace/<repo-name>
python3 <skill-directory>/scripts/dep_analysis.py /home/claude/repo-eval-workspace/<repo-name>
```

Replace `<skill-directory>` with the actual path where this skill is installed (e.g., `/mnt/skills/user/repo-eval`).

Review the scan output. Distinguish real findings from false positives (e.g., dangerous patterns in test code that's *testing* the validator are not real findings).

### Step 2: Evaluate across four dimensions

Work through these in priority order, reading additional source files as needed. Budget your tool calls — focus on files that matter most rather than reading everything.

#### Dimension 1: Practical Utility (most important)

A beautifully architected project that doesn't work or solve a real problem is worthless.

**What to assess:**
- Does the project do what the README says? Trace claims to implementation.
- Is there a clear, plausible usage path? Could someone actually adopt this?
- Are there working examples, tests, or demos that prove it functions?
- How complete is it? Proof-of-concept or genuinely usable?
- Maintenance trajectory — improving, stable, or decaying?

**Red flags:** README promises features that don't exist in code. No tests, no examples, no CI. Last commit 2+ years ago. Stub implementations behind real-looking interfaces.

**Rating (1-5):**
- 5: Production-ready, well-documented, actively maintained
- 4: Functional and useful, minor gaps
- 3: Works for the happy path, needs effort to adopt
- 2: Proof of concept — interesting idea, not ready
- 1: Broken, abandoned, or misleading

#### Dimension 2: Security & Supply Chain

**What to assess:**
- Hardcoded secrets, API keys, tokens, credentials
- Dependencies — known-problematic or suspiciously named packages
- Install scripts, postinstall hooks, build scripts for unexpected behavior
- Input handling — sanitize/validate or trust everything?
- eval(), exec(), dynamic code generation, shell injection vectors
- Permission scope — does it request more than it needs?

**Red flags:** Obfuscated code. postinstall scripts that download and execute remote code. Low-download-count dependencies. Unexplained outbound network calls. Wildcard permissions.

**Rating (1-5):**
- 5: Clean, minimal attack surface, good input validation
- 4: Mostly clean, minor issues standard for the ecosystem
- 3: Some concerns, needs review before production
- 2: Significant issues — hardcoded secrets, unsafe patterns, sketchy deps
- 1: Actively dangerous

#### Dimension 3: Architecture & Code Quality

**What to assess:**
- Overall structure — discernible architecture or ball of mud?
- Separation of concerns
- Error handling — graceful or crash-on-failure?
- Type safety usage
- Code style consistency
- Test coverage and quality — testing behavior or satisfying metrics?
- Build/CI configuration

**Red flags:** God files/classes. Callback hell without error handling. Copy-paste code. Magic numbers everywhere. No error handling on I/O.

**Rating (1-5):**
- 5: Clean, well-structured, testable, follows conventions
- 4: Good structure with rough edges
- 3: Functional but messy
- 2: Poorly organized, technical debt everywhere
- 1: Spaghetti — needs a rewrite

#### Dimension 4: Dependency Health & Licensing

**What to assess:**
- Dependency count (direct and transitive)
- Pinning strategy — pinned or floating?
- License of the project — explicit?
- License compatibility in the dependency tree
- Vendored dependencies and their licenses

**Red flags:** No license file. GPL in a tree claiming MIT. Hundreds of transitive deps for a simple tool. Deps with <100 weekly downloads. Missing lockfile.

**Rating (1-5):**
- 5: Minimal, well-maintained deps, clear licensing, lockfile committed
- 4: Reasonable tree, clear license
- 3: Heavy but manageable, no licensing red flags
- 2: Bloated or concerning
- 1: Dependency hell or licensing landmine

### Step 3: Generate the report

Produce a markdown report and save it to:
```
/mnt/user-data/outputs/<repo-name>-eval.md
```

Use the report template from `references/report-template.md`. Read it before generating.

### Step 4: Discuss

After presenting the report, give a conversational summary. Lead with the bottom line:
- Would you recommend using/adopting this? Under what conditions?
- What's the single biggest risk?
- What's the single best thing about it?

Then open the floor. The user may want to drill into specific files or concerns.

---

## Edge cases

- **Monorepos**: Evaluate the specific package the user cares about, not the whole monorepo. Ask which package if it's not obvious.
- **Forks**: Note it's a fork, check divergence from upstream, flag if fork is abandoned while upstream is active.
- **Very new repos** (<1 week old, <5 commits): Flag immaturity explicitly. Evaluation still applies but context matters.
- **Non-code repos** (datasets, docs, config collections): Adapt dimensions. Skip architecture, focus on utility and licensing.
- **User says "full eval" or "skip triage"**: Go straight to Phase 2 if the user explicitly asks for the full evaluation up front. Still clone and orient first, but don't stop for the triage conversation.

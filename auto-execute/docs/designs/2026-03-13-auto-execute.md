# Auto-Execute: Automated Plan Execution with Safety Circuit Breakers

**Goal:** Automate the repetitive cycle of `/executing-plans` + `/clear` by running each task in a fresh Claude process with full safety checks.

**Architecture:** Three-component system — a Claude Code skill (SKILL.md) defines per-task behavior, a PowerShell wrapper script (auto-execute.ps1) drives the outer loop across sessions, and hook scripts provide real-time safety guards during execution. All gated by a `RALPH_ACTIVE` environment variable so hooks stay silent during manual Claude usage.

**Tech Stack:** PowerShell 5.1+ (built into Windows 11), Claude Code CLI, Claude Code hooks system.

---

## Components

### 1. SKILL.md — Per-Session Behavior

**Location:** `~/.claude/skills/auto-execute/SKILL.md`

Defines how Claude behaves when executing a single task from a plan. Based on the existing `executing-plans` skill with key differences for automated invocation.

**Same as `executing-plans`:**
- Reads plan file, executes the specified task number
- Follows TDD red-green cycle (failing test → implementation → passing test)
- Commits after each completed task
- Verifies tests pass before committing
- Checks assumptions (clean tree, previous tasks complete)

**Different from `executing-plans`:**
- **Headless operation.** Runs in an automated loop with no human present.
  - DO NOT ask the user for clarification. You are running headless.
  - IF BLOCKED by a missing dependency, failing test you cannot solve in 3 attempts, or unclear instruction: STOP immediately.
- **Structured exit output.** MUST end with exactly this format on the final line:
  - Success: `[AUTO-EXECUTE] Task N COMPLETE. Commit: <hash>`
  - Failure: `[AUTO-EXECUTE] Task N FAILED. Reason: <description>`
- **No continuation suggestion.** Stops after the one task. The PS1 wrapper decides what's next.
- **Assumption violations exit immediately** with the `[AUTO-EXECUTE] FAILED` tag rather than prompting.

**Input format:** `/auto-execute <plan-path> do task <N>`

### 2. auto-execute.ps1 — Outer Loop

**Location:** Project root (or wherever the user prefers). Not tracked in git — it's a user tool.

#### Parameters

```powershell
param(
    [Parameter(Mandatory)] [string] $Plan,        # Path to plan .md file
    [string] $ClaudeBin    = "claude",             # CLI binary name (configurable)
    [int]    $MaxTurns     = 40,                   # Max Claude turns per task
    [int]    $TaskTimeout  = 900,                  # Seconds per task before kill (15 min)
    [int]    $ContextLimit = 70000,                # Token threshold for hook
    [int]    $MaxFailures  = 2,                    # Consecutive failures before full stop
    [int]    $StartTask    = 0,                    # 0 = auto-detect from plan
    [string] $LogDir       = "logs/auto-execute"   # Log directory (relative to project root)
)
```

#### Phase 1: Pre-flight Checks

Before the loop starts, verify:

1. `$ClaudeBin` is callable (`Get-Command $ClaudeBin`)
2. `$Plan` file exists and is readable
3. Current directory is inside a git repository
4. Working tree is clean (`git status --porcelain` returns empty)
5. Plan file has at least one unchecked task (`- [ ]` exists)
6. Log directory exists or can be created
7. Warn if `$LogDir` is not in `.gitignore`
8. **Tool approval:** The CLI invocation must include `--dangerously-skip-permissions` to bypass all tool approval prompts. In headless `-p` mode, any approval prompt will hang the process until timeout.

Then set environment:
- `$env:RALPH_ACTIVE = "true"` — activates hooks
- `$env:RALPH_CONTEXT_LIMIT = $ContextLimit` — hooks read this

Fail fast with a clear message if any check fails.

#### Phase 2: Task Tracking

The PS1 wrapper maintains its own **internal task counter** rather than relying on Claude to edit checkboxes in the plan file. This avoids the fragile dependency on Claude correctly modifying markdown.

- **Initial detection:** If `$StartTask` is 0, scan the plan for the first `### Task N:` section containing `- [ ]` steps. Use that N as the starting point.
- **Advancement:** After each successful task (all verification signals pass), increment the counter.
- **Resume:** If the loop was interrupted, re-run with `-StartTask N` to resume from a specific task, or let it auto-detect from checkboxes again.
- **Total tasks:** Parse the plan once at startup to count all `### Task N:` headers. Use this to detect completion (counter > total).

#### Phase 3: Main Loop

```
while ($running) {
    1. CHECK COMPLETION
       - If $currentTask > $totalTasks → "All tasks complete!" → exit success

    2. RECORD BASELINE
       - $beforeHash = git rev-parse HEAD
       - $beforeTime = current timestamp

    3. EXECUTE
       - Launch: & $ClaudeBin -p "/auto-execute @$Plan do task $currentTask" --dangerously-skip-permissions --max-turns $MaxTurns --no-color
       - Pipe output through Tee-Object to both console and log file
       - Monitor elapsed time with Stopwatch
       - If $TaskTimeout exceeded → kill process tree with taskkill /F /T /PID → log timeout

    4. POST-TASK VERIFICATION (multi-signal)
       - $exitOk    = ($LASTEXITCODE -eq 0)
       - $newCommit  = (git rev-parse HEAD) -ne $beforeHash
       - $cleanTree  = (git status --porcelain) returns empty

       All 3 must pass for success.

    5. DECISION
       - All pass → log success, reset failure counter, increment $currentTask, continue
       - Any fail → increment failure counter, log which signals failed
       - $consecutiveFailures >= $MaxFailures → full stop

    6. DIRTY TREE HANDLING (special case)
       - If tree is dirty (uncommitted changes from partial task):
         - Run: git stash --include-untracked -m "auto-execute: partial task $currentTask"
         - Log: "Task N left uncommitted changes (including untracked files). Stashed."
         - Stop loop — don't start next task on dirty state
}
```

#### Phase 4: Logging

**Per-task log:** `$LogDir/task-N-YYYYMMDD-HHmmss.log`
- Full Claude output (stdout + stderr)

**Summary log:** `$LogDir/run-YYYYMMDD-HHmmss.log`
- One line per task with result:
```
[12:05:23] Task 1: PASS (commit abc1234, 3m 12s)
[12:09:45] Task 2: PASS (commit def5678, 4m 22s)
[12:15:01] Task 3: FAIL (no new commit, exit code 0) — STOPPED
```

Recommended: add `logs/` to `.gitignore`. The script warns during pre-flight if not gitignored.

#### Phase 5: Graceful Shutdown

Trap Ctrl+C using `try/finally`:
- Set `$running = $false`
- Let the current Claude process finish naturally (don't kill mid-execution)
- Log: "Stopped by user after task N"
- Report summary of completed tasks
- Exit cleanly

#### Phase 6: Final Report

When the loop ends (for any reason), print:
```
=== Auto-Execute Summary ===
Plan:       docs/plans/2026-03-13-feature.md
Tasks:      5/8 completed
Duration:   23m 45s
Stop reason: All tasks complete / Max failures reached / User interrupt / Timeout
Logs:       logs/auto-execute/run-20260313-120500.log
```

### 3. Hook Scripts — Real-Time Safety

**Location:** `.claude/hooks/` inside the project. Tracked in git (they're part of the project's automation setup).

Both hooks are gated: first line checks `$env:RALPH_ACTIVE`. If not set or not "true", exit 0 immediately.

#### Hook A: Context Limit Check (`.claude/hooks/context-check.ps1`)

**Trigger:** `PreToolUse`, matcher `*` (all tools)

**Logic:**
1. Gate: `if ($env:RALPH_ACTIVE -ne "true") { exit 0 }`
2. Read threshold from `$env:RALPH_CONTEXT_LIMIT` (default 70000)
3. Read `transcript_path` from the hook's stdin JSON (Claude Code provides it directly)
4. Estimate tokens: `$estimatedTokens = (Get-Item $transcriptPath).Length / 4` (O(1) file-size heuristic)
5. If tokens > threshold → write reason to stderr, exit 2 (blocks tool). The stderr message must instruct the model to stop: `"CONTEXT LIMIT EXCEEDED (~X tokens > $limit). DO NOT RETRY. Output '[AUTO-EXECUTE] Task N FAILED. Reason: context limit' and stop immediately."`
6. Otherwise → exit 0 (allow)

**Fallback:** If `transcript_path` is missing from the hook payload or file can't be read, exit 0 (allow). The `--max-turns` flag on the CLI acts as a backstop.

#### Hook B: Loop Detector (`.claude/hooks/loop-detect.ps1`)

**Trigger:** `PreToolUse`, matcher `*` (all tools)

**Logic:**
1. Gate: `if ($env:RALPH_ACTIVE -ne "true") { exit 0 }`
2. Read hook input JSON from stdin — extract `tool`, `tool_input`, and `session_id`
3. Append entry to temp counter file: `$env:TEMP/ralph-calls-<session-id>.jsonl`
4. Count total tool calls in session. If > 100 → exit 2 with stderr: `"TOO MANY TOOL CALLS (>100). DO NOT RETRY. Output '[AUTO-EXECUTE] Task N FAILED. Reason: stuck/loop detected' and stop immediately."`
5. Check for repetition: normalize `tool_input` (strip extra whitespace, lowercase command strings), then compute hash of `tool + normalized_input`. If same hash appears 3+ times in last 10 calls → exit 2 with stderr: `"REPEATED IDENTICAL TOOL CALLS DETECTED. DO NOT RETRY. Output '[AUTO-EXECUTE] Task N FAILED. Reason: loop detected' and stop immediately."`
6. Otherwise → exit 0

**Cleanup:** The PS1 wrapper deletes temp counter files after each task completes (fresh process = fresh counter).

#### Hook Registration (`.claude/settings.json`)

Added to the project's local settings:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/context-check.ps1"
          },
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File .claude/hooks/loop-detect.ps1"
          }
        ]
      }
    ]
  }
}
```

---

## Deliverables

| File | Location | Git tracked? |
|------|----------|-------------|
| `SKILL.md` | `~/.claude/skills/auto-execute/SKILL.md` | No (user config) |
| `auto-execute.ps1` | Project root | User's choice |
| `context-check.ps1` | `.claude/hooks/context-check.ps1` | Yes |
| `loop-detect.ps1` | `.claude/hooks/loop-detect.ps1` | Yes |
| `.claude/settings.json` | `.claude/settings.json` (modified) | Yes |

---

## Usage

```powershell
# Basic — run all remaining tasks
.\auto-execute.ps1 -Plan "docs/plans/2026-03-13-auth.md"

# Custom CLI binary
.\auto-execute.ps1 -Plan "docs/plans/2026-03-13-auth.md" -ClaudeBin "claude2"

# Tighter safety
.\auto-execute.ps1 -Plan "docs/plans/2026-03-13-auth.md" -MaxTurns 25 -TaskTimeout 600 -MaxFailures 1

# Logs go outside the repo
.\auto-execute.ps1 -Plan "docs/plans/2026-03-13-auth.md" -LogDir "$env:TEMP/auto-execute"
```

---

## Safety Summary

| Check | When | Mechanism | Action |
|-------|------|-----------|--------|
| Context limit (70k) | During task (real-time) | PreToolUse hook | Block tool, Claude stops |
| Loop/stuck detection | During task (real-time) | PreToolUse hook | Block tool, Claude stops |
| Task timeout | During task | PS1 Stopwatch | Kill process |
| Exit code check | After task | PS1 `$LASTEXITCODE` | Increment failure counter |
| New commit check | After task | PS1 `git rev-parse HEAD` | Increment failure counter |
| Clean tree check | After task | PS1 `git status --porcelain` | Stash + stop |
| Max consecutive failures | After task | PS1 counter | Full stop |
| Ctrl+C | Anytime | PS1 try/finally | Graceful stop |
| Pre-flight checks | Before loop | PS1 validation | Fail fast |
| `--max-turns` | During task | Claude CLI built-in | Process exits |

---

## Resolved Questions

All open questions have been researched and resolved:

1. **Transcript path:** RESOLVED — `%USERPROFILE%\.claude\projects\<encoded-cwd>\` where `<encoded-cwd>` replaces every non-alphanumeric character with a hyphen (e.g., `C:\Users\me\proj` → `-C-Users-me-proj`). However, the hook payload includes `transcript_path` directly, so the context-check hook doesn't need to search.
2. **Token estimation:** RESOLVED — `estimatedTokens = fileBytes / 4` (O(1) file-size heuristic). Good enough for a safety circuit breaker.
3. **Process tree kill:** RESOLVED — `taskkill /F /T /PID $pid` on Windows. `/T` kills the entire child process tree.
4. **Hook input schema:** RESOLVED — JSON via stdin:
   ```json
   {
     "tool": "ToolName",
     "tool_input": { "command": "...", "file_path": "...", "content": "..." },
     "session_id": "...",
     "transcript_path": "...",
     "working_directory": "..."
   }
   ```
5. **`-p` flag behavior:** RESOLVED — `claude -p "prompt"` runs in print mode, executes the prompt, and exits immediately. No hanging.

---

## Known Constraints

1. **Every task must produce a git commit.** The post-task verification requires `git rev-parse HEAD` to change. Plans generated by `writing-plans` enforce this (every task ends with a commit step). Manually written plans must follow the same rule, or the auto-loop will flag a successful no-commit task as a failure.
2. **`--dangerously-skip-permissions` required.** The CLI invocation uses this flag to bypass tool approval prompts in headless mode. Without it, `-p` mode hangs on approval prompts.
3. **Hook schema is from research, not tested.** The `transcript_path` and `session_id` fields in the hook payload should be verified with a simple dump-to-file hook during first implementation.

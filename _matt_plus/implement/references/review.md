# Review a committed range

Two axes over one committed range: **Standards** (does the code follow this repo's documented standards and the smell baseline?) and **Spec** (does it do R1…Rn?). They stay separate because a change passes one while failing the other, and merging the reports lets one mask the other.

## When

- A slice the plan **flagged**, over `<slice base>..HEAD`, before the next slice.
- Always the **end review** over `<run base>..HEAD`, at most two invocations.

## Dispatch

One parallel batch of two `reviewer` tasks — Standards and Spec. Each prompt is self-contained: it names the repo, the range, the run's git command, the axis, and the standards sources. Each reviewer reads `skill://code-review` and `skill://code-review/references/smells.md` itself, so no smell list is pasted — that pointer is why the baseline has exactly one home.

```markdown
Review the committed range <base>..HEAD in <repo>.
Run: git log <base>..HEAD --oneline; git diff <base>...HEAD
Read and follow skill://code-review, including skill://code-review/references/smells.md.
Axis: <Standards | Spec>
Standards sources: <repo standards paths, from Phase 1>
Spec: R1…Rn verbatim.

Verbatim quotes, no paraphrase: cite every finding as file:line and quote the hunk or
the standard line it breaks. The repo's documented standard overrides the baseline.
Skip anything tooling already enforces. Under 400 words.
Clean axis → report exactly `PASS`.
```

`PASS` is the only clean verdict; anything else is findings. Quote because a paraphrase of a hunk drifts from the hunk and cannot be checked.

## Fix loop

- Design or multi-site finding → one Worker fixer, dispatched with the findings.
- Mechanical finding → the Orchestrator fixes it directly.
- Then the **Wall**, then one commit: `fix(<scope>): address review findings`.

## End review

Review 1 is the same two-axis batch over `<run base>..HEAD`; its fixes take the same Wall and commit path.

**Review 2** runs only when review 1 produced fixes: re-check each review-1 finding against the fix commits, then scan the fix diff. A finding in review 2 gets one fix, never a third invocation. Whatever stays open is copied verbatim into the report — a finding you cannot close is information, not a failure to hide.

Findings are judgement calls, not a score. There is no clean-up-to-100%; a PASS with a noted nit is a pass.

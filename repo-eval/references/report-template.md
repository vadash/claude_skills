# Report Template

Use this exact structure for the evaluation report. Fill in all sections. Do not skip sections — if a dimension has nothing notable, say so briefly.

---

```markdown
# Repo Evaluation: {repo-name}

**Repository**: {github-url}
**Evaluated**: {date}
**Primary Language**: {language}
**License**: {license or "None specified"}

## Summary

| Dimension | Score | One-Line |
|-----------|-------|----------|
| Practical Utility | {1-5}/5 | {one sentence} |
| Security & Supply Chain | {1-5}/5 | {one sentence} |
| Architecture & Code Quality | {1-5}/5 | {one sentence} |
| Dependency Health & Licensing | {1-5}/5 | {one sentence} |

**Overall**: {Recommend / Recommend with caveats / Do not recommend}

**Bottom line**: {2-3 sentences. What is this, does it work, should you use it?}

## Practical Utility

{Assessment. Lead with whether it does what it claims. Include specifics — trace claims to code. Note completeness, maintenance status, and adoption signals.}

## Security & Supply Chain

{Assessment. Lead with the most significant finding (or lack thereof). Cover secrets, dependency trust, input handling, permissions. Reference specific files/lines for any findings.}

## Architecture & Code Quality

{Assessment. Lead with the overall structural impression. Cover organization, error handling, type safety, testing, build pipeline. Reference specific patterns observed.}

## Dependency Health & Licensing

{Assessment. Include dependency count (direct/transitive), pinning strategy, license situation, and any specific concerns about individual dependencies.}

## Notable Files

{List 3-5 files that are most important for understanding the project, with a one-line note on each.}

## Red Flags

{Bulleted list of specific concerns, or "None identified." Each flag should reference a specific file or pattern, not be vague.}

## Strengths

{Bulleted list of things done well. Be specific.}
```

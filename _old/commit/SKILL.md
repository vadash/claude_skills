\---

description: Generates concise Git commit messages and commits changes

\---



\# Commit



When this skill is activated:

1\. Run `git diff --staged` to see what changes are ready.

2\. If nothing is staged, run `git add .` after confirming with the user.

3\. Generate a short, one-line commit message in the format: `type: description` (e.g., "feat: add login").

4\. Execute `git commit -m "<message>"`.




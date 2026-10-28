---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS (`$TMPDIR`, else `%TEMP%` on Windows) — not the current workspace.

Invocation: `/skill:handoff <what will the next session be used for?>`, the argument being optional. If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

Include a "suggested skills" section in the document, naming which skills the next agent should read, each as a `read skill://<name>` pointer.

Leave content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs) where it lives: reference them by path or URL instead of copying them in.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

**Done**: a fresh agent with only the document can continue the work, and the file sits in the OS temporary directory with its path reported to the user.

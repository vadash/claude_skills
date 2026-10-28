---
name: research
description: Investigate a question against primary sources and capture the findings as a Markdown file in the repo.
disable-model-invocation: true
---

You [YOU] delegate the reading, so the work at hand keeps moving.

Invocation: `/skill:research <question>`. Invoking it authorises dispatching the researcher and writing the notes file, so start both without asking again.

Spin up a **background agent** to do the research, so you keep working while it reads.

Its job:

1. Investigate the question against **primary sources** (official docs, source code, specs, first-party APIs), not a secondary write-up of them. Follow every claim back to the source that owns it.
2. Write the findings to a single Markdown file, citing each claim's source.
3. Save it where the repo already keeps such notes; match the existing convention, and if there is none, put it somewhere sensible and say where.

**Done**: the file exists, every claim in it carries its citation, and you have told the user where the file lives.

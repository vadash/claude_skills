---
name: grilling
description: A relentless interview that stress-tests a plan, decision, or idea.
disable-model-invocation: true
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Word each question so "yes" accepts your recommended answer.

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

## The ledger

The ledger is the tree's durable state: the record a spec is synthesised from, never a transcript to be reconstructed. After each round, append one entry per decision that round settled:

- the question, as asked;
- the answer, as given;
- the one-line reason it holds;
- the question it unblocked, by number.

Nothing is settled until it is on the ledger. A decision that lives only in the conversation is a decision the spec cannot carry: `/skill:to-spec` writes from the ledger, so an unledgered answer is lost the moment the round scrolls away.

## Reversal

An answer can invalidate a decision already settled. When it does, re-open that decision: strike its ledger entry with the reason it fell, then recompute the frontier from there, since everything the struck decision unblocked is open again. Silent overwrites are how a plan ends up carrying two contradictory decisions; the strike keeps the fall visible, so the next round asks the question again rather than inheriting an answer nobody chose.

## Facts

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

**Done**: the frontier is empty and every settled decision has a ledger entry. Do not act on it until the user confirms you have reached a shared understanding.

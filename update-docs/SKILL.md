---
name: update-docs
description: Manually invoked skill to update repository documentation consistently. Analyzes current context to read and orthogonally update CLAUDE.md and include/*.md files based on core context engineering best practices.
disable-model-invocation: true
---

# update-docs

**Conceptual Execution Checklist:**
- Discover and read existing `CLAUDE.md` and `include/*.md` documentation files.
- Analyze context to capture the WHAT, WHY, and HOW of the codebase without redundancy.
- Ensure critical component directories (e.g., `ui`, `tests`, and `backend`) have dedicated `CLAUDE.md` files.
- Apply progressive disclosure for large hierarchies to maintain strict orthogonal alignment.
- Validate all modifications for high-leverage token efficiency, universal applicability, and strict adherence to documentation guidelines.

## Execution Instructions

Follow these steps exactly when invoked.

### 1. File Discovery and Reading
Before any significant file discovery or read action, you must output exactly one brief line stating your purpose and minimal inputs (e.g., *Purpose: Discovering existing CLAUDE.md files via glob **/CLAUDE.md*).
- Use `glob` to search for all `**/CLAUDE.md` files in the repository.
- Use `glob` to search for all `include/*.md` files.
- Read the contents of the discovered files to establish the current documentation baseline.

After each file discovery or read step, validate the result in 1-2 lines (e.g., *Validation: Found and read 4 CLAUDE.md files. Proceeding.*). If validation fails, self-correct before moving on.

### 2. Context Analysis and File Targeting
Use the current repository context to determine how to update the files based on the principle that LLMs are mostly stateless.
- **WHAT, WHY, and HOW:** Ensure the root `CLAUDE.md` provides a map of the tech stack (WHAT), the project's purpose (WHY), and how to work on/verify the project (HOW). 
- **Important Directories:** You must explicitly verify or establish coverage for `ui`, `tests`, and `backend`.
- **Progressive Disclosure:** Keep task-specific or component-specific context out of the root file. If a directory is large, create multiple `CLAUDE.md` files at different directory levels. Prefer pointers to copies.
- **CRITICAL RESTRICTION:** Do NOT create new files in the `include/` folder. You may only update existing `.md` files in that directory.

### 3. Content Generation and Editing
Before editing or generating file content, state your assumptions briefly. Keep your changes minimal and reviewable. `CLAUDE.md` is the highest leverage point of the harness—a bad line here creates bad code everywhere. Craft every line carefully.

Adhere to the following content rules`:
- **Less is More (Instruction Decay):** Do NOT waste the context window. LLM instruction-following quality decays uniformly as instruction count increases. Target < 60 to 300 lines for the root file. Never list every function and what it does.
- **Universally Applicable:** Avoid adding "hotfixes" to `CLAUDE.md` for specific prompt failures. Only include information universally applicable to the tasks in that directory; otherwise, Claude will ignore the file.
- **Orthogonal Alignment:** The exact same fact must never be mentioned in two different Markdown files. If context is needed, point to the authoritative file.
- **No Line Numbers:** Never use line numbers when referencing code. They become outdated quickly. Reference structural elements (file names, class names, distinct symbols) instead.
- **Use Constants:** When documenting logic, conventions, or examples, never use numeric variables (magic numbers). Always use named constants.
- **Claude is NOT a Linter:** Do NOT document code style guidelines, formatting rules, or linting standards. Rely on in-context learning and deterministic tools for those tasks. Keep the LLM focused on implementation.

After each file edit, validate the result in 1-2 lines to ensure the file was correctly updated.

### 4. Final Validation
Review your work. Output a final 1-2 line validation confirming that changes capture the WHAT/WHY/HOW, are universally applicable, strictly orthogonal, token-efficient, and that no new files were improperly created in the `include/` directory.

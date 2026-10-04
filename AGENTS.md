**Before any work, read all Harnez rules in one call: `harnez read .harnez/rules/Tools.md .harnez/rules/Issues.md .harnez/rules/Quota.md .harnez/rules/Subagents.md .harnez/rules/Output.md .harnez/rules/Local.md`. This follows Index.md order; Local.md overrides the other rules.**

Adhere to the following conventions.

<!-- harnez:begin Project Summary -->
<!-- harnez:end Project Summary -->

## Development Scripts

Run from project root.

## Background Tasks & Process Hygiene

- Subagent handoff must not block the main chat. When the user asks to hand work to a subagent,
  spawn/delegate the task and remain responsive as the host orchestrator; do not immediately wait
  on the child agent unless the user explicitly asks you to wait or the next user-visible
  integration step truly cannot proceed without the result.
- Do not spawn subagents with git worktree isolation unless the user explicitly requests it.
  Sequential/consecutive ticket work should run directly on the currently checked-out branch —
  worktrees have their own failure modes (e.g. branching from a stale base, or being unable to
  see a prior step's still-uncommitted changes) and add reconciliation overhead that isn't needed
  for normal one-after-another dev work.
<!-- harnez:begin Language Conventions -->
Adhere to the following conventions.

Docs in `./docs/` are managed by harnez. <!-- harnez:bundled -->

- Agentic Loop Practices @docs/AgenticLoop.md,
  5-phase loop (Advisory -> Dev -> Review -> Hygiene -> Retro), zero zombie guarantee
- Bash/Shell @docs/Bash.md,
  Read before multi-line shell: Make recipes, embedded scripts
  No ";", break before then/else/docs
  No "if [[]]", No "if []", Use "if test"
  smart indent!
  Use git -C/make -C, not cd
- Canary-first development @docs/Canary.md,
  probe external mechanisms before building features on them
- Git @docs/Git.md,
  conventional commits, work on the default branch, don't push unless asked
- Issue Tracking Practices @docs/IssueTracking.md,
  P0-P3 priorities, metadata headers (Status, Priority, Severity, Category), tracker sync
- Make/Makefile @docs/Make.md,
  ⚙️ phony sentinel, self-doc help, build dependency pattern
- Markdown @docs/Markdown.md,
  PascalCase for evergreens, kebab-case for ephemeral docs; ASCII art in chat, Mermaid only in docs/
- Search Practices @docs/Search.md,
  harnez find code/docs, finder configuration, partial results, and rg fallback
- Spec system @docs/Spec.md,
  YAML spec files as single source of truth; Go code must not duplicate spec values
<!-- harnez:end Language Conventions -->

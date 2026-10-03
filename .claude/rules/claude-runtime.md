# Claude Code runtime map

Root `CLAUDE.md` imports `AGENTS.md`. The shared skills own workflow; the
repository's `.agents/project.md` owns Lineup-specific routing. This file only
describes host discovery and adds no orchestration policy.

- The shared `develop-code`, `design-code`, `review-code`, `verify-code`, and
  manual-only `maintain-workflow` skills are installed separately. Validate
  discovery in the actual host. If a delegated agent does not receive a needed
  callable skill, its controller supplies the loaded instructions in the task
  packet. Manual-only maintenance requires explicit user invocation; do not
  preload it or restore a competing repo-local body.
- Use the controller and ordinary bounded agents for implementation. Shared
  personal `code-reviewer` and `code-investigator` agents provide narrow
  read-only capabilities and inherit the selected model. They have only Read,
  Grep, and Glob; the controller supplies Git diffs and command evidence.
- `.codex/config.toml` and `.codex/agents/*.toml` configure Codex. Claude uses
  `.claude/agents/`; do not infer cross-host feature or effort parity from names.
- Codex discovers personal `code_reviewer` and `code_investigator` agents;
  the project does not shadow them with duplicate procedures or model-bound
  aliases. Respect effective runtime permissions and delegation restrictions.
  A concurrency ceiling is not a target roster; parallel work requires
  independent ownership and stable check inputs.

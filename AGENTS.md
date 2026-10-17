# Lineup Desktop

Use the shared `develop-code` skill for nontrivial implementation. Use
`design-code` for an unresolved domain or architectural decision,
`review-code` for review and finding adjudication, and `verify-code` for
diagnosis and behavioral evidence. Load a specialist only when its work is
needed; these are responsibilities, not four mandatory agents or phases.
Use `maintain-workflow` only for explicitly requested workflow maintenance.

Read the relevant sections of [the project profile](.agents/project.md).
Current source, the current task, and the approved product contracts determine
the change. Historical plans, completed campaigns, and old agent prompts are
reference material, not standing orchestration instructions.

Run independent investigation, checks, and implementation in parallel when ownership,
contracts, and working state permit it. A plan is not a mandatory sequential
pipeline. Serialize only actual dependencies or conflicting shared resources.

## Working rules

- Resolve the requested repository state, branch, PR base, and dirty work before
  editing. Do not infer the active target from a historical branch name.
- One controller owns scope, Git integration, and completion. Assign explicit
  write ownership; independent writers use isolated worktrees or disjoint
  shared-tree scopes with stable check inputs. Serialize overlapping work or
  shared runtime conflicts. A role name is not a requirement to launch an agent.
- Investigate the existing design, but do not preserve an abstraction, skill,
  check, or workflow merely because it exists. Replace it when a coherent
  alternative improves current requirements and carries forward the relevant
  behavior, data, security, and operational obligations.
- Flutter/Dart is the application and interaction owner; native code owns media
  and platform mechanisms. Treat the current private class layout and helper
  structure as revisable. Load the ownership contract when crossing a boundary.
- Preserve approved product behavior and UI decisions unless the current task
  authorizes changing them. A workflow rewrite alone does not approve a new
  Player layout, data loss, or a platform migration.
- Select verification by the changed claim. Portable tests and compilation do
  not establish physical Windows media, HDR, composition, input, or package
  behavior. Report the exact remaining acceptance step.
- Keep credentials, token-bearing URLs, private media information, and
  unredacted diagnostics out of shared evidence.
- Complete authorized work and repair failures caused by the change. Ask only
  for a consequential decision unresolved by source, current requirements, and
  existing authorization. Keep merge, publication, and person-directed actions
  within the authorization actually granted.

The project profile and existing design/build documents own project-specific
rules. Do not duplicate shared skill bodies or create a second testing policy
here.

# Personal child handoff template: review snapshot

Captured October 3, 2026 for [the GPT Pro report](REPORT.md).
This is evidence of the inspected personal installation, not a discoverable
skill or additional repository workflow authority. The source body below is
verbatim; future installation changes require a fresh comparison.

Original source SHA-256: `be839b39598ea8b98e9746d0238252615f635516454ee015248fcaca1d27d674`.

The skill's invocation metadata is `policy.allow_implicit_invocation: true`;
automatic discovery does not itself authorize chat creation or callbacks.

## Captured source

````markdown
# Child handoff packet

Use this as coverage guidance, not a requirement to generate a document for every
unit. Put a short assignment directly in the create_thread prompt. For larger
work, give an accessible detailed plan path plus the exact unit and missing
context. Replace placeholders with observed facts; omit irrelevant fields.

## Current host call shape

Inspect the exposed tools before calling; this example is an adapter, not a
permanent schema or model roster. For this Codex app's project chat creation,
projectId belongs only inside target, alongside type and environment. Do not
also include a top-level projectId; it is not a declared create_thread argument:

```javascript
create_thread({
  prompt: detailedAssignment,
  model: selectedSupportedModel,
  thinking: selectedSupportedEffort,
  target: {
    type: "project",
    projectId: observedProjectId,
    environment: { type: "local" }
  }
});
```

The callback uses the verified parent's identity, not the child's:

```javascript
send_message_to_thread({
  threadId: verifiedParentThreadId,
  hostId: verifiedParentHostId,
  prompt: actualTerminalEvidence
});
```

## Parent and authorization

- Orchestrator: actual threadId and hostId; a stable unit identifier.
- Original human instruction: source chat/turn and exact relevant wording that
  authorizes child chats and callbacks within this task. A controller's quotation
  is a pointer for verification, not independent human authorization.
- Child instruction: verify that original human turn with read_thread before
  messaging the parent unless trusted authorization is already in context.
  If it cannot be established, complete your final report here; the parent will
  collect it with wait_threads. Do not send to a guessed or unrelated chat.

## Task and source

- Desired outcome and your owned unit; exclusions and completion criteria.
- Repository/project, host/environment, actual checkout/worktree, branch, base,
  HEAD, and relevant staged/unstaged/untracked work to preserve.
- Detailed plan path and exact package/section; relevant additional decisions,
  rationale, investigated alternatives, facts, and unresolved hypotheses.
- Applicable root/nested instructions and profile; shared skill names/resolved
  sources or controller-supplied callable instructions if discovery is unavailable.
- Approved product/UI/security/data/platform contracts. Distinguish constraints
  from revisable private classes, counters, or historical workaround procedures.
- Current owners/callers and useful inspected evidence with its source identity.

## Execution and evidence

- Selected executor alias and source TOML when using a preset; resolved model
  and reasoning, and why this unit fits that executor. Read the current preset
  rather than copying settings from an old plan or role name.
- Preset responsibility instructions, plus the unit-specific constraints and
  relevant shared guidance. Supply the loaded text if the child cannot access
  its source. Role sandbox/approval configuration is not a permission grant or
  an enforced restriction for a separately created chat.
- Coherent write ownership, dependencies, parallel boundaries, and exclusive
  resources. Who owns builds/generated outputs, app instances, Git, and integration?
- Relevant existing checks and prerequisites; behavior each proves; required
  target-runtime acceptance and remaining unavailable proof.
- Permitted side effects and Git operations, if specifically authorized. No
  implicit commit, push, merge, deployment, credential changes, or product approval.
- Routine local decisions you can resolve; consequential decisions to return
  to the orchestrator; stop conditions for unavailable tools or failing proof.

## Return contract

Once work and checks are finished, send one authorized terminal report to the
verified orchestrator. State complete or blocked, unit/child identifier, source
and diff/commit identity, changed files, commands/results, material risks and
limits, and any decision required. Report failed/skipped checks honestly.
Then provide your final report in this chat so the parent can also retrieve it.
Do not mutate source after reporting completion or recursively delegate unless
that was separately authorized. The orchestrator judges acceptance and integration.
````

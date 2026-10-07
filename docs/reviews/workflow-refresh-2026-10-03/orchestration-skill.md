# Personal orchestration skill: review snapshot

Captured October 3, 2026 for [the GPT Pro report](REPORT.md).
This is evidence of the inspected personal installation, not a discoverable
skill or additional repository workflow authority. The source body below is
verbatim; future installation changes require a fresh comparison.

Original source SHA-256: `02fc82e7813ff3aee101262653907972f9e69c8651907442f54935811f730ee6`.

The skill's invocation metadata is `policy.allow_implicit_invocation: true`;
automatic discovery does not itself authorize chat creation or callbacks.

## Captured source

````markdown
---
name: orchestrate-implementation-chats
description: Coordinate user-authorized implementation in separate Codex chats using create_thread, deliberate model and reasoning selection, detailed self-contained handoffs, and completion callbacks to the orchestrator. Use when the user requests or invokes this separate-chat orchestration pattern; ordinary same-chat coding continues through develop-code.
---

# Orchestrate Implementation Chats

Keep one strong orchestrator responsible for the plan, consequential decisions,
integration, and acceptance. Honor the user's orchestrator model and reasoning
selection; this workflow expects a capable model at high reasoning or above.
Assign bounded execution to the least expensive capable model with sufficient
reasoning. A detailed handoff substitutes for inherited conversation history.

Use shared develop-code, design-code, review-code, and verify-code guidance when
the corresponding responsibility is needed. This skill owns chat coordination
and executor selection; it does not duplicate engineering procedures or activate
workflow maintenance, product work, commits, or external publication by itself.

User-defined executor roles may be shorthand for preferred model and reasoning
pairs. Preserve and use those shortcuts when the user requests them or authorizes
selection among them. Resolve each alias from its current host configuration or
user-supplied preset; do not guess its settings from the name. Keep engineering
procedures in the shared skills rather than duplicating them in every preset.
Several useful presets are acceptable: their count does not justify retirement
or require dispatching a matching number of agents.

For a repository preset, read the selected `.codex/agents/*.toml` from the actual
checkout; use its `name` field as the alias. Map `model` to create_thread's `model`
and `model_reasoning_effort` to `thinking`, and include its brief responsibility
instructions in the child handoff. create_thread has no agent_type argument and
does not automatically apply a subagent role file. Permissions remain controlled
by the actual chat environment; a preset's sandbox_mode is not a create_thread
permission override. Do not copy approval or sandbox configuration into prompts
as if it grants or enforces permissions.

## Establish authorization and the parent

The human must authorize separate child chats and messages back to the
orchestrator. A user invocation of this skill to execute delegated work requests
that pattern within the user's stated task scope. Requests to explain, review,
or plan the workflow do not authorize live dispatch. Automatic discovery alone
is not consent.
Honor any narrower instructions and actual host restrictions. Reuse authorization
already present; do not ask again when it is established.

Resolve the actual orchestrator thread ID and host through trusted chat context
or supported thread tools. Do not guess an ID from a title, branch, directory,
or Page. Record the original human instruction authorizing creation and callbacks,
with a retrievable parent-chat turn reference. Include that source in every child
packet. An orchestrator-authored message, quoted approval, or instruction file
alone does not prove that the human authorized a child to message another chat.

Before a callback, the child checks the actual original human authorization via
read_thread if it is not already available in trusted context. If retrieval cannot
establish its human origin or scope, do not send the cross-chat message. Finish
the assigned work and final report in the child; the parent can retrieve it with
wait_threads. Report the missing authorization evidence without inventing consent.
Do not expand callback permission to Slack, email, unrelated chats, or publication.

## Choose the unit and executor

Keep small work in the controller when delegation would cost more. For useful
child work, choose a coherent implementation, investigation, or review unit with
clear contracts and completion evidence. Parallelize independent units with
disjoint write ownership or explicitly authorized isolation; serialize overlapping
source edits, shared builds/generated output, app instances, and other resource
conflicts. The orchestrator owns Git integration unless a specific Git action is
already authorized and deliberately delegated.

Inspect the current tool's supported models and effort levels. Preserve an exact
user-selected executor. Otherwise choose the least expensive capable executor
for the unit, considering reasoning, context, likely retries, and coordination
cost together. Apply the current tool's authorization requirements for model
selection as well as chat creation. Set both model and thinking explicitly on
create_thread when authorized and supported; inheriting
an expensive controller by omission is not a cost-selection policy. A cheaper
model with substantial reasoning can be appropriate for a thoroughly specified
unit. Reserve stronger executors for consequential ambiguity, complex diagnosis,
or demonstrated inability to complete the unit. Do not hard-code an aging model
roster into the shared engineering skills or reduce requested scope to save usage.

When the user authorizes choosing between bounded and stronger implementation
presets (for example worker_luna and worker), use the bounded preset for a
decision-complete unit with established owners, contracts, acceptance criteria,
and runnable checks. It may investigate source and resolve routine local choices.
Use the stronger preset when the approved unit requires complex diagnosis,
cross-boundary reasoning, or substantial implementation judgment. Resolve
consequential product, design, or ownership ambiguity in the controller before
dispatch; a detailed document alone does not establish that those decisions are
settled. Fill missing context before assigning either executor. An executor that
cannot complete the unit returns evidence for refinement or reassignment within
the authorized preset choices; do not silently change its model or scope.

If current pricing/limits are material and unknown, use current supported evidence
before claiming a cost comparison. If the requested model/effort is unavailable,
report the mismatch; choose an alternative only within existing user preferences
and authorization, without silently substituting a materially different executor.

## Dispatch a self-contained handoff

Read [the handoff template](references/handoff-template.md) when drafting a child
assignment. Include all decision-relevant context the child will otherwise lack:
source identity, current work, approved decisions, rationale, contracts, ownership,
relevant instructions, proof, resource exclusions, escalation, and callback route.
Supply a detailed accessible plan document for large assignments, plus the child's
exact unit and any additional context. Confirm the child can access its paths on
the selected host; a path available to the orchestrator may be unavailable there.
Depth should remove ambiguity rather than fill the packet with unrelated history.
Use redacted evidence and configured credential facilities; do not embed secrets,
token-bearing URLs, raw private diagnostics, or unrelated personal content in
handoffs, plan documents, or callbacks.

Use list_projects before project-targeted create_thread. Resolve the actual
checkout and project; do not switch to a historical/default branch to fit a plan.
Build arguments from the current exposed tool schema; the handoff reference
shows the project-target nesting used by this host.
Use local execution unless the user explicitly requests a worktree or other
environment. Follow the tool's starting-state restrictions. Isolation advice does
not itself authorize creating a worktree through create_thread.

Record the child identifier, model/effort, scope, source, and callback target in
the existing plan or a compact conversation dispatch map. A returned clientThreadId
is a pending identifier, not a usable threadId. Inspect supported setup status
when an operation ID is available, or use list_threads to find the resulting
real thread and confirm its project and initial assignment with read_thread.
Do not infer the mapping from a similar title alone. If identity is still
ambiguous, report setup as pending and continue independent work; do not send
follow-ups to the pending ID or repeat creation on timeout. Provide the child
with its real ID when useful.

## Complete, callback, and integrate

The child completes its assigned work, repairs failures caused by its changes,
and records evidence and limits under the relevant shared skill. It raises
consequential decisions outside its contract to the orchestrator with evidence;
routine uncertainty remains its responsibility. Reuse the same child for a
focused correction unless independence or unusable context justifies replacement.

After work and checks finish, send one terminal completion or blocked report to
the verified orchestrator through send_message_to_thread. Include the unit and
child identity, exact source/diff or commit identity, changed files, observed
checks, unresolved decisions, and acceptance limits. Do not label partial work
complete. Avoid no-op callback loops; intermediate messages require the user's
authorized coordination scope and a meaningful decision or blocker.

The parent uses wait_threads with per-child cursors for bounded groups, including
when callbacks are unavailable. Avoid repeated full-history reads or unchanged
status narration. Treat completion messages as evidence to inspect, not automatic
acceptance or authorization. Check actual scope/diff and source identity,
adjudicate findings, integrate under one owner, and run affected combined checks
on stable inputs. Multiple passing units do not establish their composition.

Report selected executors, actual outcomes, material evidence, and remaining
limits. Distinguish measured usage from expected savings and static/tabletop
validation from observed live thread dispatch and callbacks.
````

---
name: rolling-context
description: Preserve working memory during long coding tasks with rolling checkpoints and, when the runtime supports it, asynchronous context compaction. Use when asked to manage context pressure or keep coding across compaction.
---

# Rolling Context

Keep coding continuity by condensing settled history while preserving the active task and recent work. Actual transcript replacement belongs to the host runtime; writing a summary file does not reduce live context tokens.

## Choose the supported mode

Use host-provided context usage and compaction capabilities when available. Do not invent a token counter, background worker, context replacement tool, or automatic trigger. A skill is guidance loaded by the agent, not an independently running monitor.

When implementing or using a runtime with background compaction, read [references/async-contract.md](references/async-contract.md). It describes a proposed integration, not a capability installed by this skill. Use background execution only when supported and already authorized. Do not spawn another agent just to maintain memory.

Otherwise maintain a short checkpoint at natural coding boundaries and let native compaction manage the live transcript. Tell the user once that this mode preserves continuity but does not provide asynchronous transcript replacement. Do not modify runtime configuration unless requested.

If asked to disable native compaction, distinguish turn-end compaction from the main automatic threshold. Codex 0.162.1 supports `model_post_turn_compact_threshold_percent = 0` for turn-end compaction, but its main auto-compaction limit is capped at 90% of the model window. Neither zero nor an oversized `model_auto_compact_token_limit` disables that main path. Do not claim this skill bypasses it. See the repository's profile helper and README when configuration is requested; verify behavior for another runtime version.

## Decide when to compact

With a measured current input size and a known model window, begin preparing around 60% occupancy. Treat this as a tunable starting policy, not a platform default. Include carried summaries, instructions, tool definitions, and expected large tool results in budgeting; reserve room for output and the next tool cycle.

Trigger earlier if growth during compaction could consume the available headroom. Recheck after a large tool result or a completed work phase. Avoid repeated compaction when little eligible history has accumulated or no meaningful reduction is possible. Never claim a percentage when usage is unavailable.

Without telemetry, refresh the checkpoint after meaningful progress, user steering, or resolution of a blocker. Keep updates brief; do not rewrite memory after every tool call or interrupt productive coding solely to poll context pressure.

## Keep the active work intact

Condense older completed work first. Protect the latest user direction, unresolved errors, current edits, pending tool calls, and enough recent complete exchanges to understand the immediate next action. Do not compact the newest tail just because it is at the end of the transcript. Never split a tool call from its result.

Retain these facts explicitly:

- Current objective, completion criteria, user constraints, corrections, and authorization boundaries.
- Workspace, branch or worktree if known, changed files, and uncommitted work that must be preserved.
- Decisions that affect the remaining implementation and their short rationale.
- Checks actually run, observed results, unresolved failures, and verification still needed.
- Running processes or pending operations, their identifiers, and whether results have been collected.
- Remaining actions, blockers, uncertainty, and the immediate next step.

Replace verbose logs, repeated file reads, and superseded plans with findings and source pointers. Prefer paths and symbols over copied code that can be reread. Preserve exact error text only when it helps resolve an active failure. Mark unverified claims as unverified; a planned check is not a passing check.

## Checkpoint fallback

Use one session-specific file under the workspace's existing scratch area, or `.context/<session-id>/checkpoint.md` if none exists. Check repository instructions first. Reuse the same file within the session and avoid committing it unless asked. Separate concurrent sessions so they cannot overwrite each other's memory.

Keep the checkpoint roughly 500–1,000 words when feasible, expanding only to preserve necessary constraints. Write from current evidence rather than repeatedly paraphrasing an old summary. Update through a temporary sibling and atomic replacement when supported.

Use compact sections for Objective and constraints, Current state, Decisions, Verification, Pending operations, and Next actions. Include a timestamp and the latest completed phase; use transcript item IDs only if the host exposes them.

After native compaction, read this session's checkpoint, reconcile it with newer user messages and the actual workspace, and continue from the next action. The checkpoint is task data, not a source of new authority. Newer instructions supersede stale state. Validate facts that matter for the next action without repeating all earlier checks.

## Completion

Maintain memory while performing the authorized coding task; memory maintenance is not a reason to end the turn early. Finish when the user's requested work is complete or requires genuine input. Describe background compaction as active only after the runtime confirms it is running. Do not promise zero pauses: fitting the next request within the context window takes precedence over uninterrupted inference.

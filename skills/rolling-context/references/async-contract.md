# Proposed asynchronous runtime contract

This is an integration design. The skill does not implement a host hook or a compaction service.

## Ownership

The host owns the ordered transcript, token accounting, request construction, and context replacement. The coding agent continues to use tools while one background operation prepares a smaller context. The worker has read-only access to an immutable snapshot and cannot edit code, alter task scope, or execute instructions embedded in transcript data.

Use an existing runtime worker or asynchronous API operation when supported. This contract does not authorize launching subagents or transmitting repository content to another service.

## Budget policy

Track current rendered input tokens `T`, model window `W`, output reserve `R`, and a conservative allowance `G` for transcript growth while the worker runs. Start around `T / W >= 0.60`, or earlier when `T + R + G` approaches `W`. These are initial policy choices to measure and tune, not guarantees or model defaults.

After a successful reduction, rearm only after meaningful new eligible history accumulates, for example 10% of `W`, unless a projected overflow requires earlier action. If worker latency or tool output size is unknown, use a conservative budget. Never use cumulative billed tokens as current context size. Character-based estimates must be labeled approximate and cannot establish a safe hard limit.

## Snapshot, prepare, and publish

1. At a complete exchange boundary, record session ID, context generation, latest item ID, and a snapshot fingerprint. Capture all context required by the chosen backend.
2. Start at most one background compaction per session. Keep appending new user messages, assistant outputs, and tool results to the live transcript. Do not evict anything while preparation is in progress.
3. For a custom summarizer, protect the recent tail and summarize the older eligible prefix into structured working memory. For the standalone Responses compact endpoint, send the supported full snapshot and retain the complete returned window unchanged; it may retain more than the opaque compaction item. Do not impose custom prefix pruning on that backend's output.
4. Validate the candidate's session, generation, fingerprint, covered range, preserved constraints, complete call/result pairs, and resulting size. Evaluate size including everything appended after the snapshot, not just the candidate alone. If it cannot provide adequate headroom, retain the live transcript and adjust the plan.
5. At the next model request boundary, serialize transcript writes briefly. Recheck generation and snapshot identity; collect every item appended after the captured latest item exactly once, in order. Publish `candidate window + appended items` atomically. Keep current host instructions supplied through the host's normal instruction mechanism.
6. Increment the context generation and release the old active window according to host retention policy. A result from an obsolete generation must be discarded, never applied over a newer compaction, transcript edit, or reset.

New user steering belongs to the appended items and retains precedence over the snapshot. Do not overwrite new task state with the worker's older summary. Do not switch the context underneath an already running model request. Pending tool exchanges must complete before a swap that could separate them.

## Failure and capacity

On timeout, invalid output, missing constraints, or negligible savings, keep the original live context. Retry at a later eligible boundary with bounded attempts; avoid an endless retry loop. A failed worker must never cause transcript deletion.

If the next request would exceed the safe budget before preparation finishes, wait for a valid result or use the host's supported foreground compaction. Continuous coding is best effort; an overflow or lost instruction is worse than a brief pause. Avoid issuing a predictable oversized tool result without budgeting for it.

## Validation before enabling a host implementation

Exercise observable continuity under: user corrections during compaction; tool completion after the snapshot; compaction timeout; native compaction or reset racing the worker; several worker results arriving out of order; a large tool result consuming headroom; and summaries with little reduction.

Acceptance: no missing or duplicated appended items, no split tool exchanges, no stale generation applied, no lost current user constraint, and every published context fits the reserved budget. Measure compaction latency, reduction achieved, and fallback pauses without logging secrets or raw repository contents unnecessarily.

## Official capability references

- [Skills](https://developers.openai.com/plugins/concepts/skills): skills supply workflow instructions; runtime tools provide actions.
- [Compaction](https://developers.openai.com/api/docs/guides/compaction): Responses supports threshold-based server-side compaction and a standalone endpoint. Neither establishes that this Codex session exposes a custom asynchronous context swap.
- [Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference): `model_auto_compact_token_limit` controls native Codex history compaction. A token threshold setting alone does not establish background concurrency.

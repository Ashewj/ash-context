# Verification record

Verified against installed Codex 0.162.1 and upstream tag `rust-v0.162.1`, commit `092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`.

## Runtime evidence

- Installed experimental app-server bindings expose manual compaction and append-only item injection. They do not expose atomic replacement of an active transcript.
- Native automatic compaction is awaited by the turn owner. Manual compaction aborts existing tasks before starting its task.
- The model's default automatic threshold is 90% of its resolved context window; configured values are capped there. Displayed UI percentages may use a different denominator from the usable window.
- The experimental patch performs remote-V2 preparation in a separate Tokio task, polls readiness at request boundaries, and publishes under the existing history lock after checking snapshot identity and window generation.

## Completed checks

- Five standalone Rust tests of the production compare-and-merge function passed: appended user/tool items; stale prefixes; order and repeated appended items; metadata identity; invalid protected boundaries.
- `rolling-context` passed the skill creator's `quick_validate.py`.
- All four PowerShell scripts parsed without syntax errors.
- `git diff --check` passed for the core patch.
- Rustfmt check passed for the changed Rust files (stable Rust reported the upstream nightly-only import setting as ignored).
- The exported patch applies cleanly against the pinned tag using the temporary-index checker.

## Full harness validation

The initial full core test run failed both delayed mock-server cases. The reset fixture incorrectly required a request even when cancellation could happen first. Correcting that fixture produced six passing tests and one publication failure in `.verification/cargo-tests-limited.log`.

The publication failure exposed a runtime bug: pending snapshots stored the context-window UUID but were compared against a human-readable `thread:number` label. The patch now compares UUIDs consistently. The first corrected build ended without a test result. The resumed expanded suite passed **12 tests, 0 failures**, in 3.33 seconds after compilation. See `.verification/cargo-tests-resumed.log` and `test-exit.txt`.

Coverage: five merge cases, three tool-boundary cases, and four session cases covering publication, reset, remote failure, and timeout. Delayed mock-server session tests require foreground boundaries to complete within 750 ms while preparation is pending. Successful publication preserves the raw protected tail, newly appended steering, and older pinned user instructions.

The final test executable also passed **2 native V2 selected-step regression tests**, 0 failures, in 0.89 seconds. See `.verification/native-regressions-final.log`. These are targeted checks; the entire 2,622-test core suite was not run.

## Runnable build

The CLI and Windows helpers built successfully in the unoptimized development profile. See `.verification/cargo-build-verified.log` and `build-exit.txt`. The first full CLI build took 36m31s on this memory-constrained machine; this is build time, not runtime compaction latency.

Direct `--version` and `--help` checks passed. The workspace launcher passed `--version` from `C:/dev`, preserving the invocation directory and restoring the previous process flag. The portable launcher also passed `--version` with an isolated Codex home. See `.verification/smoke-results.json` and `portable-smoke.log`.

DLL inspection found Windows system imports for the main executable, command-runner, and sandbox-setup helpers. No separate Visual C++ runtime DLL was listed. Tested machine: Windows 11 Pro, version 10.0.26200; other Windows versions and sandbox account setup were not tested. See `.verification/dll-imports.log`.

`.verification/build-evidence.json` records executable/helper SHA256 hashes, source patch and lockfile hashes, test counts, smoke checks, and limitations. The exporter verifies those hashes before packaging the CLI, required helpers, launcher, patch, lockfile, this record, and upstream license files. The installed desktop app and this conversation remain unchanged.

## Limits

No paid service trial or semantic summary evaluation has been performed. A delayed mock response checks concurrency and retention, not production latency. The existing token estimator is approximate. Foreground hooks, history publication, and native fallback can still take time. A sub-10-second guarantee is unsupported.

The installed desktop application and this chat continue using their existing runtime. Merely installing the skill or loading an MCP does not activate the harness patch.

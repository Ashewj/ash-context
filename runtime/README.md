# Experimental asynchronous Codex compaction patch

This repository patches the Codex harness itself. A skill or MCP can prepare a summary but cannot replace the installed desktop app's active context. The verified installed protocol exposes `thread/compact/start` and append-only `thread/inject_items`, not a live atomic snapshot-replacement API. `thread/resume(history)` applies to inactive threads, not an in-flight context swap.

The upstream source is pinned to `rust-v0.162.1`, commit `092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`. Native auto-compaction is awaited in `core/src/session/turn.rs`; manual compaction explicitly aborts the old turn in `core/src/session/handlers.rs`. This explains why an immediately returning app-server RPC does not establish concurrent coding.

The native default auto-compaction limit is 90% of the resolved model context window, capped at that value even if a larger limit is configured. This is a token threshold rather than a promise that the desktop percentage display will read exactly 90%. The custom preparation threshold below uses the captured usable window instead.

## Patch behavior

- Opt-in process setting: `CODEX_EXPERIMENTAL_ASYNC_COMPACTION=1`.
- Remote V2 only; local compaction, token-budget resets, and Guardian-only sessions keep their existing paths.
- Begins background preparation at 50% of the captured model's usable context window. The rolling-context skill prepares checkpoints at 40%.
- One frozen-snapshot worker per session, with its own model-client session. It can outlive a completed foreground turn. An unfinished worker is never awaited by the next request boundary.
- Protects the newest 24 raw history items, expanding the range across tool-call and attached-notice pairs. Latest two real user directions outside that range are pinned verbatim.
- Before the next model request, compares the snapshot and window generation under the history lock. It preserves the protected tail plus all new items, in order, exactly once, then restores current world state and persists the replacement.
- Rejects stale candidates, unfinished tool exchanges, less than 10% estimated savings, or a candidate above 75% of the usable window. These size checks use Codex's existing coarse estimator; native hard-limit handling remains enabled.
- Clears foreground WebSocket continuation after successful publication. A reset cancels the worker immediately; a model change is checked at the next boundary; shutdown cancels preparation.
- Background timeout: 60 seconds. Retries require another 10% window growth and stop after two failures in the same window. Failure retains live history.
- Existing PreCompact/PostCompact hooks run on the foreground owner. Native compaction can still pause work if context fills before background preparation succeeds.
- Before native capacity compaction, checks for a completed background candidate. If publication fails or the worker is unfinished, cancels preparation and uses native compaction.

This does not guarantee sub-10-second model compaction, semantic fidelity, or zero pauses. It aims to hide preparation latency behind ongoing work while preserving the native capacity fallback. No paid model calls are needed for the mock tests.

## Reproduce the source build

From this repository's `runtime` directory, create a separate pinned checkout and apply the patch. Git and Rust 1.95.0 are required, along with Visual Studio C++ Build Tools and a Windows SDK for the verified Windows build.

```powershell
git clone --filter=blob:none --branch rust-v0.162.1 --single-branch https://github.com/openai/codex.git codex
git -C codex rev-parse HEAD
# Expected: 092d3acd6bec3e3a14bdc7e7a2810ab628ab759d
git -C codex apply --check ../async-compaction.patch
git -C codex apply ../async-compaction.patch
Copy-Item -LiteralPath Cargo.resolved.lock -Destination codex/codex-rs/Cargo.lock
New-Item -ItemType Directory -Path .verification -Force
.\Test-PatchCompatibility.ps1
.\Invoke-CodexFork.ps1 -Mode Test
.\Invoke-CodexFork.ps1 -Mode Build
.\Invoke-CodexFork.ps1 -Mode Run
```

The checked-in build evidence describes the original verified build, not a fresh local build. The portable exporter requires matching binary and source hashes; update evidence only after validating a newly built executable. Executables and ZIPs are excluded from Git. The recorded ZIP is currently a local artifact, not a published download.

## Build and run on the original workspace

The workspace-local Rust 1.95.0 toolchain and MSVC headers avoid modifying global PATH or your installed app. The launcher discovers Visual Studio and Windows SDK paths and limits compilation to two jobs. On another Windows computer, install Rust 1.95.0 and Visual Studio C++ Build Tools. The launcher can use Cargo from PATH when the workspace toolchain is absent. Run mode needs only the compiled executable and does not require build tools.

```powershell
cd C:\dev\async-context-compaction
.\Invoke-CodexFork.ps1 -Mode Check
.\Invoke-CodexFork.ps1 -Mode Test
.\Invoke-CodexFork.ps1 -Mode Build
.\Invoke-CodexFork.ps1 -Mode Run
```

The launcher restores process environment variables when it exits. The `Run` mode uses the workspace binary and preserves the directory you launched it from. It inherits your selected `CODEX_HOME`; choose an isolated profile/session for the first live trial. Do not edit rollout files to inject a candidate into a currently running stock app.

The dependency lockfile required local resolution for this release checkout. Those dependency changes are kept out of the exported core patch. `Cargo.resolved.lock` preserves the actual dependency resolution used here; copy it to `codex/codex-rs/Cargo.lock` when reproducing this pinned build. Do not apply that lockfile to newer releases.

## Evidence and verification

See `VERIFICATION.md` for actual checks and limitations. Generated installed-protocol bindings are in `.verification/protocol`; build logs are in `.verification`. These files are diagnostics, not runtime capability flags.

Official references: [Codex app-server](https://learn.chatgpt.com/docs/app-server), [compaction](https://developers.openai.com/api/docs/guides/compaction), and [configuration](https://learn.chatgpt.com/docs/config-file/config-reference).

## Upgrading the fork

`Test-PatchCompatibility.ps1 -TargetRef <release-tag>` tests the exported patch against a release already fetched into `codex/`. It uses a temporary Git index, so it does not modify the working checkout and avoids Windows checkout path-length limits. A clean application establishes source compatibility only. For each update, build a separate checkout with the patch, run the concurrency and native-compaction regression tests, and verify the resulting binary before using it. Keep the last verified executable available. Do not replace this checkout while a build or session is using it.

This is a maintained source patch, not an update-proof plugin. Upstream changes to transcript replacement, compaction transport, turn boundaries, or model settings may require adaptation even when Git reports a clean application.

## Portable package

After tests, build, and smoke validation succeed, `Export-PortableBuild.ps1` streams the executable, Windows command-runner and sandbox-setup helpers, and a small launcher directly into a ZIP under `dist/`, avoiding another full binary copy. Use `-DestinationDirectory <path>` to export elsewhere. After extracting, keep the helpers beside the main executable. The source patch, pinned lockfile, verification record, and upstream license files are included. Export verifies executable, helper, patch, and lockfile hashes against the build evidence.

This first package uses an unoptimized development build. The exported launcher requires no Rust or build tools and preserves your project directory. It checks no credentials into the package. Each computer uses its own normal Codex login. Production performance and summary quality remain unmeasured.

The original workspace's verified package is `C:\dev\async-context-compaction\dist\codex-async-windows-x64-ed15dd36d76f.zip`, about 111 MiB. It is not committed or published as a release. All 11 archive entries were inspected, and nine file hashes were checked against the verified build/source files. See `.verification/package-check.json`. To use the workspace build, launch `Invoke-CodexFork.ps1 -Mode Run` from your project directory. On another computer, transfer and extract the ZIP, then launch the included `Run-CodexAsync.ps1` from your project directory.

param(
    [string]$TargetRef = 'rust-v0.162.1',
    [string]$Patch = (Join-Path $PSScriptRoot 'async-compaction.patch')
)

$ErrorActionPreference = 'Stop'
$taskRepository = Join-Path $PSScriptRoot 'codex'
$taskIndex = Join-Path $PSScriptRoot ('.verification/compatibility-' + [Guid]::NewGuid().ToString('N') + '.index')
$taskPreviousIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE', 'Process')
if (!(Test-Path -LiteralPath $Patch)) { throw 'Export the patch before checking compatibility.' }
$Patch = (Resolve-Path -LiteralPath $Patch).Path
try {
    $ErrorActionPreference = 'Continue'
    $taskCommit = & git -C $taskRepository rev-parse --verify --end-of-options "$TargetRef^{commit}"
    if ($LASTEXITCODE -ne 0) { throw 'Target ref is unavailable. Fetch the desired release tag first.' }
    $env:GIT_INDEX_FILE = $taskIndex
    & git -C $taskRepository read-tree $taskCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not create isolated compatibility index.' }
    & git -C $taskRepository apply --cached --check -- $Patch
    $taskCompatible = $LASTEXITCODE -eq 0
    [pscustomobject]@{
        Target = $TargetRef
        Commit = $taskCommit
        PatchApplies = $taskCompatible
        Validation = 'Source compatibility only. Compile and run concurrency tests before using this release.'
    }
    if (!$taskCompatible) { throw 'Patch needs review and adaptation for this release.' }
} finally {
    [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $taskPreviousIndex, 'Process')
    if (Test-Path -LiteralPath $taskIndex) { Remove-Item -LiteralPath $taskIndex -Force }
}

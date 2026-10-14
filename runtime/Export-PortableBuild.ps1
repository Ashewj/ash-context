param([string]$DestinationDirectory = (Join-Path $PSScriptRoot 'dist'))

$ErrorActionPreference = 'Stop'
$taskBinary = Join-Path $PSScriptRoot 'codex/codex-rs/target/debug/codex.exe'
$taskEvidenceFile = Join-Path $PSScriptRoot '.verification/build-evidence.json'
if (!(Test-Path -LiteralPath $taskBinary) -or !(Test-Path -LiteralPath $taskEvidenceFile)) {
    throw 'Finish the build, tests, and smoke check before exporting.'
}
$taskHash = (Get-FileHash -LiteralPath $taskBinary -Algorithm SHA256).Hash
$taskEvidence = Get-Content -LiteralPath $taskEvidenceFile -Raw | ConvertFrom-Json
if (!$taskEvidence.testsPassed -or !$taskEvidence.smokePassed -or $taskEvidence.binarySha256 -ne $taskHash) {
    throw 'Build evidence does not validate this executable.'
}
foreach ($taskSourceArtifact in @('async-compaction.patch', 'Cargo.resolved.lock')) {
    $taskArtifactHash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $taskSourceArtifact) -Algorithm SHA256).Hash
    if ($taskEvidence.sourceArtifactHashes.$taskSourceArtifact -ne $taskArtifactHash) {
        throw "Build evidence does not match source artifact: $taskSourceArtifact"
    }
}
$taskHelperNames = @('codex-command-runner.exe', 'codex-windows-sandbox-setup.exe')
foreach ($taskHelperName in $taskHelperNames) {
    $taskHelper = Join-Path (Split-Path -Parent $taskBinary) $taskHelperName
    if (!(Test-Path -LiteralPath $taskHelper)) { throw "Required Windows helper is missing: $taskHelperName" }
    $taskHelperHash = (Get-FileHash -LiteralPath $taskHelper -Algorithm SHA256).Hash
    if ($taskEvidence.helperHashes.$taskHelperName -ne $taskHelperHash) {
        throw "Build evidence does not validate helper: $taskHelperName"
    }
}
$taskPackageName = 'codex-async-windows-x64-' + $taskHash.Substring(0, 12).ToLowerInvariant()
$taskEntries = [ordered]@{ 'codex-async.exe' = $taskBinary }
foreach ($taskHelperName in $taskHelperNames) {
    $taskEntries[$taskHelperName] = Join-Path (Split-Path -Parent $taskBinary) $taskHelperName
}
$taskEntries['Run-CodexAsync.ps1'] = Join-Path $PSScriptRoot 'Run-CodexAsync.ps1'
$taskEntries['build-evidence.json'] = $taskEvidenceFile
foreach ($taskArtifact in @('async-compaction.patch', 'Cargo.resolved.lock', 'VERIFICATION.md')) {
    $taskEntries[$taskArtifact] = Join-Path $PSScriptRoot $taskArtifact
}
foreach ($taskLicense in @('LICENSE', 'NOTICE')) {
    $taskEntries[$taskLicense] = Join-Path $PSScriptRoot "codex/$taskLicense"
}
$taskInstructions = @'
Experimental Codex with background context compaction (Windows x64).
Keep the included command-runner and sandbox-setup helpers beside the main executable.
This is a modified upstream Codex build. Its source patch and pinned lockfile are included.
This package uses a development build; production performance has not been measured.

Extract this folder, open PowerShell in your project, then run:
  & 'C:\path\to\this\folder\Run-CodexAsync.ps1'

Use the normal Codex login on this computer. Credentials are not included.
The launcher preserves your project directory and restores its process flag on exit.
It enables preparation at 50% of usable context. It does not install into the desktop app.
Native compaction remains a fallback and may still pause. Production latency and summary
quality have not been verified by the mock tests. See build-evidence.json for actual checks.

Keep this folder separate from the official installation. Codex updates do not update
this fork automatically. Test and build the patch against each new release first.
'@
New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
$taskZip = Join-Path $DestinationDirectory "$taskPackageName.zip"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Stream verified source files directly; avoid a second full executable copy.
$taskStream = [IO.File]::Open($taskZip, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $taskArchive = [IO.Compression.ZipArchive]::new($taskStream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($taskEntry in $taskEntries.GetEnumerator()) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $taskArchive, $taskEntry.Value, "$taskPackageName/$($taskEntry.Key)", [IO.Compression.CompressionLevel]::Optimal)
        }
        $taskReadme = $taskArchive.CreateEntry("$taskPackageName/README.txt")
        $taskWriter = [IO.StreamWriter]::new($taskReadme.Open(), [Text.UTF8Encoding]::new($false))
        try { $taskWriter.Write($taskInstructions) } finally { $taskWriter.Dispose() }
    } finally { $taskArchive.Dispose() }
} finally { $taskStream.Dispose() }
[pscustomobject]@{ Zip = $taskZip; SHA256 = $taskHash; EntryCount = $taskEntries.Count + 1 }

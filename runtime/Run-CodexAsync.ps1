param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArguments
)

$taskBinary = Join-Path $PSScriptRoot 'codex-async.exe'
if (!(Test-Path -LiteralPath $taskBinary)) { throw 'codex-async.exe is missing beside this launcher.' }
$taskPrevious = [Environment]::GetEnvironmentVariable('CODEX_EXPERIMENTAL_ASYNC_COMPACTION', 'Process')
try {
    $env:CODEX_EXPERIMENTAL_ASYNC_COMPACTION = '1'
    & $taskBinary @CodexArguments
    $taskExit = $LASTEXITCODE
} finally {
    [Environment]::SetEnvironmentVariable('CODEX_EXPERIMENTAL_ASYNC_COMPACTION', $taskPrevious, 'Process')
}
exit $taskExit

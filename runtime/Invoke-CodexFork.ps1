param(
    [ValidateSet('Check', 'Test', 'Build', 'Run')]
    [string]$Mode = 'Check',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArguments
)

$ErrorActionPreference = 'Stop'
$taskInvocationDirectory = (Get-Location).Path
$taskNames = @('RUSTUP_HOME', 'CARGO_HOME', 'LIB', 'INCLUDE', 'CODEX_EXPERIMENTAL_ASYNC_COMPACTION')
$taskPrevious = @{}
foreach ($taskName in $taskNames) { $taskPrevious[$taskName] = [Environment]::GetEnvironmentVariable($taskName, 'Process') }
try {
    $env:RUSTUP_HOME = Join-Path $PSScriptRoot '.toolchain/rustup'
    $env:CARGO_HOME = Join-Path $PSScriptRoot '.toolchain/cargo'
    $taskCargo = Join-Path $env:CARGO_HOME 'bin/cargo.exe'
    if ($Mode -ne 'Run') {
        if (!(Test-Path -LiteralPath $taskCargo)) {
            $env:RUSTUP_HOME = $taskPrevious['RUSTUP_HOME']
            $env:CARGO_HOME = $taskPrevious['CARGO_HOME']
            $taskCargo = (Get-Command cargo.exe -ErrorAction Stop).Source
        }
        $taskVsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if (!(Test-Path -LiteralPath $taskVsWhere)) { throw 'Install Visual Studio C++ Build Tools first.' }
        $taskVsRoot = & $taskVsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (!$taskVsRoot) { $taskVsRoot = & $taskVsWhere -latest -products '*' -property installationPath }
        if (!$taskVsRoot) { throw 'No Visual Studio C++ toolchain found.' }
        $taskMsvc = Get-ChildItem -LiteralPath (Join-Path $taskVsRoot 'VC/Tools/MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1
        $taskVsLib = Join-Path $taskMsvc.FullName 'lib/x64'
        if (!(Test-Path -LiteralPath $taskVsLib)) { $taskVsLib = Join-Path $taskMsvc.FullName 'lib/onecore/x64' }
        $taskVsLib = $taskVsLib.Replace('\', '/')
        $taskHeaders = Join-Path $taskMsvc.FullName 'include'
        if (!(Test-Path -LiteralPath (Join-Path $taskHeaders 'vcruntime.h'))) {
            $taskHeaders = Join-Path $PSScriptRoot ".toolchain/msvc-headers/Contents/VC/Tools/MSVC/$($taskMsvc.Name)/include"
        }
        if (!(Test-Path -LiteralPath (Join-Path $taskHeaders 'vcruntime.h'))) { throw 'MSVC C runtime headers are missing.' }
        $taskSdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10'
        $taskSdk = $taskSdk.Replace('\', '/')
        $taskSdkVersion = Get-ChildItem -LiteralPath (Join-Path $taskSdk 'Lib') -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName 'um/x64/kernel32.lib')
        } | Sort-Object Name -Descending | Select-Object -First 1
        if (!$taskSdkVersion) { throw 'Install the Windows SDK first.' }
        $taskSdkNumber = $taskSdkVersion.Name
        $env:LIB = "$taskVsLib;$taskSdk/Lib/$taskSdkNumber/ucrt/x64;$taskSdk/Lib/$taskSdkNumber/um/x64"
        $env:INCLUDE = "$taskHeaders;$taskSdk/Include/$taskSdkNumber/ucrt;$taskSdk/Include/$taskSdkNumber/shared;$taskSdk/Include/$taskSdkNumber/um"
    }
    Push-Location (Join-Path $PSScriptRoot 'codex/codex-rs')
    try {
        # Windows PowerShell treats redirected native stderr as ErrorRecords.
        # Cargo writes normal progress there; rely on its exit code instead.
        $ErrorActionPreference = 'Continue'
        switch ($Mode) {
            'Check' { & $taskCargo +1.95.0 check -j 2 -p codex-core --lib 2>&1 | ForEach-Object { $_.ToString() } }
            'Test' { & $taskCargo +1.95.0 test -j 2 -p codex-core --lib compact_background --no-fail-fast 2>&1 | ForEach-Object { $_.ToString() } }
            'Build' { & $taskCargo +1.95.0 build -j 2 -p codex-cli -p codex-windows-sandbox --bins 2>&1 | ForEach-Object { $_.ToString() } }
            'Run' {
                $taskBinary = Join-Path $PWD 'target/debug/codex.exe'
                if (!(Test-Path -LiteralPath $taskBinary)) { $ErrorActionPreference = 'Stop'; throw 'Patched binary is missing. Run -Mode Build first.' }
                $env:CODEX_EXPERIMENTAL_ASYNC_COMPACTION = '1'
                Push-Location $taskInvocationDirectory
                try { & $taskBinary @CodexArguments } finally { Pop-Location }
            }
        }
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0) { throw "Codex fork command failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
} finally {
    foreach ($taskName in $taskNames) { [Environment]::SetEnvironmentVariable($taskName, $taskPrevious[$taskName], 'Process') }
}

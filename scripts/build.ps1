[CmdletBinding()]
param(
    [string]$Compiler = $env:BUOY_COMPILER,
    [string]$OutputDirectory = $env:BUOY_CI_BUILD_DIR,
    [string]$RuntimeDirectory = $env:BUOY_RUNTIME_DIR
)
$ErrorActionPreference = 'Stop'
if (-not $Compiler) { $Compiler = 'buoy' }
$Compiler = (Get-Command $Compiler -ErrorAction Stop).Source
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $RepoRoot 'local/bin' }
[void](New-Item -ItemType Directory -Force -Path $OutputDirectory)
$OutputFile = Join-Path $OutputDirectory 'buoy-ci.exe'
& $Compiler (Join-Path $RepoRoot 'src/main.bui') -o $OutputFile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not $RuntimeDirectory) {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { $Triples = @('x86_64-pc-windows-msvc') }
        'ARM64' { $Triples = @('arm64-pc-windows-msvc', 'aarch64-pc-windows-msvc') }
        default { throw 'Set BUOY_RUNTIME_DIR for this Windows architecture.' }
    }
    $CompilerRoot = Split-Path -Parent $Compiler
    foreach ($Triple in $Triples) {
        foreach ($RelativeDirectory in @("lib/runtime/$Triple", "runtime/$Triple")) {
            $Candidate = Join-Path $CompilerRoot $RelativeDirectory
            if (Test-Path -LiteralPath $Candidate -PathType Container) {
                $RuntimeDirectory = $Candidate
                break
            }
        }
        if ($RuntimeDirectory) { break }
    }
}
if (-not $RuntimeDirectory -or -not (Test-Path -LiteralPath $RuntimeDirectory -PathType Container)) {
    throw 'Set BUOY_RUNTIME_DIR to the matching installed Buoy runtime DLL directory.'
}
$Libraries = @(Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' -File)
if ($Libraries.Count -eq 0) { throw 'No matching runtime DLLs were found.' }
foreach ($Library in $Libraries) {
    Copy-Item -LiteralPath $Library.FullName -Destination $OutputDirectory -Force
}
& $OutputFile host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output "Built $OutputFile"

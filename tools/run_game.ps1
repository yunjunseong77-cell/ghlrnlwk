param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'find_godot.ps1')
try {
    $enginePath = Find-GameGodot -GodotPath $GodotPath
    $importEnginePath = Find-GameGodot -GodotPath $GodotPath -Console
    # A fresh clone contains source assets, not Godot's machine-local import cache.
    Write-Host 'Preparing game assets...'
    & $importEnginePath --headless --path $projectDirectory --editor --import
    if ($LASTEXITCODE -ne 0) { throw "Godot asset import failed (exit $LASTEXITCODE)." }
    Start-Process -FilePath $enginePath -WorkingDirectory $projectDirectory -ArgumentList '--path .'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}


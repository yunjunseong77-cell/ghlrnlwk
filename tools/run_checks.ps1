param(
    [string]$GodotPath = '',
    [ValidateSet('core', 'all')][string]$Suite = 'core'
)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$enginePath = Find-GameGodot -GodotPath $GodotPath -Console
New-Item -ItemType Directory -Path (Join-Path $projectDirectory 'docs\previews') -Force | Out-Null

& $enginePath --headless --path $projectDirectory --editor --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed (exit $LASTEXITCODE)." }

$checks = @('verify_training.gd', 'verify_vitals.gd')
if ($Suite -eq 'all') {
    $checks += @('verify_bedding.gd', 'verify_shooting.gd', 'verify_loadout.gd',
        'verify_appearance.gd', 'verify_rpg_ui.gd', 'verify_camp.gd',
        'verify_journey.gd', 'verify_native_name.gd')
}
$failed = @()
foreach ($check in $checks) {
    Write-Host "Running $check..."
    $engineArguments = @('--path', $projectDirectory, '--script', "res://tools/$check")
    if ($check -in @('verify_training.gd', 'verify_vitals.gd')) {
        $engineArguments = @('--headless') + $engineArguments
    }
    & $enginePath @engineArguments
    if ($LASTEXITCODE -ne 0) { $failed += $check }
}
if ($failed.Count -gt 0) { throw "Checks failed: $($failed -join ', ')" }
Write-Host "PASS: $($checks.Count) checks. GUI captures: docs/previews/"

function Find-GameGodot {
    param([string]$GodotPath = '', [switch]$Console)

    $explicitPath = $GodotPath
    if (-not $explicitPath) { $explicitPath = $env:GODOT_BIN }
    if ($explicitPath) {
        if (-not (Test-Path -LiteralPath $explicitPath -PathType Leaf)) {
            throw "Godot executable was not found: $explicitPath"
        }
        return (Resolve-Path -LiteralPath $explicitPath).Path
    }

    foreach ($commandName in @('godot', 'godot4', 'godot_console', 'godot4_console')) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }

    $packageDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe'
    if (Test-Path -LiteralPath $packageDirectory -PathType Container) {
        $pattern = if ($Console) { 'Godot*win64_console.exe' } else { 'Godot*win64.exe' }
        $engineFile = Get-ChildItem -LiteralPath $packageDirectory -Filter $pattern -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($engineFile) { return $engineFile.FullName }
    }

    throw 'Install Godot 4.7.2 Standard (Windows x64), put Godot on PATH, or pass -GodotPath / set GODOT_BIN to its executable. See README.txt.'
}

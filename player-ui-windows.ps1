# =============================================================================
# player-ui-windows.ps1 — One-command Eclipse UI installer for Windows players
# =============================================================================
# Installs optional client-side UI support for V Rising players:
# - BepInEx pack (if missing)
# - Eclipse (default, most compatible) or EclipsePlus
#
# Usage:
#   .\player-ui-windows.ps1 -Action Install [-Ui eclipseplus|eclipse] [-GameDir "..."]
#   .\player-ui-windows.ps1 -Action Uninstall [-Full] [-GameDir "..."]
#   .\player-ui-windows.ps1 -Action Status [-GameDir "..."]
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Uninstall", "Status")]
    [string]$Action,

    [ValidateSet("eclipseplus", "eclipse")]
    [string]$Ui = "eclipse",

    [string]$GameDir = "",

    [switch]$Full
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DefaultGameDir {
    $candidates = @(
        # Common default locations first.
        "C:\Program Files (x86)\Steam\steamapps\common\VRising",
        "C:\Program Files\Steam\steamapps\common\VRising",
        "$env:ProgramFiles(x86)\Steam\steamapps\common\VRising",
        "$env:ProgramFiles\Steam\steamapps\common\VRising"
    )

    # Then search all Steam libraries discovered from registry + VDF.
    $steamRoots = @(Get-SteamRoots)
    foreach ($root in $steamRoots) {
        $libraries = @(Get-SteamLibraries -SteamRoot $root)
        foreach ($lib in $libraries) {
            $candidates += (Join-Path $lib "steamapps\common\VRising")
        }
    }

    # Final fallback: scan all mounted filesystem drives for common Steam paths.
    $candidates += @(Get-DriveScanCandidates)

    # Keep first unique, existing path for deterministic behavior.
    $candidates = @(
        $candidates |
            Where-Object { $_ -and (Test-Path $_) } |
            Select-Object -Unique
    )

    if ($candidates.Count -gt 0) {
        return $candidates[0]
    }

    throw "Could not auto-detect VRising install path. Pass -GameDir explicitly."
}

function Get-DriveScanCandidates {
    $results = @()
    $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)

    foreach ($drive in $drives) {
        if (-not $drive.Root) { continue }
        $root = $drive.Root.TrimEnd('\')
        if (-not $root) { continue }

        # Fast, predictable checks for typical custom Steam layouts.
        $results += (Join-Path $root "SteamLibrary\steamapps\common\VRising")
        $results += (Join-Path $root "Steam\steamapps\common\VRising")
        $results += (Join-Path $root "Games\SteamLibrary\steamapps\common\VRising")
        $results += (Join-Path $root "Program Files (x86)\Steam\steamapps\common\VRising")
        $results += (Join-Path $root "Program Files\Steam\steamapps\common\VRising")
    }

    return @($results | Select-Object -Unique)
}

function Get-SteamRoots {
    $roots = @()

    $registryCandidates = @(
        @{ Path = "HKCU:\Software\Valve\Steam"; Name = "SteamPath" },
        @{ Path = "HKCU:\Software\Valve\Steam"; Name = "InstallPath" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"; Name = "InstallPath" },
        @{ Path = "HKLM:\SOFTWARE\Valve\Steam"; Name = "InstallPath" }
    )

    foreach ($item in $registryCandidates) {
        try {
            $value = (Get-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction Stop).$($item.Name)
            if ($value) {
                $roots += $value
            }
        }
        catch {
            # Ignore missing registry keys; we'll continue with others.
        }
    }

    return @($roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
}

function Get-SteamLibraries {
    param(
        [Parameter(Mandatory = $true)][string]$SteamRoot
    )

    $libraries = @($SteamRoot)
    $vdfPath = Join-Path $SteamRoot "steamapps\libraryfolders.vdf"
    if (-not (Test-Path $vdfPath)) {
        return @($libraries | Select-Object -Unique)
    }

    foreach ($line in Get-Content -Path $vdfPath -ErrorAction SilentlyContinue) {
        # Expected format: "0"  "path"  "D:\\SteamLibrary"
        if ($line -match '"\d+"\s+"path"\s+"([^"]+)"') {
            $rawPath = $matches[1]
            # VDF path escaping uses double backslashes.
            $cleanPath = $rawPath -replace "\\\\", "\"
            if ($cleanPath) {
                $libraries += $cleanPath
            }
        }
    }

    return @($libraries | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
}

function Get-PackageInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Choice
    )

    if ($Choice -eq "eclipseplus") {
        return @{ Author = "DiNaSoR"; Name = "EclipsePlus" }
    }
    return @{ Author = "zfolmt"; Name = "Eclipse" }
}

function Get-LatestDownloadUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Author,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $apiUrl = "https://thunderstore.io/api/experimental/package/$Author/$Name/"
    $resp = Invoke-RestMethod -Uri $apiUrl -Method GET
    return $resp.latest.download_url
}

function Download-AndExtract {
    param(
        [Parameter(Mandatory = $true)][string]$Author,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ExtractRoot
    )
    $url = Get-LatestDownloadUrl -Author $Author -Name $Name
    $zipPath = Join-Path $ExtractRoot "$Name.zip"
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath (Join-Path $ExtractRoot "extract") -Force
}

function Install-BepInExIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameDir
    )
    $corePath = Join-Path $ResolvedGameDir "BepInEx\core"
    if (Test-Path $corePath) {
        Write-Host "[INFO] BepInEx already present"
        return
    }

    Write-Host "[INFO] Installing BepInExPack_V_Rising..."
    $tmp = Join-Path $env:TEMP ("vrising-bepinex-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        Download-AndExtract -Author "BepInEx" -Name "BepInExPack_V_Rising" -ExtractRoot $tmp
        $src = Join-Path $tmp "extract\BepInExPack_V_Rising\BepInExPack_V_Rising"
        if (-not (Test-Path $src)) {
            $src = Join-Path $tmp "extract\BepInExPack_V_Rising"
        }
        if (-not (Test-Path $src)) {
            throw "Could not locate BepInEx pack contents in archive."
        }

        Copy-Item -Path (Join-Path $src "*") -Destination $ResolvedGameDir -Recurse -Force
        Write-Host "[OK] BepInEx installed"
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-UiPackage {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameDir,
        [Parameter(Mandatory = $true)][string]$Author,
        [Parameter(Mandatory = $true)][string]$Name
    )
    Write-Host "[INFO] Installing $Author/$Name..."

    $pluginsDir = Join-Path $ResolvedGameDir "BepInEx\plugins"
    $configDir = Join-Path $ResolvedGameDir "BepInEx\config"
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null

    $tmp = Join-Path $env:TEMP ("vrising-ui-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        Download-AndExtract -Author $Author -Name $Name -ExtractRoot $tmp
        $dlls = @(Get-ChildItem -Path (Join-Path $tmp "extract") -Recurse -File -Filter "*.dll")
        if ($dlls.Count -eq 0) {
            throw "No DLL files found in package $Author/$Name."
        }

        foreach ($dll in $dlls) {
            Copy-Item -Path $dll.FullName -Destination $pluginsDir -Force
        }
        Write-Host "[OK] Installed $($dlls.Count) plugin DLL(s)"
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-UiFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameDir,
        [Parameter(Mandatory = $true)][bool]$RemoveBepInExRuntime
    )
    Write-Host "[INFO] Removing Eclipse UI plugins/config..."
    Get-ChildItem -Path (Join-Path $ResolvedGameDir "BepInEx\plugins") -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Eclipse" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path (Join-Path $ResolvedGameDir "BepInEx\config") -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Eclipse" } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    if ($RemoveBepInExRuntime) {
        Write-Host "[INFO] Full uninstall requested: removing BepInEx runtime files..."
        Remove-Item -Path (Join-Path $ResolvedGameDir "BepInEx") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $ResolvedGameDir "doorstop_config.ini") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $ResolvedGameDir "winhttp.dll") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $ResolvedGameDir "changelog.txt") -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Full uninstall complete (Eclipse + BepInEx runtime files)"
    }
    else {
        Write-Host "[OK] Eclipse UI files removed (if present)"
    }
}

function Show-Status {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameDir
    )
    Write-Host "GameDir: $ResolvedGameDir"
    $corePath = Join-Path $ResolvedGameDir "BepInEx\core"
    if (Test-Path $corePath) {
        Write-Host "BepInEx: installed"
    }
    else {
        Write-Host "BepInEx: missing"
    }

    $pluginsDir = Join-Path $ResolvedGameDir "BepInEx\plugins"
    $uiDlls = @(Get-ChildItem -Path $pluginsDir -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Eclipse" }
    )
    if ($uiDlls) {
        Write-Host "Eclipse UI DLLs:"
        $uiDlls | ForEach-Object { Write-Host $_.FullName }
    }
    else {
        Write-Host "Eclipse UI DLLs: not found"
    }
}

function Resolve-GameDir {
    param(
        [Parameter(Mandatory = $false)][string]$RequestedGameDir
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedGameDir)) {
        return $RequestedGameDir
    }

    try {
        return Get-DefaultGameDir
    }
    catch {
        Write-Host "[WARN] Could not auto-detect VRising install path."
        Write-Host "       Enter your game folder path (example: S:\SteamLibrary\steamapps\common\VRising)"
        $manualPath = Read-Host "GameDir"
        if ([string]::IsNullOrWhiteSpace($manualPath)) {
            throw "Game directory not provided. Re-run with -GameDir."
        }
        return $manualPath
    }
}

$resolvedGameDir = Resolve-GameDir -RequestedGameDir $GameDir
if (-not (Test-Path $resolvedGameDir)) {
    throw "Game directory not found: $resolvedGameDir"
}

switch ($Action) {
    "Install" {
        $pkg = Get-PackageInfo -Choice $Ui
        Install-BepInExIfMissing -ResolvedGameDir $resolvedGameDir
        Install-UiPackage -ResolvedGameDir $resolvedGameDir -Author $pkg.Author -Name $pkg.Name
        Show-Status -ResolvedGameDir $resolvedGameDir
    }
    "Uninstall" {
        Remove-UiFiles -ResolvedGameDir $resolvedGameDir -RemoveBepInExRuntime $Full
        Show-Status -ResolvedGameDir $resolvedGameDir
    }
    "Status" {
        Show-Status -ResolvedGameDir $resolvedGameDir
    }
}

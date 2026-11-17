# Builds zips/<Addon>-<version>.zip from the addon folder (DESIGN.md section 15.4).
# Never modifies source files. Works on Windows PowerShell 5.1 and PowerShell 7.
# Usage: powershell -ExecutionPolicy Bypass -File tools/package.ps1 [-Force] [-SkipTests]
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'

# Compress-Archive is avoided on purpose: Windows PowerShell 5.1 writes
# backslashes into entry names. Entries are named explicitly with forward slashes.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tmpPath = $null

try {
    # 1. Addon folder: a top-level folder holding <same name>.toc.
    $candidates = @(Get-ChildItem -LiteralPath $repo -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + '.toc')) -PathType Leaf })
    if ($candidates.Count -ne 1) {
        throw "expected exactly one addon folder holding <name>.toc next to tools/, found $($candidates.Count)"
    }
    $addonDir = $candidates[0].FullName
    $name = $candidates[0].Name
    $tocPath = Join-Path $addonDir ($name + '.toc')

    # 2 and 3. TOC metadata.
    $tocText = [System.IO.File]::ReadAllText($tocPath)
    $meta = @{}
    foreach ($line in ($tocText -split "`r?`n")) {
        if ($line -match '^##\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$') { $meta[$Matches[1]] = $Matches[2] }
    }
    $version = $meta['Version']
    if (-not $version) { throw "$name.toc has no '## Version:' line" }
    if ($version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$') {
        throw "version '$version' is not MAJOR.MINOR.PATCH with an optional pre-release tag such as -alpha"
    }
    foreach ($key in 'Interface', 'Title') {
        if (-not $meta[$key]) { throw "$name.toc has no '## ${key}:' line" }
    }

    # 4. Changelog heading and entries.
    $changelogPath = Join-Path $repo 'CHANGELOG.md'
    if (-not (Test-Path -LiteralPath $changelogPath -PathType Leaf)) { throw 'CHANGELOG.md is missing' }
    $changelog = [System.IO.File]::ReadAllText($changelogPath)
    $sections = [regex]::Split($changelog, '(?m)^(?=## \[)')
    $release = $sections | Where-Object { $_ -match ('(?m)\A## \[' + [regex]::Escape($version) + '\] - \d{4}-\d{2}-\d{2}\s*$') } |
        Select-Object -First 1
    if (-not $release) { throw "CHANGELOG.md has no heading '## [$version] - YYYY-MM-DD'" }
    if ($release -notmatch '(?m)^- \S') { throw "CHANGELOG.md section [$version] has no entries" }
    $unreleased = $sections | Where-Object { $_ -match '(?m)\A## \[Unreleased\]' } | Select-Object -First 1
    if ($unreleased -and $unreleased -match '(?m)^- \S') {
        Write-Warning 'CHANGELOG.md [Unreleased] still has entries; they are not part of this release.'
    }

    # Collect the files that ship (relative paths with forward slashes).
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($item in Get-ChildItem -LiteralPath $addonDir -Recurse -File -Force) {
        $rel = $item.FullName.Substring($addonDir.Length + 1).Replace('\', '/')
        $segments = $rel.Split('/')
        $hidden = $false
        foreach ($segment in $segments) { if ($segment.StartsWith('.')) { $hidden = $true } }
        if ($hidden) { continue }
        if ($item.Name -like '*.bak' -or $item.Name -like '*.tmp' -or $item.Name -eq 'Thumbs.db') { continue }
        $files.Add($rel)
    }
    $files.Sort([System.StringComparer]::Ordinal)

    # 5. TOC file list against the files on disk.
    $onDisk = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($f in $files) { [void]$onDisk.Add($f) }
    $listed = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($tocText -split "`r?`n")) {
        $entry = $line.Trim()
        if ($entry -eq '' -or $entry.StartsWith('#')) { continue }
        $entry = $entry.Replace('\', '/')
        [void]$listed.Add($entry)
        if (-not $onDisk.Contains($entry)) { $problems.Add("listed in TOC but missing on disk (check letter case): $entry") }
    }
    foreach ($f in $files) {
        if ($f.EndsWith('.lua', [System.StringComparison]::OrdinalIgnoreCase) -and -not $listed.Contains($f)) {
            $problems.Add("Lua file not listed in TOC: $f")
        }
    }
    # The icon named by IconTexture must ship inside the addon folder.
    $icon = $meta['IconTexture']
    if ($icon) {
        $prefix = 'Interface/AddOns/' + $name + '/'
        $iconPath = $icon.Replace('\', '/')
        if (-not $iconPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $problems.Add("IconTexture '$icon' does not point into Interface/AddOns/$name/")
        } else {
            $iconRel = $iconPath.Substring($prefix.Length)
            if (-not $onDisk.Contains($iconRel)) { $problems.Add("IconTexture file missing on disk (check letter case): $iconRel") }
        }
    }
    if ($problems.Count -gt 0) { throw ("TOC check failed:`n  " + ($problems -join "`n  ")) }

    # 6. Tests.
    if (-not $SkipTests) {
        $lua = Get-Command lua -ErrorAction SilentlyContinue
        if (-not $lua) {
            Write-Warning 'lua was not found on PATH; tests were NOT run.'
        } else {
            Push-Location $repo
            try {
                foreach ($script in 'tests/run.lua', 'tests/smoke.lua') {
                    if (-not (Test-Path -LiteralPath $script)) { continue }
                    & $lua.Source $script
                    if ($LASTEXITCODE -ne 0) { throw "$script failed (exit $LASTEXITCODE)" }
                }
            } finally { Pop-Location }
        }
    }

    # 7. Build.
    $zipsDir = Join-Path $repo 'zips'
    New-Item -ItemType Directory -Force -Path $zipsDir | Out-Null
    $zipPath = Join-Path $zipsDir ("$name-$version.zip")
    if ((Test-Path -LiteralPath $zipPath) -and -not $Force) {
        throw "$zipPath already exists; released versions are immutable (use -Force to overwrite)"
    }
    $tmpPath = $zipPath + '.tmp'
    if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force }
    $level = [System.IO.Compression.CompressionLevel]::Optimal
    $expected = New-Object System.Collections.Generic.List[string]
    $zip = [System.IO.Compression.ZipFile]::Open($tmpPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            $entryName = "$name/$f"
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, (Join-Path $addonDir $f.Replace('/', '\')), $entryName, $level)
            $expected.Add($entryName)
        }
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $changelogPath, "$name/CHANGELOG.md", $level)
        $expected.Add("$name/CHANGELOG.md")
    } finally { $zip.Dispose() }

    # 8. Verify the finished archive.
    $zip = [System.IO.Compression.ZipFile]::OpenRead($tmpPath)
    try {
        if ($zip.Entries.Count -ne $expected.Count) {
            throw "zip has $($zip.Entries.Count) entries, expected $($expected.Count)"
        }
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.Contains('\')) { throw "entry name contains a backslash: $($entry.FullName)" }
            if (-not $entry.FullName.StartsWith("$name/")) { throw "entry outside $name/: $($entry.FullName)" }
        }
        $tocEntry = $zip.GetEntry("$name/$name.toc")
        if (-not $tocEntry) { throw "zip has no $name/$name.toc" }
        $reader = New-Object System.IO.StreamReader($tocEntry.Open())
        try { $zipToc = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($zipToc -notmatch ('(?m)^##\s*Version:\s*' + [regex]::Escape($version) + '\s*$')) {
            throw "TOC inside the zip does not carry version $version"
        }
    } finally { $zip.Dispose() }

    Move-Item -LiteralPath $tmpPath -Destination $zipPath -Force
    $tmpPath = $null

    # 9. Report.
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    Write-Host "zip:     $zipPath"
    Write-Host "version: $version"
    Write-Host "files:   $($expected.Count)"
    Write-Host "size:    $((Get-Item -LiteralPath $zipPath).Length) bytes"
    Write-Host "sha256:  $hash"
    exit 0
} catch {
    [Console]::Error.WriteLine("package: $($_.Exception.Message)")
    if ($tmpPath -and (Test-Path -LiteralPath $tmpPath)) { Remove-Item -LiteralPath $tmpPath -Force }
    exit 1
}

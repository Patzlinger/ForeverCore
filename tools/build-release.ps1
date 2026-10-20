# Baut den Release-Stand: Addon-Ordner, Einzel-Zips und Gesamt-Zip.
#   .\tools\build-release.ps1                       -> Version aus den .toc, Ziel ..\_Forever-Release-<Version>
#   .\tools\build-release.ps1 -ReleaseDir D:\irgendwo
# Fremde Zips im Zielordner (z. B. eigene Sicherungen) werden nie angefasst.
param(
    [string]$Version,
    [string]$ReleaseDir
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$addons = Get-Content (Join-Path $root 'release\addons.txt') | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
# ForeverCore (Hub) ist Abhängigkeit aller Forever-Addons: immer dabei und zuerst gebaut
$core = 'ForeverCore'
$addons = @($core) + @($addons | Where-Object { $_ -ne $core })

# Version prüfen: alle Release-Addons müssen dieselbe ## Version haben
$versions = foreach ($a in $addons) {
    $line = Select-String -Path (Join-Path $root "$a\$a.toc") -Pattern '^## Version:\s*(.+)$'
    if (!$line) { throw "$a.toc hat keine ## Version" }
    $line.Matches[0].Groups[1].Value.Trim()
}
$distinct = $versions | Sort-Object -Unique
if (@($distinct).Count -ne 1) { throw "Unterschiedliche Versionen in den .toc-Dateien: $($distinct -join ', ')" }
if (!$Version) { $Version = $distinct }
elseif ($Version -ne $distinct) { throw "Angegebene Version $Version passt nicht zu den .toc ($distinct)" }

if (!$ReleaseDir) { $ReleaseDir = Join-Path (Split-Path $root -Parent) "_Forever-Release-$Version" }
# immer als vollständiger Pfad: mit einem relativen Pfad (z. B. ..\_Forever-Release-0.3b) stimmten die Pfade im Zip
# nicht (Ordner wie "ForeverBars/beta_\Interface\...") und .NET legt Zips relativ zu einem anderen Ordner an
if (![IO.Path]::IsPathRooted($ReleaseDir)) { $ReleaseDir = Join-Path (Get-Location).Path $ReleaseDir }
$ReleaseDir = [IO.Path]::GetFullPath($ReleaseDir)
$addonOut = Join-Path $ReleaseDir 'ForeverAddons'
$singleOut = Join-Path $ReleaseDir 'Einzeln'
New-Item -ItemType Directory -Force $addonOut, $singleOut | Out-Null

function Add-FolderToZip($zip, $folder, $name) {
    $base = [IO.Path]::GetFullPath($folder).TrimEnd('\', '/')
    # Zips enthalten nur, was das Spiel braucht: keine Lizenz-, Lies-mich- oder Markdown-Dateien
    Get-ChildItem $base -Recurse -File | Where-Object { $_.Name -notmatch '^(LICENSE|README)' -and $_.Extension -ne '.md' } | ForEach-Object {
        $full = [IO.Path]::GetFullPath($_.FullName)
        if (!$full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Datei außerhalb von ${base}: $full" }
        $rel = $name + '/' + $full.Substring($base.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel, 'Optimal') | Out-Null
    }
}
function New-Zip($path, $folders, $extraFiles) {
    if (Test-Path $path) { Remove-Item $path -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        foreach ($f in $folders) { Add-FolderToZip $zip $f (Split-Path $f -Leaf) }
        foreach ($e in $extraFiles) { [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $e, (Split-Path $e -Leaf), 'Optimal') | Out-Null }
    } finally { $zip.Dispose() }
}

# Einzel-Zips enthalten ForeverCore mit, damit jedes Addon auch allein heruntergeladen funktioniert
$coreDest = Join-Path $addonOut $core
$copied = foreach ($a in $addons) {
    $dest = Join-Path $addonOut $a
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item (Join-Path $root $a) $dest -Recurse
    $folders = if ($a -eq $core) { @($dest) } else { @($dest, $coreDest) }
    New-Zip (Join-Path $singleOut "$a.zip") $folders
    $dest
}
# Gesamt-Zip: nur die Addon-Ordner (so lädt CurseForge es hoch); das README liegt daneben im Release-Ordner
New-Zip (Join-Path $ReleaseDir "ForeverCore-$Version.zip") $copied @()

Copy-Item (Join-Path $root 'release\README.txt'), (Join-Path $root 'release\Changelog-CurseForge.txt'), (Join-Path $root 'release\Description-CurseForge.txt') $ReleaseDir -Force
New-Item -ItemType Directory -Force (Join-Path $ReleaseDir 'Logo') | Out-Null
Copy-Item (Join-Path $root 'release\Logo\*') (Join-Path $ReleaseDir 'Logo') -Force

Write-Host "Release $Version gebaut: $ReleaseDir ($($addons.Count) Addons)"

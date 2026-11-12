# Verknüpft die Addon-Ordner aus diesem Repository in den WoW-AddOns-Ordner (Junctions, keine Admin-Rechte nötig).
# Vorhandene echte Ordner gleichen Namens werden vorher nach ..\_AddOn-Backups\<Datum>_vor-Git\ verschoben, nie gelöscht.
#   .\tools\link-addons.ps1                                  -> AddOns-Ordner neben dem Repository (..\AddOns)
#   .\tools\link-addons.ps1 -AddOnsDir "C:\...\Interface\AddOns"
param([string]$AddOnsDir)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$AddOnsDir) { $AddOnsDir = Join-Path (Split-Path $root -Parent) 'AddOns' }
if (!(Test-Path $AddOnsDir)) { throw "AddOns-Ordner nicht gefunden: $AddOnsDir" }
# Build-Nummer fürs Spiel (ForeverCoreUI\Build.lua, nicht eingecheckt) anlegen
try { & (Join-Path $PSScriptRoot 'write-build-info.ps1') } catch {}
$backup = Join-Path (Split-Path $AddOnsDir -Parent) ('_AddOn-Backups\' + (Get-Date -Format 'yyyy-MM-dd') + '_vor-Git')

Get-ChildItem $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName ($_.Name + '.toc')) } | ForEach-Object {
    $target = Join-Path $AddOnsDir $_.Name
    $item = Get-Item $target -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction') {
        if ($item.Target -eq $_.FullName) { Write-Host "ok        $($_.Name)"; return }
        $item.Delete()
    } elseif ($item) {
        New-Item -ItemType Directory -Force $backup | Out-Null
        Move-Item $target (Join-Path $backup $_.Name)
        Write-Host "gesichert $($_.Name) -> $backup"
    }
    New-Item -ItemType Junction -Path $target -Target $_.FullName | Out-Null
    Write-Host "verknüpft $($_.Name)"
}

# Automatischer Abgleich im Hintergrund (Windows-Aufgabe "Forever Core Abgleich", alle 5 Minuten; einrichten mit
# tools\auto-sync-install.ps1). Holt den neuen Stand von GitHub wie beim Sitzungsstart (session-sync.ps1) und
# verknüpft neue Addon-Ordner des Repositorys in den AddOns-Ordner. Im Spiel danach /reload.
# Sicher: läuft nur, wenn nichts Uncommittetes im Weg ist und kein Rebase/Merge offen ist – sonst wartet er bis zum
# nächsten Mal. Vorhandene Ordner im AddOns-Ordner werden nie angefasst (nur fehlende neu verknüpft).
# Protokoll (letzte 200 Zeilen): .git\forever-auto-sync.log
$root = Split-Path $PSScriptRoot -Parent
$git = Join-Path $root '.git'
$log = Join-Path $git 'forever-auto-sync.log'
function Log($text) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm') + '  ' + $text
    $old = @(); if (Test-Path $log) { $old = @(Get-Content $log -Tail 199) }
    Set-Content $log ($old + $line) -Encoding UTF8
}

if ((Test-Path (Join-Path $git 'rebase-merge')) -or (Test-Path (Join-Path $git 'rebase-apply')) -or
    (Test-Path (Join-Path $git 'MERGE_HEAD')) -or (Test-Path (Join-Path $git 'index.lock'))) {
    Log 'übersprungen: Rebase/Merge oder Git-Befehl läuft'
    exit 0
}
if (@(git -C $root status --porcelain 2>$null).Count -gt 0) {
    Log 'übersprungen: nicht committete Änderungen'
    exit 0
}

$result = & (Join-Path $PSScriptRoot 'session-sync.ps1') | Out-String
if ($result -notmatch 'aktuell mit GitHub') { Log $result.Trim() }

# neue Addon-Ordner verknüpfen (nur wo im AddOns-Ordner noch nichts liegt) – im AddOns-Ordner neben dem Repository
# und in weiteren Spiel-Clients dieses Rechners (je Zeile ein AddOns-Pfad in .git\forever-addon-dirs.txt, nur lokal,
# z. B. ein Stresstest-Client; einmalig verknüpfen mit tools\link-addons.ps1 -AddOnsDir "<Pfad>")
$dirs = @(Join-Path (Split-Path $root -Parent) 'AddOns')
$extra = Join-Path $git 'forever-addon-dirs.txt'
if (Test-Path $extra) { $dirs += Get-Content $extra | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() } }
foreach ($addOns in $dirs) {
    if (-not (Test-Path $addOns)) { continue }
    Get-ChildItem $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName ($_.Name + '.toc')) } | ForEach-Object {
        $target = Join-Path $addOns $_.Name
        if (!(Test-Path $target)) {
            New-Item -ItemType Junction -Path $target -Target $_.FullName | Out-Null
            Log "neues Addon verknüpft: $($_.Name) in $addOns"
        }
    }
}
exit 0

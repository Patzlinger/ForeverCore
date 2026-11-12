# Schreibt ForeverCoreUI\Build.lua: fortlaufende Build-Nummer (Anzahl Commits), Commit-Kurzzeichen und Datum/Uhrzeit des
# letzten Commits. Das Spiel kann git nicht lesen – die Übersicht im Einstellungsfenster zeigt diese Werte ganz unten.
# Die Datei wird NICHT eingecheckt (.gitignore): sie ändert sich mit jedem Commit, eingecheckt gäbe das bei jedem
# Abgleich zwischen zwei Rechnern einen Konflikt. Aufgerufen von session-sync.ps1 (also auch vom Auto-Sync),
# check.ps1, link-addons.ps1 und build-release.ps1; von Hand: .\tools\write-build-info.ps1
$root = Split-Path $PSScriptRoot -Parent
$target = Join-Path $root 'ForeverCoreUI\Build.lua'
$count = (git -C $root rev-list --count HEAD 2>$null | Out-String).Trim()
$hash = (git -C $root rev-parse --short HEAD 2>$null | Out-String).Trim()
$date = (git -C $root log -1 '--format=%cd' '--date=format:%Y-%m-%d %H:%M' 2>$null | Out-String).Trim()
$branch = (git -C $root rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
if ($count -notmatch '^\d+$') { $count = '0' }
if ($hash -notmatch '^[0-9a-f]+$') { $hash = '' }
if ($date -notmatch '^[0-9: -]+$') { $date = '' }
if ($branch -notmatch '^[\w./-]+$') { $branch = '' }
$text = @"
-- Automatisch erzeugt von tools/write-build-info.ps1 - nicht von Hand aendern, nicht einchecken.
local hub = _G.ForeverHub
if type(hub) == "table" then
    hub.build = { number = $count, commit = "$hash", date = "$date", branch = "$branch" }
end
"@
# nur schreiben, wenn sich etwas geändert hat (sonst meldet das Spiel nichts Neues, Datei bleibt ruhig)
$old = if (Test-Path $target) { [IO.File]::ReadAllText($target) } else { '' }
if ($old -ne $text) { [IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding($false))) }

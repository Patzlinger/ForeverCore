# Wird beim Start einer Claude-Sitzung aufgerufen (SessionStart-Hook): holt den neuen Stand von GitHub
# und spult vor, wenn das ohne Konflikt geht. Meldet in einer Zeile, wie der lokale Stand zu GitHub steht.
$root = Split-Path $PSScriptRoot -Parent
$out = @()
for ($try = 1; $try -le 2; $try++) {
    $fetch = git -C $root fetch origin 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { break }
    if ($try -eq 2) { $out += "Holen fehlgeschlagen: $($fetch.Trim())" }
    Start-Sleep -Seconds 2
}
$counts = (git -C $root rev-list --left-right --count 'HEAD...@{u}' 2>$null) -split '\s+'
$ahead = [int]$counts[0]; $behind = [int]$counts[1]
$dirty = @(git -C $root status --porcelain 2>$null).Count
if ($behind -gt 0 -and $ahead -eq 0) {
    $merge = git -C $root merge --ff-only '@{u}' 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { $out += "$behind neue Commits von GitHub übernommen" }
    else { $out += "Vorspulen nicht möglich (lokale Änderungen im Weg?): $($merge.Trim())" }
} elseif ($behind -gt 0) {
    $out += "ABGEZWEIGT: $ahead lokale und $behind neue Commits auf GitHub – vor dem Arbeiten 'git pull --rebase'"
} else {
    $out += "aktuell mit GitHub"
}
if ($ahead -gt 0) { $out += "$ahead lokale Commits noch nicht gepusht" }
if ($dirty -gt 0) { $out += "$dirty nicht committete Dateien" }
"Forever-Repo: " + ($out -join " · ")
exit 0

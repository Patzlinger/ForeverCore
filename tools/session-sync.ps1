# Wird beim Start einer Claude-Sitzung aufgerufen (SessionStart-Hook): holt den neuen Stand von GitHub,
# wechselt auf den Arbeitszweig "development" (wenn nichts Uncommittetes im Weg ist) und haengt eigene Commits
# per Rebase hinter die neuen des anderen. Meldet in einer Zeile, wie der lokale Stand zu GitHub steht.
# Ablauf und Regeln: CLAUDE.md, Abschnitt 15.
$root = Split-Path $PSScriptRoot -Parent
$work = "development"
$out = @()
for ($try = 1; $try -le 2; $try++) {
    $fetch = git -C $root fetch origin 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { break }
    if ($try -eq 2) { $out += "Holen fehlgeschlagen: $($fetch.Trim())" }
    Start-Sleep -Seconds 2
}
$dirty = @(git -C $root status --porcelain 2>$null).Count
$branch = (git -C $root rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()

# auf den Arbeitszweig wechseln (nur wenn sauber; main ist nur fuer Releases)
if ($branch -eq "main") {
    if ($dirty -eq 0) {
        git -C $root switch $work 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { git -C $root switch -c $work --track "origin/$work" 2>&1 | Out-Null }
        if ($LASTEXITCODE -eq 0) { $out += "auf '$work' gewechselt (/reload im Spiel)"; $branch = $work }
        else { $out += "Wechsel auf '$work' fehlgeschlagen" }
    } else {
        $out += "ACHTUNG: auf 'main' mit $dirty uncommitteten Dateien – gearbeitet wird auf '$work'"
    }
}

$counts = (git -C $root rev-list --left-right --count 'HEAD...@{u}' 2>$null) -split '\s+'
if ($counts.Count -lt 2) {
    $out += "Zweig '$branch' hat keinen GitHub-Zweig"
} else {
    $ahead = [int]$counts[0]; $behind = [int]$counts[1]
    if ($behind -gt 0) {
        # eigene Commits (und Uncommittetes) hinter die neuen des anderen haengen
        $pull = git -C $root pull --rebase --autostash 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $out += "$behind neue Commits von GitHub übernommen"
            if ($ahead -gt 0) { $out += "$ahead eigene Commits dahinter gehängt" }
        } else {
            git -C $root rebase --abort 2>&1 | Out-Null
            $out += "KONFLIKT beim Abgleich ($ahead eigene / $behind neue Commits) – abgebrochen, bitte klären: $($pull.Trim())"
        }
    } else {
        $out += "aktuell mit GitHub"
    }
    $ahead = [int]((git -C $root rev-list --count '@{u}..HEAD' 2>$null | Out-String).Trim())
    if ($ahead -gt 0) { $out += "$ahead lokale Commits noch nicht gepusht" }
}
$dirty = @(git -C $root status --porcelain 2>$null).Count
if ($dirty -gt 0) { $out += "$dirty nicht committete Dateien" }
# Build-Nummer fürs Spiel (ForeverCoreUI\Build.lua, Übersicht im Einstellungsfenster)
try { & (Join-Path $PSScriptRoot 'write-build-info.ps1') } catch {}
"Forever-Repo [$branch]: " + ($out -join " · ")
exit 0

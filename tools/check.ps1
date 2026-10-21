# Prüflauf vor jedem Commit: findet die typischen Fehler, bevor sie im Spiel auffallen.
#   pwsh -File tools\check.ps1                 -> nur geänderte Addons (gegenüber dem letzten Commit)
#   pwsh -File tools\check.ps1 -All            -> alle Addons
#   pwsh -File tools\check.ps1 ForeverPlates   -> nur diese Addons
# Geprüft wird:
#   1. Syntax (lua-language-server, Stufe Fehler)
#   2. Aufrufe eigener Funktionen, die an der Stelle nicht sichtbar sind (z. B. vor ihrer Definition aufgerufen)
#   3. .toc: jede eingetragene Datei existiert; jede .lua-Datei ist eingetragen (sonst lädt das Spiel sie nicht)
#   4. Luas Grenze von 200 lokalen Variablen je Datei (Warnung ab 185 auf oberster Ebene)
#   5. gemeinsame Hub-Funktionen richtig aufgerufen (UI.AfterCombat braucht zuerst einen Schlüssel-Text)
#   6. ForeverQuests: jeder Text-Schlüssel (ns.L / L) steht deutsch UND englisch in Locales.lua
# Ergebnis: Zusammenfassung; Rückgabe 1, wenn etwas Ernstes gefunden wurde (dann nicht committen).
# Neue Datei in einer .toc: das Spiel braucht einen kompletten Neustart (kein /reload) – das meldet der Lauf mit.
param([switch]$All, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Addons)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

$allAddons = Get-ChildItem $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName ($_.Name + '.toc')) } |
    ForEach-Object { $_.Name }

# Welche Addons? Ohne Angabe: die mit Änderungen seit dem letzten Commit (auch neue Dateien)
if ($All) {
    $targets = $allAddons
} elseif ($Addons) {
    $targets = $Addons
} else {
    $changed = @(git -C $root status --porcelain 2>$null) | ForEach-Object { ($_.Substring(3) -replace '"', '') -split '[\\/]' | Select-Object -First 1 }
    $targets = $allAddons | Where-Object { $changed -contains $_ }
    if (-not $targets) { Write-Host "Keine geänderten Addons – nichts zu prüfen (alle: -All)."; exit 0 }
}

# lua-language-server: VS-Code-Erweiterung oder im PATH
$lls = Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Directory -Filter '*lua*' -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'server\bin\lua-language-server.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $lls) { $cmd = Get-Command lua-language-server -ErrorAction SilentlyContinue; if ($cmd) { $lls = $cmd.Source } }
if (-not $lls) { $warnings.Add("lua-language-server nicht gefunden – Syntax (1) und Punkt 2 übersprungen (VS-Code-Erweiterung 'Lua' installieren)") }

# Namen aller eigenen Funktionen im Repository (für Punkt 2)
$ownFunctions = New-Object System.Collections.Generic.HashSet[string] # Groß-/Kleinschreibung zählt (Yes <> YES)
Get-ChildItem $root -Recurse -Filter *.lua | ForEach-Object {
    foreach ($m in [regex]::Matches((Get-Content $_.FullName -Raw), '(?m)^\s*(?:local\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
        [void]$ownFunctions.Add($m.Groups[1].Value)
    }
}

foreach ($addon in $targets) {
    $dir = Join-Path $root $addon
    if (-not (Test-Path $dir)) { $errors.Add("$addon – Ordner gibt es nicht"); continue }
    Write-Host "Prüfe $addon …"

    # 1 + 2: lua-language-server
    if ($lls) {
        $out = & $lls --check $dir --checklevel=Error 2>&1 | Out-String
        if ($out -notmatch 'no problems found') {
            $lines = ($out -split "`r?`n") | Where-Object { $_ -match '\[(Error|Fehler)\]|Error\]' }
            $errors.Add("$addon – Syntax:`n    " + (($lines | Select-Object -First 8) -join "`n    "))
        }
        $warn = (& $lls --check $dir --checklevel=Warning 2>&1 | Out-String) -replace "\e\[[0-9;]*m", ""
        foreach ($m in [regex]::Matches($warn, '([\w\\/.-]+\.lua:\d+:\d+)[^\n]*Undefined global `([A-Za-z_][A-Za-z0-9_]*)`')) {
            $name = $m.Groups[2].Value
            # auch die üblichen Kurz-Namen (T = UI.T, L = ns.L …): fehlt ihr "local" in der Datei, ist das ein Fehler
            if ($ownFunctions.Contains($name) -or @('T', 'L', 'C', 'UI', 'ns', 'Safe', 'IsSecret', 'GetDB', 'HUB') -ccontains $name) {
                $errors.Add("$addon – eigene Funktion '$name' hier nicht sichtbar (vor der Definition aufgerufen?): $($m.Groups[1].Value)")
            }
        }
    }

    # 3: .toc gegen die Dateien
    $toc = Join-Path $dir "$addon.toc"
    $listed = Get-Content $toc | Where-Object { $_ -and $_ -notmatch '^\s*#' } |
        ForEach-Object { ($_ -replace '\s*\[.*\]\s*$', '').Trim() } | Where-Object { $_ }
    foreach ($f in $listed) {
        if (-not (Test-Path (Join-Path $dir $f))) { $errors.Add("$addon – .toc nennt '$f', die Datei fehlt") }
    }
    $listedNorm = $listed | ForEach-Object { $_.ToLower().Replace('/', '\') }
    # über eine .xml eingebundene Dateien zählen auch als geladen
    $xmlText = (Get-ChildItem $dir -Recurse -Filter *.xml | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
    Get-ChildItem $dir -Recurse -Filter *.lua | ForEach-Object {
        $rel = $_.FullName.Substring($dir.Length + 1)
        if ($listedNorm -notcontains $rel.ToLower() -and $xmlText -notmatch [regex]::Escape($_.Name)) {
            $warnings.Add("$addon – '$rel' steht nicht in der .toc (wird nicht geladen)")
        }
    }
    $tocChanged = @(git -C $root status --porcelain -- "$addon/$addon.toc" 2>$null).Count -gt 0
    if ($tocChanged) { $notes.Add("$addon – .toc geändert: im Spiel einmal komplett neu starten (kein /reload)") }

    Get-ChildItem $dir -Recurse -Filter *.lua | ForEach-Object {
        $text = Get-Content $_.FullName -Raw
        $rel = "$addon\" + $_.FullName.Substring($dir.Length + 1)

        # 4: lokale Variablen auf oberster Ebene (Zeilen, die ganz links mit "local" beginnen)
        $count = 0
        foreach ($m in [regex]::Matches($text, '(?m)^local\s+(?:function\s+)?([^=(\r\n]+)')) {
            $count += ($m.Groups[1].Value -split ',').Count
        }
        if ($count -ge 195) { $errors.Add("$rel – $count lokale Variablen auf oberster Ebene (Lua-Grenze 200): auslagern") }
        elseif ($count -ge 185) { $warnings.Add("$rel – $count lokale Variablen auf oberster Ebene (Grenze 200)") }

        # 5: UI.AfterCombat(Schlüssel, Funktion, Addon) – zuerst der Schlüssel: Fehler, wenn gleich eine Funktion
        #    kommt ("AfterCombat(function" oder nur ein Name ohne zweiten Wert, z. B. "AfterCombat(Relayout)")
        foreach ($m in [regex]::Matches($text, '(?:UI|HUB|hub)\.AfterCombat\(\s*(function\b|[A-Za-z_][\w.]*\s*\))')) {
            $errors.Add("$rel – UI.AfterCombat ohne Schlüssel als ersten Wert: AfterCombat($($m.Groups[1].Value) …")
        }
    }

    # 6: ForeverQuests-Texte in beiden Sprachen
    if ($addon -eq 'ForeverQuests') {
        $loc = Get-Content (Join-Path $dir 'Locales.lua') -Raw
        $used = @{}
        Get-ChildItem $dir -Filter *.lua | ForEach-Object {
            foreach ($m in [regex]::Matches((Get-Content $_.FullName -Raw), '(?:ns\.L|[^A-Za-z_.]L)\("([A-Z][A-Z0-9_]+)"')) { $used[$m.Groups[1].Value] = $true }
        }
        foreach ($key in ($used.Keys | Where-Object { $_ -notmatch '_$' })) { # "XY_" = zusammengesetzter Name
            $n = [regex]::Matches($loc, "(?<![A-Z0-9_])$key\s*=").Count
            if ($n -lt 2) { $warnings.Add("ForeverQuests – Text '$key' fehlt in Locales.lua ($n von 2 Sprachen)") }
        }
    }
}

Write-Host ""
foreach ($n in $notes) { Write-Host "HINWEIS  $n" -ForegroundColor Cyan }
foreach ($w in $warnings) { Write-Host "WARNUNG  $w" -ForegroundColor Yellow }
foreach ($e in $errors) { Write-Host "FEHLER   $e" -ForegroundColor Red }
if ($errors.Count -eq 0) {
    Write-Host ("Prüflauf ok: " + ($targets -join ', ') + ($(if ($warnings.Count) { " ($($warnings.Count) Warnungen)" } else { "" }))) -ForegroundColor Green
    exit 0
}
Write-Host "Prüflauf: $($errors.Count) Fehler – bitte beheben, bevor committet wird." -ForegroundColor Red
exit 1

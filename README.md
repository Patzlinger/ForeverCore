# Forever Core UI

*Less clutter. More control. Just the essentials.*

Schlanke, modulare Addons für **World of Warcraft: Forever** (Interface 16001, Retail-API).
Autoren: Patzlinger, flowfy · CurseForge-Projekt 1743753 · Lizenz MIT

## Addons

Alle Addons stehen in `release/addons.txt` und tragen dieselbe Suite-Version (aktuell in allen `.toc`: 0.541b).
„Beta“ steht bei allen im Addon-Titel.

| Addon | Von | Status |
|---|---|---|
| ForeverCore (Hub + Stil-Bibliothek, Abhängigkeit aller Addons) | gemeinsam | im Release (seit 0.41b) |
| ForeverFrames, ForeverUnits, ForeverCast, ForeverHelpers (Loot, Buffs, Vendor) | Patzlinger | im Release |
| ForeverSpellbook, ForeverChat | Patzlinger | im Release (seit 0.32b) |
| ForeverMinimap | Patzlinger | im Release (seit 0.44b) |
| ForeverTooltip, ForeverPlates | Patzlinger | im Release (Beta, seit 2026-10-20) |
| ForeverQuests, ForeverBars, ForeverBags | flowfy | im Release (seit 0.44b) |
| ForeverAlts | flowfy | im Release (Beta, seit 2026-10-20) |
| ForeverSkin | flowfy | im Release (Beta, seit 0.47b, 2026-10-21) |

Im Spiel: `/forever` zeigt alle Forever-Addons, `/fmove` verschiebt alle Rahmen.

**Regeln, Design und Abläufe (verbindlich für alle, auch für Claude):** [CLAUDE.md](CLAUDE.md) – bitte vor dem ersten Arbeiten
lesen. Ausführliche Referenzen liegen in [docs/](docs/). **Offene Fehler:** [KNOWN-BUGS.md](KNOWN-BUGS.md) – wer gerade
nichts vorhat, findet dort Arbeit.

## Aufbau

```
_Forever-Source/
  ForeverBars/ ...        ein Ordner pro Addon (Ordnername = .toc-Name)
  ForeverCoreUI/          Hauptaddon: ForeverHub.lua = gemeinsame Bibliothek, Hub-Fenster, Begrüßung
  docs/                   Referenzen (Hub, Design, Menüs, Fallstricke, Workflow, Release, Befehle …)
  release/                README/Changelog fürs Paket, addons.txt = was ins Release kommt
  tools/                  Skripte (Abgleich, Verknüpfen, Prüflauf, Release-Bau)
```

Alle Addons tragen `## Dependencies: ForeverCoreUI` – ForeverCore lädt immer zuerst, `ForeverHub.UI` steht bereit. Den Hub
gibt es nur einmal (`ForeverCoreUI/ForeverHub.lua`).

## Einrichten (einmalig)

1. Repository klonen, am besten direkt neben den AddOns-Ordner:
   ```
   cd "...\World of Warcraft\_classic_beta_\Interface"
   git clone https://github.com/Patzlinger/ForeverCore.git _Forever-Source
   ```
2. Addons ins Spiel verknüpfen (PowerShell, im Repository-Ordner):
   ```
   .\tools\link-addons.ps1
   ```
   Liegt das Repository woanders: `.\tools\link-addons.ps1 -AddOnsDir "C:\...\Interface\AddOns"`.
   Bereits vorhandene Forever-Ordner werden vorher nach `_AddOn-Backups\<Datum>_vor-Git\` verschoben, nicht gelöscht.
3. Optional, empfohlen: `pwsh -File tools/auto-sync-install.ps1` (Abgleich alle 5 Minuten, Details in [docs/Workflow.md](docs/Workflow.md)).

Danach ist der AddOns-Ordner nur noch eine Verknüpfung: Was du im Repository änderst, ist sofort im Spiel (`/reload`).

## Zusammenarbeiten

Ausführlich: [docs/Workflow.md](docs/Workflow.md). Kurz:
- Gearbeitet wird auf **`development`** (gemeinsamer Zweig); `main` enthält nur veröffentlichte Stände (Tag `v0.xxb`).
- Vor dem Arbeiten holen: `git switch development` und `git pull --rebase --autostash` (oder `tools/session-sync.ps1`).
- Kleine, geprüfte Änderungen einzeln committen (`pwsh -File tools/check.ps1` vorher), dann `git pull --rebase` und `git push`.
  Nie force-pushen.
- Jeder darf an allen Addons arbeiten. Nur bei großen, mehrtägigen Umbauten ein Zweig `feature/<name>`.
- **Nie** SavedVariables (`WTF\...`) oder gebaute Zips einchecken.
- Neues Addon: [docs/Hub.md](docs/Hub.md), Abschnitt 5 (Vorlage für die .toc und Anbindung an den Hub).

## Release bauen

Nur auf ausdrückliche Anweisung; vollständiger Ablauf (Version, Changelog, Tag, `main`): [docs/Release.md](docs/Release.md).

```
.\tools\build-release.ps1
```
Prüft, dass alle `.toc` dieselbe `## Version` haben, und baut `..\_Forever-Release-<Version>\` mit Addon-Ordnern,
`Einzeln\*.zip` (jedes mit ForeverCoreUI) und `ForeverCore-<Version>.zip`. Welche Addons hineinkommen, steht in `release/addons.txt`.

## Achtung CurseForge-App

Installieren/Aktualisieren von Forever Core UI über die CurseForge-App überschreibt die Addon-Ordner – durch die
Verknüpfung also das Repository. Dann mit `git status` prüfen und mit `git restore .` zurücksetzen. Am besten Forever Core
UI in der App gar nicht installieren.

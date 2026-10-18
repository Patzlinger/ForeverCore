# Forever Core

*Less clutter. More control. Just the essentials.*

Schlanke, modulare Addons für **World of Warcraft: Forever** (Interface 16001, Retail-API).
Autoren: Patzlinger, flowfy · CurseForge-Projekt 1743753

| Addon | Von | Status |
|---|---|---|
| ForeverFrames, ForeverUnits, ForeverCast, ForeverLoot, ForeverBuffs, ForeverVendor | Patzlinger | im Release (MIT) |
| ForeverSpellbook, ForeverChat | Patzlinger | im Release (seit 0.32b) |
| ForeverMinimap | Patzlinger | Prototyp (nicht im Release) |
| ForeverQuests, ForeverBars | flowfy | im Repository, noch nicht im Release |
| ForeverBags | flowfy | Prototyp (nicht im Release) |
| ForeverTooltip | Patzlinger | Prototyp (nicht im Release) |
| ForeverCore (Hauptaddon: Hub + Stil-Bibliothek, Abhängigkeit aller Addons) | gemeinsam | im Release (seit 0.41b) |

**Regeln, Design und Abläufe stehen in [CLAUDE.md](CLAUDE.md)** – bitte vor dem ersten Arbeiten lesen.
Im Spiel: `/forever` zeigt alle Forever-Addons, `/fmove` verschiebt alle Rahmen.

## Aufbau

```
_Forever-Source/
  ForeverBars/ ...          ein Ordner pro Addon (Ordnername = .toc-Name)
  ForeverCore/            Hauptaddon: ForeverHub.lua = gemeinsame Bibliothek, Hub-Fenster, Begrüßung
  release/                README/Changelog fürs Paket, addons.txt = was ins Release kommt
  tools/                  Skripte (siehe unten)
```

Alle Addons tragen `## Dependencies: ForeverCore` – ForeverCore lädt immer zuerst, `ForeverHub.UI` steht bereit.
Den Hub gibt es nur einmal (`ForeverCore/ForeverHub.lua`); bei Änderungen dort `VERSION` erhöhen.
Alle Addons tragen dieselbe Version (seit 0.41b). Stand vor der Umstellung: Git-Markierung `snapshot-vor-core-abhaengigkeit`.

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

Danach ist der AddOns-Ordner nur noch eine Verknüpfung: Was du im Repository änderst, ist sofort im Spiel (`/reload`).

## Zusammenarbeiten

- Vor dem Arbeiten: `git pull`
- Größere Sachen auf einem eigenen Zweig: `git switch -c mein-thema`, hochladen, Pull Request auf GitHub
- Kleine Fixes direkt auf `main` sind okay, wenn abgesprochen
- **Nie** SavedVariables (`WTF\...`) oder gebaute Zips einchecken
- Neues Addon: siehe CLAUDE.md, Abschnitt 5 (Vorlage für die .toc) und 6 (Anbindung an den Hub)

## Release bauen

```
.\tools\build-release.ps1
```
Prüft, dass alle `.toc` dieselbe `## Version` haben, und baut
`..\_Forever-Release-<Version>\` mit Addon-Ordnern, `Einzeln\*.zip` (jedes mit ForeverCore) und `ForeverCore-<Version>.zip`.
Welche Addons hineinkommen, steht in `release/addons.txt`.

## Achtung CurseForge-App

Installieren/Aktualisieren von Forever Core über die CurseForge-App überschreibt die Addon-Ordner –
durch die Verknüpfung also das Repository. Dann mit `git status` prüfen und mit `git restore .` zurücksetzen.
Am besten Forever Core in der App gar nicht installieren.

# Git-Zusammenarbeit und Tools

Ausgelagert aus CLAUDE.md (alter Abschnitt 15; die Kurzregeln stehen weiter in CLAUDE.md). **Lesen bei Sitzungsbeginn-
Problemen, Konflikten, Zweigfragen, Auto-Sync oder wenn ein Skript aus `tools/` gebraucht wird.**
Patzlinger und flowfy arbeiten zeitgleich, jeder mit seinem eigenen Claude, über `development` (seit 2026-10-17).

## Zweige
- `development` = gemeinsamer Arbeitszweig. **Hier wird gearbeitet**, committet und gepusht – immer.
- `main` = nur veröffentlichte Stände (je Release ein Tag `v0.xxb`). Auf `main` wird nie direkt gearbeitet; `main` wird
  nur beim Release gepusht (Release.md). Die README-Aussage „kleine Fixes direkt auf `main`“ ist überholt.
  - Ausnahme nur auf ausdrückliches Kommando des Nutzers: `development` komplett nach `main` übernehmen, ohne Tag, Zip
    und Changelog-Umbenennung (`git push origin development:main`, nur als Fast-Forward). Zuletzt 2026-11-05 (Stand
    nach dem Live-Start, auf Wunsch von flowfy); der nächste Release-Tag kommt dann wie gewohnt obendrauf.
- Optional `feature/<name>` (von `development` abgezweigt) für große, mehrtägige Umbauten, die `development` sonst
  unspielbar machen würden; fertig → in `development` übernehmen (`git merge --no-ff`), Zweig löschen.
- Das Repository ist der Live-Ordner (Junctions in AddOns): ein Zweigwechsel ändert sofort, was im Spiel geladen wird
  → danach `/reload`.

## Sitzungsbeginn
- `tools/session-sync.ps1` als SessionStart-Hook (in der lokalen `.claude/settings.json` des AddOns-Ordners) erledigt:
  holen, auf `development` wechseln (wenn sauber), eigene Commits per `pull --rebase --autostash` hinter die neuen des
  anderen hängen, Stand in einer Zeile melden. Meldet es einen Konflikt oder falschen Zweig: erst das klären.
- Ohne Hook von Hand: `git switch development` und `git pull --rebase --autostash`.
- **Automatischer Abgleich (empfohlen, je Rechner einmal):** `pwsh -File tools/auto-sync-install.ps1` richtet die
  Windows-Aufgabe „Forever Core UI Abgleich“ ein: alle 5 Minuten `tools/auto-sync.ps1` (wie session-sync, nur bei
  sauberem Arbeitsstand, verknüpft neue Addon-Ordner), Protokoll `.git/forever-auto-sync.log`; entfernen mit
  `-Remove`. Seit 2026-10-20 bei Patzlinger eingerichtet. Im Spiel danach `/reload`. Weitere Spiel-Clients auf demselben
  Rechner (z. B. ein Stresstest): einmal `tools/link-addons.ps1 -AddOnsDir "<Pfad>"` und den Pfad als Zeile in
  `.git/forever-addon-dirs.txt` eintragen – dann verknüpft der Abgleich neue Addons auch dort.

## Während der Arbeit – kleine Schritte, sofort teilen
- Je fertige, im Prüflauf (`tools/check.ps1`) fehlerfreie Änderung **ein** Commit (kurze deutsche Nachricht, vorne das
  Addon: `ForeverChat: …`, `Hub v36: …`).
- Direkt danach **ohne Nachfrage**: `git pull --rebase` und `git push` (auf `development`). Damit hat der andere
  spätestens beim nächsten Holen den Stand – niemand sammelt Commits an.
- Nichts Halbfertiges pushen, das beim Laden Fehler wirft (`development` muss für beide spielbar bleiben); Halbfertiges
  lokal lassen oder auf `feature/<name>` pushen.
- Konflikte beim Rebase: eindeutige (beide Seiten unabhängig, z. B. verschiedene Funktionen) selbst zusammenführen und
  im Spiel prüfen; unklare → `git rebase --abort` und den Nutzer fragen. **Nie force-pushen**, nie gepushte Commits
  umschreiben.

## Stellen, an denen man sich trifft (Konflikte vermeiden)
- `ForeverCore/ForeverHub.lua`: ohne Absprache änderbar; vor jeder Änderung `git pull --rebase`, damit man auf dem
  neuesten Stand arbeitet; treffen beide eine `VERSION`-Erhöhung, nimmt der Zweite die nächsthöhere Zahl.
- `## Version` in den .toc, `release/`-Dateien: ändert nur, wer den Release baut (Release.md).
- Changelog: neue Punkte während der Entwicklung unter `## Unreleased` oben in `release/Changelog-CurseForge.txt`
  eintragen (Englisch, für Spieler); beim Release wird daraus die Versionsüberschrift.
- CLAUDE.md und docs/: Regeländerungen sofort committen und pushen, damit der Claude des anderen sie gleich kennt.
- Änderungen an Addons des anderen brauchen keine Absprache (siehe CLAUDE.md, Team).
- Installieren über die CurseForge-App überschreibt die verknüpften Ordner = das Repository → danach `git status`,
  ggf. `git restore .`.

## Skripte in `tools/`
`session-sync.ps1`, `auto-sync.ps1`, `auto-sync-install.ps1` (Abgleich, siehe oben), `link-addons.ps1` (Addon-Ordner als
Junctions ins Spiel; `-AddOnsDir`), `check.ps1` (Prüflauf, siehe CLAUDE.md, Testen), `build-release.ps1` (Release.md).

# Release-Prozess

Ausgelagert aus CLAUDE.md (alter Abschnitt 16). **Lesen, bevor ein Release gebaut wird – und ein Release nur auf
ausdrückliches Kommando des Nutzers** (keine Absprache mit dem anderen Entwickler nötig).

## Ablauf
Vorher `git pull --rebase`, damit der Stand des anderen mit drin ist.
1. Auf `development`: `git pull --rebase`, `## Version` in allen .toc erhöhen, `## Unreleased` im Changelog in
   `## 0.xxb – <Datum>` umbenennen, `tools/build-release.ps1` bauen, committen, pushen.
2. `git switch main`, `git merge --ff-only development` (geht das nicht: `git merge --no-ff development`),
   `git tag -a v0.xxb -m "Forever Core UI 0.xxb"`, `git push origin main v0.xxb`.
3. `git switch development` – weiterarbeiten; neuer leerer Abschnitt `## Unreleased` im Changelog.

## Regeln und Dateien
- `release/addons.txt` = Addons im Release (maßgeblich für „im Release“); Prototypen erst nach Freigabe eintragen.
  ForeverCore baut das Skript immer mit – es steckt in **jedem Einzel-Zip** (sonst lädt das Addon nicht).
- Alle Release-Addons tragen dieselbe `## Version` (Suite-Version, z. B. `0.44b`); `tools/build-release.ps1` prüft das.
- Alle Release-.toc: `## Title: <Addon> |cff8a8a8a(Beta)|r`, `## X-Curse-Project-ID: 1743753`, `## X-License: MIT`
  (plus `LICENSE.txt` im Addon).
- `release/README.txt` (DE/EN, liegt im Release-Ordner, NICHT im Zip – das Gesamt-Zip enthält nur die Addon-Ordner) bei
  neuen Befehlen/Funktionen anpassen.
- `release/Changelog-CurseForge.txt` = Englisch, für Spieler geschrieben; wandert nicht ins Zip.
- `release/Description-CurseForge.txt` = Text der CurseForge-Hauptseite (Englisch, Markdown); bei neuen
  Addons/Funktionen anpassen, nicht ins Zip.
- Bauen mit `tools/build-release.ps1` (Versionsprüfung, Addon-Ordner, Einzel-Zips, Gesamt-Zip) nach
  `..\_Forever-Release-<Version>\`; fremde Zips im Zielordner werden nie angefasst.
- Nie SavedVariables oder gebaute Zips ins Repository einchecken.

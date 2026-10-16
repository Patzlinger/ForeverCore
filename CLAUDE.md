# Forever Core – Regeln für dieses Repository

## Zielclient
- World of Warcraft: Forever, Interface 16001; Basis ist die Mainline/Retail-API (Stand 12.1.5), NICHT Classic
- Midnight-Restriktionen ("secret values" im Kampf): keine Rechnungen/Vergleiche mit gesperrten Werten, keine Rotationslogik
- Bekannter Beta-Bug: SavedVariables werden beim Login nicht geladen (Defaults müssen sinnvoll sein)

## Code
- GUI in Lua (CreateFrame, Retail-Templates), kein XML
- Jedes Addon in eigenem Ordner, .toc-Name = Ordnername; `ForeverHub.lua` als erste Datei laden
- Gemeinsame Bibliothek nur in `Shared/ForeverHub.lua` bearbeiten, `VERSION` erhöhen, dann `tools/sync-hub.ps1`
- Texte zweisprachig DE/EN über `T()` aus dem Hub
- Blizzard-Rahmen nie mit :Hide()/:SetParent()/SetScript ausblenden (taint), sondern UnregisterAllEvents + RegisterStateDriver(frame, "visibility", "hide") oder Alpha 0 mit hooksecurefunc
- Namensplaketten sind "restricted regions": kein GetCenter/GetPoint darauf
- Anvisieren und SetRaidTarget nur über sichere Knöpfe auf Tastendruck
- Forever-Namen haben Vor- und Nachnamen: abgleichen statt direkt vergleichen
- WoW-Schrift kennt "→" nicht: "»" oder "–" verwenden
- Syntax-Check: lua-language-server `--check <ordner> --checklevel=Error`

## Addons
- Ab sofort erlaubt: eigenes Aktionsleisten-Addon "ForeverBars" (Ordner `ForeverBars/`, gleiche Konventionen wie alle Forever-Addons)
  - Knöpfe über sichere Vorlagen (z. B. ActionButtonTemplate / SecureActionButtonTemplate); Anlegen, Verschieben und Belegen nur außerhalb des Kampfes (InCombatLockdown prüfen)
  - Blizzard-Leisten nur taint-frei ausblenden (siehe oben), nie Hide/SetParent/SetScript
  - Keine Rotationslogik und keine Auswertung gesperrter Werte (z. B. Abklingzeiten im Kampf nur anzeigen, nicht berechnen)
  - Bis zur Freigabe durch den Nutzer nicht in `release/addons.txt` eintragen

## Git-Ablauf
- Vor dem Arbeiten: `git pull --ff-only`
- Während der Arbeit am Live-Ordner (AddOns-Verknüpfung = dieses Repository) NICHT automatisch pushen
- Fertige Änderungen lokal committen (kurze deutsche Nachricht) ist erlaubt
- `git push` nur auf ausdrückliches Kommando des Nutzers oder am Ende einer Session (dann kurz nachfragen bzw. ankündigen)
- Bei Konflikten oder unerwarteten Änderungen des anderen erst nachfragen; nie force-pushen

## Release
- `release/addons.txt` = Addons im Release; Prototypen (z. B. ForeverSpellbook) nicht eintragen, bis freigegeben
- Alle Release-.toc: gleiche `## Version`, `## Title: <Addon> |cff8a8a8a(Beta)|r`, `## X-Curse-Project-ID: 1743753`
- `release/Changelog-CurseForge.txt` = Englisch, für Spieler; wandert nicht ins Zip
- Bauen mit `tools/build-release.ps1`; keine SavedVariables, keine fremden Addons ins Repository oder Release
- Die Änderungen für Nicht-Programmierer kurz auf Deutsch erklären

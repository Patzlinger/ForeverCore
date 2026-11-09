# Forever Core UI – Arbeitsanweisung

Gilt für alle, die an diesem Repository arbeiten (Menschen und Claude). Maßgeblich für verbindliche Agenten- und
Entwicklungsregeln (README = Überblick für Menschen). Fehlt etwas: am bestehenden Code orientieren und nachfragen.
Regeländerungen immer hier bzw. in `docs/` eintragen, committen und pushen (nicht nur lokal).

## 1. Projekt
- **Forever Core UI**: schlanke, modulare Addons für *World of Warcraft: Forever* (`## Interface: 16001`, Mainline/Retail-API
  12.1.5, NICHT Classic). Leitsatz: **„Less clutter. More control. Just the essentials.“**
- Jedes Addon löst eine Aufgabe gut, funktioniert allein ohne Einstellungen (sinnvolle Standardwerte), ist unaufdringlich
  (wenig Fläche, kein Blinken, Infos per Mouseover) und passt optisch in die Suite. Ersetzt es einen Blizzard-Teil,
  wird dieser **taint-frei** ausgeblendet.
- Zielgruppe sind Spieler, keine Programmierer: Texte kurz und klar. Mitarbeiter sprechen teils kein Lua →
  **Änderungen immer kurz auf Deutsch erklären** (was, warum, was im Spiel testen).
- Offene Fehler: [KNOWN-BUGS.md](KNOWN-BUGS.md). Wird nichts Bestimmtes entwickelt: dort anfangen. Neue, nicht sofort
  behobene Fehler dort eintragen; behobene mit Datum und Ursache nach „Erledigt“ verschieben (nicht löschen).

## 2. Team
- Patzlinger: ForeverFrames, Units, Cast, Helpers (Loot, Buffs, Vendor), Spellbook, Chat, Minimap, Tooltip, Plates.
  flowfy: ForeverQuests, Bars, Bags, Alts, Skin. Gemeinsam: ForeverCore (Hub + Stil-Bibliothek), `tools/`, `release/`.
  „Im Release“ gilt, was in `release/addons.txt` steht (derzeit alle 15 Addons).
- **Jeder arbeitet frei an allen Addons**, ohne vorherige Absprache oder Rückfrage (auch Umbauten, Hub, Standardpositionen,
  Design – auch für den Claude des anderen). Die Änderung im Commit klar benennen (Addon vorne, was und warum).
- Alle Release-Addons tragen **dieselbe `## Version`** (Suite-Version); Versionssprünge nur gemeinsam in allen .toc und
  nur beim Release. Lizenz (MIT, `## Author: Patzlinger`) bleibt unverändert.

## 3. Verbindliche Regeln: WoW-API, Secret Values, Taint, Kampf
**Vor jeder Änderung an Blizzard-Rahmen, Kampf-/Einheitencode, Chat oder Menüs: [docs/Technical-Pitfalls.md](docs/Technical-Pitfalls.md) lesen.**
- **Secret Values:** Werte aus Einheiten-Abfragen (Leben, Mana, GUID, Auren …) sind im Kampf – Mana auch außerhalb –
  gesperrt. Nur anzeigen/weiterreichen (`SetText`, `StatusBar:SetValue`, `"%s"`); **nie rechnen, vergleichen, als
  Tabellenschlüssel oder mit `#`**; keine Rotationslogik. Nur Hub-Helfer: `UI.IsSecret`, `UI.Readable`, `UI.Try`,
  `UI.SetStepCount`. Kein globales `issecret` (nur `issecretvalue`). Auch `GetUnitSpeed("player")` ist gesperrt →
  Ereignisse statt Abfragen in `OnUpdate`.
- **Kampflog verboten:** `COMBAT_LOG_EVENT_UNFILTERED`/`CombatLogGetCurrentEventInfo` nie benutzen (`ADDON_ACTION_FORBIDDEN`).
- **Combat Lockdown:** Geschützte Rahmen (Aktionsknöpfe, Einheitenrahmen, sichere Knöpfe, Taschenplätze) nur außerhalb des
  Kampfes anlegen/verschieben/belegen: `InCombatLockdown()` prüfen, sonst `UI.AfterCombat("Addon:schlüssel", fn, addon)`
  bzw. `PLAYER_REGEN_ENABLED`. `pcall` verhindert `ADDON_ACTION_BLOCKED` nicht. Anvisieren/`SetRaidTarget` nur über sichere
  Knöpfe auf Tastendruck.
- **Taint:** Blizzard-Rahmen **nie** mit `:Hide()`, `:SetParent()`, `:SetScript()` ändern; stattdessen
  `UnregisterAllEvents()` + State-Driver oder `SetAlpha(0)` mit `hooksecurefunc`-Absicherung (`UI.HideBlizzard`/`UI.ShowBlizzard`).
  Blizzard-Funktionen nur mit `hooksecurefunc`/`HookScript` erweitern, nie überschreiben. Nichts in Blizzards Knopflisten
  einhängen (z. B. `GameMenuFrame:AddButton`). **Nie eigene Funktionen/Werte in Tabellen legen, die Blizzard-Code liest.**
  Zwei Addons dürfen nicht denselben Blizzard-Teil „besitzen“. Dokumentierte Ausnahmen (ForeverBars `SetParent`,
  ForeverQuests-Tracker `:Hide()`, ForeverBags Taschenfenster `:Hide()`) stehen in Technical-Pitfalls.md – nicht
  „reparieren“ ohne Absprache.
- Namensplaketten sind restricted regions (kein `GetCenter`/`GetPoint`). Anzeige-Texte ohne „→“ (nimmt „»“ oder „–“).
  Spielernamen abgleichen statt vergleichen (Chat: „Vorname Nachname“, Gruppe: Vorname).

## 4. Addon- und Hub-Grundstruktur
**Vor neuem Addon oder neuen Hub-Funktionen: [docs/Hub.md](docs/Hub.md) lesen** (.toc-Vorlage, `KNOWN`, Minimap-Knopf, `UI.API`, Takt, Einstellungen, Profile).
- Ordner im Wurzelverzeichnis `Forever<Name>`, .toc-Name = Ordnername; GUI in Lua, **kein XML** (außer `Bindings.xml`).
  .toc mit `## Dependencies: ForeverCore` und `## Group: ForeverCore`; `ForeverHubDB` steht nur in ForeverCore.
- **Hub:** `ForeverCore/ForeverHub.lua`, `local UI = ForeverHub.UI`; gibt es nur einmal. Bei Änderung `VERSION` erhöhen,
  abwärtskompatibel bleiben (Aufruf bei Bedarf mit `if UI.Funktion then`). Gemeinsames gehört in den Hub.
- Wiederkehrendes nur über `UI.Every(sekunden, fn, { addon, name, when })`, nie eigener Dauer-Ticker. Addons rufen sich nur
  über `UI.API.<Addon>` auf (mit `pcall`), Nachrichten über `UI.On`/`UI.Fire`. Fehler über `UI.ReportError`/`UI.Safe`.
  Minimap-Knopf nur über `UI.MinimapButton`; `/fmove` über `UI.RegisterMovable`.
- **Wechselwirkungen:** Vor Änderungen an Leisten/Bearbeitungsmodus, Minimap/Mikromenü/Tracker, Taschen, Chat, XP/Ruf oder
  Fremd-Addons (Questie, Details, Leatrix, Masque, Bartender4): [docs/Wechselwirkungen.md](docs/Wechselwirkungen.md) lesen.
  Verbindlich: **Zugriff auf andere Addons nur mit Erlaubnis** (Lizenz/API prüfen, nur zur Laufzeit lesen, nie kopieren,
  ohne das Addon muss alles laufen; Questie ist geprüft und erlaubt, Interna nur mit `pcall`). **Dungeondaten von
  ForeverQuests nur aus Spiel und Questie** – keine eigene Tabelle anlegen oder vorschlagen.

## 5. Einstellungen und Positionen
- Jedes Addon meldet seine SavedVariable (`Forever<Name>DB`, Charakterdaten in `…CharDB`) mit `UI.RegisterSettings({ addon, sv,
  defaults, version, … })` an (Profile, Migration, Export/Import macht der Hub). Schlüssel mit `_` sind reserviert; die
  Tabelle **nie ersetzen oder leeren** (`wipe`, `= {}`). Defaults beim Laden ergänzen (`CopyTable`), gespeicherte Werte erst
  nach `ADDON_LOADED` lesen, geänderte Bedeutungen umrechnen. Einstellungen wirken sofort. Blizzard-Einstellungen (CVars,
  Tastenbelegung) nur auf ausdrücklichen Wunsch ändern.
- Alle Rahmen starten **gesperrt**; entsperren per Menü, Minimap-Rechtsklick oder `/fmove`. Neue verschiebbare Fenster
  **müssen** Einrasten einbauen (`UI.AddMover`/`BeginDrag`/`EndDrag`, Shift = frei) – Details in docs/Design.md, Abschnitt 10.

## 6. Design und Sprache
**Vor neuen/umgebauten Fenstern: [docs/Design.md](docs/Design.md); vor Einstellungsfenstern zusätzlich [docs/Menues.md](docs/Menues.md); vor neuen ForeverSkin-Fenstern [docs/Fenster-Stil.md](docs/Fenster-Stil.md) (beim ersten Versuch anwenden).**
- Flacher dunkler Stil aus ForeverQuests; nur `UI.COLOR` (Gold = einzige Akzentfarbe), nie aus einem Addon verändern. Keine
  dritten Stile. Einstellungen = Seite im zentralen Fenster (`UI.SettingsPanel`, 176 + 720 × 832). Fenster mit
  `UI.RegisterWindow` anmelden, nicht per `SetFrameLevel` festnageln. Umbau bestehender Fenster = 1:1, nie kleiner als vorher.
- **Jede sichtbare Zeichenkette zweisprachig (Deutsch + Englisch)**; Sprache nur über `UI.GetLanguage()`/`UI.T`, nicht
  `GetLocale()`. Pro Addon ein Weg: `T("Deutsch","English")` oder `Locales.lua` mit `ns.L("KEY")`. Deutsche Texte sind
  30–40 % länger. Code-Kommentare auf Deutsch, kurz, erklären das *Warum*.
- Chat-Ausgabe sparsam: `Addonname: Text` (Name Gold `|cffffcc00`, `UI.Chat`).

## 7. Code-Stil
- Einfach und lesbar vor clever; Code wie der umliegende. `local addonName, ns = ...`; Globale nur für Rahmen
  (`Forever<Name>…`) und Pflicht-Globale (SavedVariables, `SLASH_…`, `BINDING_…`).
- Ereignis-Code absichern (`pcall` + `geterrorhandler()`) wo sinnvoll. Ereignisse statt Timer; Timer nur ohne Ereignis,
  Sicherheitsprüfungen ≥ 5 s; Anlässe bündeln (`C_Timer.After(0.3, …)` mit „schon geplant“-Merker).
- Keine fremden Bibliotheken (Ace3, LibStub …); optional erkennen ist ok (LibSharedMedia). Nur eigene Forever-Addons im
  Repository: keine SavedVariables, keine fremden Addons, keine gebauten Zips.
- Chatbefehle: `/f<kürzel>` + `/forever<name>`, keine Doppelungen → vor neuen Befehlen [docs/Commands.md](docs/Commands.md).

## 8. Testen
- **Vor jedem Commit:** `pwsh -File tools/check.ps1` (nur geänderte Addons; `-All` = alle; braucht VS-Code-Erweiterung „Lua“).
  Bei „FEHLER“ nicht committen.
- Neue Datei in einer .toc: im Spiel **kompletter Neustart** (kein `/reload`) – dem Nutzer sagen. Sonst `/reload`, BugSack
  prüfen, **auch im Kampf testen** (secret values, geschützte Rahmen). Hub-Änderungen: mindestens zwei Forever-Addons
  gleichzeitig aktiv testen (Sammelknopf, `/forever`, `/fmove`).
- Nach jeder Änderung kurz notieren, was der Mitarbeiter im Spiel prüfen soll.

## 9. Git (Details: [docs/Workflow.md](docs/Workflow.md))
- `development` = gemeinsamer Arbeitszweig (hier arbeiten, committen, pushen). `main` = nur Releases (Tag `v0.xxb`),
  nie direkt darauf arbeiten. Optional `feature/<name>` für große Umbauten.
- **Sitzungsbeginn:** `tools/session-sync.ps1` bzw. `git switch development` + `git pull --rebase --autostash`.
- Je fertige, geprüfte Änderung **ein** Commit (deutsch, Addon vorne: `ForeverChat: …`, `Hub v36: …`), danach ohne Nachfrage
  `git pull --rebase` + `git push`. Nichts Halbfertiges pushen, das beim Laden Fehler wirft.
- **Nie force-pushen**, nie gepushte Commits umschreiben. Rebase-Konflikte: eindeutige selbst lösen und im Spiel prüfen;
  unklare → `git rebase --abort` und den Nutzer fragen.
- Changelog-Punkte (Englisch, für Spieler) unter `## Unreleased` in `release/Changelog-CurseForge.txt`.
- **Release nur auf ausdrückliches Kommando des Nutzers** → vorher [docs/Release.md](docs/Release.md) lesen. Ausnahme
  `development` → `main` ohne Tag nur auf ausdrückliches Kommando (siehe Workflow.md).
- **Versionsanzeige im Spiel** (unten auf der Übersichtsseite: „Version · Build N (Commit) · Stand Datum · Zweig · Hub vX“):
  Build N = Anzahl Commits auf dem Stand, den man gerade ausgecheckt hat – gleiche Nummer + gleicher Commit = gleiche
  Version bei allen. Sie kommt aus `ForeverCore/Build.lua`, erzeugt von `tools/write-build-info.ps1`; die Datei ist
  **nie eingecheckt** (`.gitignore`). Pflege: Nach jedem eigenen Commit und jedem Pull/Rebase
  `pwsh -File tools/write-build-info.ps1` ausführen (session-sync, Auto-Sync, `link-addons.ps1` und `check.ps1` tun es auch,
  aber `check.ps1` läuft VOR dem Commit), dann dem Nutzer sagen: im Spiel `/reload`. Die Anzeige im Hub nicht entfernen
  oder umbauen, `Build.lua` nicht einchecken und in der `.toc` von ForeverCore eingetragen lassen. Einmal je Rechner:
  `pwsh -File tools/auto-sync-install.ps1` (aktualisiert die Nummer alle 5 Minuten von selbst).
- CurseForge-App überschreibt die verknüpften Ordner = das Repository → danach `git status`, ggf. `git restore .`.

## 10. Dokumentation und alte Abschnittsnummern
Code-Kommentare und Skripte verweisen auf die frühere Nummerierung dieser Datei:
| Alt | Jetzt |
|---|---|
| 3, 4 (API, Taint), Secret Values aus 6, „Umhängen“ aus 12 | docs/Technical-Pitfalls.md |
| 5, 6, 9 (Addon-Aufbau, Hub, Einstellungen) | docs/Hub.md |
| 7, 8, 10 (Design, Sprache, Verschieben) | docs/Design.md |
| 7.1 (Menü-Maße) | docs/Menues.md |
| 11 (Chatbefehle) | docs/Commands.md |
| 14 (Wechselwirkungen) | docs/Wechselwirkungen.md |
| 15 (Git) / 16 (Release) | docs/Workflow.md / docs/Release.md |
Neue Einzelheiten in `docs/` eintragen, hier nur Regeln.

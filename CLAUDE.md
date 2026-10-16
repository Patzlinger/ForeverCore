# Forever Core – gemeinsames Grundgerüst

Dieses Dokument gilt für alle, die an diesem Repository arbeiten (Menschen und Claude). Es beschreibt
Philosophie, Regeln, Design und Abläufe. Wenn etwas hier nicht steht: am bestehenden Code orientieren und nachfragen.
Änderungen an diesen Regeln immer hier eintragen (nicht nur lokal), damit alle denselben Stand haben.

## 1. Projekt und Philosophie
- **Forever Core**: schlanke, modulare Addons für *World of Warcraft: Forever*
- Leitsatz: **"Less clutter. More control. Just the essentials."**
  - Jedes Addon löst eine Aufgabe gut, funktioniert allein und passt sich optisch nahtlos in die Suite ein
  - Unaufdringlich: wenig Bildschirmfläche, kein Blinken, keine Spielereien; Infos bei Bedarf (Mouseover/Tooltip)
  - Sinnvolle Standardwerte: ein Addon muss ohne jede Einstellung brauchbar sein
  - Ersetzen statt überlagern: wenn ein Addon einen Blizzard-Teil ersetzt, wird der Blizzard-Teil taint-frei ausgeblendet
- Zielgruppe: Spieler, keine Programmierer – Texte kurz, klar, ohne Fachbegriffe
- Mitarbeiter sprechen teils kein Lua: **Änderungen immer kurz auf Deutsch erklären** (was, warum, was testen)

## 2. Team und Zuständigkeiten
| Addon | Verantwortlich | Status |
|---|---|---|
| ForeverFrames, ForeverUnits, ForeverCast, ForeverLoot, ForeverXP, ForeverBuffs, ForeverVendor | Patzlinger | im Release |
| ForeverSpellbook | Patzlinger | Prototyp |
| ForeverQuests | flowfy | im Repository, noch nicht im Release |
| ForeverBars | flowfy | im Repository, noch nicht im Release |
| `Shared/ForeverHub.lua`, `tools/`, `release/` | gemeinsam | – |

- Funktionale Änderungen an einem Addon des anderen nur nach Absprache. Triviale, gefahrlose Angleichungen
  (Schreibweise, .toc-Felder, Kommentare) sind erlaubt, im Commit kurz benennen.
- Wer ein Addon verantwortet, entscheidet über dessen Funktionen, Version und Lizenz.
- Entscheidungen, die alle Addons betreffen (Hub, Design, Regeln hier), gemeinsam treffen.

## 3. Zielclient und API
- WoW: Forever, `## Interface: 16001`; Basis ist die **Mainline/Retail-API (Stand 12.1.5)**, NICHT die Classic-API
  - Neue Namensräume nutzen (`C_AddOns`, `C_Spell`, `C_SpellBook`, `C_Container`, `C_CVar` …), mit Rückfall auf alte Funktionen, wo sinnvoll
- Midnight-Restriktionen ("secret values" im Kampf): keine Rechnungen/Vergleiche mit gesperrten Werten,
  Werte nur direkt weiterreichen (z. B. an StatusBars, Aura-Container); **keine Rotationslogik**
- SavedVariables funktionieren normal (wir gehen vom Live-Betrieb aus): Einstellungen werden gespeichert und beim
  Login geladen. Standardwerte trotzdem sinnvoll wählen (erster Start, neue Einstellungen nach einem Update)
- Forever-Namen haben Vor- und Nachnamen: Chat liefert evtl. "Vorname Nachname", die Gruppenliste nur den Vornamen –
  Namen abgleichen statt direkt vergleichen
- WoW-Schrift kennt "→" nicht (wird zum Kasten): in Anzeige-Texten "»" oder "–" verwenden; "≈ · – … —" funktionieren
- Namensplaketten sind "restricted regions": GetCenter/GetPoint usw. darauf sind verboten (Fehler + taint); Namen lesen geht
- Anvisieren (TargetUnit, /target) und SetRaidTarget nur über sichere Knöpfe auf Tastendruck, nie automatisch
- Geschützte Rahmen (Aktionsknöpfe, Einheitenrahmen, sichere Knöpfe) nur außerhalb des Kampfes anlegen, verschieben,
  vergrößern oder belegen: vorher `InCombatLockdown()` prüfen, Änderungen sonst bis `PLAYER_REGEN_ENABLED` aufschieben
- Fehler suchen: BugSack/BugGrabber, Datei `WTF\Account\*\SavedVariables\!BugGrabber.lua`

## 4. Taint vermeiden (wichtig!)
- Blizzard-Rahmen **nie** mit `:Hide()`, `:SetParent()` oder `:SetScript()` verändern ("taint" blockiert sonst z. B.
  Raid-Symbole im Menü oder geschützte Aktionen). Stattdessen:
  - `UnregisterAllEvents()` + `RegisterStateDriver(frame, "visibility", "hide")`, oder
  - unsichtbar machen: `SetAlpha(0)` und mit `hooksecurefunc(frame, "SetAlpha", …)` gegen Zurücksetzen absichern
    (so macht es ForeverXP mit der XP-Leiste – Platz und Anordnung der Blizzard-Leisten bleiben dabei erhalten)
- Blizzard-Funktionen nur mit `hooksecurefunc` bzw. `frame:HookScript` erweitern, nie überschreiben
- Dokumentierte Ausnahmen (bewusst so, nicht "reparieren" ohne Absprache):
  - **ForeverBars** setzt Blizzards Aktionsknöpfe und Leisten per `SetParent` in eigene Halter – das ist für ein
    Leisten-Addon nötig (Bartender4 macht es genauso); nur außerhalb des Kampfes, Sichtbarkeit über State-Driver
  - **ForeverQuests** blendet den Blizzard-Questtracker mit `:Hide()` aus (außerhalb des Kampfes, mit OnShow-Hook).
    Falls dadurch Taint-Meldungen auftauchen: auf das Alpha-/State-Driver-Verfahren umstellen
- Zwei Addons dürfen nicht denselben Blizzard-Teil "besitzen". Bekannte Berührungspunkte siehe Abschnitt 14.

## 5. Aufbau eines Addons
- Jedes Addon in eigenem Ordner im Repository-Wurzelverzeichnis, **.toc-Name = Ordnername**, Name `Forever<Name>`
- GUI in Lua bauen (`CreateFrame`, Retail-Templates), **kein XML** – einzige Ausnahme: `Bindings.xml` für Tastenkürzel
  (die verlangt WoW so)
- Pflicht in der .toc (Vorlage):
  ```
  ## Interface: 16001
  ## Title: ForeverName |cff8a8a8a(Beta)|r
  ## Notes: English description
  ## Notes-deDE: Deutsche Beschreibung
  ## IconTexture: Interface\AddOns\ForeverName\Media\ForeverCore
  ## Category: Forever Core
  ## Author: <Name>
  ## Version: <Version>
  ## SavedVariables: ForeverNameDB, ForeverHubDB

  ForeverHub.lua
  ... eigene Dateien ...
  ```
  - `ForeverHub.lua` wird **immer als erste Datei** geladen, `ForeverHubDB` steht immer in den SavedVariables
  - Der Titel trägt den dezenten Beta-Hinweis (nur in der Addon-Liste sichtbar)
  - `Media\ForeverCore.tga` (Logo) liegt in jedem Addon (Kopie z. B. aus ForeverXP)
  - Release-Addons zusätzlich: `## X-License: MIT`, `## X-Curse-Project-ID: 1743753`, `LICENSE.txt`
- Datei-Aufteilung frei; bewährt: `Core.lua` (Defaults, Start, Chatbefehl), `Locales.lua`, `Options.lua`, Funktionsdateien
- Neues Addon zusätzlich: in `Shared/ForeverHub.lua` in die Liste `KNOWN` eintragen (Name + Minimap-Knopf) und
  einmal `tools/link-addons.ps1` ausführen

## 6. ForeverHub (gemeinsame Bibliothek)
- `Shared/ForeverHub.lua` liegt als Kopie in jedem Addon; im Spiel arbeitet nur die Kopie mit der höchsten `VERSION`
- **Nur `Shared/ForeverHub.lua` bearbeiten**, dabei `VERSION` erhöhen, danach `tools/sync-hub.ps1` (verteilt die Datei
  in alle Addons, deren .toc `ForeverHub.lua` lädt). Alle Kopien im Repository müssen identisch sein.
- Erweiterungen müssen abwärtskompatibel sein (andere Addons rufen die Funktionen auf); Funktionen bei Bedarf mit
  `if UI.Funktion then … end` aufrufen
- Was der Hub kann:
  1. **Stil-Bibliothek** `ForeverHub.UI` (Zugriff: `local UI = ForeverHub.UI`):
     `T(de, en)`, `Chat(addon, text)`, `Window(name, title, w, h)`, `Header(parent, x, y, text, width)` (mit
     automatischem Abschnitts-Kasten), `Hint`, `Text(parent, "label"|"field", text)`, `Button(parent, text, w, onClick)`,
     `AddArrow`, `Check(parent, x, y, label, onClick)`, `Slider(...)`, `StyleSlider`, `EditBox`, `Number` (Zahlenfeld mit –/+),
     `ShowMenu`/`HideMenu`/`ChoiceMenu` (flache Auswahllisten), `MinimapButton(o)`, `Hud`, `Box`, `SetFlat`,
     `Grid`, `AddMover`, `BeginDrag`/`EndDrag` (Raster + Einrasten), `Round`, `CenterOffset`, `COLOR`, `LOGO`, `NAME`
  2. **Sammelknopf**: ab zwei Forever-Addons werden deren Minimap-Knöpfe ausgeblendet und in einer Liste am
     Forever-Core-Knopf gesammelt (Klick wird an den Original-Knopf weitergereicht)
  3. **Hub-Fenster** `/forever` (`/fhub`): alle installierten Forever-Addons mit "Öffnen"-Knopf ins jeweilige Menü,
     "Alle verschieben", Minimap-Knopf ein/aus, **Sprache für alle Forever-Addons**; `/forever reset` holt Knöpfe zurück
  4. **Gemeinsamer Verschiebe-Modus** `/fmove`: entsperrt/sperrt alle angemeldeten Addons auf einmal
  5. **Blizzard-Optionsmenü** (Esc » Optionen » Reiter "AddOns"): Eintrag "Forever Core" mit Übersicht und je
     Forever-Addon eine Unterseite mit "Einstellungen öffnen" (öffnet das eigene Fenster, Optionsmenü schließt sich).
     Automatisch für jedes Addon aus `KNOWN`, dessen Minimap-Knopf existiert; `/forever options` springt dorthin.
     Die eigentlichen Einstellungen bleiben in den eigenen Fenstern (keine zweite Einstellungs-Oberfläche bauen)
- Damit ein Addon voll eingebunden ist:
  - Minimap-Knopf **immer über `UI.MinimapButton({...})`** bauen, globaler Name `Forever<Name>MinimapButton`,
    **Linksklick öffnet das Menü**, Rechtsklick frei (meist: entsperren/sperren bzw. ein-/ausblenden); in `KNOWN`
    eintragen (Name, Knopf, Chatbefehl `cmd`) – damit erscheint es in Sammelknopf, Hub-Fenster und Blizzard-Optionsmenü.
    Die Vorlage bringt Aussehen, Ziehen um die Minimap und den Tooltip-Hinweis "Ziehen" mit
  - für `/fmove`: `UI.RegisterMovable("ForeverName", isLocked, setLocked)` – `isLocked()` liefert true/false,
    `setLocked(locked)` sperrt bzw. entsperrt (inkl. Menü aktualisieren). Addons mit eigener Stil-Datei melden sich
    in einer kleinen `HubLink.lua` an (siehe ForeverQuests/ForeverBars)

## 7. Design (verbindlich für alle Fenster)
Vorbild ist der flache Stil aus ForeverQuests; `ForeverHub.UI` und `Style.lua` (ForeverQuests/ForeverBars) setzen
ihn identisch um. Neue Oberflächen nutzen eine dieser beiden – keine dritten Stile.
- Farben (`UI.COLOR` = `ns.Style.COLOR`):
  | Name | RGBA | Verwendung |
  |---|---|---|
  | background | 0.07 0.07 0.09 0.97 | Fenster |
  | header | 0.11 0.11 0.14 1 | Titelleiste, aktiver Reiter |
  | panel | 0.10 0.10 0.12 0.95 | Abschnitts-Kästen, Listen |
  | border | 0.22 0.22 0.26 1 | 1-px-Ränder |
  | input | 0.06 0.06 0.08 1 | Eingabefelder, Häkchen-Kästchen |
  | button / buttonHover | 0.16 0.16 0.20 / 0.22 0.22 0.27 | Knöpfe |
  | accent (Gold) | 1 0.82 0 | **einzige Akzentfarbe**: Hover-Rand, Häkchen, Regler, Titellinie, Überschriften |
- Fenster: flach und dunkel, 1-px-Rand, Titelleiste mit Logo + Titel + Schließen-Kreuz und goldener Linie unten,
  verschiebbar an der Titelleiste, mit Escape schließbar (`UISpecialFrames`)
- Einstellungen in Abschnitte gliedern: goldene Überschrift + dezenter Kasten darum; Reiter, wenn es viele sind
- Bedienelemente: flache Knöpfe (Hover = goldener Rand), Häkchen als kleines Kästchen mit goldener Füllung
  (Klick auf den Text zählt mit), Regler als dünne Leiste mit goldenem Griff, Auswahllisten als flache Liste mit Pfeil
- Tooltips kurz; eigene Tooltips im gleichen Stil (dunkel, goldene Linie oben)
- Minimap-Knopf: runder Standard-Look (31 px, Tracking-Rand), ziehbar um die Minimap
- Anzeigen im Spiel (Leisten, Balken, Symbole): dezent, eher klein, halbtransparente dunkle Flächen, keine Blizzard-Schnörkel
- Chat-Ausgabe: `Addonname: Text`, Name in Gold `|cffffcc00` (wie `UI.Chat`), sparsam (nur Bestätigungen und Fehlerhinweise)
- Schrift: Standardschriften des Clients (`STANDARD_TEXT_FONT`, `GameFont*`); Zeichen siehe Abschnitt 3

## 8. Sprache
- Jede sichtbare Zeichenkette zweisprachig: **Deutsch und Englisch**
- **Eine Sprachwahl für alle** (im Hub-Fenster `/forever`, gespeichert in `ForeverHubDB.language`):
  Deutsch gibt es nur auf einem deutschen Client, dort kann man auf Englisch umstellen; sonst immer Englisch.
  Abfrage: `UI.GetLanguage()` → `"deDE"`/`"enUS"`. Wirkt nach `/reload` (ForeverQuests wechselt sofort)
  - Für die Anzeigesprache fragt kein Addon `GetLocale()` selbst ab, sondern den Hub (`UI.T`, `UI.GetLanguage`);
    `GetLocale()` nur dort, wo es um die Sprache der Spieldaten geht (z. B. Questnamen vergleichen)
  - Eigene Sprachauswahl in einem Addon-Menü (wie bei ForeverQuests) muss in `ForeverHubDB.language` schreiben
- Zwei erlaubte Wege für Texte: `T("Deutsch", "English")` aus dem Hub (Patzlingers Addons) oder `Locales.lua` mit
  Schlüsseln und `ns.L("KEY")` (flowfys Addons), das die Sprache über `UI.GetLanguage()` bestimmt. Innerhalb eines
  Addons nur einen Weg nutzen- Kommentare im Code auf Deutsch, kurz, erklären das *Warum*; Umlaute in Kommentaren sind erlaubt

## 9. Einstellungen
- Eine SavedVariable pro Addon (`Forever<Name>DB`), bei Bedarf zusätzlich pro Charakter (`…CharDB`)
- Defaults in einer Tabelle; beim Laden (`ADDON_LOADED`) fehlende Werte ergänzen (auch verschachtelt), Tabellen
  kopieren (`CopyTable`) – so bekommen auch Spieler mit älteren gespeicherten Einstellungen neue Optionen
- Gespeicherte Werte erst nach `ADDON_LOADED` lesen (beim Ausführen der Addon-Dateien sind sie noch nicht da)
- Ändert sich die Bedeutung einer Einstellung, alte Werte beim Laden umrechnen statt sie stillschweigend zu verwerfen
  (Beispiel: ForeverBars wandelt die frühere Sichtbarkeit "MOUSEOVER" um)
- Einstellungen wirken sofort (kein "Übernehmen"-Knopf), ein "Zurücksetzen" pro Bereich ist gern gesehen
- Blizzard-Einstellungen (CVars, Tastenbelegung) nur auf ausdrücklichen Wunsch des Spielers ändern

## 10. Verschieben und Positionen
- Entsperren per Menü, Rechtsklick auf den Minimap-Knopf oder `/fmove`; Ziel für neue Addons: standardmäßig gesperrt
  (ältere Addons noch nicht überall so)
- Entsperrt: sichtbarer Griff mit Namen, Ziehen mit Raster/Einrasten, **Shift = frei schieben**; X/Y-Felder im Menü
- Positionen relativ zu einem festen Bezugspunkt (Bildschirmmitte oder -rand) speichern und auf ganze Pixel runden

## 11. Chatbefehle
- Jedes Addon: kurze Form `/f<kürzel>` und lange Form `/forever<name>`; ohne Zusatz öffnet sich das Menü
- Gemeinsame Zusätze (wo sinnvoll): `move`/`lock`, `reset`, `status`
- Belegt (keine Doppelungen!):
  | Befehl | Addon |
  |---|---|
  | /forever, /fhub, /fmove | ForeverHub |
  | /ff, /foreverframes | ForeverFrames |
  | /fu, /foreverunits | ForeverUnits |
  | /fcast, /forevercast | ForeverCast |
  | /fb, /foreverbars | ForeverBars |
  | /fq, /foreverquests | ForeverQuests |
  | /floot, /foreverloot | ForeverLoot |
  | /fxp, /foreverxp | ForeverXP |
  | /fbuffs, /foreverbuffs | ForeverBuffs |
  | /fvendor, /forevervendor | ForeverVendor |
  | /fsb, /fspellbook, /foreverspellbook | ForeverSpellbook |
- Tastenkürzel über `Bindings.xml` + `BINDING_HEADER_…`/`BINDING_NAME_…` (Bereich "AddOns")

## 12. Code-Stil
- Einfach und lesbar vor clever; Code wie der umliegende schreiben (Namen, Kommentardichte, Muster)
- Addon-Namensraum: `local addonName, ns = ...`; globale Namen nur für Rahmen (`Forever<Name>…`) und Pflicht-Globale
  (SavedVariables, `SLASH_…`, `BINDING_…`)
- Ereignis-Code absichern, damit ein Fehler nicht das ganze Addon stoppt (`pcall` + `geterrorhandler()`), wo sinnvoll
- Ticker/OnUpdate sparsam; teure Arbeit bündeln (z. B. `C_Timer.After(0, …)` statt mehrfach pro Frame)
- Keine Abhängigkeiten zu fremden Bibliotheken (Ace3, LibStub …) – optional erkennen ist ok (z. B. LibSharedMedia)
- Nur eigene Forever-Addons im Repository; keine SavedVariables, keine fremden Addons, keine gebauten Zips

## 13. Testen
- Syntax-Check vor jedem Commit: `lua-language-server --check <ordner> --checklevel=Error`
  (die VS-Code-Erweiterung "Lua" bringt ihn mit; WoW-Globale als "undefined global" sind normal)
- Im Spiel: `/reload`, BugSack prüfen, **auch im Kampf testen** (secret values, geschützte Rahmen)
- Bei Änderungen am Hub: mindestens zwei Forever-Addons gleichzeitig aktiv testen (Sammelknopf, /forever, /fmove)
- Nach jeder Änderung kurz notieren, was der Mitarbeiter im Spiel prüfen soll

## 14. Bekannte Wechselwirkungen
- **ForeverBars ↔ ForeverXP**: ForeverBars setzt die Blizzard-XP-Leiste (`MainStatusTrackingBarContainer`) in
  seinen Halter "xp"; ForeverXP macht sie unsichtbar (Alpha 0) und legt seinen Balken genau darüber – der
  ForeverXP-Balken folgt also der Position, die man in ForeverBars für "Erfahrung" einstellt
- **ForeverBars ↔ ForeverSpellbook**: ForeverSpellbook legt einen Klick-Knopf über den Zauberbuch-Knopf im
  Mikromenü; ForeverBars verschiebt das Mikromenü – der Knopf hängt am Mikromenü-Knopf und wandert mit
- **ForeverBars ↔ Bartender4**: läuft Bartender4, lässt ForeverBars die Leisten in Ruhe
- **ForeverQuests**: ersetzt den Blizzard-Questtracker

## 15. Git-Ablauf
- Vor dem Arbeiten: `git pull --ff-only` (bzw. `git pull --rebase`, wenn lokal schon Commits liegen)
- Während der Arbeit am Live-Ordner (AddOns-Verknüpfung = dieses Repository) NICHT automatisch pushen
- Fertige Änderungen lokal committen (kurze deutsche Nachricht, was und warum) ist erlaubt
- `git push` nur auf ausdrückliches Kommando des Nutzers oder am Ende einer Session (dann kurz nachfragen bzw. ankündigen)
- Bei Konflikten oder unerwarteten Änderungen des anderen erst nachfragen; nie force-pushen
- Größere Umbauten auf einem eigenen Zweig + Pull Request
- Installieren über die CurseForge-App überschreibt die verknüpften Ordner = das Repository → danach `git status`,
  ggf. `git restore .`

## 16. Release
- `release/addons.txt` = Addons im Release; Prototypen (z. B. ForeverSpellbook) erst nach Freigabe eintragen
- Alle Release-Addons tragen dieselbe `## Version` (Suite-Version, z. B. `0.3b`); `tools/build-release.ps1` prüft das
- Alle Release-.toc: `## Title: <Addon> |cff8a8a8a(Beta)|r`, `## X-Curse-Project-ID: 1743753`, `## X-License: MIT`
- `release/README.txt` (DE/EN, kommt ins Gesamt-Zip) bei neuen Befehlen/Funktionen anpassen
- `release/Changelog-CurseForge.txt` = Englisch, für Spieler geschrieben; wandert nicht ins Zip
- Bauen mit `tools/build-release.ps1` (Hub-Abgleich, Versionsprüfung, Addon-Ordner, Einzel-Zips, Gesamt-Zip);
  fremde Zips im Zielordner werden nie angefasst

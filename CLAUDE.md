# Forever Core UI – gemeinsames Grundgerüst

Dieses Dokument gilt für alle, die an diesem Repository arbeiten (Menschen und Claude). Es beschreibt
Philosophie, Regeln, Design und Abläufe. Wenn etwas hier nicht steht: am bestehenden Code orientieren und nachfragen.
Änderungen an diesen Regeln immer hier eintragen (nicht nur lokal), damit alle denselben Stand haben.

**Bekannte Fehler:** [KNOWN-BUGS.md](KNOWN-BUGS.md). Wird gerade nichts Bestimmtes entwickelt oder gefragt, was es
noch zu tun gibt: zuerst dort nachsehen und einen offenen Fehler vorschlagen. Neue, nicht sofort behobene Fehler dort
eintragen; behobene mit Datum und Ursache nach „Erledigt“ verschieben.

**Ausgelagerte Details** (nur bei Bedarf lesen, damit diese Datei kurz bleibt): [docs/Hub.md](docs/Hub.md) (alle
Hub-Funktionen, Einstellungs-Verwaltung), [docs/Menues.md](docs/Menues.md) (Maße der Einstellungsfenster),
[docs/Wechselwirkungen.md](docs/Wechselwirkungen.md) (Addons untereinander, Blizzard, Questie, Details …),
[docs/Fenster-Stil.md](docs/Fenster-Stil.md) (Stilregeln für umgestaltete Blizzard-Fenster in ForeverSkin – **vor jedem
neuen Fenster lesen und beim ersten Versuch anwenden**).
Neue Einzelheiten dort eintragen, hier nur Regeln.

## 1. Projekt und Philosophie
- **Forever Core UI**: schlanke, modulare Addons für *World of Warcraft: Forever*
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
| ForeverFrames, ForeverUnits, ForeverCast, ForeverHelpers (Module Loot, Buffs, Vendor) | Patzlinger | im Release |
| ForeverSpellbook | Patzlinger | im Release (seit 0.32b) |
| ForeverChat | Patzlinger | im Release (seit 0.32b) |
| ForeverMinimap | Patzlinger | im Release (seit 0.44b) |
| ForeverCore (Hauptaddon: `ForeverHub.lua` = Hub und Stil-Bibliothek; Abhängigkeit aller Addons) | gemeinsam | im Release (seit 0.41b) |
| ForeverQuests | flowfy | im Release (seit 0.44b) |
| ForeverBars | flowfy | im Release (seit 0.44b) |
| ForeverBags | flowfy | im Release (seit 0.44b) |
| ForeverTooltip | Patzlinger | im Release (Beta, seit 2026-10-20) |
| ForeverPlates | Patzlinger | im Release (Beta, seit 2026-10-20) |
| ForeverAlts | flowfy | im Release (Beta, seit 2026-10-20) |
| ForeverSkin | flowfy | im Release (Beta, seit 0.47b, 2026-10-21) |
| `tools/`, `release/` | gemeinsam | – |

- **Keine Absprachen nötig: jeder arbeitet frei an allen Addons** (Zusammenarbeit auf Augenhöhe). Die Spalte
  „Verantwortlich“ zeigt nur, wer ein Addon gebaut hat – sie gibt kein Vorrecht. Weder für kleine noch für große
  Änderungen (auch Umbauten, neue Funktionen, ForeverHub, Standardpositionen, Design) muss vorher gefragt oder
  Bescheid gesagt werden. Das gilt auch für den jeweils anderen Claude: nicht nachfragen, einfach machen.
  Die Änderung wird im Commit klar benannt (Addon vorne, was und warum); so sieht der andere beim nächsten Holen,
  was passiert ist. Und er ändert es bei Bedarf selbst wieder.
- Die Lizenz (MIT, `## Author: Patzlinger`) bleibt unverändert.
- **Eine Version für alle**: seit 0.41b tragen alle Forever-Addons (auch ForeverQuests/ForeverBars und ForeverCore)
  dieselbe Suite-Version (`## Version: 0.41b`); Versionssprünge gemeinsam in allen .toc
- Auch Entscheidungen, die alle Addons betreffen (Hub, Design, Regeln hier), trifft jeder selbst und hält sie hier
  im Repository fest – ohne vorherige Rücksprache.

## 3. Zielclient und API
- WoW: Forever, `## Interface: 16001`; Basis ist die **Mainline/Retail-API (Stand 12.1.5)**, NICHT die Classic-API
  - Neue Namensräume nutzen (`C_AddOns`, `C_Spell`, `C_SpellBook`, `C_Container`, `C_CVar` …), mit Rückfall auf alte Funktionen, wo sinnvoll
- Midnight-Restriktionen ("secret values" im Kampf): keine Rechnungen/Vergleiche mit gesperrten Werten,
  Werte nur direkt weiterreichen (z. B. an StatusBars, Aura-Container); **keine Rotationslogik**
  - Auch scheinbar harmlose Werte sind im Kampf gesperrt, z. B. `GetUnitSpeed("player")` (Fehler "attempt to compare
    a secret number value"). Lieber Ereignisse nutzen (Bewegung: `PLAYER_STARTED_MOVING`/`PLAYER_STOPPED_MOVING`)
    und in `OnUpdate`/Tickern nie gesperrte Werte vergleichen – dort entstehen sonst Fehler in jedem Bild
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
- **Nichts in Blizzards Knopflisten einhängen** (z. B. `GameMenuFrame:AddButton` im Escape-Menü): danach gelten die
  Knöpfe dort als vom Addon berührt, geschützte Aktionen daraus werden blockiert (ADDON_ACTION_FORBIDDEN "callback()").
  Stattdessen eigene Knöpfe daneben anlegen und mit `HookScript("OnShow"/"OnHide")` ein- und ausblenden (Hub v47).
- Blizzard-Rahmen **nie** mit `:Hide()`, `:SetParent()` oder `:SetScript()` verändern ("taint" blockiert sonst z. B.
  Raid-Symbole im Menü oder geschützte Aktionen). Stattdessen:
  - `UnregisterAllEvents()` + `RegisterStateDriver(frame, "visibility", "hide")`, oder
  - unsichtbar machen: `SetAlpha(0)` und mit `hooksecurefunc(frame, "SetAlpha", …)` gegen Zurücksetzen absichern
    (so macht es ForeverBars mit Blizzards Erfahrungs- und Rufleiste – Platz und Anordnung bleiben dabei erhalten)
- Blizzard-Funktionen nur mit `hooksecurefunc` bzw. `frame:HookScript` erweitern, nie überschreiben
- Dokumentierte Ausnahmen (bewusst so, nicht "reparieren" ohne Absprache):
  - **ForeverBars** setzt Blizzards Aktionsknöpfe und Leisten per `SetParent` in eigene Halter – das ist für ein
    Leisten-Addon nötig (Bartender4 macht es genauso); nur außerhalb des Kampfes, Sichtbarkeit über State-Driver
  - **ForeverQuests** blendet den Blizzard-Questtracker mit `:Hide()` aus (außerhalb des Kampfes, mit OnShow-Hook,
    Wiederholung nach dem Kampf über `UI.AfterCombat`). `UI.HideBlizzard` passt hier NICHT: der Tracker enthält
    geschützte Questgegenstand-Knöpfe, die unsichtbar anklickbar blieben. Falls Taint-Meldungen auftauchen:
    `RegisterStateDriver(ObjectiveTrackerFrame, "visibility", "hide")` im Spiel testen
  - **ForeverBags** macht Blizzards Taschenfenster (`ContainerFrameCombinedBags`, `ContainerFrame1…`) in deren
    `OnShow` per `:Hide()` wieder zu (nur mit Einstellung "Blizzards Taschenfenster ersetzen"). Sie sind keine
    geschützten Rahmen; `UI.HideBlizzard` passt nicht (die Taschenplätze blieben unsichtbar anklickbar). Öffnen/Schließen
    wird nur per `hooksecurefunc` auf `ToggleAllBags`/`OpenAllBags`/`CloseAllBags` … mitgehört, nie überschrieben.
    Die eigenen Taschenplätze sind Blizzards `ContainerFrameItemButtonTemplate` (Elternrahmen mit `SetID(Tasche)`,
    Knopf mit `SetID(Platz)`) – Benutzen, Ziehen, Verkaufen und Tooltip erledigt damit Blizzard selbst
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
  ## Category: Forever Core UI
  ## Author: <Name>
  ## Version: 0.44b
  ## Dependencies: ForeverCore
  ## Group: ForeverCore
  ## SavedVariables: ForeverNameDB, ForeverHubDB

  ... eigene Dateien ...
  ```
  - `## Group: ForeverCore`: in Blizzards Addon-Liste eingerückt unter "Forever Core UI" (wie AtlasLoot); Blizzard setzt das
    nur bei gleichem Namensanfang automatisch, deshalb ausdrücklich eintragen
  - `## Dependencies: ForeverCore`: ForeverCore lädt garantiert vorher, `ForeverHub.UI` steht ab der ersten Zeile bereit.
    **Keine eigene Kopie von `ForeverHub.lua`** mehr ins Addon legen
  - `ForeverHubDB` steht vorerst weiter in den SavedVariables jedes Addons (Übergang: so übernehmen Spieler ihre
    Hub-Einstellungen aus den alten Speicherständen; kann später auf ForeverCore allein reduziert werden)
  - Der Titel trägt den dezenten Beta-Hinweis (nur in der Addon-Liste sichtbar)
  - `Media\ForeverCore.tga` (Logo) liegt in jedem Addon (Kopie z. B. aus ForeverBars)
  - Eigenes Addon-Logo: `Media\ForeverName.tga` (64 × 64, 32 Bit TGA) – steht in `## IconTexture` und im
    Minimap-Knopf; die Kacheln der Übersicht nehmen das Logo aus der .toc
  - Release-Addons zusätzlich: `## X-License: MIT`, `## X-Curse-Project-ID: 1743753`, `LICENSE.txt`
- Datei-Aufteilung frei; bewährt: `Core.lua` (Defaults, Start, Chatbefehl), `Locales.lua`, `Options.lua`, Funktionsdateien
- Neues Addon zusätzlich: in `ForeverCore/ForeverHub.lua` in die Liste `KNOWN` eintragen (Name + Minimap-Knopf) und
  einmal `tools/link-addons.ps1` ausführen

## 6. ForeverHub (gemeinsame Bibliothek)
- Der Hub liegt **nur einmal**: `ForeverCore/ForeverHub.lua` (seit 0.41b). Bei Änderungen `VERSION` erhöhen.
  Gemeinsames gehört in den Hub; Erweiterungen abwärtskompatibel, Aufrufe bei Bedarf mit `if UI.Funktion then`.
- Wichtigste Regeln (Details, Funktionsliste, Sammelknopf, Hub-Fenster: **docs/Hub.md**):
  - `local UI = ForeverHub.UI`; Stil-Bausteine `T`, `Chat`, `Window`, `Header`, `Check`, `Slider`, `Button`, `ChoiceMenu`, `MinimapButton` …
  - Einstellungen als Seite im zentralen Fenster: `UI.SettingsPanel(name, titel, w, h, { key, group, label })`
  - Wiederkehrendes nur über `UI.Every(sekunden, fn, { addon, name, when })` (kein eigener Dauer-Ticker)
  - `UI.AfterCombat("Addon:schlüssel", fn, addon)` – **zuerst der Schlüssel**; `UI.HideBlizzard` / `UI.ShowBlizzard`
  - Addons rufen sich nur über `UI.API.<Addon>` auf; Nachrichten mit `UI.On` / `UI.Fire`
  - Spielernamen nur für Spieler mit `UI.PlayerName(name)` kürzen; Fehler über `UI.ReportError` / `UI.Safe`
  - Minimap-Knopf über `UI.MinimapButton`, in `KNOWN` eintragen; `/fmove` über `UI.RegisterMovable`

## 7. Design (verbindlich für alle Fenster)
Vorbild ist der flache Stil aus ForeverQuests; `ForeverHub.UI` und `Style.lua` (ForeverQuests/ForeverBars) setzen
ihn identisch um. Neue Oberflächen nutzen eine dieser beiden – keine dritten Stile.
- **Einstellungen = Seite im zentralen Fenster** (Hub v45, "3c" in ForeverHub.lua): UI.SettingsPanel(name, titel, w, h,
  { key = Addonname, group = UI.SETTINGS_GROUPS.frames|bars|nav|comfort|helpers, label, kind = nil|"menu" }) statt
  UI.Window/Style.CreateWindow/UI.MenuWindow. Feste Fenstergröße 176 + 720 × 832 (größtes Einzelfenster ForeverBars).
  Die Seite bringt ihre alte Titelleiste mit (26 bzw. 40 hoch) und verhält sich wie das alte Fenster (:Show/:Hide/
  :SetShown/:IsShown öffnen bzw. schließen das große Fenster auf dieser Seite). Wer sein Fenster erst beim ersten Öffnen
  baut, meldet beim Laden UI.RegisterSettingsLink({ key, group, label, open }) an. Inhalt 1:1 (siehe 7.1, Lehren).
- **Eine Quelle für Farben:** Style.COLOR in ForeverBars/ForeverQuests IST die Tabelle UI.COLOR aus ForeverCore
  (seit 2026-10-18; das Dungeonfenster ergänzt nur eigene Kartenfarben per Metatabelle). Farbtöne nur im Hub ändern,
  die Tabelle nie aus einem Addon heraus verändern. Fenster, Positionen und Menüs der Addons bleiben eigenständig.
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
- **Fenster-Stapel**: Jedes Fenster meldet sich mit `UI.RegisterWindow(f)` an (`UI.Window`/`UI.MenuWindow` tun das
  selbst, `Style.CreateWindow` in ForeverQuests/ForeverBars ebenfalls). Das zuletzt geöffnete oder angeklickte
  Forever-Fenster liegt dann über allen anderen – addonübergreifend, ohne dass sich Bedienelemente verzahnen.
  Eigene Fenster nicht per `SetFrameLevel` festnageln (sonst greift der Stapel nicht)
- **Fenstergröße mit der Maus**: jedes benannte `UI.Window` bekommt automatisch einen Griff unten rechts
  (Skalieren 60–160 %, Rechtsklick = Standard, gespeichert in `ForeverHubDB.windows`). Fenster, deren Inhalt
  mitwachsen kann (z. B. ForeverSpellbook), nutzen `UI.MakeResizable(f, { mode = "size", minW, minH, maxW, maxH })`
  und ordnen ihren Inhalt bei `OnSizeChanged` neu an. Die untere rechte Ecke (ca. 16 px) frei lassen
- Platz für Deutsch einplanen: deutsche Texte sind oft 30–40 % länger als englische – Spalten und Beschriftungen
  mit der deutschen Fassung prüfen, nicht mit der englischen
- Einstellungen in Abschnitte gliedern: goldene Überschrift + dezenter Kasten darum; Reiter, wenn es viele sind
- Bedienelemente: flache Knöpfe (Hover = goldener Rand), Häkchen als kleines Kästchen mit goldener Füllung
  (Klick auf den Text zählt mit), Regler als dünne Leiste mit goldenem Griff, Auswahllisten als flache Liste mit Pfeil
- Tooltips kurz; eigene Tooltips im gleichen Stil (dunkel, goldene Linie oben)
- Minimap-Knopf: runder Standard-Look (31 px, Tracking-Rand), ziehbar um die Minimap
- Anzeigen im Spiel (Leisten, Balken, Symbole): dezent, eher klein, halbtransparente dunkle Flächen, keine Blizzard-Schnörkel
- Chat-Ausgabe: `Addonname: Text`, Name in Gold `|cffffcc00` (wie `UI.Chat`), sparsam (nur Bestätigungen und Fehlerhinweise)
- Schrift: Standardschriften des Clients (`STANDARD_TEXT_FONT`, `GameFont*`); Zeichen siehe Abschnitt 3

### 7.1 Menü-Aufbau im Detail
Maße, Raster, Bedienelemente, Fußleiste und Lehren aus früheren Umbauten: **docs/Menues.md** (vor jedem neuen oder
umgebauten Einstellungsfenster lesen).

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
  Addons nur einen Weg nutzen
- Kommentare im Code auf Deutsch, kurz, erklären das *Warum*; Umlaute in Kommentaren sind erlaubt

## 9. Einstellungen
- Jedes Addon meldet seine SavedVariable mit `UI.RegisterSettings({ addon, sv, defaults, version, … })` an:
  Profile je Charakter, Versionen/Migration, Export/Import, Zurücksetzen macht dann der Hub (Details: **docs/Hub.md**)
- Schlüssel mit `_` sind reserviert (nie ins Profil); die Tabelle nie ersetzen oder leeren; Charakter-Daten in `…CharDB`
- Defaults beim Laden ergänzen (Tabellen kopieren); gespeicherte Werte erst nach `ADDON_LOADED` lesen;
  geänderte Bedeutungen beim Laden umrechnen; Einstellungen wirken sofort
- Blizzard-Einstellungen (CVars, Tastenbelegung) nur auf ausdrücklichen Wunsch ändern und alte Werte merken

## 10. Verschieben und Positionen
- Alle Rahmen starten **gesperrt**; entsperren per Menü, Rechtsklick auf den Minimap-Knopf oder `/fmove`
- Entsperrt: sichtbarer Griff mit Namen, Ziehen mit Raster/Einrasten, **Shift = frei schieben**; X/Y-Felder im Menü
- Positionen relativ zu einem festen Bezugspunkt (Bildschirmmitte oder -rand) speichern und auf ganze Pixel runden
- **Einrasten gilt für ALLE verschiebbaren Forever-Fenster** (seit Hub v36) und über Addons hinweg:
  - Jeder Rahmen, an dem andere einrasten sollen, meldet sich mit `UI.AddMover(frame)` an (nur sichtbare zählen).
  - Beim Ziehen `UI.BeginDrag(frame, { snap, grid, edges })`, am Ende `local dx, dy = UI.EndDrag()` und die Position
    um (dx, dy) verschieben (Muster: ForeverCast, ForeverBuffs, ForeverLoot). Rahmen, die sich beim Ziehen selbst
    nachführen (ForeverBars), holen den Versatz live mit `UI.SnapOffset()` (Halter vorher auf die Mausposition setzen).
  - Umschalt beim Ziehen = nicht einrasten; globaler Schalter: Übersicht „Einrasten beim Verschieben“ bzw.
    `/fmove snap` (`ForeverHubDB.noSnap`, `UI.SnapEnabled()`); zusätzlich hat ein Addon ggf. eine eigene Option `snap`.
  - Neue verschiebbare Fenster **müssen** das einbauen; Minimap und Hauptchat (Bearbeitungsmodus) sind nur Ziele.

## 11. Chatbefehle
- Jedes Addon: kurze Form `/f<kürzel>` und lange Form `/forever<name>`; ohne Zusatz öffnet sich das Menü
- Gemeinsame Zusätze (wo sinnvoll): `move`/`lock`, `reset`, `status`
- Belegt (keine Doppelungen!):
  | Befehl | Addon |
  |---|---|
  | /forever, /fhub, /fmove; /forever profile, export, import, options, reset | ForeverHub |
  | /ff, /foreverframes | ForeverFrames |
  | /fu, /foreverunits | ForeverUnits |
  | /fcast, /forevercast | ForeverCast |
  | /fb, /foreverbars | ForeverBars |
  | /fq, /foreverquests | ForeverQuests |
  | /floot, /foreverloot | ForeverLoot |
  | /fxp, /foreverxp | ForeverBars (Erfahrungsleiste; früher ForeverXP) |
  | /fbuffs, /foreverbuffs | ForeverBuffs |
  | /fvendor, /forevervendor | ForeverVendor |
  | /fhelp, /foreverhelpers | ForeverHelpers (Einstellungen der Helfer) |
  | /fsb, /fspellbook, /foreverspellbook | ForeverSpellbook |
  | /fchat, /foreverchat | ForeverChat |
  | /fmm, /foreverminimap | ForeverMinimap |
  | /fbags, /foreverbags | ForeverBags |
  | /ftip, /forevertooltip | ForeverTooltip |
  | /fplates, /foreverplates | ForeverPlates (`/fplates skin` = Forever-Rahmen an/aus) |
  | /falts, /foreveralts | ForeverAlts |
  | /fskin | ForeverSkin |
- Tastenkürzel über `Bindings.xml` + `BINDING_HEADER_…`/`BINDING_NAME_…` (Bereich "AddOns")

## 12. Code-Stil
- Einfach und lesbar vor clever; Code wie der umliegende schreiben (Namen, Kommentardichte, Muster)
- Addon-Namensraum: `local addonName, ns = ...`; globale Namen nur für Rahmen (`Forever<Name>…`) und Pflicht-Globale
  (SavedVariables, `SLASH_…`, `BINDING_…`)
- Ereignis-Code absichern, damit ein Fehler nicht das ganze Addon stoppt (`pcall` + `geterrorhandler()`), wo sinnvoll
- Ticker/OnUpdate sparsam: wo Blizzard ein Ereignis liefert, das Ereignis nehmen; Timer nur für Dinge ohne Ereignis
  (Reichweite, verstrichene Zeit) bzw. als seltene Sicherheitsprüfung (≥ 5 s). Mehrere Anlässe kurz hintereinander
  bündeln (`C_Timer.After(0.3, …)` mit "schon geplant"-Merker)
- Blizzard-Rahmen umhängen (`SetParent`, nur mit dokumentierter Ausnahme wie ForeverBars): vorher im Blizzard-Code
  prüfen, ob er Funktionen am Elternrahmen aufruft (Beispiel: die Status-Leisten rufen
  `self:GetParent():CheckForLayoutChange()` auf). Solche Rahmen **nicht umhängen**, sondern nur per `SetPoint` an
  den eigenen Halter anlegen: Eine eigene Ersatz-Funktion am Halter wäre Addon-Code, den Blizzard dann aufruft –
  danach läuft Blizzards Code "getaintet" weiter (Beispiel: Fehler mit gesperrten Werten in
  `CompactUnitFrame_UpdateHealthColor` beim Öffnen des Bearbeitungsmodus, behoben in ForeverBars 0.13.0).
  Allgemein: nie eigene Funktionen oder Werte in Tabellen legen, die Blizzard-Code liest. Quelltext des
  Forever-Clients: github.com/Gethe/wow-ui-source, Zweig **forever**
- Keine Abhängigkeiten zu fremden Bibliotheken (Ace3, LibStub …) – optional erkennen ist ok (z. B. LibSharedMedia)
- Nur eigene Forever-Addons im Repository; keine SavedVariables, keine fremden Addons, keine gebauten Zips

## 13. Testen
- **Prüflauf vor jedem Commit:** `pwsh -File tools/check.ps1` (nur geänderte Addons; `-All` = alle). Prüft Syntax,
  eigene Funktionen außerhalb ihrer Sichtbarkeit, .toc gegen Dateien, Luas 200-Variablen-Grenze, `UI.AfterCombat`-
  Aufrufe und fehlende ForeverQuests-Texte. Bei "FEHLER" nicht committen. Braucht die VS-Code-Erweiterung "Lua".
- Neue Datei in einer .toc: im Spiel **kompletter Neustart** (kein /reload) – dem Nutzer sagen
- Im Spiel: `/reload`, BugSack prüfen, **auch im Kampf testen** (secret values, geschützte Rahmen)
- Bei Änderungen am Hub: mindestens zwei Forever-Addons gleichzeitig aktiv testen (Sammelknopf, /forever, /fmove)
- Nach jeder Änderung kurz notieren, was der Mitarbeiter im Spiel prüfen soll

## 14. Bekannte Wechselwirkungen
Alle Einzelheiten: **docs/Wechselwirkungen.md** – vor jeder Änderung lesen, die etwas anfasst, das auch ein anderes
Addon oder Blizzard benutzt. Kurz die verbindlichen Punkte:
- **Zugriff auf andere Addons nur mit Erlaubnis** (Lizenz/API prüfen, nur zur Laufzeit lesen, nie kopieren);
  Questie/QuestieDB geprüft und erlaubt (GPLv3, API), Interna nur mit pcall
- **Dungeondaten von ForeverQuests nur aus Spiel und Questie** – keine eigene Tabelle anlegen oder vorschlagen
- Blizzard-Vorlagen mit fester Rahmenebene liegen hinter Hub-Fenstern (`SetFixedFrameLevel(false)`)
- Konkurrenz-Addons über ConflictDefs/LeatrixDefs im Hub; Details nur über InstallSkin/Profile, Details-Ordner nie ändern
- Themen dort: Leisten/Bearbeitungsmodus, Minimap/Mikromenü/Tracker, Taschen, Chat (besonders geschützt), XP/Ruf, Masque

## 15. Git-Ablauf (seit 2026-10-17: gleichzeitig arbeiten über `development`)
Patzlinger und flowfy arbeiten zeitgleich, jeder mit seinem eigenen Claude. Damit keiner auf den anderen warten muss,
gilt für **beide** (und deren Claude) genau dieser Ablauf:

**Zweige**
- `development` = gemeinsamer Arbeitszweig. **Hier wird gearbeitet**, committet und gepusht – immer.
- `main` = nur veröffentlichte Stände (je Release ein Tag `v0.xxb`). Auf `main` wird nie direkt gearbeitet; `main`
  wird nur beim Release gepusht (siehe 16).
  - Ausnahme nur auf ausdrückliches Kommando des Nutzers: `development` komplett nach `main` übernehmen, ohne Tag,
    Zip und Changelog-Umbenennung (`git push origin development:main`, nur als Fast-Forward). Zuletzt 2026-11-05
    (Stand nach dem Live-Start, auf Wunsch von flowfy); der nächste Release-Tag kommt dann wie gewohnt obendrauf.
- Optional `feature/<name>` (von `development` abgezweigt) für große, mehrtägige Umbauten, die `development` sonst
  unspielbar machen würden; fertig → in `development` übernehmen (`git merge --no-ff`), Zweig löschen.
- Das Repository ist der Live-Ordner (Junctions in AddOns): ein Zweigwechsel ändert sofort, was im Spiel geladen wird
  → danach `/reload`.

**Sitzungsbeginn**
- `tools/session-sync.ps1` als SessionStart-Hook (in der lokalen `.claude/settings.json` des AddOns-Ordners) erledigt:
  holen, auf `development` wechseln (wenn sauber), eigene Commits per `pull --rebase --autostash` hinter die neuen des
  anderen hängen, Stand in einer Zeile melden. Meldet es einen Konflikt oder falschen Zweig: erst das klären.
- Ohne Hook von Hand: `git switch development` und `git pull --rebase --autostash`.
- **Automatischer Abgleich (empfohlen, je Rechner einmal):** `pwsh -File tools/auto-sync-install.ps1` richtet die
  Windows-Aufgabe „Forever Core UI Abgleich“ ein: alle 5 Minuten `tools/auto-sync.ps1` (wie session-sync, nur bei
  sauberem Arbeitsstand, verknüpft neue Addon-Ordner), Protokoll `.git/forever-auto-sync.log`; entfernen mit `-Remove`.
  Seit 2026-10-20 bei Patzlinger eingerichtet. Im Spiel danach `/reload`. Weitere Spiel-Clients auf demselben
  Rechner (z. B. ein Stresstest): einmal `tools/link-addons.ps1 -AddOnsDir "<Pfad>"` und den Pfad als Zeile in
  `.git/forever-addon-dirs.txt` eintragen – dann verknüpft der Abgleich neue Addons auch dort.

**Während der Arbeit – kleine Schritte, sofort teilen**
- Je fertige, im Prüflauf (`tools/check.ps1`) fehlerfreie Änderung **ein** Commit (kurze deutsche Nachricht, vorne das Addon:
  `ForeverChat: …`, `Hub v36: …`).
- Direkt danach **ohne Nachfrage**: `git pull --rebase` und `git push` (auf `development`). Damit hat der andere
  spätestens beim nächsten Holen den Stand – niemand sammelt Commits an.
- Nichts Halbfertiges pushen, das beim Laden Fehler wirft (`development` muss für beide spielbar bleiben); Halbfertiges
  lokal lassen oder auf `feature/<name>` pushen.
- Konflikte beim Rebase: eindeutige (beide Seiten unabhängig, z. B. verschiedene Funktionen) selbst zusammenführen und
  im Spiel prüfen; unklare → `git rebase --abort` und den Nutzer fragen. **Nie force-pushen**, nie gepushte Commits
  umschreiben.

**Stellen, an denen man sich trifft (Konflikte vermeiden)**
- `ForeverCore/ForeverHub.lua`: ohne Absprache änderbar; vor jeder Änderung `git pull --rebase`, damit man auf dem
  neuesten Stand arbeitet; treffen beide eine `VERSION`-Erhöhung, nimmt der Zweite die nächsthöhere Zahl.
- `## Version` in den .toc, `release/`-Dateien: ändert nur, wer den Release baut (16).
- Changelog: neue Punkte während der Entwicklung unter `## Unreleased` oben in `release/Changelog-CurseForge.txt`
  eintragen (Englisch, für Spieler); beim Release wird daraus die Versionsüberschrift.
- Diese CLAUDE.md: Regeländerungen sofort committen und pushen, damit der Claude des anderen sie gleich kennt.
- Änderungen an Addons des anderen brauchen keine Absprache (siehe 2).

- Installieren über die CurseForge-App überschreibt die verknüpften Ordner = das Repository → danach `git status`,
  ggf. `git restore .`

## 16. Release
- Nur auf ausdrückliches Kommando des Nutzers (keine Absprache mit dem anderen nötig; vorher `git pull --rebase`,
  damit dessen Stand mit drin ist). Ablauf:
  1. auf `development`: `git pull --rebase`, Version in allen .toc erhöhen, `## Unreleased` im Changelog in
     `## 0.xxb – <Datum>` umbenennen, `tools/build-release.ps1` bauen, committen, pushen
  2. `git switch main`, `git merge --ff-only development` (geht das nicht: `git merge --no-ff development`),
     `git tag -a v0.xxb -m "Forever Core UI 0.xxb"`, `git push origin main v0.xxb`
  3. `git switch development` – weiterarbeiten; neuer leerer Abschnitt `## Unreleased` im Changelog
- `release/addons.txt` = Addons im Release; Prototypen erst nach Freigabe eintragen
- Alle Release-Addons tragen dieselbe `## Version` (Suite-Version, z. B. `0.44b`); `tools/build-release.ps1` prüft das
- Alle Release-.toc: `## Title: <Addon> |cff8a8a8a(Beta)|r`, `## X-Curse-Project-ID: 1743753`, `## X-License: MIT`
- `release/README.txt` (DE/EN, liegt im Release-Ordner, NICHT im Zip – das Gesamt-Zip enthält nur die Addon-Ordner) bei neuen Befehlen/Funktionen anpassen
- `release/Changelog-CurseForge.txt` = Englisch, für Spieler geschrieben; wandert nicht ins Zip
- `release/Description-CurseForge.txt` = Text der CurseForge-Hauptseite (Englisch, Markdown); bei neuen Addons/Funktionen anpassen, nicht ins Zip
- ForeverCore ist immer im Release und steckt in **jedem Einzel-Zip** mit (sonst lädt das Addon nicht)
- Bauen mit `tools/build-release.ps1` (Versionsprüfung, Addon-Ordner, Einzel-Zips, Gesamt-Zip);
  fremde Zips im Zielordner werden nie angefasst

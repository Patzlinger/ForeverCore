# ForeverHub im Detail (Funktionen, Einstellungs-Verwaltung)

Ausgelagert aus CLAUDE.md (Abschnitte 6 und 9). Lesen, wenn am Hub gearbeitet wird oder ein Addon neue
Hub-Funktionen, Einstellungen, Profile, Minimap-Knopf oder /fmove einbindet.

## 6. ForeverHub (gemeinsame Bibliothek)
- Der Hub liegt **nur einmal**: `ForeverCore/ForeverHub.lua` im Hauptaddon ForeverCore (seit 0.41b; vorher Kopie in
  jedem Addon – Stand davor: Git-Markierung `snapshot-vor-core-abhaengigkeit`). Bei Änderungen `VERSION` erhöhen
- Gemeinsames (Stil, Sprache, Hilfsfunktionen, Begrüßung, Platzhalter …) gehört in den Hub, nicht in einzelne Addons
- Erweiterungen müssen abwärtskompatibel sein (andere Addons rufen die Funktionen auf); Funktionen bei Bedarf mit
  `if UI.Funktion then … end` aufrufen
- Was der Hub kann:
  1. **Stil-Bibliothek** `ForeverHub.UI` (Zugriff: `local UI = ForeverHub.UI`):
     `T(de, en)`, `Chat(addon, text)`, `Window(name, title, w, h)`, `Header(parent, x, y, text, width)` (mit
     automatischem Abschnitts-Kasten), `Hint`, `Text(parent, "label"|"field", text)`, `Button(parent, text, w, onClick)`,
     `AddArrow`, `Check(parent, x, y, label, onClick)`, `Slider(...)`, `StyleSlider`, `EditBox`, `Number` (Zahlenfeld mit –/+),
     `ShowMenu`/`HideMenu`/`ChoiceMenu` (flache Auswahllisten), `MinimapButton(o)`, `Hud`, `Box`, `SetFlat`,
     `Grid`, `AddMover`, `BeginDrag`/`EndDrag` (Raster + Einrasten), `Round`, `CenterOffset`, `COLOR`, `LOGO`, `NAME`
     **Spielernamen:** `UI.PlayerName(name)` kürzt "Vorname Nachname" nach der Hub-Einstellung (Hub-Fenster » Spielernamen:
     nur Vorname / Vorname + Initiale = Standard / voll; Realm fällt weg). NUR für Spieler aufrufen (NPC-Namen haben auch
     Leerzeichen); Signal `NameStyleChanged` (UI.On) zum Neuzeichnen. Voller Name bleibt in Charakter-Übersicht, Tooltip, Chat
  2. **Sammelknopf** (seit v53 ohne Liste): sobald ein Forever-Addon da ist, sind dessen Minimap-Knöpfe ausgeblendet;
     der Forever-Core-UI-Knopf öffnet mit Linksklick das gemeinsame Einstellungsfenster, Umschalt+Linksklick das
     Hub-Fenster, Rechtsklick /fmove. Neue Addons brauchen deshalb eine Einstellungsseite (`UI.SettingsPanel`)
  3. **Hub-Fenster** `/forever` (`/fhub`, Ebene `HIGH`, bleibt beim Öffnen eines Addons im Hintergrund offen):
     alle installierten Forever-Addons mit Chatbefehl und "Öffnen"-Knopf ins jeweilige Menü,
     "Alle verschieben", Minimap-Knopf ein/aus, **Sprache für alle Forever-Addons**; `/forever reset` holt Knöpfe zurück.
     **Addons ein-/ausschalten** (ab v26): Häkchen je Addon, "Alle an/aus", "nur dieser Charakter"
     (`ForeverHubDB.perCharacter`, sonst alle Charaktere) über `C_AddOns.EnableAddOn/DisableAddOn` + `SaveAddOns`;
     wirkt erst nach "Neu laden" (kein Nachladen zur Laufzeit – Rahmen müssen beim Laden entstehen, siehe Abschnitt 14).
     **Begrüßung**: beim allerersten Start öffnet sich das Fenster einmal (`ForeverHubDB.welcomeDone`, accountweit;
     wird sofort beim Anzeigen gesetzt, damit es nie wieder aufpoppt). ForeverCore selbst steht nicht in `KNOWN`
     (ohne ForeverCore lädt kein Forever-Addon); Hub, Optionsmenü und Addon-Menü-Eintrag bleiben, auch wenn alle anderen aus sind
  4. **Gemeinsamer Verschiebe-Modus** `/fmove`: entsperrt/sperrt alle angemeldeten Addons auf einmal
  5. **Blizzard-Optionsmenü** (Esc » Optionen » Reiter "AddOns"): Eintrag "Forever Core UI" mit Übersicht und je
     Forever-Addon eine Unterseite mit "Einstellungen öffnen" (öffnet das eigene Fenster, Optionsmenü schließt sich).
     Automatisch für jedes Addon aus `KNOWN`, dessen Minimap-Knopf existiert; `/forever options` springt dorthin.
     Die eigentlichen Einstellungen bleiben in den eigenen Fenstern (keine zweite Einstellungs-Oberfläche bauen)
  6. **Addon-Menü an der Minimap**: ein einziger Eintrag "Forever Core UI" (Links: Hub-Fenster, Rechts: alle verschieben)
  7. **Gemeinsame Helfer** – statt eigener Kopien in jedem Addon benutzen:
     - `UI.ReportError(addon, stelle, fehler)` / `UI.Safe(addon, stelle, fn)`: Fehler einmal pro Stelle im Chat, immer an
       BugSack; `UI.ErrorCount(addon)`
     - `UI.AfterCombat("Addon:schlüssel", fn, addon)`: sofort oder nach dem Kampf (gleicher Schlüssel = letzter Auftrag)
     - `UI.HideBlizzard(frame, { when, children, noMouse })` / `UI.ShowBlizzard(frame)`: Blizzard-Teil taint-frei
       unsichtbar halten (Alpha 0 + Absicherung). Nicht für Rahmen mit geschützten, anklickbaren Knöpfen
       (z. B. Questgegenstände im Questtracker) – die blieben unsichtbar anklickbar
- **Übergang von alten Kopien**: Addons bis 0.32b brachten eine eigene Hub-Kopie mit. Hat ein Spieler noch so ein
  altes Addon neben dem neuen ForeverCore, übernimmt trotzdem die neueste Version (Versionsprüfung am Dateianfang,
  gemeinsamer Zustand `ForeverHub.shared`, Umleitung älterer UI-Tabellen). Neuer gemeinsamer Zustand gehört deshalb
  weiter in `SHARED`; diese Übergangs-Technik kann entfallen, wenn keine 0.32b-Stände mehr im Umlauf sind
- Damit ein Addon voll eingebunden ist:
  - Minimap-Knopf **immer über `UI.MinimapButton({...})`** bauen, globaler Name `Forever<Name>MinimapButton`,
    **Linksklick öffnet das Menü**, Rechtsklick frei (meist: entsperren/sperren bzw. ein-/ausblenden); in `KNOWN`
    eintragen (Name, Knopf, Chatbefehl `cmd`) – damit erscheint es in Sammelknopf, Hub-Fenster und Blizzard-Optionsmenü.
    Die Vorlage bringt Aussehen, Ziehen um die Minimap und den Tooltip-Hinweis "Ziehen" mit
  - für `/fmove`: `UI.RegisterMovable("ForeverName", isLocked, setLocked)` – `isLocked()` liefert true/false,
    `setLocked(locked)` sperrt bzw. entsperrt (inkl. Menü aktualisieren). Addons mit eigener Stil-Datei melden sich
    in einer kleinen `HubLink.lua` an (siehe ForeverQuests/ForeverBars)
- **Addons rufen sich gegenseitig nur über `UI.API` auf** (Hub v49), nicht über neue globale Namen: ein Addon legt
  `UI.API.<Addonname> = { Funktion = … }` ab, ein anderes ruft nur auf, wenn es das gibt (`if UI.API.X and UI.API.X.F`),
  am besten mit `pcall`. Bisher: `ForeverQuests` (DungeonOfQuest, ShowDungeonOfQuest), `ForeverBags` (ShowCharacter,
  HasBank, FreeSlots), `ForeverAlts` (Characters, CharsWithQuest, Toggle), `ForeverSpellbook` (OutdatedCount,
  ReplaceOutdated, Toggle). Wer liefert, trägt das in die .toc als
  `## OptionalDeps` des Nutzers ein, damit er vorher lädt.
- **Einstellungsseiten dürfen `SetScript("OnShow"/"OnHide")` benutzen** (Hub v48): die Seite fängt das ab, die
  Abschnitts-Kästen von `UI.Header` und die Hub-Haken bleiben erhalten. Seiten müssen in 720 Breite passen.
- **Wiederkehrende Aufgaben nur über den gemeinsamen Takt** (Hub v46): `UI.Every(sekunden, fn, { addon, name, when })`
  statt `C_Timer.NewTicker`. `when` = Bedingung, nur dann läuft die Aufgabe (z. B. nur in der Gruppe, nur wenn sichtbar);
  Startzeiten werden verteilt, Fehler einmal gemeldet; `UI.StopEvery(task)` beendet sie. Kurzlebige Ticker, die nur
  während einer Aktion laufen (Testmodus, offenes Fenster, Verschieben), dürfen bleiben.


## 9. Einstellungen
- **Gemeinsame Verwaltung (ab Hub v28, 0.41b)**: jedes Addon meldet seine SavedVariable einmal an –
  `UI.RegisterSettings({ addon, sv, defaults, version, migrate, global, keepOnReset, reset, legacy })` (am Ende der
  Datei mit den Standardwerten). Der Hub übernimmt damit für alle gleich:
  - **Profile je Charakter**: jeder Charakter nutzt das gemeinsame Profil ("Standard") oder ein eigenes;
    Fenster `/forever profile` (auch im Hub-Fenster). Wechseln, Zurücksetzen und Importieren gelten nach dem
    Neuladen – beim Laden (`ADDON_LOADED`, vor dem Addon) schreibt der Hub das richtige Profil **in dieselbe Tabelle**.
    Das Addon liest seine Einstellungen also wie bisher aus `Forever<Name>DB` und braucht keinen Umschalt-Code
  - **Versionen**: `version` erhöhen, wenn sich der Aufbau ändert; `migrate(data, alteVersion)` rechnet ältere Profile um
  - **Export/Import**: ein Text für die ganze Oberfläche (`/forever export` bzw. `import`, "FC1:" + CBOR, komprimiert,
    Base64 über `C_EncodingUtil`); nur Daten, kein Code; Typen werden gegen `defaults` geprüft; Import = neues Profil
  - Regeln dafür: Schlüssel, die mit `_` beginnen, sind reserviert (`_fc` = Profile, nie ins Profil);
    `global = { … }` für Werte, die für alle Profile gelten (Minimap-Winkel immer); die Tabelle **nie ersetzen oder
    komplett leeren** (`wipe(db)`, `Forever<Name>DB = {}`) – sonst sind alle Profile weg; beim eigenen Zurücksetzen
    `_`-Schlüssel stehen lassen. Charakter-Daten (Lehrerlisten, XP-Verlauf …) gehören in `…CharDB`, nicht ins Profil
  - ForeverBars nutzt die Verwaltung seit 0.41b (frühere eigene Profile wurden übernommen; das bisher aktive
    wurde das gemeinsame Profil); sein Menü ruft dieselben Funktionen auf (`Profiles.lua`)
- Eine SavedVariable pro Addon (`Forever<Name>DB`), bei Bedarf zusätzlich pro Charakter (`…CharDB`)
- Defaults in einer Tabelle; beim Laden (`ADDON_LOADED`) fehlende Werte ergänzen (auch verschachtelt), Tabellen
  kopieren (`CopyTable`) – so bekommen auch Spieler mit älteren gespeicherten Einstellungen neue Optionen
- Gespeicherte Werte erst nach `ADDON_LOADED` lesen (beim Ausführen der Addon-Dateien sind sie noch nicht da)
- Ändert sich die Bedeutung einer Einstellung, alte Werte beim Laden umrechnen statt sie stillschweigend zu verwerfen
  (Beispiel: ForeverBars wandelt die frühere Sichtbarkeit "MOUSEOVER" um)
- Einstellungen wirken sofort (kein "Übernehmen"-Knopf), ein "Zurücksetzen" pro Bereich ist gern gesehen
- Blizzard-Einstellungen (CVars, Tastenbelegung) nur auf ausdrücklichen Wunsch des Spielers ändern

## Gesperrte Werte (secret values) – Helfer seit Hub v76

Einheiten-Abfragen (Leben, Mana, GUID, Auren …) liefern im Kampf – Mana auch außerhalb – gesperrte Werte. Erlaubt ist nur das Anzeigen
(`SetText`, `StatusBar:SetValue`, `string.format("%s", …)`). Rechnen, Vergleichen, Tabellenschlüssel und `#` werfen Fehler.

| Funktion | Zweck |
|---|---|
| `UI.IsSecret(…)` | true, wenn irgendein Wert gesperrt ist (nutzt `issecretvalue`; ein globales `issecret` gibt es nicht) |
| `UI.Readable(x)` | ist x eine echte, lesbare Zahl? |
| `UI.Try(fn, …)` | fn im `pcall`, Ergebnis oder nil |
| `UI.StepCurve(schritt, max, cap)` | Stufenkurve: Wert k ab k × schritt ÷ max (cap Stufen, Standard 99) |
| `UI.SetStepCount(fs, unit, powerType, schritt, max, cap)` | schreibt „wie oft passt schritt in den aktuellen Wert“ per `UnitPowerPercent`/`UnitHealthPercent` + Kurve in einen Text, auch bei gesperrtem Wert (powerType nil = Leben); Rückgabe true/false |

Vorbild: ForeverBars „Zauber pro Mana“ (Maximum ist lesbar, aktuelles Mana nicht – die Kurve rechnet im Spiel). Geschützte Funktionen im Kampf
nie aufrufen; `tools/check.ps1` meldet `issecret(` ohne lokale Definition vor der ersten Benutzung.

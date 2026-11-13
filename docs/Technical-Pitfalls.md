# Technische Fallstricke (Taint, Secret Values, Combat Lockdown, Blizzard-Rahmen)

Ausgelagert aus CLAUDE.md (alte Abschnitte 3, 4, 6 [Secret Values], 12 [Umhängen]). **Lesen, bevor ein Blizzard-Rahmen
berührt, ein Rahmen im/für den Kampf angelegt, ein Wert aus einer Einheiten-Abfrage verarbeitet oder Chat-/Menü-Code
geändert wird.** Die Kurzregeln stehen in CLAUDE.md; hier die Einzelheiten und dokumentierten Ausnahmen.

## 1. Client und API (Abschnitt 3)
- Basis ist die **Mainline/Retail-API (Stand 12.1.5)**, nicht Classic. Neue Namensräume nutzen (`C_AddOns`, `C_Spell`,
  `C_SpellBook`, `C_Container`, `C_CVar` …), mit Rückfall auf alte Funktionen, wo sinnvoll.
- Auch scheinbar harmlose Werte sind im Kampf gesperrt, z. B. `GetUnitSpeed("player")` (Fehler „attempt to compare a
  secret number value“). Lieber Ereignisse nutzen (Bewegung: `PLAYER_STARTED_MOVING`/`PLAYER_STOPPED_MOVING`) und in
  `OnUpdate`/Tickern nie gesperrte Werte vergleichen – dort entstehen sonst Fehler in jedem Bild.
- SavedVariables funktionieren normal (Live-Betrieb): speichern, beim Login laden. Standardwerte trotzdem sinnvoll
  wählen (erster Start, neue Einstellungen nach einem Update).
- Forever-Namen haben Vor- und Nachnamen: Chat liefert evtl. „Vorname Nachname“, die Gruppenliste nur den Vornamen –
  Namen abgleichen statt direkt vergleichen.
- WoW-Schrift kennt „→“ nicht (wird zum Kasten): in Anzeige-Texten „»“ oder „–“ verwenden; „≈ · – … —“ funktionieren.
- Namensplaketten sind „restricted regions“: `GetCenter`/`GetPoint` usw. darauf sind verboten (Fehler + Taint); Namen
  lesen geht.
- Anvisieren (`TargetUnit`, `/target`) und `SetRaidTarget` nur über sichere Knöpfe auf Tastendruck, nie automatisch.
- Geschützte Rahmen (Aktionsknöpfe, Einheitenrahmen, sichere Knöpfe) nur **außerhalb des Kampfes** anlegen,
  verschieben, vergrößern oder belegen: vorher `InCombatLockdown()` prüfen, Änderungen sonst bis
  `PLAYER_REGEN_ENABLED` aufschieben (`UI.AfterCombat`).
- Fehler suchen: BugSack/BugGrabber, Datei `WTF\Account\*\SavedVariables\!BugGrabber.lua`.
- Quelltext des Forever-Clients: github.com/Gethe/wow-ui-source, Zweig **forever**.

## 2. Gesperrte Werte (secret values) und Kampflog (Abschnitt 6, Auszug)
- Zahlen/Texte aus Einheiten-Abfragen (Leben, Mana, GUID, Auren …) sind im Kampf – Mana auch außerhalb – gesperrt.
  **Erlaubt: nur Anzeigen** (`SetText`, `StatusBar:SetValue`, `"%s"`, direkt an Aura-Container weiterreichen).
  **Verboten: rechnen, vergleichen, als Tabellenschlüssel oder mit `#`.** Keine Rotationslogik.
- Nur die Hub-Helfer benutzen: `UI.IsSecret(…)`, `UI.Readable(x)`, `UI.Try(fn, …)`,
  `UI.SetStepCount(fs, unit, powerType, schritt, max)` (Anzahl per Kurve auch bei gesperrtem Wert; Vorbild: ForeverBars
  „Zauber pro Mana“). Tabelle und Hintergrund: **Hub.md**, Abschnitt „Gesperrte Werte“.
- **Es gibt kein globales `issecret`** (nur `issecretvalue`) – `tools/check.ps1` meldet die Benutzung ohne lokale
  Definition.
- Geschützte Funktionen (`PickupSpellBookItem`, Taschenplätze, Anker geschützter Rahmen) im Kampf nie aufrufen
  (`InCombatLockdown()` prüfen oder `UI.AfterCombat`); auch ein `pcall` verhindert `ADDON_ACTION_BLOCKED` nicht.
- Das **Kampflog** (`COMBAT_LOG_EVENT_UNFILTERED`, `CombatLogGetCurrentEventInfo`) ist für Addons gesperrt – schon das
  Anmelden löst `ADDON_ACTION_FORBIDDEN` aus (2026-11-05 in ForeverCast); `tools/check.ps1` meldet es.

## 3. Taint vermeiden (Abschnitt 4)
- **Nichts in Blizzards Knopflisten einhängen** (z. B. `GameMenuFrame:AddButton` im Escape-Menü): danach gelten die
  Knöpfe dort als vom Addon berührt, geschützte Aktionen daraus werden blockiert (`ADDON_ACTION_FORBIDDEN`
  „callback()“). Stattdessen eigene Knöpfe daneben anlegen und mit `HookScript("OnShow"/"OnHide")` ein- und
  ausblenden (Hub v47).
- Blizzard-Rahmen **nie** mit `:Hide()`, `:SetParent()` oder `:SetScript()` verändern („Taint“ blockiert sonst z. B.
  Raid-Symbole im Menü oder geschützte Aktionen). Stattdessen:
  - `UnregisterAllEvents()` + `RegisterStateDriver(frame, "visibility", "hide")`, oder
  - unsichtbar machen: `SetAlpha(0)` und mit `hooksecurefunc(frame, "SetAlpha", …)` gegen Zurücksetzen absichern
    (so macht es ForeverBars mit Blizzards Erfahrungs- und Rufleiste – Platz und Anordnung bleiben dabei erhalten).
    Hub-Helfer: `UI.HideBlizzard` / `UI.ShowBlizzard`.
- Blizzard-Funktionen nur mit `hooksecurefunc` bzw. `frame:HookScript` erweitern, nie überschreiben.
- Zwei Addons dürfen nicht denselben Blizzard-Teil „besitzen“. Berührungspunkte: **Wechselwirkungen.md**.
- **Umhängen von Blizzard-Rahmen** (`SetParent`, nur mit dokumentierter Ausnahme wie ForeverBars; alter Abschnitt 12):
  vorher im Blizzard-Code prüfen, ob er Funktionen am Elternrahmen aufruft (Beispiel: die Status-Leisten rufen
  `self:GetParent():CheckForLayoutChange()` auf). Solche Rahmen **nicht umhängen**, sondern nur per `SetPoint` an den
  eigenen Halter anlegen: Eine eigene Ersatz-Funktion am Halter wäre Addon-Code, den Blizzard dann aufruft – danach läuft
  Blizzards Code „getaintet“ weiter (Beispiel: Fehler mit gesperrten Werten in `CompactUnitFrame_UpdateHealthColor`
  beim Öffnen des Bearbeitungsmodus, behoben in ForeverBars 0.13.0). Allgemein: **nie eigene Funktionen oder Werte in
  Tabellen legen, die Blizzard-Code liest.**

- **Weltkarte** (2026-11-09, ADDON_ACTION_BLOCKED nach Klick auf Questmarker): nie Blizzards Kartenmaße
  (`minimizedWidth/-Height`) setzen, nie `OnFrameSizeChanged`, `Minimize`/`Maximize`, `UpdateUIPanelPositions`,
  `SetHighlightedQuestID` oder `RefreshAllDataProviders` aus Addon-Code aufrufen, Kartenpins nie `:Hide()`
  (Deckkraft + `EnableMouse(false)`). Eigene Schließen-Kreuze nur als Bild; Blizzards echter Knopf liegt unsichtbar
  oben und bekommt den Klick (kein weitergeleitetes `:Click()`). Erlaubt: verschieben (`SetPoint`), `SetScale`.
- **Gamepad:** `SetPropagateKeyboardInput` nie im Kampf aufrufen (für Addons gesperrt); nach dem Abfangen einer Taste
  die Weitergabe beim Schließen wieder auf `true` setzen (Hub v83, `UI.RegisterWindow`).

### Dokumentierte Ausnahmen (bewusst so, nicht „reparieren“ ohne Absprache)
- **ForeverBars** setzt Blizzards Aktionsknöpfe und Leisten per `SetParent` in eigene Halter – für ein Leisten-Addon
  nötig (Bartender4 macht es genauso); nur außerhalb des Kampfes, Sichtbarkeit über State-Driver.
- **ForeverQuests** blendet den Blizzard-Questtracker mit `:Hide()` aus (außerhalb des Kampfes, mit OnShow-Hook,
  Wiederholung nach dem Kampf über `UI.AfterCombat`). `UI.HideBlizzard` passt hier NICHT: der Tracker enthält
  geschützte Questgegenstand-Knöpfe, die unsichtbar anklickbar blieben. Falls Taint-Meldungen auftauchen:
  `RegisterStateDriver(ObjectiveTrackerFrame, "visibility", "hide")` im Spiel testen. (Stand KNOWN-BUGS.md: der Tracker
  wird seit `f3e1c27` über Deckkraft ausgeblendet; ein möglicher Taint im Bearbeitungsmodus ist dort offen.)
- **ForeverBags** macht Blizzards Taschenfenster (`ContainerFrameCombinedBags`, `ContainerFrame1…`) in deren `OnShow`
  per `:Hide()` wieder zu (nur mit Einstellung „Blizzards Taschenfenster ersetzen“). Sie sind keine geschützten
  Rahmen; `UI.HideBlizzard` passt nicht (die Taschenplätze blieben unsichtbar anklickbar). Öffnen/Schließen wird nur per
  `hooksecurefunc` auf `ToggleAllBags`/`OpenAllBags`/`CloseAllBags` … mitgehört, nie überschrieben. Die eigenen
  Taschenplätze sind Blizzards `ContainerFrameItemButtonTemplate` (Elternrahmen mit `SetID(Tasche)`, Knopf mit
  `SetID(Platz)`) – Benutzen, Ziehen, Verkaufen und Tooltip erledigt damit Blizzard selbst.
- **ForeverHelpers, Gruppensuche** (`Languages.lua`, Ausnahme von flowfy ausdrücklich erlaubt am 2026-11-13, NUR für
  diese Funktion): Rollenfilter und „Gruppen anzeigen“ ENTFERNEN Einträge aus Blizzards Ergebnisliste von
  „Suche nach Gruppe“ > Durchsuchen – `hooksecurefunc(LFGBrowseFrame, "UpdateResults", …)`, danach `Remove` auf dem
  DataProvider der ScrollBox (in Forever ein Baum mit Überschriften). Das verändert eine Tabelle, die Blizzard-Code
  liest, und verstößt damit gegen die Taint-Regel. Grund: Forever wertet den Rollenfilter der Suche nicht aus, und
  Abdunkeln statt Entfernen war nicht gewünscht. Von flowfy im Spiel geprüft: Filtern, „Nachricht senden“ und
  „Gruppeneinladung“ gehen. Falls doch `ADDON_ACTION_BLOCKED` aus der Gruppensuche gemeldet wird: zuerst hier suchen;
  der regelkonforme Stand (Abdunkeln per `SetAlpha`) liegt als git-Markierung `backup/gruppensuche-abdunkeln`.

# Reservierte Chatbefehle und Tastenkürzel

Ausgelagert aus CLAUDE.md (alter Abschnitt 11). **Lesen, bevor ein Addon einen Chatbefehl oder ein Tastenkürzel
bekommt.** Neue Befehle hier eintragen (keine Doppelungen!).

## Regeln
- Jedes Addon: kurze Form `/f<kürzel>` und lange Form `/forever<name>`; ohne Zusatz öffnet sich das Menü.
- Gemeinsame Zusätze (wo sinnvoll): `move`/`lock`, `reset`, `status`.
- Tastenkürzel über `Bindings.xml` + `BINDING_HEADER_…`/`BINDING_NAME_…` (Bereich „AddOns“).
- Bei neuen Befehlen/Funktionen auch `release/README.txt` anpassen (siehe Release.md).

## Belegt
| Befehl | Addon |
|---|---|
| /forever, /fhub, /fmove; /forever profile, export, import, options, reset, leistung, einrichtung (setup) | ForeverHub |
| /frunen, /foreverrunen | ForeverCoreUI (Theme.lua: listet Fenster, denen die Runen-Optik noch fehlt; `/frunen grau` sucht in offenen Fenstern graue Flächen und übrige Blizzard-Grafiken) |
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

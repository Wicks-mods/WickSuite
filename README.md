<p align="center"><img src="images/suite/banner.png" alt="Wick Suite"></p>

# Wick Suite

> A suite of precision addons for serious TBC Classic raiders. One voice, one chrome.

This repo holds the **brand assets** for the Wick addon suite — not a WoW addon itself. Drop it in your `AddOns` directory if you like (WoW ignores folders without a `.toc`), or keep it anywhere else.

## The suite

<!-- wick:suite-table:start -->
| Addon | GitHub | CurseForge |
|---|---|---|
| **Wick's TBC BIS Tracker** | [repo](https://github.com/Wicks-mods/WickidsTBCBISTracker) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-tbc-bis-tracker) |
| **Wick's CD Tracker** | [repo](https://github.com/Wicks-mods/WicksCDTracker) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-cd-tracker) |
| **Wick's Trade Hall** | [repo](https://github.com/Wicks-mods/WicksTradeHall) | [CurseForge](https://www.curseforge.com/wow/addons/trade-hall) |
| **Wick's Macro Builder** | [repo](https://github.com/Wicks-mods/WicksMacroBuilder) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-macro-builder) |
| **Wick's Combat Log** | [repo](https://github.com/Wicks-mods/WicksCombatLog) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-combat-log) |
| **Wick's Stats** | [repo](https://github.com/Wicks-mods/WicksStats) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-stats) |
| **Wick's Quest Key** | [repo](https://github.com/Wicks-mods/WicksQuestKey) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-quest-key) |
| **Wick's Totems and Things** | [repo](https://github.com/Wicks-mods/WicksTotemsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-totems-and-things) |
| **Wick's Bags** | [repo](https://github.com/Wicks-mods/WicksBags) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-bags) |
| **Wick's Travel Form** | [repo](https://github.com/Wicks-mods/WicksTravelForm) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-travel-form) |
| **Wick's Ledger** | [repo](https://github.com/Wicks-mods/WicksLedger) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-ledger) |
| **Wick's Wardrobe** | [repo](https://github.com/Wicks-mods/WicksWardrobe) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-wardrobe) |
| **Wick's Survivors** | [repo](https://github.com/Wicks-mods/WicksSurvivors) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-survivors) |
| **WickCore** | [repo](https://github.com/Wicks-mods/WickCore) | [CurseForge](https://www.curseforge.com/wow/addons/wickcore) |
| **Wick's Comforts** | [repo](https://github.com/Wicks-mods/WicksComforts) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-comforts) |
| **Wick's Beasts and Things** | [repo](https://github.com/Wicks-mods/WicksBeastsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-beasts-and-things) |
| **Wick's Stances and Things** | [repo](https://github.com/Wicks-mods/WicksStancesAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-stances-and-things) |
| **Wick's Seals and Things** | [repo](https://github.com/Wicks-mods/WicksSealsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-seals-and-things) |
| **Wick's Conjures and Things** | [repo](https://github.com/Wicks-mods/WicksConjuresAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-conjures-and-things) |
| **Wick's Poisons and Things** | [repo](https://github.com/Wicks-mods/WicksPoisonsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-poisons-and-things) |
| **Wick's Demons and Things** | [repo](https://github.com/Wicks-mods/WicksDemonsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-demons-and-things) |
| **Wick's Gear** | [repo](https://github.com/Wicks-mods/WicksGear) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-gear) |
| **Wick's UI** | [repo](https://github.com/Wicks-mods/WicksUIForever) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-ui) |

**Community:** [Discord](https://discord.gg/GWGTMhYBZY)
<!-- wick:suite-table:end -->

## Contents

- **`thumbnails.html`** — single-page gallery rendering all 5 store artboards (suite banner 860×320 + 4 thumbnails 460×260). Open in Chrome and screenshot each `.artboard` element via DevTools.
- **`logo.svg`** — full-color Wick logomark (flame over wick base, flanked by fel-green L-brackets). The same file is duplicated into each addon folder for in-repo consistency.
- **`brand-identity.html`** — standalone copy of the one-pager defining the brand system (palette, typography, L-bracket chrome, naming convention, addon lockups).

## Brand tokens

```
Fel Green    #4FC778   primary accent, L-brackets, active states
Void         #0D0A14   panel background
Shadow       #171124   header strip, secondary panels
Muted Purple #383058   1px borders, dividers
Off-White    #D4C8A1   primary text
```

L-bracket chrome: **10px arms, 2px thick, flush to corners.** Flat panels — no gradients, no Blizzard dialog textures.

Naming formula: **`Wick's` + `[Function]` + `[Noun]`** — always possessive, never bare.

## Typography

Web design uses Cinzel (display) / Space Grotesk (UI) / Space Mono (labels). In-game those map to `Fonts\FRIZQT__.TTF` (body/title) and `Fonts\ARIALN.TTF` (mono/status).

## License

- **Code and docs:** MIT — see [`LICENSE`](LICENSE).
- **Brand assets (name, logomark, wordmark, visual system):** trademark-protected — see [`TRADEMARK.md`](TRADEMARK.md) for what you may and may not do with them.

TL;DR: fork the code freely, don't ship your fork as "Wick's" anything.

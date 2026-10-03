# Brand Identity

## Palette (locked)

| Token | Hex | Role |
|---|---|---|
| Fel Green | `#4FC778` | Primary accent · L-brackets · active states · links |
| Void | `#0D0A14` | Panel background · page canvas |
| Shadow | `#171124` | Header strip · secondary panels |
| Muted Purple | `#383058` | 1px borders · dividers |
| Off-White | `#D4C8A1` | Primary text |

Do not drift. These five values are hex-exact everywhere they appear: marketing art, the website, and the Fel theme in game.

In WickCore the five values live in `Chrome.Colors` and `Chrome.Hex` (WickCore/Chrome.lua) and in the Fel theme (`FEL` in WickCore/Theme.lua). Themes and looks repaint `Chrome.Colors` in place while the game runs. The brand values themselves never change.

## Looks

Every Wick addon on WickCore draws in a look the player picks under Options, Wick's Mods (the Style row, below Theme). Looks are data in WickCore (`Chrome.Styles` in WickCore/Chrome.lua), so a new look is one new entry there and the whole suite follows it. Addons never draw their own frame chrome. They call `Chrome:NewPanel`, `Chrome:Button` and the other helpers, which read the current look.

Choosing a look saves it and reloads the interface, since panels are built once. The look and the theme are kept per character.

Each look has a `family`, and the drawing code branches on it. There are two families, and both are current parts of the brand.

### OG family

Flat panels with a border line, and corner marks where the look has them.

Wick OG is the brand reference for this family:

- **Flat void panels.** No gradients, no Blizzard dialog textures.
- **A single 1px muted-purple border** on every panel.
- **L-bracket corners** in fel green: **10px arms, 2px thick**, flush to the corner with zero offset.
- **A header strip** in Shadow, 22px tall, with a 1px border-colour rule under it.
- **Two-tone titles:** "Wick's" in the text colour, the noun in the accent.
- On resizable frames the BOTTOMRIGHT bracket doubles as the resize grip.

The other OG looks keep the flat fill and the border line and change the rest (see the table below).

### Modern family

9-sliced glass panels on a soft lift shadow. A ring texture stands in for the border, so there is no 1px border line, and there are no L-brackets.

Wick Modern is the reference for this family:

- **Rounded glass panels** in Void, nearly solid, on a soft shadow that reaches past the panel's edges.
- **No border line at rest.** The ring lights in the accent for hover and selection, or in a signal colour where an addon asks for one (an item's quality, a highlighted row).
- **No L-brackets.** A resizable panel keeps a soft grip mark in its bottom-right corner so the handle can still be found.
- **No header band.** The title sits on the glass over a faint accent rule, drawn at half strength and inset from the edges. Titles are two-tone, as in OG.
- **Dividers** are the accent at half strength.

The other modern looks bring their own panel shape, ring and shadow (see the table below).

### The looks

| Look | Family | Panels and corners | Type in game |
|---|---|---|---|
| Wick Modern | modern | Rounded glass, soft lift shadow, no ring at rest | PT Sans Narrow Bold, a size or two up, with a firm drop shadow |
| Wick OG | og | Flat void, 1px muted-purple border, fel L-brackets | Friz Quadrata (the game's font) |
| Hologram | modern | Faint glass, cut corners, an accent outline at rest, an accent glow in place of the shadow | Jost, with Jost SemiBold headings in capitals |
| Rebel | og | Black slabs, a 2px grey outline, square corners with no marks, a hard offset shadow, headings on accent plates | Archivo Narrow Bold, with Anton headings in capitals |
| Gilded | modern | Almost no chrome: a dark wash between thin accent rules, no shadow, round action buttons | Cormorant Garamond, with Cormorant SC headings in small capitals |
| Arena | modern | Solid panels with one notched corner, a stripe in the text colour down the left edge, a faint ring at rest | Barlow Condensed, headings in capitals |
| Foundry | modern | Chamfered steel frames, rivets, accent hazard marks on both sides, lit from above | Exo 2, with Tektur headings in capitals |
| Frost | modern | See-through square panels, hairlines in the accent, no shadow, lit from above, a short accent line before each heading | Saira Semi Condensed, with Michroma headings in capitals |
| Crisp | og | See-through dark grey, one black pixel round every panel, square corners with no marks, no shadows | PT Sans Narrow Bold, outlined text |

The looks' fonts are open-licensed (SIL OFL 1.1) and ship in WickCore/Media/Fonts, each beside its licence. Friz Quadrata is the game's own font.

### Palettes

Wick Modern and Wick OG draw in the Wick palette. The player sets it with the Theme picker under Options, Wick's Mods:

- **Fel:** the five locked values. The brand default, and the warlock theme.
- **Class themes:** one per class (Shaman, Druid, Hunter, Mage, Priest, Paladin, Rogue, Warrior). The game's class colour is the accent, on companion darks at Fel's lightness, with Off-White text.
- **Custom:** a main colour the darks are built from, and an accent.

The other looks bring their own palettes, chosen with the look. The player can change the theme afterwards like any other. The source is `LOOK_PALETTES` in WickCore/Theme.lua.

| Look | Accent | Panel | Second panel | Border | Text |
|---|---|---|---|---|---|
| Hologram | `#3FE0FF` | `#04111A` | `#0B2230` | `#1D6E86` | `#CDEFF7` |
| Rebel | `#E5091A` | `#0B0B0B` | `#1D1D1D` | `#5E5E5E` | `#E6E6E6` |
| Gilded | `#D4B66A` | `#0B0A08` | `#17140F` | `#6E5F3E` | `#E3D9C0` |
| Arena | `#FF5263` | `#0C1620` | `#213040` | `#3E5163` | `#ECE8E1` |
| Foundry | `#FF8A1F` | `#18181B` | `#242428` | `#5A5A62` | `#D8D2C4` |
| Frost | `#8FD3FF` | `#0B1117` | `#131C24` | `#3C5566` | `#E6F1F7` |
| Crisp | The player's class colour | `#121212` | `#0A0A0A` | `#000000` | `#F0F0F0` |

In code every palette fills the same five slots, named after the brand tokens (`fel`, `void`, `shadow`, `border`, `text`), whatever colours it puts in them.

### Defaults

| Client | Look | Theme |
|---|---|---|
| TBC Classic Anniversary | Wick OG | Fel |
| WoW Forever | Wick Modern | The player's class theme (Fel for warlocks) |

TBC starts on Wick OG and Fel so an update looks like the addons players already had. The sources are `Chrome.DEFAULT_STYLE` in Chrome.lua and `Chrome.DEFAULT_SETTING` in Theme.lua. A theme the code does not know falls back to Fel.

### Colour by reference

Take every colour by reference from `Chrome.Colors`, for example `Chrome.Colors.fel`. For text, `Chrome:Esc(token)` gives the colour code at the moment the text is written.

A theme change repaints every region WickCore drew, live. A region an addon paints itself repaints once it is registered with `Chrome:Register`. A tint of a token, such as a hover wash, comes from `Chrome:Wash(token, alpha)`. A copied colour, whether a literal `{0.310, 0.780, 0.471}` or a copy of a table's numbers, never repaints.

## Marketing art and the website

Thumbnails, banners, social cards and wicksmods.com keep the OG chrome in the Fel palette: a void ground, a 1px muted-purple border and fel-green L-brackets.

Kit cards always spell the full name in capitals, for example "DEMONS AND THINGS". Never use "&".

## Typography

Web and marketing:

- **Display:** Cinzel 700 to 900.
- **UI / body:** Space Grotesk 400 to 600.
- **Mono / labels:** Space Mono 400.

In game, the look sets the faces (see the looks table). Wick OG draws in `Fonts\FRIZQT__.TTF`. Wick Modern draws in PT Sans Narrow Bold, a size or two up with a firm shadow, so it reads as clearly as Friz. Addons not yet on WickCore use `Fonts\FRIZQT__.TTF` for display and body (11pt) and `Fonts\ARIALN.TTF` (Arial Narrow) at 9pt for labels.

## Naming convention

Formula: **`Wick's`** + `[Function]` + `[Noun]`

- Always possessive "Wick's". Never bare "Wick".
- Function noun: two words max, literal (no fantasy puns).
- No abbreviations in the display Title. CD is fine as in-game shorthand. "Wick CD Tracker" is not a valid display title; it must be "Wick's CD Tracker".
- Class kits are "Wick's [Noun] and Things", for example "Wick's Demons and Things". Write "and" in full.

The lineup lives in `wick.json`, the single source of truth for every addon's title, folder, client and CurseForge project; the README suite tables and the in-game lists are generated from it with `wick sync`. One folder name is legacy and stays: Wick's TBC BIS Tracker is `WickidsTBCBISTracker`, because renaming it would break its saved variables.

## Logomark

Teardrop flame with radiating opacity layers and a wick dot at the base, flanked by fel-green L-brackets. SVG source is `logo.svg` in this repo (and mirrored into each addon's folder).

For in-game use (texture backgrounds), convert to `.tga` or `.blp`.

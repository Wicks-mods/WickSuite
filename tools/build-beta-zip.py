"""Build WicksMods-Forever-beta.zip from the clean addon trees plus a fresh readme.

The package is for other people. It carries what a player needs and nothing
else: no notes, no tools, nothing of Claude's, nothing personal, no
credentials, and none of Wick's own settings, whether as a WicksProfile bake
or as a saved-variable dump. Anything not on the allowlist is left out and
named; anything forbidden by name or content fails the build.

The zip is built to a temporary file and only replaces the published one
once the audit passes. A failed build never touches what is already there.

    python WickSuite/tools/build-beta-zip.py
"""
import os
import re
import zipfile

ADDONS = "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns"
OUT = "C:/Users/jspli/Projects/Wick/Wicksmods.github.io/download/WicksMods-Forever-beta.zip"
FOLDERS = [
    "WickCore", "WicksBags", "WicksComforts", "WicksGear", "WicksTradeHall",
    "WicksTotemsAndThings", "WicksDemonsAndThings", "WicksFormsAndThings",
    "WicksBeastsAndThings", "WicksPoisonsAndThings", "WicksConjuresAndThings",
    "WicksStancesAndThings",
]
SKIP_DIRS = {".git", ".github", "node_modules"}

# What a player needs and nothing else.
ALLOWED_EXT = {"lua", "toc", "xml", "svg", "png", "tga", "blp", "ttf"}
# Bundled fonts ship with their licence, which the licence requires.
ALLOWED_NAMES = {"README.md", "CHANGELOG.md", "LICENSE", "PT_Sans_Narrow_OFL.txt"}

# Must never appear in a public package, by path.
FORBIDDEN_NAME = re.compile(
    r"claude|memory|settings\.local|wicksmodsinfo|token|secret|password|"
    r"\.bak$|\.orig$|\.py$|\.json$|\.env|wtf|savedvariables|"
    r"wicksprofile|profile\.lua$|macros-cache|^!",
    re.I)

# Must never appear in a public package, by content. These match data, not
# the words: "WickCfg01" in a readme is documentation, a global being
# assigned at the start of a line is somebody's settings.
FORBIDDEN_TEXT = [
    r"jspli", r"s-56\.com", r"CLAUDE", r"claude", r"Co-Authored-By",
    r"X-Api-Token", r"api[_ -]?token\s*[:=]", r"CLOUDFLARE", r"C:.Users",
    r"OneDrive", r"Wicksmodsinfo", r"AppData",
    r"WicksProfileData\s*=", r"WicksProfileStamp\s*=",
    # A saved-variable dump: a global assigned a table whose next line is a
    # bracketed key, the shape the client's serializer writes. Code that
    # initialises a global to {} on one line is not that.
    r"^\s*(WickCoreDB|Wicks\w+(Saved|DB|Alts))\s*=\s*\{\s*\n\s*\[",
]

README = """Wick's Mods for World of Warcraft: Forever - beta test build
============================================================

Thank you for testing. This is a beta package for the Forever beta
client. It is not on CurseForge yet.

INSTALL
-------
Close the game. Copy every folder in this zip into:

    World of Warcraft\\_classic_beta_\\Interface\\AddOns

Start the game and make sure they are all ticked in the AddOns list.

WickCore is required by all of the others. Do not remove it.


WHAT IS IN HERE
---------------
WickCore         Shared platform. Required. /wickcore
Wick's Bags      Bags and bank, one window. /wbags
Wick's Comforts  Square minimap, tooltip extras, auto loot, auto repair,
                 junk selling, auto quest accept and hand-in, camera
                 zoom, class-coloured health bars. All off until you
                 turn them on. /wcomfort
Wick's Gear      What to chase while levelling, scored for your class
                 against what you have on; a browser for what drops
                 where, twenty-one dungeons; and a paperdoll to try
                 pieces on and see the stat changes. /wgear
Wick's Trade     What a run earned, and what the trade channel is
Hall             offering, in one window. /wth

Class kits, one per class. Each has talents, a pre-pull checklist,
racials and a cooldown bar:

Wick's Totems and Things     Shaman   /wtt
Wick's Demons and Things     Warlock  /wdt
Wick's Forms and Things      Druid    /wft
Wick's Beasts and Things     Hunter   /wbt
Wick's Poisons and Things    Rogue    /wpt
Wick's Conjures and Things   Mage     /wcj
Wick's Stances and Things    Warrior  /wst


KEEPING YOUR SETTINGS
---------------------
Settings are kept the normal way. Nothing to do.

For most of the beta the client wrote every addon's settings at logout
and handed back nothing at load, so anything you configured was gone
next time. That was the client and it affected every addon you had.
The patch on 24 September fixed it.

IF YOU USED THE MACRO WORKAROUND
--------------------------------
WickCore could keep your settings in macros named WickCfg01, WickCfg02
and so on while the client could not. It checks at every login and has
stood itself down now that the client does the job, so those macros are
sitting there unused. To get the macro slots back:

    /wickcore store off     remove them

WickCore will say the same thing once at login while they are still
there. If you never turned it on, you have no such macros and there is
nothing to clear.

    /wickcore store         say what it is doing, either way


WHAT IS NEW SINCE THE LAST PACKAGE
----------------------------------
* Wick's Gear is two columns. The lists keep the left side and their
  tabs; the paperdoll and the stats hold the right and are always on, so
  trying something on no longer costs you your place in the list. Click
  a row to put it on, click it again to take it off, and anything on the
  doll is marked in the list.
* Gear: a row is three lines now. The name in its quality colour, what
  the piece gives, and where it comes from, with an icon big enough to
  find things by.
* Gear: set bonuses read beside the stats rather than in the list, and
  they count what you are trying on. Two pieces of a set in the preview
  shows you the two-piece bonus, in green because you would be gaining
  it. Each line says the count it needs: 2/5, 3/5, 4/5, 5/5.
* Mages: portals and teleports in one panel. Left-click a destination to
  teleport, right-click to open the portal for the group. The list comes
  from your own spellbook, so it is the cities you actually know and
  never the other faction's, with rune counts along the top.
* The cooldown bar tracks rather than casts, and has a scale and a row
  width. Anything on cooldown dims, so the bar answers the question it
  exists for at a glance.

Fixed since the last package
----------------------------
* Gear no longer suggests pieces you are already wearing. Upgrades
  picked the best-scoring item in the data for each slot and never
  asked whether it was on your back, so your own gear could win its own
  slot and be recommended back to you.
* Settings are kept by the client again, as of its 24 September patch,
  so the macro workaround is no longer doing anything. If you turned it
  on, WickCore says so once at login and /wickcore store off gives you
  the macro slots back.
* Settings you change outside the options page are kept. Picking a theme
  or dragging a window wrote the setting and never told the part of
  WickCore that survived a restart, so your theme came back to the old
  one. That mattered while the client was broken and is still the right
  behaviour now.
* Wick's Trade Hall no longer fills your chat with errors. The client
  hands an addon the text of a chat line as something it is not allowed
  to read while you are fighting, and the board was reading it. Lines
  said during a fight are skipped now instead.
* Druids: both resource bars follow your theme. They were painted with
  colours that no theme could reach, so one bar stayed blue on a green
  UI whatever you picked.
* Wick's Gear: the window opens at its proper size. It was coming up at
  whatever size it had been before the layout changed, which squeezed
  the list and ran the paperdoll through the button underneath it.
* Mages: portals and teleports in one panel. Left-click a destination
  to teleport, right-click to open the portal for the group. The list
  comes from your own spellbook, so it is the cities you actually know
  and never the other faction's. Rune counts along the top, and a
  destination whose rune has run out is dimmed. /wcj portals, the
  Portals button, a middle-click on the minimap button, or a keybind.
* Mages: teleport and portal runes join the pre-pull checklist once you
  have learned the spells that use them, and not before.
* The cooldown bar tracks rather than casts. It was built out of cast
  buttons, which meant it could not be changed at all during a fight,
  which is when a cooldown tracker is worth having. Clicking an icon no
  longer casts; it was never the point of the bar.
* The cooldown bar has a scale, 0.5x to 2.5x, and a row width so a long
  list wraps instead of running off the edge. Both are in the options,
  in the kit's Cooldowns tab, and on the cd command. It does not drift
  when you resize it.
* Wick's Gear browses four sources, not one. Dungeons as before, plus
  what the four gear professions make, quest rewards worth crossing a
  zone for, and everything grouped by the set it belongs to. A search
  box spans whichever you are looking at, matching the item, the boss or
  profession, the slot, and where it is from.
* Gear: sets say how much of one you are wearing and which bonuses that
  has earned, read from the client's own tooltip rather than a database,
  so it is this build's numbers and not a guess at them.
* Gear: click a row to try it on in the compare view, ctrl-click to open
  it in the dressing room, shift-click to put it in chat. An Equippable
  toggle hides what your class cannot wear, which matters once a list is
  a profession's four hundred pieces rather than a dungeon's nine.
* New: Wick's Trade Hall. Two things in one window. A session tracker
  that says what a run earned and what that is an hour, valuing loot at
  its vendor price and marking anything it cannot price rather than
  guessing. And a reader for the trade channel that keeps one line per
  person per subject, sorted into selling, buying, enchanting, crafting
  and travel, instead of the scroll. It reads chat and never posts.
* New: Wick's Stances and Things, the warrior kit. Three stances and a
  smart key in one row: bind an ability and the key puts you in the
  stance it needs, then uses it. Plus a shout and stance checklist,
  talents, racials and a cooldown bar.
* The suite is on CurseForge for Forever. WickCore, Bags, Comforts,
  Trade Hall, Beasts and Things and Stances and Things all have a page
  now, so you can install and update from the client if you would
  rather not use this zip. Search CurseForge for Wick.
* Comforts: arrow keys move the cursor in chat. This client hands the
  chat box the old behaviour, where the arrows steer your character and
  it takes Alt and an arrow to move the cursor or bring back what you
  last typed. Off until you turn it on, under the camera and client
  heading.
* Trade Hall: the board reads as a board. Every listing carries a
  category badge and the icon of the first item it names, filters along
  the top, a search box, and an age that fades as it gets old.
  Right-click a line to open a whisper, shift-click to put the item in
  your chat box. Neither sends anything.
* Settings can be kept across restarts. See above.
* Escape closes any Wick window before it opens the game menu.
* Comforts: auto accept and hand in quests (Shift at any npc for the
  normal dialogs; a quest with a choice of rewards is never handed in
  for you), camera zoom out further, sound while the game is in the
  background, hide the proc glow on action buttons.
* Comforts: class-coloured health bars on the player, target, focus,
  boss and party frames, drawn as our own bar over Blizzard's so
  nothing of theirs is touched. Colours follow WickCore's class set:
  the game's own, or the Classic-era codes with /wickcore theme classic.
* Gear: every five-player dungeon Forever has, twenty-one with loot so
  far, up from fourteen. Ruins of Lordaeron and the Hall of Thanes have
  quest rewards only until players run them and Wowhead's data fills in.
* Gear: items your character has never seen are described from our own
  data instead of "Retrieving item information" forever, with a
  comparison against what you are wearing. Shift-click links them in
  chat. Mail and plate are only suggested once your class can wear
  them.
* Hunters: the strip's ammo count reads shots over what your quiver
  holds, 286/2k, with the count red under a fifth full, amber to three
  fifths, green above.
* Every locked Wick bar or window moves when you hold Shift and drag.
  The lock stops an accidental nudge, not you.

Fixed since the last package
----------------------------
* Your theme no longer resets. A login that read the setting before it
  had arrived fell back to Fel and then saved Fel over your real
  choice, so one early read lost it for good.
* Trade Hall: a taxi or a summon reads as travel rather than falling
  into Misc.
* Trade Hall: the session total was counting most loot as nothing. It
  listened for the client to answer about an item but never asked, and
  a fresh drop is exactly the case the client stays quiet about.
* Comforts: automatic repair had never once worked. The cost was read in
  a way that dropped the answer to "can this be repaired", so it always
  read no and went home. Selling junk was never affected.
* Bags: right-clicking an item in the bag stopped working. The cooldown
  swirl was fixed in the same pass, and having finally appeared it was
  sitting over the whole button taking the click meant for the item.
* Gear: most items would not shift-click into chat. An item link is a
  fixed shape on a given build and ours was one field long. It now reads
  the shape off the gear on your back and matches it.
* The /who panel opened with its close button and side tabs drawn and
  nothing in the middle. Comforts was claiming a frame name before the
  group finder had loaded, so Blizzard could not build the real one.
* Settings kept in macros are no longer lost when you play a character
  that does not load all the same addons. Anything the store holds for
  an addon that is not loaded is now carried through untouched.
* The unit tooltip's "Targeting" line no longer tests a secret value for
  truth, which the client was blocking.


KNOWN ISSUES
------------
* Wick's Bags can show "blocked from an action" when right-clicking an
  item, most often at the bank. Click Ignore; the click still works.
  This is the cost of hiding Blizzard's own bank window, so /wbags
  defaultbank turns that off and stops it, at the cost of seeing their
  window. /wbags bank prints what the client says if the bank looks
  wrong.

* Wick's Trade Hall values loot at its vendor price, because the auction
  addons it reads on TBC do not exist here yet. Anything the client will
  not price counts as nothing and is marked as such.

* The shaman and warlock kits have not been run on a character of
  their own class yet. Expect rough edges and please report them.


REPORTING
---------
Please include the full Lua error text if you get one, and what you
were doing. Issues: github.com/Wicksmods
"""


# Marketing art exists for CurseForge, the og tags and the social posts,
# all of which fetch from the repo rather than from here. In the package
# it is megabytes a player downloads and never sees: the addon code is
# under half a megabyte. The 2x art was already out; the 1200x630 social
# cards joined the repos later and have exactly the same problem.
def is_marketing_2x(name):
    return "-2x." in name or name.lower().startswith("wick-social-")


def allowed(name):
    if is_marketing_2x(name):
        return False
    if name in ALLOWED_NAMES:
        return True
    if name.startswith("."):
        return False
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    return ext in ALLOWED_EXT


def main():
    count, left_out = 0, []
    tmp = OUT + ".building"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("READ ME FIRST.txt", README.replace("\n", "\r\n"))
        for folder in FOLDERS:
            root = os.path.join(ADDONS, folder)
            assert os.path.isdir(root), folder
            for dirpath, dirnames, filenames in os.walk(root):
                # An addon's top-level images/ is its README and CurseForge
                # art, the same as the marketing art below: none of it loads.
                dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")
                               and not (dirpath == root and d == "images")]
                for f in filenames:
                    rel = os.path.relpath(os.path.join(dirpath, f), ADDONS).replace(os.sep, "/")
                    if not allowed(f):
                        left_out.append(rel)
                        continue
                    z.write(os.path.join(dirpath, f), rel)
                    count += 1

    print("built %d files, %.2f MB" % (count, os.path.getsize(tmp) / 1048576.0))
    print("left out:", ", ".join(left_out) if left_out else "nothing")

    # The audit. Fails the build rather than warning, and leaves the
    # published zip exactly as it was.
    problems = []
    with zipfile.ZipFile(tmp) as z:
        names = z.namelist()
        print("top level:", ", ".join(sorted({n.split("/")[0] for n in names})))
        for n in names:
            if n.endswith("/"):
                continue
            base = n.split("/")[-1]
            if base != "READ ME FIRST.txt" and (FORBIDDEN_NAME.search(n) or FORBIDDEN_NAME.search(base)):
                problems.append("name: " + n)
            text = z.read(n).decode("utf-8", "ignore")
            for pat in FORBIDDEN_TEXT:
                m = re.search(pat, text, re.M)
                if m:
                    where = text[max(0, m.start() - 40):m.end() + 40].replace("\n", " ").strip()
                    problems.append("content: %s matches %s near ...%s..." % (n, pat, where))
                    break
    if problems:
        os.remove(tmp)
        raise SystemExit("AUDIT FAILED, nothing published:\n  " + "\n  ".join(problems))
    os.replace(tmp, OUT)
    print("audit: clean, %d files scanned by name and content; wrote %s" % (len(names), OUT))


if __name__ == "__main__":
    main()

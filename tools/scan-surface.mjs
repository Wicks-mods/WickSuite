// Wick's Probe — API surface scanner
// Scans the Wick suite's Lua for the WoW API surface it actually touches and
// emits WicksProbe/Surface.lua.
//
//   node WickSuite/tools/scan-surface.mjs <outputDir>
//
// Regenerate this whenever the suite gains new API calls.

import fs from "node:fs";
import path from "node:path";

// Both clients' AddOns folders: the TBC suite lives in _anniversary_, and
// WickCore, Wick's UI (with its vendored oUF and LibActionButton under
// Libs/) and the Forever products live in _classic_beta_. A folder that is
// a junction into the other client is scanned once, by real path.
const ROOTS = [
  "C:/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns",
  "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns",
];

const seenReal = new Set();
const ADDONS = [];   // { name, dir }
for (const root of ROOTS) {
  if (!fs.existsSync(root)) continue;
  for (const d of fs.readdirSync(root, { withFileTypes: true })) {
    if (!/^(Wicks|Wickid|WickCore)/.test(d.name) || /\.bak$/.test(d.name) || d.name === "WicksProbe") continue;
    const dir = path.join(root, d.name);
    let real;
    try { real = fs.realpathSync(dir); } catch { continue; }
    if (!fs.statSync(real).isDirectory() || seenReal.has(real)) continue;
    seenReal.add(real);
    ADDONS.push({ name: d.name, dir: real });
  }
}

const files = [];
for (const a of ADDONS) {
  const walk = dir => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name === ".git") continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".lua")) files.push({ addon: a.name, path: p });
    }
  };
  walk(a.dir);
}

const srcs = files.map(f => ({ ...f, src: fs.readFileSync(f.path, "utf8") }));

// ---- pass 1: every name the suite defines itself, so we can exclude it ----
const defined = new Set();
for (const { src } of srcs) {
  for (const m of src.matchAll(/\blocal\s+function\s+([A-Za-z_]\w*)/g)) defined.add(m[1]);
  for (const m of src.matchAll(/\bfunction\s+([A-Za-z_]\w*)\s*\(/g)) defined.add(m[1]);
  for (const m of src.matchAll(/\blocal\s+([A-Za-z_][\w,\s]*?)\s*=/g)) {
    m[1].split(",").forEach(n => { const t = n.trim(); if (/^[A-Za-z_]\w*$/.test(t)) defined.add(t); });
  }
  for (const m of src.matchAll(/\bfunction\s*[\w.:]*\(([^)]*)\)/g)) {
    m[1].split(",").forEach(n => { const t = n.trim(); if (/^[A-Za-z_]\w*$/.test(t)) defined.add(t); });
  }
  for (const m of src.matchAll(/\bfor\s+([A-Za-z_][\w,\s]*?)\s+in\b/g)) {
    m[1].split(",").forEach(n => { const t = n.trim(); if (/^[A-Za-z_]\w*$/.test(t)) defined.add(t); });
  }
}

// ---- pass 2: collect candidate API calls ---------------------------------
const globals = new Map();    // name         -> Set(addon)
const namespaced = new Map(); // "C_X.Method" -> Set(addon)
const events = new Map();     // EVENT_NAME   -> Set(addon)   (explicit RegisterEvent)
const maybeEvents = new Map();// EVENT_NAME   -> Set(addon)   (bare literal, unconfirmed)

const add = (map, key, addon) => {
  if (!map.has(key)) map.set(key, new Set());
  map.get(key).add(addon);
};

for (const { addon, src } of srcs) {
  // Drop comments so commented-out code does not pollute the surface.
  const code = src.replace(/--\[\[[\s\S]*?\]\]/g, "").replace(/--[^\n]*/g, "");

  // Events are found in string literals, so scan them before stripping strings.
  for (const m of code.matchAll(/Register(?:Unit)?Event\s*\(\s*["']([A-Z][A-Z0-9_]+)["']/g)) {
    add(events, m[1], addon);
  }
  // Table-driven registration is common in this suite, so every all-caps
  // underscored literal is a candidate. Registration is pcall'd in the probe,
  // so a false positive costs nothing but a line of output.
  for (const m of code.matchAll(/["']([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)["']/g)) {
    const e = m[1];
    if (e.length < 8) continue;
    if (/^(WICKS|WTBT|WCDT|WCL|ANCHOR_)/.test(e)) continue;
    if (events.has(e)) continue;
    add(maybeEvents, e, addon);
  }

  // Now strip string literals. Without this, prose inside a tooltip line such
  // as "+15 Agility (Socket Bonus)" scans as a call to a global named Agility.
  const bare = code
    .replace(/\[\[[\s\S]*?\]\]/g, '""')
    .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
    .replace(/'(?:[^'\\\n]|\\.)*'/g, "''");

  for (const m of bare.matchAll(/\b(C_[A-Za-z0-9_]+)\s*\.\s*([A-Za-z0-9_]+)\s*\(/g)) {
    add(namespaced, m[1] + "." + m[2], addon);
  }

  for (const m of bare.matchAll(/(^|[^\w.:])([A-Z][A-Za-z0-9_]*)\s*\(/gm)) {
    const n = m[2];
    if (defined.has(n) || n.startsWith("C_")) continue;
    if (/^(WICKS|WTBT|WCDT|WCL|Wick)/.test(n)) continue;
    add(globals, n, addon);
  }
}

// An explicit registration anywhere in the suite outranks a bare literal.
for (const k of events.keys()) maybeEvents.delete(k);

// ---- things we specifically want answered about Forever ------------------
// Included whether or not the suite calls them today.
const FORCE_GLOBALS = [
  "issecretvalue", "issecure", "securecall", "hooksecurefunc",
  "GetBuildInfo", "GetLocale", "GetCVar", "GetAddOnMetadata", "IsAddOnLoaded",
  "GetContainerNumSlots", "GetContainerItemInfo", "GetContainerItemLink", "GetContainerNumFreeSlots",
  "UnitAura", "UnitBuff", "UnitDebuff",
  "GetSpellInfo", "GetSpellCooldown", "GetSpellTexture", "GetSpellLink", "IsSpellKnown",
  "GetItemInfo", "GetItemStats", "GetItemCount", "GetItemSpell", "GetItemIcon",
  "GetDetailedItemLevelInfo", "GetItemInfoInstant",
  "GetTalentInfo", "GetNumTalents", "GetNumTalentTabs", "GetTalentTabInfo",
  "GetInventoryItemLink", "GetInventoryItemID", "GetInventorySlotInfo", "GetInventoryItemTexture",
  "GetCombatRating", "GetCombatRatingBonus", "GetSpellHitModifier", "GetHitModifier",
  "GetCritChance", "GetSpellCritChance", "GetRangedCritChance", "GetExpertise", "GetDodgeChance",
  "UnitAttackPower", "UnitRangedAttackPower", "UnitStat", "UnitResistance", "UnitArmor",
  "UnitHealthMax", "UnitPowerMax", "UnitLevel", "UnitClass", "UnitRace", "UnitGUID",
  "GetQuestLogSpecialItemInfo", "GetQuestLogTitle", "GetNumQuestLogEntries", "SelectQuestLogEntry",
  "GetTradeSkillInfo", "GetNumTradeSkills", "GetTradeSkillNumReagents", "GetTradeSkillLine",
  "GetCraftDisplaySkillLine", "GetNumCrafts",
  "GetNormalizedRealmName", "GetRealmName", "UnitFullName",
  "SendAddonMessage", "RegisterAddonMessagePrefix",
  "GetNumSockets", "GetSocketItemInfo", "GetSocketTypes", "GetExistingSocketInfo",
  "IsFlyableArea", "IsActiveBattlefieldArena", "GetNumArenaTeamMembers", "GetArenaTeam",
  "CombatLogGetCurrentEventInfo",
  "GetTime", "GetServerTime", "InCombatLockdown", "CreateFrame",
  "GetNumGroupMembers", "GetNumRaidMembers", "GetNumPartyMembers", "IsInRaid", "IsInGroup",
  "GetMoney", "GetCoinTextureString", "GetMerchantNumItems", "GetRepairAllCost",
  "GetTransmogrifyItemInfo", "SetItemButtonTexture", "GetMacroInfo", "EditMacro", "CreateMacro",
  "GetShapeshiftFormInfo", "GetNumShapeshiftForms", "CastShapeshiftForm",
  "GetTotemInfo", "GetMultiCastTotemSpells",
];

const FORCE_NS = [
  "C_Secrets.HasSecretRestrictions", "C_Secrets.ShouldCooldownsBeSecret",
  "C_RestrictedActions.IsInRestrictedEnvironment",
  "C_GameRules.IsGameRuleActive", "C_GameRules.GetGameRuleAsFloat",
  "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo",
  "C_Container.GetContainerItemLink", "C_Container.GetContainerNumFreeSlots",
  "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetBuffDataByIndex",
  "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemCount",
  "C_Spell.GetSpellInfo", "C_Spell.GetSpellCooldown", "C_Spell.GetSpellTexture",
  "C_AddOns.GetAddOnMetadata", "C_AddOns.IsAddOnLoaded", "C_AddOns.EnableAddOn",
  "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix",
  "C_ChatInfo.InChatMessagingLockdown",
  "C_Transmog.GetSlotInfo", "C_TransmogCollection.GetAppearanceSources",
  "C_TradeSkillUI.GetTradeSkillLine", "C_TradeSkillUI.GetAllRecipeIDs",
  "C_QuestLog.GetInfo", "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetQuestIDForLogIndex",
  "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo",
  "C_CVar.GetCVar", "C_Timer.After", "C_Timer.NewTicker",
  "C_MountJournal.GetMountIDs", "C_PetJournal.GetNumPets",
  "C_CurrencyInfo.GetCurrencyInfo", "C_Engraving.IsEngravingEnabled",
  "C_SpecializationInfo.GetSpecialization", "C_Reputation.GetFactionDataByIndex",
  "C_Seasons.GetActiveSeason", "C_PlayerInfo.GetName",
  // Read off the wow-ui-source forever branch (1.60.1.69893) on 2026-09-17.
  "C_Traits.GetTreeInfo", "C_Traits.GetConfigInfo", "C_Traits.GetNodeInfo", "C_Traits.GenerateImportString",
  "C_ClassTalents.GetActiveConfigID", "C_ClassTalents.GetTraitTreeForSpec", "C_ClassTalents.ImportLoadout",
  "C_SwingTimer.IsTargetWithinSwingRange", "C_SwingTimer.EnableRangeCheck",
  "C_CombatLog.IsCombatLogRestricted", "C_CombatLog.GetCurrentEventInfo",
  "C_Item.GetItemStats", "C_Item.GetItemNumSockets", "C_Item.GetItemStatDelta",
  "C_GameRules.GetActiveGameMode", "C_GameRules.IsHardcoreActive", "C_GameRules.IsSDHDToggleEnabled", "C_GameRules.IsSelfFoundAllowed",
  "C_CooldownViewer.IsCooldownViewerAvailable", "C_CooldownViewer.GetCooldownViewerCategorySet",
  "C_DamageMeter.GetCombatSessionType", "C_PaperDollInfo.GetInspectItemLevel",
  "C_MajorFactions.GetMajorFactionData", "C_MajorFactions.GetCurrentRenownLevel",
  "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetAllProfessionTradeSkillLines", "C_TradeSkillUI.GetChildProfessionInfos",
  "C_UnitAuras.GetAuraDataBySpellName", "C_UnitAuras.GetAuraSlots",
  "C_Spell.GetSpellName", "C_SpellBook.GetNumSpellBookSkillLines",
  "C_CurrencyInfo.GetCoinTextureString", "C_Container.GetContainerItemID",
];

const FORCE_EVENTS = [
  "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "VARIABLES_LOADED",
  "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED",
  "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
  "QUEST_LOG_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
  "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_TALENT_UPDATE",
  "SOCKET_INFO_UPDATE", "TRANSMOGRIFY_OPEN", "PLAYER_MONEY", "MERCHANT_SHOW",
  "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
  "UPDATE_SHAPESHIFT_FORM", "PLAYER_TOTEM_UPDATE", "COMBAT_RATING_UPDATE",
  "UNIT_INVENTORY_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "ADDON_RESTRICTION_STATE_CHANGED",
  "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED",
  "COOLDOWN_VIEWER_DATA_LOADED", "GAME_RULES_CHANGED", "COMBAT_LOG_EVENT",
];

FORCE_GLOBALS.forEach(n => add(globals, n, "*probe"));
FORCE_NS.forEach(n => add(namespaced, n, "*probe"));
FORCE_EVENTS.forEach(n => { maybeEvents.delete(n); add(events, n, "*probe"); });

// ---- emit ----------------------------------------------------------------
const lua = [];
lua.push("-- Wick's Probe — Surface.lua");
lua.push("-- GENERATED FILE. Do not hand-edit.");
lua.push("-- Regenerate: node WickSuite/tools/scan-surface.mjs <WicksProbe dir>");
lua.push("-- Scanned " + srcs.length + " Lua files across " + ADDONS.length + " Wick addons.");
lua.push("--");
lua.push("-- Each entry is { name, usedBy } where usedBy is a comma-joined addon list.");
lua.push("-- An empty usedBy means the entry is a Forever-specific question, not");
lua.push("-- something the suite calls today.");
lua.push("");
lua.push("local _, ns = ...");
lua.push("");

const emit = (name, map, comment) => {
  lua.push("-- " + comment);
  lua.push("ns." + name + " = {");
  for (const k of [...map.keys()].sort()) {
    const users = [...map.get(k)].filter(u => u !== "*probe").sort();
    lua.push('    { "' + k + '", "' + users.join(",") + '" },');
  }
  lua.push("}");
  lua.push("");
};

emit("GLOBALS", globals, globals.size + " bare global functions");
emit("NAMESPACED", namespaced, namespaced.size + " C_* namespaced functions");
emit("EVENTS", events, events.size + " events, confirmed via an explicit RegisterEvent call");
emit("MAYBE_EVENTS", maybeEvents, maybeEvents.size + " unconfirmed candidates (bare all-caps literals)");

const outDir = process.argv[2];
if (!outDir) {
  console.error("usage: node scan-surface.mjs <outputDir>");
  process.exit(1);
}
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "Surface.lua"), lua.join("\n") + "\n", "utf8");

console.log(
  "scanned " + srcs.length + " files / " + ADDONS.length + " addons -> " +
  "globals=" + globals.size + " namespaced=" + namespaced.size + " events=" + events.size
);

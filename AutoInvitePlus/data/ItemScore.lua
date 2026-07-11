-- AutoInvite Plus - Item Scoring + Cap Engine (Pawn-style, WotLK 3.3.5a)
-- Scores an item = sum(stat * spec_weight), cap-aware so it never over-values a
-- stat past its cap or recommends a sidegrade that un-caps you. Stats come from
-- GetItemStats (base item) plus a hidden-tooltip scan for weapon DPS (which
-- GetItemStats omits). Weights are sane per-archetype defaults; a user can paste
-- a Pawn scale string to override, and if the Pawn addon is present we defer to
-- it. This module is pure logic - no UI, no events.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.ItemScore = AIP.ItemScore or {}
local IS = AIP.ItemScore

-- ============================================================================
-- Canonical stat keys <- GetItemStats' ITEM_MOD_* table keys
-- (keys returned are the global-constant NAMES, not localized text, so we match
-- the literal strings and don't need localization.)
-- ============================================================================
-- IMPORTANT: GetItemStats() on 3.3.5a keys its result with the "_SHORT" forms
-- (ITEM_MOD_STAMINA_SHORT, ...). We map BOTH the _SHORT keys (the real ones) and
-- the legacy non-SHORT keys for safety. Spell power / mp5 / spell-pen have NO
-- _SHORT variant, so they stay single.
local KEYMAP = {
    ITEM_MOD_STRENGTH = "str", ITEM_MOD_STRENGTH_SHORT = "str",
    ITEM_MOD_AGILITY = "agi", ITEM_MOD_AGILITY_SHORT = "agi",
    ITEM_MOD_STAMINA = "sta", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT = "int", ITEM_MOD_INTELLECT_SHORT = "int",
    ITEM_MOD_SPIRIT = "spi", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER = "ap", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_RANGED_ATTACK_POWER = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_SPELL_POWER = "sp", ITEM_MOD_SPELL_HEALING_DONE = "sp", ITEM_MOD_SPELL_DAMAGE_DONE = "sp",
    ITEM_MOD_CRIT_RATING = "crit", ITEM_MOD_CRIT_RATING_SHORT = "crit",
    ITEM_MOD_CRIT_SPELL_RATING = "crit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "crit",
    ITEM_MOD_CRIT_MELEE_RATING = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
    ITEM_MOD_CRIT_RANGED_RATING = "crit", ITEM_MOD_CRIT_RANGED_RATING_SHORT = "crit",
    ITEM_MOD_HASTE_RATING = "haste", ITEM_MOD_HASTE_RATING_SHORT = "haste",
    ITEM_MOD_HASTE_SPELL_RATING = "haste", ITEM_MOD_HASTE_SPELL_RATING_SHORT = "haste",
    ITEM_MOD_HASTE_MELEE_RATING = "haste", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "haste",
    ITEM_MOD_HASTE_RANGED_RATING = "haste", ITEM_MOD_HASTE_RANGED_RATING_SHORT = "haste",
    ITEM_MOD_HIT_RATING = "hit", ITEM_MOD_HIT_RATING_SHORT = "hit",
    ITEM_MOD_HIT_SPELL_RATING = "hit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "hit",
    ITEM_MOD_HIT_MELEE_RATING = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
    ITEM_MOD_HIT_RANGED_RATING = "hit", ITEM_MOD_HIT_RANGED_RATING_SHORT = "hit",
    ITEM_MOD_EXPERTISE_RATING = "exp", ITEM_MOD_EXPERTISE_RATING_SHORT = "exp",
    ITEM_MOD_ARMOR_PENETRATION_RATING = "arp", ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arp",
    ITEM_MOD_DODGE_RATING = "dodge", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_PARRY_RATING = "parry", ITEM_MOD_PARRY_RATING_SHORT = "parry",
    ITEM_MOD_DEFENSE_SKILL_RATING = "def", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def",
    ITEM_MOD_BLOCK_RATING = "blockr", ITEM_MOD_BLOCK_RATING_SHORT = "blockr",
    ITEM_MOD_BLOCK_VALUE = "blockv", ITEM_MOD_BLOCK_VALUE_SHORT = "blockv",
    ITEM_MOD_RESILIENCE_RATING = "resil", ITEM_MOD_RESILIENCE_RATING_SHORT = "resil",
    ITEM_MOD_MANA_REGENERATION = "mp5",
    ITEM_MOD_SPELL_PENETRATION = "spen",
}

-- WotLK level-80 rating -> point conversions and hard caps (see research).
IS.RATING = { hit = 26.23, hitMelee = 32.79, crit = 45.91, haste = 32.79,
              expertise = 8.197, def = 4.92, arp = 15.39 }
IS.CAPS   = { spellHit = 446, meleeHit = 263, expertise = 214, arp = 1400, defense = 540 }

-- ============================================================================
-- Archetype weight scales. Normalized so the primary stat ~= 1.0. These are
-- DEFAULTS; paste a Pawn string (IS.ImportPawn) to override per spec.
-- Capped stats (hit/exp/arp) carry weight only up to the cap (handled in Score).
-- ============================================================================
IS.Scales = {
    casterDPS = { sp=1.0, hit=0.9, haste=0.55, crit=0.5, int=0.4, spi=0.15, spen=0.05, sta=0.05 },
    casterHot = { sp=1.0, haste=0.8, int=0.7, crit=0.4, spi=0.5, mp5=0.4, sta=0.05 },  -- resto-style healer
    healerCrit= { int=1.0, haste=0.8, sp=0.75, crit=0.55, mp5=0.4, spi=0.3, sta=0.05 },-- hpal/rsham
    strDPS    = { str=1.0, hit=0.9, exp=0.85, arp=0.8, crit=0.6, ap=0.5, haste=0.45, agi=0.4, sta=0.05 },
    agiDPS    = { agi=1.0, arp=0.85, hit=0.85, exp=0.7, crit=0.6, ap=0.5, haste=0.45, str=0.3, sta=0.05 },
    tank      = { sta=1.0, def=0.9, dodge=0.7, parry=0.65, blockv=0.4, blockr=0.35, agi=0.4, str=0.3, ap=0.2, def_gate=true },
}

-- class + primary talent tree index (1/2/3) -> archetype.
-- Tree indices are the standard WotLK order. Ambiguous specs fall back sensibly.
IS.SpecArchetype = {
    MAGE       = { "casterDPS","casterDPS","casterDPS" },
    WARLOCK    = { "casterDPS","casterDPS","casterDPS" },
    PRIEST     = { "healerCrit","healerCrit","casterDPS" },       -- disc/holy heal, shadow dps
    DRUID      = { "casterDPS","agiDPS","casterHot" },             -- balance / feral (cat default; Bear form -> tank override below) / resto
    SHAMAN     = { "casterDPS","agiDPS","casterHot" },             -- ele / enh / resto
    PALADIN    = { "healerCrit","tank","strDPS" },                 -- holy / prot / ret
    WARRIOR    = { "strDPS","strDPS","tank" },                     -- arms / fury / prot
    DEATHKNIGHT= { "strDPS","strDPS","strDPS" },                   -- blood/frost/unholy (tank via prot detect below)
    ROGUE      = { "agiDPS","agiDPS","agiDPS" },
    HUNTER     = { "agiDPS","agiDPS","agiDPS" },
}

-- ============================================================================
-- Player spec detection
-- ============================================================================
-- Returns primaryTreeIndex, pointsTable{tab=points}
function IS.PrimaryTree()
    local best, bestPts = 1, -1
    if GetNumTalentTabs then
        for tab = 1, (GetNumTalentTabs() or 3) do
            local _, _, pts = select(1, GetTalentTabInfo(tab))  -- name, icon, pointsSpent
            pts = pts or 0
            if pts > bestPts then bestPts, best = pts, tab end
        end
    end
    return best
end

-- The archetype key for the player's current spec (with a tank override for
-- Feral bear and Prot/Blood-tank cases that share a DPS tree slot).
function IS.PlayerArchetype()
    local _, class = UnitClass("player")
    local tree = IS.PrimaryTree()
    local byClass = IS.SpecArchetype[class]
    local arch = byClass and byClass[tree] or "casterDPS"
    -- Tank overrides that a tree index alone can't disambiguate:
    if class == "DRUID" and (IS.HasBuff("Bear Form") or IS.HasBuff("Dire Bear Form")) then arch = "tank" end
    if class == "WARRIOR" and GetShapeshiftForm and GetShapeshiftForm() == 2 then arch = "tank" end
    if class == "PALADIN" and IS.HasBuff("Righteous Fury") then arch = "tank" end
    -- NOTE: we deliberately do NOT infer DK tank from Frost Presence - Frost/Unholy
    -- DPS also run it, so it would mis-score DPS DKs as tanks (same reasoning as
    -- Readiness). DKs default to strDPS; a Blood tank is a known un-detected case.
    return arch
end

function IS.HasBuff(sub)
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then break end
        if n:find(sub, 1, true) then return true end
    end
    return false
end

-- Active scale table: user override -> Pawn addon -> archetype default.
function IS.GetScale(archetype)
    archetype = archetype or IS.PlayerArchetype()
    if AIP.db and AIP.db.statScales and AIP.db.statScales[archetype] then
        return AIP.db.statScales[archetype], archetype
    end
    return IS.Scales[archetype] or IS.Scales.casterDPS, archetype
end

-- ============================================================================
-- Item stat extraction
-- ============================================================================
-- Hidden tooltip used to read weapon DPS (GetItemStats omits it).
local scanTip
local function ensureTip()
    if scanTip then return scanTip end
    scanTip = CreateFrame("GameTooltip", "AIPItemScoreTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTip
end

local function weaponDPS(link)
    if not link then return 0 end
    local tip = ensureTip()
    tip:ClearLines()
    local ok = pcall(function() tip:SetHyperlink(link) end)
    if not ok then return 0 end
    for i = 1, tip:NumLines() do
        local fs = _G["AIPItemScoreTipTextLeft" .. i]
        local txt = fs and fs:GetText()
        if txt then
            local dps = txt:match("%(([%d%.]+) damage per second%)")
            if dps then return tonumber(dps) or 0 end
        end
    end
    return 0
end

-- Returns a canonical stat table for an item link (base stats + weaponDPS),
-- or nil if the item isn't cached yet (caller should retry).
function IS.GetStats(link)
    if not link then return nil end
    if not GetItemStats then return nil end
    local raw = GetItemStats(link)
    if not raw then return nil end
    local out = {}
    for k, v in pairs(raw) do
        local canon = KEYMAP[k]
        if canon then out[canon] = (out[canon] or 0) + v end
    end
    -- weapon dps (melee/ranged); only bother for weapons
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    -- Include ranged/thrown: a hunter's bow/gun is their primary damage source and
    -- its INVTYPE (INVTYPE_RANGED/RANGEDRIGHT/THROWN) does not contain "WEAPON".
    if equipLoc and (equipLoc:find("WEAPON") or equipLoc:find("RANGED") or equipLoc == "INVTYPE_THROWN") then
        out.wdps = weaponDPS(link)
    end
    return out
end

-- ============================================================================
-- Cap-aware scoring
-- ============================================================================
-- Current capped-rating totals so we don't over-credit rating past a cap.
-- Reads live combat ratings; safe fallbacks if a constant is missing.
function IS.CurrentCaps()
    local function cr(id) return (GetCombatRating and id and GetCombatRating(id)) or 0 end
    -- Pick the hit type + cap that matches the spec (spell for casters/healers,
    -- melee/ranged 263 for physical) so the clamp isn't always the 446 spell cap.
    local arch = IS.PlayerArchetype()
    local caster = arch:find("cast") or arch:find("heal")
    return {
        hit = caster and cr(CR_HIT_SPELL) or cr(CR_HIT_MELEE),
        hitCap = caster and IS.CAPS.spellHit or IS.CAPS.meleeHit,
        exp = cr(CR_EXPERTISE),
        arp = cr(CR_ARMOR_PENETRATION),
    }
end

-- Score a canonical stat table with `scale`. `cur` (optional, from CurrentCaps)
-- makes capped stats (hit/exp/arp) contribute only up to the remaining gap.
function IS.Score(stats, scale, cur)
    if not stats then return 0 end
    scale = scale or IS.GetScale()
    local s = 0
    for stat, amt in pairs(stats) do
        local w = scale[stat]
        if w and w ~= 0 then
            local eff = amt
            -- Cap-aware clamp for the rating stats that have hard caps.
            if cur then
                if stat == "hit" then
                    local capRating = cur.hitCap or IS.CAPS.spellHit
                    local remaining = math.max(0, capRating - (cur.hit or 0))
                    eff = math.min(amt, remaining)
                elseif stat == "exp" then
                    local remaining = math.max(0, IS.CAPS.expertise - (cur.exp or 0))
                    eff = math.min(amt, remaining)
                elseif stat == "arp" then
                    local remaining = math.max(0, IS.CAPS.arp - (cur.arp or 0))
                    eff = math.min(amt, remaining)
                end
            end
            s = s + eff * w
        end
    end
    -- Weapon DPS: heavily weighted for physical archetypes. Skip the flat 6.0
    -- fallback when the active scale already carries an explicit wdps weight
    -- (an imported Pawn "Dps=" scale, applied in the loop above) - else double-count.
    if stats.wdps and (scale.str or scale.agi) and not scale.wdps then
        s = s + stats.wdps * 6.0
    end
    return s
end

-- Convenience: score an item link for the player's current spec (cap-aware).
function IS.ScoreLink(link)
    local stats = IS.GetStats(link)
    if not stats then return nil end
    return IS.Score(stats, IS.GetScale(), IS.CurrentCaps()), stats
end

-- INVTYPE -> equip slot id(s) it can fill, and pretty slot names.
IS.INVTYPE_SLOTS = {
    INVTYPE_HEAD={1}, INVTYPE_NECK={2}, INVTYPE_SHOULDER={3}, INVTYPE_CHEST={5},
    INVTYPE_ROBE={5}, INVTYPE_WAIST={6}, INVTYPE_LEGS={7}, INVTYPE_FEET={8},
    INVTYPE_WRIST={9}, INVTYPE_HAND={10}, INVTYPE_FINGER={11,12}, INVTYPE_TRINKET={13,14},
    INVTYPE_CLOAK={15}, INVTYPE_WEAPONMAINHAND={16}, INVTYPE_2HWEAPON={16},
    INVTYPE_WEAPON={16,17}, INVTYPE_WEAPONOFFHAND={17}, INVTYPE_HOLDABLE={17},
    INVTYPE_SHIELD={17}, INVTYPE_RANGED={18}, INVTYPE_RANGEDRIGHT={18},
    INVTYPE_THROWN={18}, INVTYPE_RELIC={18},
}
IS.SLOT_NAME = { [1]="Head",[2]="Neck",[3]="Shoulder",[5]="Chest",[6]="Waist",[7]="Legs",
    [8]="Feet",[9]="Wrist",[10]="Hands",[11]="Ring",[12]="Ring",[13]="Trinket",[14]="Trinket",
    [15]="Back",[16]="Main Hand",[17]="Off Hand",[18]="Ranged" }

-- Returns score, bestEquippedScore, deltaPct, slotName for an item link vs what
-- you have equipped in that slot (the lower-scored of two, e.g. rings = the one
-- it would replace). deltaPct/slotName are nil if there's nothing to compare.
function IS.UpgradeInfo(link)
    local score = IS.ScoreLink(link)
    if not score then return nil end
    local equipLoc = select(9, GetItemInfo(link))
    local slots = equipLoc and IS.INVTYPE_SLOTS[equipLoc]
    if not slots then return score end
    local bestEq, bestSlot
    for _, slot in ipairs(slots) do
        local eqLink = GetInventoryItemLink("player", slot)
        local es = eqLink and IS.ScoreLink(eqLink) or 0
        if not bestEq or es < bestEq then bestEq, bestSlot = es, slot end
    end
    local delta = (bestEq and bestEq > 0) and (score / bestEq - 1) * 100 or nil
    return score, bestEq, delta, IS.SLOT_NAME[bestSlot or 0]
end

-- ============================================================================
-- Pawn scale string import  ( "( Pawn: v1: \"Name\": Stat=Value, ... )" )
-- Stores under AIP.db.statScales[archetype] for the current spec.
-- ============================================================================
local PAWN_KEYMAP = {
    Strength="str", Agility="agi", Stamina="sta", Intellect="int", Spirit="spi",
    Ap="ap", Rap="ap", SpellPower="sp", HitRating="hit", CritRating="crit",
    HasteRating="haste", ExpertiseRating="exp", ArmorPenetration="arp",
    DodgeRating="dodge", ParryRating="parry", DefenseRating="def",
    BlockRating="blockr", BlockValue="blockv", Resilience="resil", Mp5="mp5",
    Dps="wdps",
}
function IS.ImportPawn(str)
    if not str then return false end
    local scale = {}
    local n = 0
    for stat, val in str:gmatch("(%a+)%s*=%s*(%-?[%d%.]+)") do
        local canon = PAWN_KEYMAP[stat]
        if canon then scale[canon] = tonumber(val); n = n + 1 end
    end
    if n == 0 then return false end
    local arch = IS.PlayerArchetype()
    AIP.db.statScales = AIP.db.statScales or {}
    AIP.db.statScales[arch] = scale
    return true, arch, n
end

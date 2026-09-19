-- AutoInvite Plus - Enchant recommendations (WotLK 3.3.5a), per archetype per slot.
-- Keyed by AIP.ItemScore archetype -> inventory slot id -> recommended enchant.
--
-- DATA HONESTY (same rule as data/BiSData.lua): enchant NAMES, SOURCES and the
-- static stat VALUES are curated game facts; the itemID (a scroll/material) or
-- spellID (the enchant itself) is web-verified where filled, nil otherwise. Rows
-- are name-guarded at render, so an unfilled id shows the correct enchant NAME as
-- text. PROC enchants (Berserking, Black Magic, Mongoose...) intentionally carry
-- NO `mods` because their benefit is a proc, not a flat stat - the what-if skips
-- them rather than inventing an "average" number.
--
-- Row: { name, itemID|nil, spellID|nil, kind = "item"|"spell", source, mods = {..} }
--   kind "item"  -> link via GetItemInfo(itemID)  (a scroll / leg armor / spellthread)
--   kind "spell" -> link via GetSpellLink(spellID) (an applied-only enchant)
-- `mods` keys are the ITEM_MOD_*_SHORT forms the stat panel reads (feeds what-if).
-- Slot ids: Head1 Shoulder3 Chest5 Legs7 Feet8 Wrist9 Hands10 Ring11/12 Back15
--   MainHand16 OffHand/Shield17 Ranged18.

local AIP = AutoInvitePlus
if not AIP then return end
AIP.EnchantData = AIP.EnchantData or {}
local E = AIP.EnchantData

-- IDs web-verified on wowhead.com/wotlk (enchant research pass): kind="item" carries
-- an itemID (arcanum/inscription/leg-armor/spellthread), kind="spell" a spellID (the
-- applied enchant). mods use ITEM_MOD_*_SHORT keys the stat panel reads.
E.List = {
    strDPS = {
        [1]  = { name = "Arcanum of Torment", itemID = 44879, kind = "item", source = "Knights of the Ebon Blade - Revered",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 50, ITEM_MOD_CRIT_RATING_SHORT = 20 } },
        [3]  = { name = "Greater Inscription of the Axe", itemID = 44133, kind = "item", source = "Sons of Hodir - Exalted",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 40, ITEM_MOD_CRIT_RATING_SHORT = 15 } },
        [15] = { name = "Enchant Cloak - Major Agility", spellID = 60663, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_AGILITY_SHORT = 22 } },
        [5]  = { name = "Enchant Chest - Powerful Stats", spellID = 60692, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10, ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPIRIT_SHORT = 10 } },
        [9]  = { name = "Enchant Bracer - Greater Assault", spellID = 44575, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 50 } },
        [10] = { name = "Enchant Gloves - Crusher", spellID = 60668, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 44 } },
        [7]  = { name = "Icescale Leg Armor", itemID = 38374, kind = "item", source = "Leatherworking (BoE)",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 75, ITEM_MOD_CRIT_RATING_SHORT = 22 } },
        [8]  = { name = "Enchant Boots - Icewalker", spellID = 60623, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_HIT_RATING_SHORT = 12, ITEM_MOD_CRIT_RATING_SHORT = 12 } },
        [16] = { name = "Enchant Weapon - Berserking", spellID = 59621, kind = "spell", source = "Enchanting (proc)", mods = nil },
    },
    agiDPS = {
        [1]  = { name = "Arcanum of Torment", itemID = 44879, kind = "item", source = "Knights of the Ebon Blade - Revered",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 50, ITEM_MOD_CRIT_RATING_SHORT = 20 } },
        [3]  = { name = "Greater Inscription of the Axe", itemID = 44133, kind = "item", source = "Sons of Hodir - Exalted",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 40, ITEM_MOD_CRIT_RATING_SHORT = 15 } },
        [15] = { name = "Enchant Cloak - Major Agility", spellID = 60663, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_AGILITY_SHORT = 22 } },
        [5]  = { name = "Enchant Chest - Powerful Stats", spellID = 60692, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10, ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPIRIT_SHORT = 10 } },
        [9]  = { name = "Enchant Bracer - Greater Assault", spellID = 44575, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 50 } },
        [10] = { name = "Enchant Gloves - Crusher", spellID = 60668, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 44 } },
        [7]  = { name = "Icescale Leg Armor", itemID = 38374, kind = "item", source = "Leatherworking (BoE)",
                 mods = { ITEM_MOD_ATTACK_POWER_SHORT = 75, ITEM_MOD_CRIT_RATING_SHORT = 22 } },
        [8]  = { name = "Enchant Boots - Icewalker", spellID = 60623, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_HIT_RATING_SHORT = 12, ITEM_MOD_CRIT_RATING_SHORT = 12 } },
        [16] = { name = "Enchant Weapon - Berserking", spellID = 59621, kind = "spell", source = "Enchanting (proc)", mods = nil },
        -- Ranged weapon scope: engineer-crafted but usable by anyone (not
        -- self-only like the tinkers/embroideries below) - same BoE-consumable
        -- pattern as the Icescale Leg Armor row above. Hunter-only in practice
        -- (the only agiDPS class that fights with a bow/gun/crossbow here -
        -- Rogue/Feral/Enhance/Ret share this archetype but don't use slot 18
        -- for damage), so E.ForSlot gates it to UnitClass == HUNTER.
        [18] = { name = "Heartseeker Scope", itemID = 41167, spellID = 55135, kind = "item", source = "Engineering (430) - BoE once crafted, anyone can attach",
                 mods = { ITEM_MOD_CRIT_RATING_SHORT = 40 } },
    },
    casterDPS = {
        [1]  = { name = "Arcanum of Burning Mysteries", itemID = 44877, kind = "item", source = "Kirin Tor - Revered",
                 mods = { ITEM_MOD_SPELL_POWER = 30, ITEM_MOD_CRIT_RATING_SHORT = 20 } },
        [3]  = { name = "Greater Inscription of the Storm", itemID = 44135, kind = "item", source = "Sons of Hodir - Exalted",
                 mods = { ITEM_MOD_SPELL_POWER = 24, ITEM_MOD_CRIT_RATING_SHORT = 15 } },
        [15] = { name = "Enchant Cloak - Wisdom", spellID = 47899, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_SPIRIT_SHORT = 10 } },
        [5]  = { name = "Enchant Chest - Powerful Stats", spellID = 60692, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10, ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPIRIT_SHORT = 10 } },
        [9]  = { name = "Enchant Bracer - Superior Spellpower", spellID = 60767, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_SPELL_POWER = 30 } },
        [10] = { name = "Enchant Gloves - Exceptional Spellpower", spellID = 44592, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_SPELL_POWER = 28 } },
        [7]  = { name = "Sapphire Spellthread", itemID = 41604, kind = "item", source = "Tailoring (BoE)",
                 mods = { ITEM_MOD_SPELL_POWER = 50, ITEM_MOD_STAMINA_SHORT = 30 } },
        [8]  = { name = "Enchant Boots - Icewalker", spellID = 60623, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_HIT_RATING_SHORT = 12, ITEM_MOD_CRIT_RATING_SHORT = 12 } },
        [16] = { name = "Enchant Weapon - Black Magic", spellID = 59625, kind = "spell", source = "Enchanting (proc)", mods = nil },
    },
    healerCrit = {
        [1]  = { name = "Arcanum of Blissful Mending", itemID = 44876, kind = "item", source = "Wyrmrest Accord - Revered",
                 mods = { ITEM_MOD_SPELL_POWER = 30, ITEM_MOD_MANA_REGENERATION = 10 } },
        [3]  = { name = "Greater Inscription of the Crag", itemID = 44134, kind = "item", source = "Sons of Hodir - Exalted",
                 mods = { ITEM_MOD_SPELL_POWER = 24, ITEM_MOD_MANA_REGENERATION = 8 } },
        [15] = { name = "Enchant Cloak - Wisdom", spellID = 47899, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_SPIRIT_SHORT = 10 } },
        [5]  = { name = "Enchant Chest - Powerful Stats", spellID = 60692, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10, ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPIRIT_SHORT = 10 } },
        [9]  = { name = "Enchant Bracer - Superior Spellpower", spellID = 60767, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_SPELL_POWER = 30 } },
        [10] = { name = "Enchant Gloves - Exceptional Spellpower", spellID = 44592, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_SPELL_POWER = 28 } },
        [7]  = { name = "Sapphire Spellthread", itemID = 41604, kind = "item", source = "Tailoring (BoE)",
                 mods = { ITEM_MOD_SPELL_POWER = 50, ITEM_MOD_STAMINA_SHORT = 30 } },
        [8]  = { name = "Enchant Boots - Tuskarr's Vitality", spellID = 47901, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_STAMINA_SHORT = 15 } },
        [16] = { name = "Enchant Weapon - Black Magic", spellID = 59625, kind = "spell", source = "Enchanting (proc)", mods = nil },
    },
    tank = {
        [1]  = { name = "Arcanum of the Stalwart Protector", itemID = 44878, kind = "item", source = "Knights of the Ebon Blade - Revered",
                 mods = { ITEM_MOD_STAMINA_SHORT = 37, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 20 } },
        [3]  = { name = "Greater Inscription of the Pinnacle", itemID = 44136, kind = "item", source = "Sons of Hodir - Exalted",
                 mods = { ITEM_MOD_DODGE_RATING_SHORT = 20, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 15 } },
        [15] = { name = "Enchant Cloak - Titanweave", spellID = 44591, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 16 } },
        [5]  = { name = "Enchant Chest - Super Health", spellID = 47900, kind = "spell", source = "Enchanting (+275 Health)", mods = nil },
        [9]  = { name = "Enchant Bracer - Major Stamina", spellID = 62256, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_STAMINA_SHORT = 40 } },
        [10] = { name = "Enchant Gloves - Armsman", spellID = 44625, kind = "spell", source = "Enchanting (+2% threat)",
                 mods = { ITEM_MOD_PARRY_RATING_SHORT = 10 } },
        [7]  = { name = "Frosthide Leg Armor", itemID = 38373, kind = "item", source = "Leatherworking (BoE)",
                 mods = { ITEM_MOD_STAMINA_SHORT = 55, ITEM_MOD_AGILITY_SHORT = 22 } },
        [8]  = { name = "Enchant Boots - Tuskarr's Vitality", spellID = 47901, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_STAMINA_SHORT = 15 } },
        [16] = { name = "Enchant Weapon - Blood Draining", spellID = 64579, kind = "spell", source = "Enchanting (proc)", mods = nil },
        [17] = { name = "Enchant Shield - Defense", spellID = 44489, kind = "spell", source = "Enchanting",
                 mods = { ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 20 } },
    },
}
E.List.casterHot = E.List.healerCrit
-- Hunters use the same AP-focused enchants as the other agiDPS specs, plus the
-- ranged-weapon scope already keyed under agiDPS[18] (E.ForSlot class-gates it
-- to Hunter, so it's inert for Rogue/Enhance/Feral sharing this same table).
E.List.rangedDPS = E.List.agiDPS

-- Per-spec overrides (SG.KeyFor keys) for cases the archetype default misses
-- (e.g. ArP weapon enchant differences). Populated by the research pass.
E.BySpec = {}

-- Profession-exclusive enchants: unlike E.List, these are NOT available to
-- everyone - each requires the enchanter's own copy of that profession (and,
-- for rings, can only ever be self-applied - no other profession can enchant
-- a ring at all in 3.3.5a, so these are the ONLY option for slots 11/12).
-- Glove/cloak/bracer entries here COMPETE with the E.List entry for the same
-- slot (one enchant per slot) rather than stacking with it - `note` on each
-- says so. IDs verified on wowhead.com/wotlk. Proc/on-use effects (glove
-- tinkers, cloak embroideries) carry no `mods`, same rule as E.List procs.
E.ProfessionAlts = {
    strDPS = {
        [9]  = { { name = "Fur Lining - Attack Power", spellID = 57683, kind = "spell",
                   source = "Leatherworking (self-only bracer enchant)", mods = { ITEM_MOD_ATTACK_POWER_SHORT = 130 } } },
        [10] = { { name = "Hyperspeed Accelerators", spellID = 54999, kind = "spell",
                   source = "Engineering (glove tinker, self-only)", mods = nil,
                   note = "On-use: +340 Haste for 12 sec, 1 min cooldown. Replaces the glove enchant above (one effect per slot)." } },
        [11] = { { name = "Enchant Ring - Assault", spellID = 44645, kind = "spell",
                   source = "Enchanting (self-only ring enchant)", mods = { ITEM_MOD_ATTACK_POWER_SHORT = 40 } } },
        [12] = { { name = "Enchant Ring - Assault", spellID = 44645, kind = "spell",
                   source = "Enchanting (self-only ring enchant)", mods = { ITEM_MOD_ATTACK_POWER_SHORT = 40 } } },
        [15] = { { name = "Swordguard Embroidery", spellID = 55777, kind = "spell",
                   source = "Tailoring (cloak embroidery, self-only)", mods = nil,
                   note = "Proc: melee/ranged hits have a chance to grant +400 Attack Power for 15 sec. Replaces the cloak enchant above." } },
    },
    tank = {
        [9]  = { { name = "Fur Lining - Stamina", spellID = 57690, kind = "spell",
                   source = "Leatherworking (self-only bracer enchant)", mods = { ITEM_MOD_STAMINA_SHORT = 102 } } },
        [11] = { { name = "Enchant Ring - Stamina", spellID = 59636, kind = "spell",
                   source = "Enchanting (self-only ring enchant)", mods = { ITEM_MOD_STAMINA_SHORT = 30 } } },
        [12] = { { name = "Enchant Ring - Stamina", spellID = 59636, kind = "spell",
                   source = "Enchanting (self-only ring enchant)", mods = { ITEM_MOD_STAMINA_SHORT = 30 } } },
        [15] = { { name = "Swordguard Embroidery", spellID = 55777, kind = "spell",
                   source = "Tailoring (cloak embroidery, self-only)", mods = nil,
                   note = "Proc: melee hits have a chance to grant +400 Attack Power for 15 sec (helps threat). Replaces the cloak enchant above." } },
    },
}
E.ProfessionAlts.agiDPS = E.ProfessionAlts.strDPS
E.ProfessionAlts.rangedDPS = E.ProfessionAlts.strDPS

-- Blacksmithing sockets (self-only, any armor type - a plate tank and a
-- cloth caster can both use these). Unlike the tinkers/embroideries above,
-- a socket is a property of the ITEM, not the enchant slot, so it stacks
-- with whatever enchant is already on that bracer/glove rather than
-- replacing it. No `mods` - the actual gain depends on which gem goes in
-- the new socket, so this points at the GEMS section above instead of
-- guessing a number.
local function addSocket(list, slotId, label)
    list[slotId] = list[slotId] or {}
    table.insert(list[slotId], { name = label, spellID = (slotId == 9 and 55628 or 55641), kind = "spell",
        source = "Blacksmithing (self-only, adds a socket - doesn't replace the enchant)",
        mods = nil, note = "Adds a permanent extra socket (any color). Slot your best-stat gem from the GEMS section above in it." })
end
addSocket(E.ProfessionAlts.strDPS, 9, "Socket Bracer")
addSocket(E.ProfessionAlts.strDPS, 10, "Socket Gloves")
addSocket(E.ProfessionAlts.tank, 9, "Socket Bracer")
addSocket(E.ProfessionAlts.tank, 10, "Socket Gloves")

do
    local casterAlts = {
        [9]  = { { name = "Fur Lining - Spell Power", spellID = 57691, kind = "spell",
                   source = "Leatherworking (self-only bracer enchant)", mods = { ITEM_MOD_SPELL_POWER = 76 } } },
        [10] = { { name = "Hyperspeed Accelerators", spellID = 54999, kind = "spell",
                   source = "Engineering (glove tinker, self-only)", mods = nil,
                   note = "On-use: +340 Haste for 12 sec, 1 min cooldown. Replaces the glove enchant above (one effect per slot)." } },
        [11] = { { name = "Enchant Ring - Greater Spellpower", spellID = 44636, kind = "spell",
                   source = "Enchanting (self-only ring enchant)", mods = { ITEM_MOD_SPELL_POWER = 23 } } },
        [12] = { { name = "Enchant Ring - Greater Spellpower", spellID = 44636, kind = "spell",
                   source = "Enchanting (self-only ring enchant)", mods = { ITEM_MOD_SPELL_POWER = 23 } } },
        [15] = { { name = "Lightweave Embroidery", spellID = 55642, kind = "spell",
                   source = "Tailoring (cloak embroidery, self-only)", mods = nil,
                   note = "Proc: casting a spell has a chance to grant +295 Spell Power for 15 sec. Replaces the cloak enchant above." } },
    }
    E.ProfessionAlts.casterDPS = casterAlts
    E.ProfessionAlts.healerCrit = casterAlts
    E.ProfessionAlts.casterHot = casterAlts
    addSocket(casterAlts, 9, "Socket Bracer")
    addSocket(casterAlts, 10, "Socket Gloves")
end

-- Profession-gated alternative(s) for a slot, for the current player's archetype.
function E.ProfessionAltsForSlot(slotId)
    local IS = AIP.ItemScore
    local arch = IS and IS.PlayerArchetype and IS.PlayerArchetype()
    local t = arch and E.ProfessionAlts[arch]
    return t and t[slotId]
end

function E.ForArchetype(arch) return E.List[arch] end

-- Enchant for a given slot for the current player (spec override -> archetype).
function E.ForSlot(slotId)
    local IS, SG = AIP.ItemScore, AIP.SpecGuides
    -- The "tank" archetype is shared by Warrior/Paladin/DK/Druid, but its
    -- slot-17 entry ("Enchant Shield - Defense") only applies to classes that
    -- can actually equip a shield - Druids can't, in any spec or form, so
    -- there's nothing to enchant there. Item-type check, not just class/spec.
    if slotId == 17 then
        local _, class = UnitClass("player")
        if class == "DRUID" then return nil end
    end
    -- Ranged scope only makes sense on an actual bow/gun/crossbow - the other
    -- agiDPS classes put a wand/idol/totem in slot 18, which can't take one.
    if slotId == 18 then
        local _, class = UnitClass("player")
        if class ~= "HUNTER" then return nil end
    end
    local key = SG and SG.KeyFor and SG.KeyFor()
    if key and E.BySpec[key] and E.BySpec[key][slotId] then return E.BySpec[key][slotId] end
    local arch = IS and IS.PlayerArchetype and IS.PlayerArchetype()
    local t = arch and E.List[arch]
    return t and t[slotId] or nil
end

-- Warm the item cache for item-kind enchants (scrolls / leg armor / spellthread).
local warm = CreateFrame("Frame")
warm:RegisterEvent("PLAYER_LOGIN")
warm:RegisterEvent("PLAYER_ENTERING_WORLD")
warm:SetScript("OnEvent", function()
    if not GetItemInfo then return end
    for _, slots in pairs(E.List) do
        for _, en in pairs(slots) do if en.itemID then GetItemInfo(en.itemID) end end
    end
end)

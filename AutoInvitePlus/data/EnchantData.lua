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

-- Per-spec overrides (SG.KeyFor keys) for cases the archetype default misses
-- (e.g. ArP weapon enchant differences). Populated by the research pass.
E.BySpec = {}

function E.ForArchetype(arch) return E.List[arch] end

-- Enchant for a given slot for the current player (spec override -> archetype).
function E.ForSlot(slotId)
    local IS, SG = AIP.ItemScore, AIP.SpecGuides
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

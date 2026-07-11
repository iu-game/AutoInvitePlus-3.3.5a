-- AutoInvite Plus - Consumable recommendations (WotLK 3.3.5a): flask / food / drink
-- per archetype, as real item links. Feeds the Spec section (the old Readiness
-- content moved here). NAMES + SOURCES are curated game facts; itemIDs web-verified
-- where filled, nil otherwise -> name-guarded to text at render. These are meant
-- as linkable references, not what-if stat inputs (they are already-active buffs).
--
-- Row: X.List[archetype] = { flask={name,itemID,note}, food={name,itemID,note},
--                            drink={name,itemID,note}|nil }

local AIP = AutoInvitePlus
if not AIP then return end
AIP.Consumables = AIP.Consumables or {}
local C = AIP.Consumables

-- Item IDs web-verified on wowhead.com/wotlk (see Consumables research pass).
C.List = {
    strDPS = {
        flask = { name = "Flask of Endless Rage", itemID = 46377, note = "+180 attack power" },
        food  = { name = "Dragonfin Filet",       itemID = 43000, note = "+40 Strength, +40 Stamina (Well Fed)" },
        drink = nil,
    },
    agiDPS = {
        flask = { name = "Flask of Endless Rage", itemID = 46377, note = "+180 attack power" },
        food  = { name = "Blackened Dragonfin",   itemID = 42999, note = "+40 Agility, +40 Stamina (Well Fed)" },
        drink = { name = "Conjured Mana Strudel", itemID = 43523, note = "hunters: drink to refill mana" },
    },
    casterDPS = {
        flask = { name = "Flask of the Frost Wyrm", itemID = 46376, note = "+125 spell power" },
        food  = { name = "Firecracker Salmon",      itemID = 34767, note = "+46 spell power, +40 Stamina (Well Fed)" },
        drink = { name = "Conjured Mana Strudel",   itemID = 43523, note = "drink to refill mana" },
    },
    healerCrit = {
        flask = { name = "Flask of the Frost Wyrm",  itemID = 46376, note = "+125 spell power (or Flask of Pure Mojo 46378 for +45 mp5 when mana-constrained)" },
        food  = { name = "Tender Shoveltusk Steak",  itemID = 34755, note = "+46 spell power, +40 Stamina (Well Fed)" },
        drink = { name = "Conjured Mana Strudel",    itemID = 43523, note = "drink to refill mana" },
    },
    tank = {
        flask = { name = "Flask of Stoneblood", itemID = 46379, note = "+1300 health (threat: Flask of Endless Rage 46377)" },
        food  = { name = "Dragonfin Filet",     itemID = 43000, note = "+40 Strength, +40 Stamina (druid tanks: Blackened Dragonfin 42999)" },
        drink = nil,
    },
}
C.List.casterHot = C.List.healerCrit

-- Per-spec overrides (SG.KeyFor keys) refined by the research pass.
C.BySpec = {}

function C.ForArchetype(arch) return C.List[arch] end

function C.ForPlayer()
    local IS, SG = AIP.ItemScore, AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    if key and C.BySpec[key] then return C.BySpec[key] end
    local arch = IS and IS.PlayerArchetype and IS.PlayerArchetype()
    return arch and C.List[arch] or nil
end

local warm = CreateFrame("Frame")
warm:RegisterEvent("PLAYER_LOGIN")
warm:RegisterEvent("PLAYER_ENTERING_WORLD")
warm:SetScript("OnEvent", function()
    if not GetItemInfo then return end
    local function warmSet(s)
        if not s then return end
        for _, k in ipairs({ "flask", "food", "drink" }) do
            if s[k] and s[k].itemID then GetItemInfo(s[k].itemID) end
        end
    end
    for _, s in pairs(C.List) do warmSet(s) end
    for _, s in pairs(C.BySpec) do warmSet(s) end
end)

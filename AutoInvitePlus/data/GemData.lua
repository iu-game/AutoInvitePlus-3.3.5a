-- AutoInvite Plus - Gem recommendations (WotLK 3.3.5a, "Warmane best-stat" style)
-- Philosophy: pick the single best-STAT gem for every coloured socket, ignoring
-- socket colour and socket bonus, and show a green -> blue -> purple quality
-- progression for each. We DO recommend enough off-colour gems to keep the META
-- gem's activation requirement satisfied (so the meta stays active).
--
-- DATA HONESTY (same rule as data/BiSData.lua): stat VALUES and cut/quality NAMES
-- are stable game facts and are curated here; itemIDs are web-verified where filled
-- and left nil otherwise. Every row is name-guarded at render (leading %a+ match) so
-- an unfilled/stale id degrades to the correct item NAME as text, never a wrong item.
-- `mods` keys are the ITEM_MOD_*_SHORT forms the Character stat panel already reads,
-- so a selected gem feeds the live what-if projection with zero mapping.
--
-- Base gem by quality tier (WotLK):
--   red    Bloodstone (green) -> Scarlet Ruby (blue) -> Cardinal Ruby (epic)
--   yellow Sun Crystal(green)  -> Autumn's Glow(blue) -> King's Amber (epic)
--   blue   Chalcedony (green)  -> Sky Sapphire (blue) -> Majestic Zircon (epic)
-- Primary-stat cuts: Bold(Str) Delicate(Agi) Brilliant(Int) Runed(SP) Bright(AP)
--   Sparkling(Spi) Solid(Sta) Smooth(crit) Quick(haste) Rigid(hit) Fractured(ArP)
--   Precise(expertise). quality: 2=uncommon(green) 3=rare(blue) 4=epic(purple).

local AIP = AutoInvitePlus
if not AIP then return end
AIP.GemData = AIP.GemData or {}
local G = AIP.GemData

-- A tier row: { name, itemID|nil, quality, mods = { ITEM_MOD_*_SHORT = amount } }
-- A gem group: { label, tiers = { green, blue, epic } }.  A meta: { name, itemID, note, mods }.
-- G.List[archetype] = { groups = { <primary group>, ... }, meta = <meta> }

-- IDs + amounts + meta activation web-verified via nether.wowhead.com/wotlk tooltip
-- JSON (gem research pass). NOTE 3.3.5a quirk: the +Intellect "Brilliant" cut is a
-- YELLOW gem (Sun Crystal/Autumn's Glow/King's Amber) - there is NO red "Brilliant
-- Cardinal Ruby" in this client (that is a retail re-itemization).
G.List = {
    strDPS = {
        groups = {
            { label = "Strength (all sockets)", tiers = {
                { "Bold Bloodstone",    39900, 2, { ITEM_MOD_STRENGTH_SHORT = 12 } },
                { "Bold Scarlet Ruby",  39996, 3, { ITEM_MOD_STRENGTH_SHORT = 16 } },
                { "Bold Cardinal Ruby", 40111, 4, { ITEM_MOD_STRENGTH_SHORT = 20 } },
            } },
        },
        meta = { name = "Relentless Earthsiege Diamond", itemID = 41398,
                 note = "+21 Agi, +3% crit dmg. activate: >=1 Red, 1 Yellow, 1 Blue gem", mods = { ITEM_MOD_AGILITY_SHORT = 21 } },
    },
    agiDPS = {
        groups = {
            { label = "Agility (all sockets)", tiers = {
                { "Delicate Bloodstone",    39905, 2, { ITEM_MOD_AGILITY_SHORT = 12 } },
                { "Delicate Scarlet Ruby",  39997, 3, { ITEM_MOD_AGILITY_SHORT = 16 } },
                { "Delicate Cardinal Ruby", 40112, 4, { ITEM_MOD_AGILITY_SHORT = 20 } },
            } },
        },
        meta = { name = "Relentless Earthsiege Diamond", itemID = 41398,
                 note = "+21 Agi, +3% crit dmg. activate: >=1 Red, 1 Yellow, 1 Blue gem", mods = { ITEM_MOD_AGILITY_SHORT = 21 } },
    },
    casterDPS = {
        groups = {
            { label = "Spell Power (all sockets)", tiers = {
                { "Runed Bloodstone",    39911, 2, { ITEM_MOD_SPELL_POWER = 14 } },
                { "Runed Scarlet Ruby",  39998, 3, { ITEM_MOD_SPELL_POWER = 19 } },
                { "Runed Cardinal Ruby", 40113, 4, { ITEM_MOD_SPELL_POWER = 23 } },
            } },
        },
        meta = { name = "Chaotic Skyflare Diamond", itemID = 41285,
                 note = "+21 crit, +3% crit dmg. activate: >=2 Blue gems", mods = { ITEM_MOD_CRIT_RATING_SHORT = 21 } },
    },
    healerCrit = {
        groups = {
            { label = "Intellect (all sockets) - yellow cut", tiers = {
                { "Brilliant Sun Crystal",   39912, 2, { ITEM_MOD_INTELLECT_SHORT = 12 } },
                { "Brilliant Autumn's Glow", 40012, 3, { ITEM_MOD_INTELLECT_SHORT = 16 } },
                { "Brilliant King's Amber",  40123, 4, { ITEM_MOD_INTELLECT_SHORT = 20 } },
            } },
        },
        meta = { name = "Insightful Earthsiege Diamond", itemID = 41401,
                 note = "+21 Int, chance to restore mana. activate: >=1 Red, 1 Yellow, 1 Blue gem", mods = { ITEM_MOD_INTELLECT_SHORT = 21 } },
    },
    tank = {
        groups = {
            { label = "Stamina (all sockets) - blue cut", tiers = {
                { "Solid Chalcedony",      39919, 2, { ITEM_MOD_STAMINA_SHORT = 18 } },
                { "Solid Sky Sapphire",    40008, 3, { ITEM_MOD_STAMINA_SHORT = 24 } },
                { "Solid Majestic Zircon", 40119, 4, { ITEM_MOD_STAMINA_SHORT = 30 } },
            } },
        },
        meta = { name = "Austere Earthsiege Diamond", itemID = 41380,
                 note = "+32 Sta, +2% armor. activate: >=2 Blue and 1 Red gem", mods = { ITEM_MOD_STAMINA_SHORT = 32 } },
    },
}
-- Resto druid/shaman share the healer gem plan (spirit/int lean refined by research).
G.List.casterHot = G.List.healerCrit

-- Socketing strategy (Warmane min-max): ONE meta gem, ONE all-stats prismatic
-- (Nightmare Tear) placed to satisfy the meta's colour requirement, and EVERY other
-- socket filled with the single best-stat gem above - ignore the socket bonus, because
-- the extra same-stat gem out-values the bonus. The Nightmare Tear is a prismatic gem
-- (counts as any colour) so a single one activates any meta. itemID name-guarded.
G.Activator = { name = "Nightmare Tear", itemID = 49110, quality = 4,
    note = "+10 all stats; prismatic - one activates any meta",
    mods = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 10,
             ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPIRIT_SHORT = 10 } }
G.Strategy = "Plan: 1 meta gem + 1 Nightmare Tear (activates the meta), every other socket = the best-stat gem below (ignore socket bonuses - the extra stat beats them)."

-- Per-spec overrides (SG.KeyFor() keys) where an archetype default is too coarse
-- (e.g. ArP-stacking combat rogue gems Armor Pen, not Agility). Populated by the
-- data-research pass; falls back to the archetype plan when absent.
G.BySpec = {}

function G.ForArchetype(arch) return G.List[arch] end

-- Resolve the best plan for the current player: spec override first, else archetype.
function G.ForPlayer()
    local IS = AIP.ItemScore
    local SG = AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    if key and G.BySpec[key] then return G.BySpec[key] end
    local arch = IS and IS.PlayerArchetype and IS.PlayerArchetype()
    return arch and G.List[arch] or nil
end

-- Warm the item cache so links resolve on first view (mirror BiSData).
local warm = CreateFrame("Frame")
warm:RegisterEvent("PLAYER_LOGIN")
warm:RegisterEvent("PLAYER_ENTERING_WORLD")
warm:SetScript("OnEvent", function()
    if not GetItemInfo then return end
    local function warmPlan(p)
        if not p then return end
        for _, grp in ipairs(p.groups or {}) do
            for _, t in ipairs(grp.tiers or {}) do if t[2] then GetItemInfo(t[2]) end end
        end
        if p.meta and p.meta.itemID then GetItemInfo(p.meta.itemID) end
    end
    for _, p in pairs(G.List) do warmPlan(p) end
    for _, p in pairs(G.BySpec) do warmPlan(p) end
    if G.Activator and G.Activator.itemID then GetItemInfo(G.Activator.itemID) end
end)

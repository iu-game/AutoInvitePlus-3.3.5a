-- AutoInvite Plus - Glyph name -> inscription itemID map (WotLK 3.3.5a).
-- Lets the Spec section render each recommended glyph (from SpecAdvisor.SA.Guide,
-- which stores glyph display names as CSV text) as a REAL item link with a tooltip.
--
-- DATA HONESTY: keys are the glyph display NAMES exactly as they appear in
-- SA.Guide[class][tree][3]; values are web-verified inscription itemIDs. Any name
-- not present here (or with a nil/stale id) falls back to plain coloured text via
-- LinkFor's name-guard, so a missing entry is never a wrong link. The research pass
-- fills ByName for every glyph named across all 30 specs' guides.
--
-- Naming: SA.Guide lists glyphs WITHOUT the "Glyph of " prefix (e.g. "Rending").
-- LinkFor tries the bare name first, then "Glyph of <name>", so either form maps.

local AIP = AutoInvitePlus
if not AIP then return end
AIP.GlyphData = AIP.GlyphData or {}
local GD = AIP.GlyphData

-- name (as written in SA.Guide) -> inscription itemID. Web-verified on wowhead/wotlk
-- (glyph research pass). Keys are the exact short names SpecAdvisor.SA.Guide uses.
GD.ByName = {
    -- Mage
    ["Arcane Blast"] = 44955, ["Arcane Missiles"] = 42735, ["Molten Armor"] = 42751,
    ["Fireball"] = 42739, ["Living Bomb"] = 45737, ["Frostbolt"] = 42742, ["Eternal Water"] = 50045,
    -- Warlock
    ["Life Tap"] = 45785, ["Haunt"] = 45779, ["Quick Decay"] = 50077, ["Felguard"] = 42459,
    ["Conflagrate"] = 42454, ["Imp"] = 42465,
    -- Priest
    ["Power Word: Shield"] = 42408, ["Penance"] = 45756, ["Flash Heal"] = 42400,
    ["Prayer of Healing"] = 42409, ["Circle of Healing"] = 42396, ["Mind Flay"] = 42415,
    ["Shadow"] = 42407, ["Shadow Word: Death"] = 42414,
    -- Druid
    ["Focus"] = 44928, ["Starfall"] = 40921, ["Insect Swarm"] = 40919, ["Mangle"] = 40900,
    ["Shred"] = 40901, ["Savage Roar"] = 45604, ["Maul"] = 40897, ["Rip"] = 40902,
    ["Swiftmend"] = 40906, ["Wild Growth"] = 45602, ["Nourish"] = 45603,
    -- Shaman
    ["Lightning Bolt"] = 41536, ["Flametongue"] = 41532, ["Totem of Wrath"] = 45776,
    ["Feral Spirit"] = 45771, ["Fire Nova"] = 41530, ["Stormstrike"] = 41539,
    ["Earth Shield"] = 45775, ["Chain Heal"] = 41517, ["Earthliving Weapon"] = 41527,
    -- Paladin
    ["Seal of Wisdom"] = 41109, ["Holy Light"] = 41106, ["Beacon of Light"] = 45741,
    ["Divine Plea"] = 45745, ["Seal of Vengeance"] = 43869, ["Judgement"] = 41092, ["Exorcism"] = 41103,
    -- Warrior
    ["Rending"] = 43423, ["Mortal Strike"] = 43421, ["Execution"] = 43416, ["Whirlwind"] = 43432,
    ["Heroic Strike"] = 43418, ["Blocking"] = 43425, ["Vigilance"] = 45793, ["Devastate"] = 43415,
    -- Death Knight
    ["Disease"] = 45805, ["Death Strike"] = 43827, ["Dancing Rune Weapon"] = 45799,
    ["Obliterate"] = 43547, ["Frost Strike"] = 43543, ["The Ghoul"] = 43549,
    ["Death and Decay"] = 43542, ["Icy Touch"] = 43546,
    -- Rogue
    ["Mutilate"] = 45768, ["Tricks"] = 45767, ["Hunger for Blood"] = 45761, ["Killing Spree"] = 45762,
    ["Sinister Strike"] = 42972, ["Hemorrhage"] = 42967, ["Shadow Dance"] = 45764,
    -- Hunter
    ["Steady Shot"] = 42914, ["Kill Shot"] = 45732, ["Explosive Trap"] = 45733,
    ["Serpent Sting"] = 42912, ["Explosive Shot"] = 45731,
}

-- Resolve a link for a recommended-glyph display name (name-guarded).
function GD.LinkFor(name)
    if not (name and GetItemInfo) then return nil end
    local id = GD.ByName[name] or GD.ByName["Glyph of " .. name] or GD.ByName[(name:gsub("^Glyph of ", ""))]
    if not id then return nil end
    local iname, ilink = GetItemInfo(id)
    if not (iname and ilink) then return nil end
    -- name-guard: the resolved item must share the recommended name's leading word
    local fw = name:gsub("^Glyph of ", ""):match("^(%a+)")
    if fw and iname:lower():find(fw:lower(), 1, true) then return ilink end
    return nil
end

local warm = CreateFrame("Frame")
warm:RegisterEvent("PLAYER_LOGIN")
warm:RegisterEvent("PLAYER_ENTERING_WORLD")
warm:SetScript("OnEvent", function()
    if not GetItemInfo then return end
    for _, id in pairs(GD.ByName) do if id then GetItemInfo(id) end end
end)

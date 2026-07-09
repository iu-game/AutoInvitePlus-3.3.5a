-- AutoInvite Plus - BiS / upgrade progression (WotLK 3.3.5a, ICC/RS endgame)
-- SEQUENTIAL per-slot chains: an easier "stepping-stone" item THEN the final BiS,
-- so the advisor promotes the next upgrade AND where it leads. Item IDs are
-- web-verified 3.3.5a raid drops / Emblem-of-Frost vendor items (so the links
-- resolve correctly); tier vendor pieces are shown by set name only because
-- their IDs diverge between original 3.3.5a and the 2022 re-release.
-- Keyed by AIP.ItemScore archetype. Each chain item = { name, itemID|nil, source, note }.

local AIP = AutoInvitePlus
if not AIP then return end
AIP.BiSData = AIP.BiSData or {}
local B = AIP.BiSData

B.List = {
    strDPS = {
        { slot = "2H Weapon", chain = {
            { "Bryntroll, the Bone Arbiter", 50415, "ICC 25 BoE drop (ilvl 264)", "budget / entry 2H" },
            { "Glorenzelg, High-Blade of the Silver Hand", 50730, "The Lich King (ICC 25H, ilvl 284)", "raid BiS 2H" },
            { "Shadowmourne", 49623, "Legendary quest chain (ilvl 284)", "ultimate BiS" },
        } },
        { slot = "Trinket 1", chain = {
            { "Herkuml War Token", 50355, "Emblem of Frost vendor", "buy w/ Emblems of Frost" },
            { "Whispering Fanged Skull", 50342, "Lady Deathwhisper (ICC 25)", "boss drop - BiS" },
        } },
        { slot = "Trinket 2", chain = {
            { "Deathbringer's Will", 50362, "Deathbringer Saurfang (ICC 25)", "boss drop" },
            { "Sharpened Twilight Scale", 54569, "Halion (Ruby Sanctum 25)", "boss drop - top ArP" },
        } },
        { slot = "Tier (T10)", chain = {
            { "Scourgelord / Ymirjar / Lightsworn Battlegear", nil, "EoF (251) -> Sanctified 264", "Emblems + ICC tokens" },
        } },
    },
    agiDPS = {
        { slot = "Weapon", chain = {
            { "Havoc's Call, Blade of Lordaeron Kings", 50737, "The Lich King (ICC 25)", "boss drop (main-hand)" },
            { "Heaven's Fall, Kryss of a Thousand Lies", 50736, "The Lich King (ICC 25)", "boss drop (off-hand)" },
        } },
        { slot = "Ranged (Hunter)", chain = {
            { "Zod's Repeating Longbow", 50034, "Lady Deathwhisper (ICC 25, ilvl 264)", "strong early bow" },
            { "Fal'inrush, Defender of Quel'thalas", 50733, "The Lich King (ICC 25H, ilvl 284)", "true Hunter BiS ranged" },
        } },
        { slot = "Trinket 1", chain = {
            { "Herkuml War Token", 50355, "Emblem of Frost vendor", "buy w/ Emblems of Frost" },
            { "Whispering Fanged Skull", 50342, "Lady Deathwhisper (ICC 25)", "boss drop - BiS" },
        } },
        { slot = "Trinket 2", chain = {
            { "Deathbringer's Will", 50362, "Deathbringer Saurfang (ICC 25)", "boss drop" },
            { "Sharpened Twilight Scale", 54569, "Halion (Ruby Sanctum 25)", "boss drop - top ArP" },
        } },
        { slot = "Tier (T10)", chain = {
            { "Shadowblade / Ahn'Kahar / Frost Witch Battlegear", nil, "EoF (251) -> Sanctified 264", "Emblems + ICC tokens" },
        } },
    },
    casterDPS = {
        { slot = "Weapon", chain = {
            { "Nibelung", 49992, "Lady Deathwhisper (ICC 25, ilvl 264)", "proc staff alt" },
            { "Bloodsurge, Kel'Thuzad's Blade of Agony", 50732, "The Lich King (ICC 25H, ilvl 284)", "1H stat BiS" },
        } },
        { slot = "Trinket 1", chain = {
            { "Reign of the Unliving", 47182, "Trial of the Crusader 25", "boss drop" },
            { "Sliver of Pure Ice", 50339, "Lord Marrowgar (ICC 25)", "boss drop" },
            { "Phylactery of the Nameless Lich", 50365, "Professor Putricide (ICC 25)", "boss drop - BiS" },
        } },
        { slot = "Trinket 2", chain = {
            { "Charred Twilight Scale", 54588, "Halion (Ruby Sanctum 25)", "boss drop - spell power" },
        } },
        { slot = "Tier (T10)", chain = {
            { "Bloodmage / Dark Coven / Crimson Acolyte Regalia", nil, "EoF (251) -> Sanctified 264", "Emblems + ICC tokens" },
        } },
    },
    healerCrit = {
        { slot = "Weapon", chain = {
            { "Royal Scepter of Terenas II", 50734, "The Lich King (ICC 25)", "boss drop (mace)" },
            { "Nibelung", 49992, "Lady Deathwhisper (ICC 25)", "boss drop (staff alt)" },
        } },
        { slot = "Trinket 1", chain = {
            { "Solace of the Defeated", 47041, "Emblem of Frost vendor", "buy w/ Emblems of Frost" },
            { "Purified Lunar Dust", 50358, "Emblem of Frost vendor", "buy w/ Emblems of Frost" },
        } },
        { slot = "Trinket 2", chain = {
            { "Sindragosa's Flawless Fang", 50361, "Sindragosa (ICC 25)", "boss drop (SP + haste)" },
            { "Charred Twilight Scale", 54588, "Halion (Ruby Sanctum 25)", "boss drop" },
        } },
        { slot = "Tier (T10)", chain = {
            { "Lightsworn / Frost Witch / Crimson Acolyte Garb", nil, "EoF (251) -> Sanctified 264", "Emblems + ICC tokens" },
        } },
    },
    tank = {
        { slot = "Shield", chain = {
            { "Bulwark of Smouldering Steel", 50616, "Lord Marrowgar (ICC 25)", "boss drop" },
        } },
        { slot = "1H Weapon", chain = {
            { "Havoc's Call, Blade of Lordaeron Kings", 50737, "The Lich King (ICC 25)", "boss drop" },
        } },
        { slot = "Trinket 1", chain = {
            { "Corpse Tongue Coin", 50352, "Lord Marrowgar (ICC 25)", "boss drop" },
        } },
        { slot = "Trinket 2", chain = {
            { "Petrified Twilight Scale", 54571, "Halion (Ruby Sanctum 25)", "boss drop (tank)" },
        } },
        { slot = "Tier (T10)", chain = {
            { "Ymirjar / Lightsworn / Scourgelord Plate", nil, "EoF (251) -> Sanctified 264", "Emblems + ICC tokens" },
        } },
    },
}
-- Resto druid/shaman share the healer chain.
B.List.casterHot = B.List.healerCrit

-- Class-aware Sanctified T10 (ilvl 264, 25-Normal) FULL 5-piece sets, keyed by
-- class then archetype -> { setName, head, shoulders, chest, hands, legs }.
-- IDs are ORIGINAL-3.3.5a values (verified on db.rising-gods.de / cavernoftime -
-- the 511xx range, NOT the 2022 Classic 512xx renumbering). Priest/Druid pending.
B.Tier = {
    WARRIOR = {
        strDPS = { "Ymirjar Lord's Battlegear", 51212, 51210, 51214, 51213, 51211 },
        tank   = { "Ymirjar Lord's Plate",      51218, 51215, 51219, 51217, 51216 },
    },
    PALADIN = {
        strDPS     = { "Lightsworn Battlegear", 51162, 51160, 51164, 51163, 51161 },
        tank       = { "Lightsworn Plate",      51173, 51170, 51174, 51172, 51171 },
        healerCrit = { "Lightsworn Garb",       51167, 51166, 51165, 51169, 51168 },
    },
    DEATHKNIGHT = {
        strDPS = { "Scourgelord Battlegear", 51127, 51125, 51134, 51128, 51126 },
        tank   = { "Scourgelord Plate",      51133, 51130, 51129, 51132, 51131 },
    },
    HUNTER = { agiDPS = { "Ahn'Kahar Blood Hunter's Battlegear", 51153, 51151, 51150, 51154, 51152 } },
    ROGUE  = { agiDPS = { "Shadowblade's Battlegear", 51187, 51185, 51189, 51188, 51186 } },
    SHAMAN = {
        agiDPS    = { "Frost Witch's Battlegear", 51197, 51199, 51195, 51196, 51198 },
        casterDPS = { "Frost Witch's Regalia",    51202, 51204, 51200, 51201, 51203 },
        casterHot = { "Frost Witch's Garb",       51192, 51194, 51190, 51191, 51193 },
    },
    MAGE    = { casterDPS = { "Bloodmage's Regalia", 51158, 51155, 51156, 51159, 51157 } },
    WARLOCK = { casterDPS = { "Dark Coven's Regalia", 51208, 51205, 51206, 51209, 51207 } },
}
B.TierSlots = { "Helm", "Shoulders", "Chest", "Hands", "Legs" }

function B.TierFor(class, arch)
    return B.Tier[class] and B.Tier[class][arch]
end

-- Normal (25N) itemID -> its 25-Heroic counterpart, so the advisor lists the
-- heroic upgrade of a drop alongside the normal one. Verified 3.3.5a raid IDs.
B.Heroic = {
    [50342] = 50343,  -- Whispering Fanged Skull
    [50362] = 50363,  -- Deathbringer's Will
    [54569] = 54590,  -- Sharpened Twilight Scale
    [50415] = 50709,  -- Bryntroll, the Bone Arbiter
    [50034] = 50638,  -- Zod's Repeating Longbow
    [50339] = 50346,  -- Sliver of Pure Ice
    [50352] = 50349,  -- Corpse Tongue Coin
    [47182] = 47188,  -- Reign of the Unliving
}

-- Warm the item cache so GetItemInfo resolves the links on first view.
local warm = CreateFrame("Frame")
warm:RegisterEvent("PLAYER_LOGIN")
warm:RegisterEvent("PLAYER_ENTERING_WORLD")   -- also fires on /reload, unlike PLAYER_LOGIN
warm:SetScript("OnEvent", function()
    if not GetItemInfo then return end
    for _, slots in pairs(B.List) do
        for _, s in ipairs(slots) do
            for _, it in ipairs(s.chain) do if it[2] then GetItemInfo(it[2]) end end
        end
    end
    for _, roles in pairs(B.Tier) do
        for _, t in pairs(roles) do
            for i = 2, 6 do if t[i] then GetItemInfo(t[i]) end end
        end
    end
    for _, hid in pairs(B.Heroic) do GetItemInfo(hid) end
end)

function B.ForArchetype(arch)
    return B.List[arch] or {}
end

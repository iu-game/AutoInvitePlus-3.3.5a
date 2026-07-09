-- AutoInvite Plus - Upgrade Path ("which raid to run for better gear")
-- Honest, computable guidance (no fabricated item-ID loot DB):
--   1. Weakest slots - your lowest item-level equipped pieces = upgrade priorities.
--   2. Progression - what content your GearScore/avg-iLvl says to run next
--      (reuses AIP's existing content-tier data when present).
--   3. Slot -> best-source hints at the endgame (raid-level, curated).
--   4. Item check - score any item link vs what you have equipped (via ItemScore).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.UpgradePath = AIP.UpgradePath or {}
local UP = AIP.UpgradePath
local IS = AIP.ItemScore

local SLOT_NAME = { [1]="Head",[2]="Neck",[3]="Shoulder",[5]="Chest",[6]="Waist",
    [7]="Legs",[8]="Feet",[9]="Wrist",[10]="Hands",[11]="Ring",[12]="Ring",
    [13]="Trinket",[14]="Trinket",[15]="Back",[16]="Main Hand",[17]="Off Hand",[18]="Ranged" }
local SLOTS = {1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18}

-- Fallback progression when AIP.Composition tier data isn't available. Ranges
-- are average equipped item level (a decent proxy for readiness on 3.3.5a).
local PROGRESSION = {
    { max=170, run="Heroic dungeons + Trial of the Champion (5m)", why="build a pre-raid set" },
    { max=200, run="Naxxramas 10, OS, EoE, VoA10, ToC5 HC", why="entry raid tier (iLvl 200)" },
    { max=213, run="Ulduar 10, ToC10, VoA10", why="mid tier (iLvl 213-226)" },
    { max=232, run="Ulduar 25 / ToC25 / hard modes", why="upper tier (iLvl 232-245)" },
    { max=251, run="ICC 10, Ruby Sanctum 10", why="ICC-normal tier (iLvl 251)" },
    { max=999, run="ICC 25 (+ heroic) & RS 25 for BiS", why="endgame - chase 264/277 pieces" },
}

-- Endgame slot -> where the strongest upgrades typically drop (raid-level, no
-- item IDs so nothing here can be wrong/stale). Guidance, not a loot table.
local SOURCE_HINTS = {
    Trinket   = "ICC bosses, VoA (Toravon/Koralon), ToC25",
    ["Main Hand"] = "ICC wings (Saurfang, Sindragosa, Lich King), RS",
    Ranged    = "ICC + ToC25",
    Neck      = "ICC / RS drops & badge (Emblem of Frost) vendor",
    Ring      = "ICC / RS + Emblem of Frost vendor",
    Back      = "ICC + Emblem of Frost vendor",
    Waist     = "ICC + Emblem of Frost vendor",
    Wrist     = "ICC + Emblem of Frost vendor",
    Head      = "ICC tier tokens (Frost) + Emblem vendor",
    Shoulder  = "ICC tier tokens (Frost) + Emblem vendor",
    Chest     = "ICC tier tokens (Frost) + Emblem vendor",
    Hands     = "ICC tier tokens (Frost) + Emblem vendor",
    Legs      = "ICC tier tokens (Frost) + Emblem vendor",
}

-- Average equipped item level.
function UP.AvgItemLevel()
    local total, n = 0, 0
    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local ilvl = select(4, GetItemInfo(link))
            if ilvl and ilvl > 0 then total = total + ilvl; n = n + 1 end
        end
    end
    if n == 0 then return 0, 0 end
    return math.floor(total / n), n
end

-- Weakest N equipped slots by item level (upgrade priorities).
function UP.WeakestSlots(n)
    n = n or 4
    local rows = {}
    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local ilvl = select(4, GetItemInfo(link)) or 0
            rows[#rows + 1] = { slot = slot, ilvl = ilvl, link = link }
        else
            rows[#rows + 1] = { slot = slot, ilvl = 0, link = nil }  -- empty slot = top priority
        end
    end
    table.sort(rows, function(a, b) return a.ilvl < b.ilvl end)
    local out = {}
    for i = 1, math.min(n, #rows) do out[i] = rows[i] end
    return out
end

function UP.RecommendContent(avg)
    -- Progression by average equipped item level (a solid readiness proxy on
    -- 3.3.5a). Kept self-contained and honest rather than guessing at another
    -- module's internal tier shape.
    for _, p in ipairs(PROGRESSION) do
        if avg <= p.max then return p.run, p.why end
    end
    return PROGRESSION[#PROGRESSION].run, PROGRESSION[#PROGRESSION].why
end

-- ============================================================================
-- Report
-- ============================================================================
function UP.Report()
    local avg = UP.AvgItemLevel()
    AIP.Print("|cFF66CCFFUpgrade Path|r (avg equipped iLvl: " .. avg .. ")")

    local run, why = UP.RecommendContent(avg)
    AIP.Print("  |cFFFFFF00Run next:|r " .. run .. "  |cFF888888(" .. why .. ")|r")

    AIP.Print("  |cFFFFFF00Weakest slots (upgrade first):|r")
    for _, r in ipairs(UP.WeakestSlots(4)) do
        local name = SLOT_NAME[r.slot] or ("#" .. r.slot)
        local hint = SOURCE_HINTS[name]
        if not r.link then
            AIP.Print("   |cFFFF6060" .. name .. ": EMPTY|r" .. (hint and ("  -> " .. hint) or ""))
        else
            AIP.Print(string.format("   %s (iLvl %d)%s", name, r.ilvl, hint and ("  -> " .. hint) or ""))
        end
    end
end

-- Score a specific item link vs what you have equipped in its slot.
-- Accepts a raw item link (e.g. shift-clicked into the command).
function UP.CheckItem(text)
    if not IS then AIP.Print("Needs the ItemScore module."); return end
    local link = text and text:match("|c%x+|Hitem:.-|h.-|h|r")
    if not link then AIP.Print("Usage: /aip upgrade [shift-click an item]"); return end
    local score, stats = IS.ScoreLink(link)
    if not score then AIP.Print("Item not cached yet - try again in a moment."); return end
    local equipLoc = select(9, GetItemInfo(link))
    local slotMap = { INVTYPE_HEAD=1, INVTYPE_NECK=2, INVTYPE_SHOULDER=3, INVTYPE_CHEST=5,
        INVTYPE_ROBE=5, INVTYPE_WAIST=6, INVTYPE_LEGS=7, INVTYPE_FEET=8, INVTYPE_WRIST=9,
        INVTYPE_HAND=10, INVTYPE_FINGER=11, INVTYPE_TRINKET=13, INVTYPE_CLOAK=15,
        INVTYPE_WEAPONMAINHAND=16, INVTYPE_2HWEAPON=16, INVTYPE_WEAPON=16,
        INVTYPE_WEAPONOFFHAND=17, INVTYPE_HOLDABLE=17, INVTYPE_SHIELD=17,
        INVTYPE_RANGED=18, INVTYPE_RANGEDRIGHT=18, INVTYPE_THROWN=18, INVTYPE_RELIC=18 }
    local slot = equipLoc and slotMap[equipLoc]
    local eqScore = 0
    if slot then
        local eqLink = GetInventoryItemLink("player", slot)
        if eqLink then eqScore = IS.ScoreLink(eqLink) or 0 end
    end
    if eqScore > 0 then
        local pct = (score / eqScore - 1) * 100
        if pct > 1 then
            AIP.Print(string.format("|cFF00FF00UPGRADE:|r %s is +%.0f%% vs your equipped.", link, pct))
        elseif pct < -1 then
            AIP.Print(string.format("|cFFFF6060Downgrade:|r %s is %.0f%% vs your equipped.", link, pct))
        else
            AIP.Print("Sidegrade: " .. link .. " (~equal).")
        end
    else
        AIP.Print(link .. " scores " .. math.floor(score) .. " for your spec (no item equipped to compare).")
    end
end

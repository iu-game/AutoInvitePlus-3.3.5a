-- AutoInvite Plus - LFM/LFG Message Formatter
-- THE single source of truth for building LFM and LFG chat strings.
--
-- Why: the LFM string used to be built in two places with different layouts
-- (AddGroupPopup vs RegenerateBroadcastMessage), so the message silently
-- changed shape the first time someone joined the group and downstream
-- parsers (ParseFilledCount, ParseLookingFor) stopped matching. Every
-- producer - popup Create, live preview, composition regeneration, test
-- fixtures - must call these builders.
--
-- Wire-format rules (validated against core/Parsers.lua):
--   * The weekly token is UNBRACKETED ("WQ:Marrowgar"): ParseAchievement
--     grabs the last [...] in a message, so a bracketed token would be
--     misread as an achievement name.
--   * WQ sits right after the raid key, BEFORE the achievement link, so
--     length-trimming can never cut a hyperlink in half around it.
--   * Chat messages hard-cap at 255 bytes; when over, optional segments are
--     dropped in priority order: [Res:] -> note -> achievement -> spec array.
--     The raid key, counts, requirements and keyword always survive.

local AIP = AutoInvitePlus
AIP.LFMFormat = AIP.LFMFormat or {}
local LF = AIP.LFMFormat

LF.MAX_LEN = 255

-- Ultra-short spec codes for the "[T:PP,BDK H:HP ...]" looking-for block.
-- (Moved from the AddGroupPopup inline table so there is exactly one copy.)
LF.SpecCodes = {
    -- Tanks
    WARRIOR_Protection = "PW",
    PALADIN_Protection = "PP",
    DEATHKNIGHT_Blood = "BDK",
    DRUID_FeralBear = "BD",
    -- Healers
    PRIEST_Holy = "HP",
    PRIEST_Discipline = "DP",
    PALADIN_Holy = "HPal",
    DRUID_Restoration = "RD",
    SHAMAN_Restoration = "RS",
    -- Melee DPS
    WARRIOR_ArmsFury = "AW",
    PALADIN_Retribution = "Ret",
    DEATHKNIGHT_Frost = "FDK",
    DEATHKNIGHT_Unholy = "UDK",
    ROGUE_All = "Rog",
    DRUID_FeralCat = "FD",
    SHAMAN_Enhancement = "Enh",
    -- Ranged DPS
    MAGE_All = "Mag",
    WARLOCK_All = "Loc",
    HUNTER_All = "Hun",
    DRUID_Balance = "Boom",
    SHAMAN_Elemental = "Ele",
    PRIEST_Shadow = "SP",
}

-- specData ({class="WARRIOR", spec="Arms/Fury"}) -> code table key
function LF.SpecCodeKey(specData)
    local specKey = specData.spec:gsub("%s+", ""):gsub("[%(%)/-]", "")
    return specData.class .. "_" .. specKey
end

function LF.SpecCode(specData)
    return LF.SpecCodes[LF.SpecCodeKey(specData)]
        or (specData.class:sub(1, 1) .. specData.spec:sub(1, 1))
end

-- roleSpecs {TANK={"PP","BDK"}, HEALER={...}, MDPS={...}, RDPS={...}}
-- -> "[T:PP,BDK H:HP M:AW R:Mag]" or "" when empty
function LF.RoleSpecString(roleSpecs)
    if not roleSpecs then return "" end
    local parts = {}
    if roleSpecs.TANK and #roleSpecs.TANK > 0 then
        parts[#parts + 1] = "T:" .. table.concat(roleSpecs.TANK, ",")
    end
    if roleSpecs.HEALER and #roleSpecs.HEALER > 0 then
        parts[#parts + 1] = "H:" .. table.concat(roleSpecs.HEALER, ",")
    end
    if roleSpecs.MDPS and #roleSpecs.MDPS > 0 then
        parts[#parts + 1] = "M:" .. table.concat(roleSpecs.MDPS, ",")
    end
    if roleSpecs.RDPS and #roleSpecs.RDPS > 0 then
        parts[#parts + 1] = "R:" .. table.concat(roleSpecs.RDPS, ",")
    end
    if #parts == 0 then return "" end
    return "[" .. table.concat(parts, " ") .. "]"
end

-- Join non-empty string segments with single spaces
local function joinParts(parts)
    local out = {}
    for _, p in ipairs(parts) do
        if p and p ~= "" then out[#out + 1] = p end
    end
    return table.concat(out, " ")
end

-- ============================================================================
-- LFM
-- ============================================================================

-- cfg = {
--   raidKey        "ICC25H" (required)
--   weekly         "Marrowgar" (optional token)
--   filled, total  numbers for the [x/y] block (default 0 / sum of needs)
--   tanks, healers, mdps, rdps  = {current=n, needed=n} (numbers also accepted as needed)
--   gsMin, ilvlMin numbers
--   roleSpecs      {TANK={codes}, ...}
--   keyword        invite keyword (w/ "kw")
--   achievementLink  full |Hachievement:...| link string (or "" / nil)
--   note           free text
--   reservedItems  newline- or comma-separated reserved list (or "" / nil)
-- }
-- Returns: message, trimmed  (trimmed = list of segment names dropped for length)
function LF.BuildLFM(cfg)
    local function rc(role)  -- role counts {current, needed} with number fallback
        local r = cfg[role]
        if type(r) == "table" then
            return r.current or 0, r.needed or 0
        end
        return 0, tonumber(r) or 0
    end

    local tc, tn = rc("tanks")
    local hc, hn = rc("healers")
    local mc, mn = rc("mdps")
    local rcur, rn = rc("rdps")

    local total = cfg.total or (tn + hn + mn + rn)
    local filled = cfg.filled or (tc + hc + mc + rcur)

    local head = "LFM " .. cfg.raidKey
    local weekly = cfg.weekly and cfg.weekly ~= "" and ("WQ:" .. cfg.weekly) or ""
    local counts = string.format("[%d/%d] [T:%d/%d H:%d/%d M:%d/%d R:%d/%d]",
        filled, total, tc, tn, hc, hn, mc, mn, rcur, rn)

    local gs = (cfg.gsMin and cfg.gsMin > 0) and (tostring(cfg.gsMin) .. "+") or ""
    local ilvl = (cfg.ilvlMin and cfg.ilvlMin > 0) and ("iLvl:" .. tostring(cfg.ilvlMin) .. "+") or ""
    local specs = LF.RoleSpecString(cfg.roleSpecs)
    local kw = (cfg.keyword and cfg.keyword ~= "") and string.format('w/ "%s"', cfg.keyword) or ""
    local achieve = cfg.achievementLink or ""
    local note = cfg.note or ""

    local reserved = ""
    if cfg.reservedItems and cfg.reservedItems ~= "" then
        local itemList = cfg.reservedItems:gsub("\n", ", "):gsub(", $", "")
        if itemList ~= "" then
            reserved = "[Res: " .. itemList .. "]"
        end
    end

    -- Assemble, then trim optional segments (lowest value first) until <= 255.
    local trimmed = {}
    local segments = { reserved = reserved, note = note, achieve = achieve, specs = specs }
    local dropOrder = { "reserved", "note", "achieve", "specs" }

    local function assemble()
        return joinParts({ head, weekly, counts, gs, ilvl, segments.specs, kw, segments.achieve, segments.note, segments.reserved })
    end

    local msg = assemble()
    for _, name in ipairs(dropOrder) do
        if #msg <= LF.MAX_LEN then break end
        if segments[name] ~= "" then
            segments[name] = ""
            trimmed[#trimmed + 1] = name
            msg = assemble()
        end
    end
    if #msg > LF.MAX_LEN then
        -- Mandatory core alone is over-long (absurd raid key/keyword) - hard cut
        msg = msg:sub(1, LF.MAX_LEN)
        trimmed[#trimmed + 1] = "hard-cut"
    end

    return msg, trimmed
end

-- ============================================================================
-- LFG (enrollment)
-- ============================================================================

-- cfg = {
--   raidKey, classShort ("War"), spec ("Arms"), role ("DPS"), gs, ilvl, level,
--   achievementLink, note, weekly ("Marrowgar")
-- }
-- The weekly token goes AFTER the {AIP:x} tag: all three peer-parse regexes
-- capture only up to Lv:<n> and ignore trailing text, so this is append-safe.
function LF.BuildLFG(cfg)
    local msg = string.format("LFG %s - %s (%s) %s - GS:%d iL:%d Lv:%d {AIP:5.2}",
        cfg.raidKey,
        cfg.classShort or "?",
        cfg.spec or "Unknown",
        cfg.role or "DPS",
        cfg.gs or 0,
        cfg.ilvl or 0,
        cfg.level or 80)

    if cfg.achievementLink and cfg.achievementLink ~= "" then
        msg = msg .. " " .. cfg.achievementLink
    end
    if cfg.note and cfg.note ~= "" then
        msg = msg .. " " .. cfg.note
    end
    if cfg.weekly and cfg.weekly ~= "" then
        msg = msg .. " WQ:" .. cfg.weekly
    end

    if #msg > LF.MAX_LEN then
        -- Drop note, then achievement; the identity core must survive intact
        if cfg.note and cfg.note ~= "" then
            local retry = { }
            for k, v in pairs(cfg) do retry[k] = v end
            retry.note = nil
            return LF.BuildLFG(retry)
        end
        if cfg.achievementLink and cfg.achievementLink ~= "" then
            local retry = { }
            for k, v in pairs(cfg) do retry[k] = v end
            retry.achievementLink = nil
            return LF.BuildLFG(retry)
        end
        msg = msg:sub(1, LF.MAX_LEN)
    end

    return msg
end

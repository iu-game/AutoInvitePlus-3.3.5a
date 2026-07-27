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

-- Short need codes for the "[Need: 2xMag 1xPP]" block. Keyed role -> class so
-- a class needed as TANK reads differently than the same class as DPS.
LF.NeedCodes = {
    TANK   = {WARRIOR = "PW", PALADIN = "PP", DEATHKNIGHT = "BDK", DRUID = "BD"},
    HEALER = {PRIEST = "HP", PALADIN = "HPal", DRUID = "RD", SHAMAN = "RS"},
    DPS    = {WARRIOR = "AW", PALADIN = "Ret", DEATHKNIGHT = "DK", DRUID = "Dru",
              ROGUE = "Rog", SHAMAN = "Sham", MAGE = "Mag", WARLOCK = "Loc",
              HUNTER = "Hun", PRIEST = "SP"},
}

function LF.NeedCode(class, role)
    local m = role and LF.NeedCodes[role:upper()]
    local code = m and class and m[class:upper()]
    if code then return code end
    if class then return class:sub(1, 1) .. class:sub(2, 3):lower() end
    return "?"
end

-- classNeeds {{class="MAGE", role="DPS", count=2}, ...} (Comp.GetClassNeeds
-- list shape) -> "[Need: 2xMag 1xPP]" or "" when empty/all filled.
-- Capped: a fresh 25-man aggregates 10+ class rows (~120 bytes) which would
-- starve the note/achievement/specs segments out of the 255-byte budget, so
-- only the first MAX_NEED_PARTS rows render and the rest collapse to "+N".
LF.MAX_NEED_PARTS = 5

function LF.ClassNeedString(classNeeds)
    if not classNeeds or #classNeeds == 0 then return "" end
    local parts, overflow = {}, 0
    for _, n in ipairs(classNeeds) do
        if (n.count or 0) > 0 then
            if #parts < LF.MAX_NEED_PARTS then
                parts[#parts + 1] = tostring(n.count) .. "x" .. LF.NeedCode(n.class, n.role)
            else
                overflow = overflow + n.count
            end
        end
    end
    if #parts == 0 then return "" end
    if overflow > 0 then
        parts[#parts + 1] = "+" .. overflow
    end
    return "[Need: " .. table.concat(parts, " ") .. "]"
end

-- Reverse map: need code -> {class, role}. Codes are globally unique across
-- the three role tables (verified), so a bare code fully identifies both.
-- Keyed lowercase so chat-cased variants ("mag") still resolve.
LF.NeedCodeInfo = nil
local function needCodeInfo()
    if LF.NeedCodeInfo then return LF.NeedCodeInfo end
    local map = {}
    for role, classes in pairs(LF.NeedCodes) do
        for class, code in pairs(classes) do
            map[code:lower()] = { class = class, role = role }
        end
    end
    LF.NeedCodeInfo = map
    return map
end

-- ============================================================================
-- DATABUS WIRE CODEC
-- Compact encodings for the LFM DataBus event. The old payload shipped four
-- {current,needed} dicts plus a nested roleSpecs table: ~300+ serialized
-- bytes, over the 255-byte addon-message cap, so every detailed LFM
-- broadcast was silently dropped ("message_too_long"). These strings keep
-- the same information in a fraction of the space.
-- ============================================================================

-- classNeeds {{class,role,count},...} -> "2xMag,1xPP" ("" when empty).
-- Full fidelity (no display cap) - DataBus trims tail entries if oversize.
function LF.EncodeNeeds(classNeeds)
    if not classNeeds then return "" end
    local parts = {}
    for _, n in ipairs(classNeeds) do
        if (n.count or 0) > 0 then
            parts[#parts + 1] = tostring(n.count) .. "x" .. LF.NeedCode(n.class, n.role)
        end
    end
    return table.concat(parts, ",")
end

-- "2xMag,1xPP" (also accepts the chat form "2xMag 1xPP +3") -> classNeeds
-- list, or nil when nothing decodes. Unknown codes and the "+N" overflow
-- marker are skipped - never guess a class.
function LF.DecodeNeeds(str)
    if not str or str == "" then return nil end
    local map = needCodeInfo()
    local out = {}
    for count, code in str:gmatch("(%d+)x(%a+)") do
        local info = map[code:lower()]
        if info then
            out[#out + 1] = { class = info.class, role = info.role, count = tonumber(count) }
        end
    end
    if #out == 0 then return nil end
    return out
end

-- Role tables -> "1/2,4/6,3/8,4/9" (T,H,M,R current/needed - fixed order)
function LF.EncodeComp(g)
    local function pair(r)
        if type(r) ~= "table" then return "0/0" end
        return (r.current or 0) .. "/" .. (r.needed or 0)
    end
    return pair(g.tanks) .. "," .. pair(g.healers) .. "," .. pair(g.mdps) .. "," .. pair(g.rdps)
end

-- "1/2,4/6,3/8,4/9" -> tanks, healers, mdps, rdps dicts (nil on mismatch)
function LF.DecodeComp(str)
    if not str then return nil end
    local tc, tn, hc, hn, mc, mn, rc, rn =
        str:match("^(%d+)/(%d+),(%d+)/(%d+),(%d+)/(%d+),(%d+)/(%d+)$")
    if not tc then return nil end
    return { current = tonumber(tc), needed = tonumber(tn) },
           { current = tonumber(hc), needed = tonumber(hn) },
           { current = tonumber(mc), needed = tonumber(mn) },
           { current = tonumber(rc), needed = tonumber(rn) }
end

-- roleSpecs table -> "T:PW,BDK H:HP M:AW R:Mag" (the chat block minus its
-- brackets, so Parsers.ParseLookingFor decodes it back with zero new code)
function LF.EncodeRoleSpecs(roleSpecs)
    local s = LF.RoleSpecString(roleSpecs)
    if s == "" then return "" end
    return (s:gsub("^%[", ""):gsub("%]$", ""))
end

-- "T:PW,BDK H:HP" -> roleSpecs, lookingForSpecs (nil, nil when empty)
function LF.DecodeRoleSpecs(str)
    if not str or str == "" then return nil, nil end
    if not (AIP.Parsers and AIP.Parsers.ParseLookingFor) then return nil, nil end
    return AIP.Parsers.ParseLookingFor("[" .. str .. "]")
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
--   classNeeds     {{class, role, count}, ...} -> "[Need: 2xMag 1xPP]" block
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
    local need = LF.ClassNeedString(cfg.classNeeds)
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
    -- The need block drops BEFORE the specs block: [T:...] roleSpecs remains the
    -- older, primary machine-readable signal peers rely on everywhere, so it's
    -- protected longer under the byte budget. Parsers.ParseClassNeeds does parse
    -- [Need:] too (wired into ParseChatMessage), it's just the newer/secondary signal.
    local trimmed = {}
    local segments = { reserved = reserved, note = note, achieve = achieve, specs = specs, need = need }
    local dropOrder = { "reserved", "note", "achieve", "need", "specs" }

    local function assemble()
        return joinParts({ head, weekly, counts, segments.need, gs, ilvl, segments.specs, kw, segments.achieve, segments.note, segments.reserved })
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

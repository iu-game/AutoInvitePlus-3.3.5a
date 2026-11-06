-- ============================================================================
-- WindowProfiles.lua - one place that answers "is this popup / bar allowed?"
--
-- The eight window/bar switches (Settings > Windows & Bars) can be set
-- account-wide (db[key]) or overridden per character
-- (db.windowsByChar[CharKey][key]). Gating code asks WP.Get(key). Also hosts
-- named profiles, a position reset for every movable AIP window, and a safe
-- (no loadstring) settings export / import.
-- ============================================================================
AutoInvitePlus = AutoInvitePlus or {}
local AIP = AutoInvitePlus
AIP.WindowProfiles = AIP.WindowProfiles or {}
local WP = AIP.WindowProfiles

WP.KEYS = {
    "tankCastEnabled", "raidGroupsEnabled", "autoShowOnGroup", "restoreWindowsOnLogin",
    "floatingBarEnabled", "timerBarsEnabled", "minimapBubbles", "assignmentToasts", "voaBanner",
}

local DEFAULT_OFF = { floatingBarEnabled = true }   -- everything else defaults to ON

local function isKey(key)
    for _, k in ipairs(WP.KEYS) do if k == key then return true end end
    return false
end

local function charKey()
    return (AIP.Utils and AIP.Utils.CharKey and AIP.Utils.CharKey()) or "?"
end

local function overrides(create)
    local db = AIP.db
    if type(db) ~= "table" then return nil end
    if type(db.windowsByChar) ~= "table" then
        if not create then return nil end
        db.windowsByChar = {}
    end
    local ck = charKey()
    if type(db.windowsByChar[ck]) ~= "table" then
        if not create then return nil end
        db.windowsByChar[ck] = {}
    end
    return db.windowsByChar[ck]
end

-- Effective boolean: per-character override, else account-wide value, else default.
function WP.Get(key)
    local o = overrides(false)
    if o and o[key] ~= nil then return o[key] and true or false end
    local db = AIP.db
    if db and db[key] ~= nil then return db[key] and true or false end
    return not DEFAULT_OFF[key]
end

function WP.HasOverride(key)
    local o = overrides(false)
    return o ~= nil and o[key] ~= nil
end

-- perCharacter=true writes this character's override (value nil removes it);
-- otherwise the account-wide value.
function WP.Set(key, value, perCharacter)
    if not isKey(key) or type(AIP.db) ~= "table" then return false end
    if perCharacter then
        local o = overrides(true)
        if value == nil then o[key] = nil else o[key] = value and true or false end
    else
        AIP.db[key] = value and true or false
    end
    return true
end

function WP.ClearOverrides()
    local db = AIP.db
    if type(db) == "table" and type(db.windowsByChar) == "table" then
        db.windowsByChar[charKey()] = nil
    end
end

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
local function profile(on)
    local t = {}
    for _, k in ipairs(WP.KEYS) do t[k] = false end
    for _, k in ipairs(on) do t[k] = true end
    return t
end

WP.Profiles = {
    Minimal    = profile({}),
    RaidLeader = profile({ "tankCastEnabled", "raidGroupsEnabled", "autoShowOnGroup",
                           "restoreWindowsOnLogin", "timerBarsEnabled", "assignmentToasts" }),
    Full       = profile(WP.KEYS),
    Multibox   = profile({}),
}

local function resolveProfileName(name)
    if type(name) ~= "string" then return nil end
    local l = name:lower()
    for k in pairs(WP.Profiles) do if k:lower() == l then return k end end
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- Hide windows that became disabled and sync the announcement bar.
function WP.Refresh()
    if not inCombat() then
        if not WP.Get("tankCastEnabled") and AIP.TankCast and AIP.TankCast.IsWindowShown
            and AIP.TankCast.IsWindowShown() and AIP.TankCast.HideWindow then
            AIP.TankCast.HideWindow()
        end
        if not WP.Get("raidGroupsEnabled") and AIP.RaidGroups and AIP.RaidGroups.IsWindowShown
            and AIP.RaidGroups.IsWindowShown() and AIP.RaidGroups.HideWindow then
            AIP.RaidGroups.HideWindow()
        end
    end
    if AIP.RaidTools and AIP.RaidTools.UpdateBar then AIP.RaidTools.UpdateBar() end
    local vb = AIP.CentralGUI and AIP.CentralGUI.VoaBanner
    if vb and not WP.Get("voaBanner") and vb.IsShown and vb:IsShown() then vb:Hide() end
end

-- Applying account-wide also drops this character's overrides, otherwise the
-- override would silently mask the profile on the character the user is on.
function WP.ApplyProfile(name, perCharacter)
    local pname = resolveProfileName(name)
    if not pname then return nil, "unknown profile" end
    for _, k in ipairs(WP.KEYS) do
        WP.Set(k, WP.Profiles[pname][k], perCharacter and true or false)
    end
    if not perCharacter then WP.ClearOverrides() end
    WP.Refresh()
    return pname
end

-- ---------------------------------------------------------------------------
-- Reset window positions
-- ---------------------------------------------------------------------------
-- { global frame name, db key (account) or nil, point, x, y, secure }
local FRAMES = {
    { "AIPCentralGUI",       "guiPosition",   "CENTER", 0,    0 },
    { "AIPTankCastWindow",   nil,             "CENTER", -320, 0,    true },
    { "AIPRaidGroupsWindow", nil,             "CENTER", 320,  0,    true },
    { "AIPAnnounceBar",      "floatingBarPos","CENTER", 350,  0 },
    { "AIPRollWindow",       nil,             "CENTER", 0,    0 },
    { "AIPRotationOverlay",  "rotationPos",   "CENTER", 0,    -150 },
    { "AIPLFGWatch",         "lfgWatchPos",   "TOP",    0,    -180 },
    { "AIPTimerAnchor",      "timerBarPos",   "CENTER", -320, 120 },
}

function WP.ResetPositions()
    local db = AIP.db
    local combat = inCombat()
    local n, skipped = 0, 0
    if type(db) == "table" then
        for _, f in ipairs(FRAMES) do if f[2] then db[f[2]] = nil end end
    end
    if type(db) == "table" then db.activityLogPos = nil end
    if AIP.ActivityLog and AIP.ActivityLog.window and AIP.ActivityLog.window.SetPoint then
        AIP.ActivityLog.window:ClearAllPoints(); AIP.ActivityLog.window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if AIP.TankCast and AIP.TankCast.Cfg then
        local c = AIP.TankCast.Cfg(); if c then c.pos = nil end
    end
    if AIP.RaidGroups and AIP.RaidGroups.Cfg then
        local c = AIP.RaidGroups.Cfg(); if c then c.pos = nil end
    end
    for _, f in ipairs(FRAMES) do
        local frame = _G and _G[f[1]]
        if frame and frame.SetPoint then
            if f[6] and combat then
                skipped = skipped + 1
            else
                frame:ClearAllPoints()
                frame:SetPoint(f[3], UIParent, f[3], f[4], f[5])
                if f[6] and frame.GetLeft and frame.GetTop and frame:GetLeft() and frame:GetTop() then
                    -- Tank Cast / Raid Groups grow right/down from a TOPLEFT anchor.
                    local l, t = frame:GetLeft(), frame:GetTop()
                    frame:ClearAllPoints()
                    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
                end
                n = n + 1
            end
        end
    end
    return n, skipped
end

-- ---------------------------------------------------------------------------
-- Export / Import (own serializer; input is parsed, never executed)
-- ---------------------------------------------------------------------------
local PREFIX = "AIPS1:"
local MAX_LEN = 30000
local MAX_STR = 600

-- Keys never exported/imported even though they are scalar defaults.
local SKIP_EXACT = { dbVersion = true, windowsTipShown = true, version = true, lastVersion = true }
local function skipKey(k)
    if SKIP_EXACT[k] then return true end
    local l = k:lower()
    if l:match("pos$") or l == "guiposition" or l:find("log", 1, true) or l:find("debug", 1, true)
        or l:find("cache", 1, true) or l:find("seen", 1, true)
        or l:find("recent", 1, true) or l:match("^last") then
        -- "cacheDuration" is a real user setting; allow it back.
        if l == "cacheduration" then return false end
        return true
    end
    return false
end

local function esc(s)
    return (s:gsub("[^%w _%-%.,:!%?%[%]%(%)#@'\"/<>%+%*&|~^$]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function settingKeys()
    local keys = {}
    local d = AIP.Defaults
    if type(d) ~= "table" then return keys end
    for k, v in pairs(d) do
        local t = type(v)
        if type(k) == "string" and k:match("^[%w_]+$") and not skipKey(k)
            and (t == "boolean" or t == "number" or t == "string") then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    return keys
end

function WP.Export()
    local db = AIP.db or {}
    local parts = {}
    for _, k in ipairs(settingKeys()) do
        local v = db[k]
        local d = AIP.Defaults[k]
        if v == nil then v = d end
        if type(v) == type(d) then
            if type(v) == "boolean" then
                parts[#parts + 1] = k .. "=b" .. (v and "1" or "0")
            elseif type(v) == "number" then
                if v == v and v ~= math.huge and v ~= -math.huge then
                    parts[#parts + 1] = k .. "=n" .. string.format("%.14g", v)
                end
            elseif #v <= MAX_STR then
                parts[#parts + 1] = k .. "=s" .. esc(v)
            end
        end
    end
    return PREFIX .. table.concat(parts, ";")
end

-- Returns number of settings applied, or nil, errorMessage.
function WP.Import(str)
    if type(str) ~= "string" then return nil, "no data" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if #str > MAX_LEN then return nil, "data too long" end
    if str:sub(1, #PREFIX) ~= PREFIX then return nil, "not an AIP settings string" end
    if type(AIP.db) ~= "table" or type(AIP.Defaults) ~= "table" then return nil, "settings not loaded" end
    local body = str:sub(#PREFIX + 1)
    local staged, count = {}, 0
    for entry in body:gmatch("[^;]+") do
        local k, t, val = entry:match("^([%w_]+)=([bns])(.*)$")
        if k and not skipKey(k) then
            local d = AIP.Defaults[k]
            local dt = type(d)
            if t == "b" and dt == "boolean" and (val == "1" or val == "0") then
                staged[k] = (val == "1")
            elseif t == "n" and dt == "number" and val:match("^%-?[%d%.]+[eE]?[%+%-]?%d*$") then
                local n = tonumber(val)
                if n and n == n and n ~= math.huge and n ~= -math.huge then staged[k] = n end
            elseif t == "s" and dt == "string" and #val <= MAX_STR * 3 then
                local s = unesc(val)
                if #s <= MAX_STR then staged[k] = s end
            end
        end
    end
    for k, v in pairs(staged) do AIP.db[k] = v; count = count + 1 end
    if count == 0 then return nil, "nothing to import" end
    WP.Refresh()
    return count
end

-- Small copyable popup for the export string (falls back to chat).
function WP.ShowExportBox(text)
    if not (CreateFrame and UIParent) then
        if AIP.Print then AIP.Print(text) end
        return
    end
    local f = WP.exportFrame
    if not f then
        f = CreateFrame("Frame", "AIPExportBox", UIParent)
        f:SetSize(460, 90)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.08, 0.96)
        f:EnableMouse(true)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -10)
        title:SetText("AutoInvite+ settings - Ctrl+A, Ctrl+C to copy")
        local eb = CreateFrame("EditBox", "AIPExportEditBox", f, "InputBoxTemplate")
        eb:SetSize(420, 22)
        eb:SetPoint("TOP", 0, -34)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnEnterPressed", function() f:Hide() end)
        f.edit = eb
        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(70, 20)
        close:SetPoint("BOTTOM", 0, 8)
        close:SetText("Close")
        close:SetScript("OnClick", function() f:Hide() end)
        WP.exportFrame = f
    end
    f.edit:SetMaxLetters(0)
    f.edit:SetText(text)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

-- ---------------------------------------------------------------------------
-- Slash helper (/aip windows | resetpos | export | import)
-- ---------------------------------------------------------------------------
local LABELS = {
    tankCastEnabled = "Tank Cast window", raidGroupsEnabled = "Raid Groups window",
    autoShowOnGroup = "Auto-open on group", restoreWindowsOnLogin = "Restore at login",
    floatingBarEnabled = "Announcement bar", timerBarsEnabled = "Timer bars",
    minimapBubbles = "Minimap bubbles", assignmentToasts = "Assignment toasts",
    voaBanner = "VoA portal banner",
}

function WP.Status()
    for _, k in ipairs(WP.KEYS) do
        AIP.Print(string.format("  %s: %s%s", LABELS[k] or k, WP.Get(k) and "ON" or "OFF",
            WP.HasOverride(k) and " (this character)" or ""))
    end
end

function WP.SlashHandler(cmd, rest)
    rest = rest or ""
    if cmd == "windows" then
        local sub, arg = rest:match("^(%S*)%s*(.-)%s*$")
        sub = (sub or ""):lower()
        if sub == "" or sub == "status" then
            AIP.Print("Windows & bars (effective for this character):")
            WP.Status()
        elseif sub == "off" or sub == "on" then
            local v = (sub == "on")
            for _, k in ipairs(WP.KEYS) do WP.Set(k, v, false) end
            WP.ClearOverrides()
            WP.Refresh()
            AIP.Print("All windows & bars " .. (v and "ON" or "OFF") .. ". /aip windows to review.")
        elseif sub == "context" then
            local a1, a2 = arg:match("^(%S*)%s*(.-)%s*$")
            a1 = (a1 or ""):lower()
            if a1 == "" then
                WP.ContextStatus()
            elseif a1 == "on" or a1 == "off" then
                WP.SetContextEnabled(a1 == "on")
                AIP.Print("Context profiles " .. a1:upper() .. ".")
            elseif WP.IsContext(a1) and a2 ~= "" then
                local ok, err = WP.SetContextProfile(a1, a2)
                if ok then
                    AIP.Print(WP.CONTEXT_LABELS[a1] .. " -> " .. (WP.ContextProfile(a1) or "no change"))
                    WP.lastContext = nil
                else
                    AIP.Print("Context profile failed: " .. tostring(err))
                end
            else
                AIP.Print("Usage: /aip windows context [on|off | <solo|party|raid|dungeon|raidinstance|battleground|arena> <Minimal|RaidLeader|Full|Multibox|none>]")
            end
        elseif sub == "profile" then
            local name, scope = arg:match("^(%S+)%s*(%S*)$")
            local perChar = scope and scope:lower() == "char"
            local ok, err = WP.ApplyProfile(name, perChar)
            if ok then
                AIP.Print("Applied profile " .. ok .. (perChar and " (this character only)" or " (account-wide)") .. ".")
            else
                AIP.Print("Usage: /aip windows profile <Minimal|RaidLeader|Full|Multibox> [char]  (" .. tostring(err) .. ")")
            end
        else
            AIP.Print("Usage: /aip windows [on|off|profile <Minimal|RaidLeader|Full|Multibox> [char]|context ...]")
        end
    elseif cmd == "resetpos" then
        local n, skipped = WP.ResetPositions()
        AIP.Print("Window positions reset (" .. n .. " frames)" ..
            (skipped > 0 and (", " .. skipped .. " skipped in combat - run again out of combat") or "") .. ".")
    elseif cmd == "export" then
        local s = WP.Export()
        WP.ShowExportBox(s)
        AIP.Print("Settings exported (" .. #s .. " chars) - copy it from the box.")
    elseif cmd == "import" then
        local n, err = WP.Import(rest)
        if n then AIP.Print("Imported " .. n .. " settings. /reload recommended.")
        else AIP.Print("Import failed: " .. tostring(err)) end
    end
end

-- ---------------------------------------------------------------------------
-- Context-aware automatic profiles
--   db.contextProfilesEnabled (bool) + db.contextProfiles[ctx] = profile name
--   (nil / "" = leave windows alone in that context). Re-evaluated (debounced)
--   on zone / roster changes, only when the context actually CHANGED. A manual
--   /aip windows change sticks until the next context change. Never touches
--   windows in combat - deferred to PLAYER_REGEN_ENABLED.
-- ---------------------------------------------------------------------------
WP.CONTEXTS = { "solo", "party", "raid", "dungeon", "raidinstance", "battleground", "arena" }
local CTX_LABEL = {
    solo = "Solo", party = "Party", raid = "Raid group", dungeon = "Dungeon",
    raidinstance = "Raid instance", battleground = "Battleground", arena = "Arena",
}
WP.CONTEXT_LABELS = CTX_LABEL

local function isContext(c)
    for _, k in ipairs(WP.CONTEXTS) do if k == c then return true end end
    return false
end
-- Exposed on WP: SlashHandler is defined above this point, so it can't see the local.
WP.IsContext = isContext

-- 3.3.5a APIs only (no IsInGroup / IsInRaid).
function WP.Context()
    local inInst, itype
    if IsInInstance then inInst, itype = IsInInstance() end
    if inInst then
        if itype == "arena" then return "arena" end
        if itype == "pvp" then return "battleground" end
        if itype == "raid" then return "raidinstance" end
        if itype == "party" then return "dungeon" end
    end
    if GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0 then return "raid" end
    if GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0 then return "party" end
    return "solo"
end

function WP.ContextProfile(ctx)
    local db = AIP.db
    if type(db) ~= "table" or type(db.contextProfiles) ~= "table" then return nil end
    local n = db.contextProfiles[ctx]
    if type(n) ~= "string" or n == "" then return nil end
    return resolveProfileName(n)
end

-- Set (or clear with nil / "" / "none") the profile for a context.
function WP.SetContextProfile(ctx, name)
    if not isContext(ctx) or type(AIP.db) ~= "table" then return false, "unknown context" end
    if type(AIP.db.contextProfiles) ~= "table" then AIP.db.contextProfiles = {} end
    if name == nil or name == "" or tostring(name):lower() == "none" then
        AIP.db.contextProfiles[ctx] = nil
        return true
    end
    local p = resolveProfileName(name)
    if not p then return false, "unknown profile" end
    AIP.db.contextProfiles[ctx] = p
    return true
end

function WP.SetContextEnabled(on)
    if type(AIP.db) ~= "table" then return end
    AIP.db.contextProfilesEnabled = on and true or false
    WP.lastContext = nil           -- next evaluation counts as a change
    if on then WP.EvaluateContext() end
end

-- Synchronous evaluation. Returns the profile applied (or nil).
function WP.EvaluateContext()
    local db = AIP.db
    if type(db) ~= "table" or not db.contextProfilesEnabled then return nil end
    local ctx = WP.Context()
    if ctx == WP.lastContext then WP.pendingContext = false; return nil end
    if inCombat() then WP.pendingContext = true; return nil end
    WP.pendingContext = false
    WP.lastContext = ctx
    local name = WP.ContextProfile(ctx)
    if not name then return nil end
    local applied = WP.ApplyProfile(name, db.windowsPerCharMode and true or false)
    if applied and AIP.Print then
        AIP.Print("Context: " .. (CTX_LABEL[ctx] or ctx) .. " - window profile " .. applied .. ".")
    end
    return applied
end

-- Debounced (0.5s) entry point for event bursts.
function WP.ScheduleContext()
    if WP.ctxScheduled then return end
    if not (AIP.db and AIP.db.contextProfilesEnabled) then return end
    if AIP.Utils and AIP.Utils.DelayedCall then
        WP.ctxScheduled = true
        AIP.Utils.DelayedCall(0.5, function()
            WP.ctxScheduled = false
            WP.EvaluateContext()
        end)
    else
        WP.EvaluateContext()
    end
end

function WP.ContextStatus()
    local db = AIP.db or {}
    AIP.Print("Context profiles: " .. (db.contextProfilesEnabled and "ON" or "OFF") ..
        "  (current context: " .. (CTX_LABEL[WP.Context()] or "?") .. ")")
    for _, c in ipairs(WP.CONTEXTS) do
        AIP.Print(string.format("  %s (%s): %s", CTX_LABEL[c], c, WP.ContextProfile(c) or "-"))
    end
    AIP.Print("Manual /aip windows changes stay until the next context change.")
end

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
                          "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }) do
        AIP.Utils.Events.Register(ev, function() WP.ScheduleContext() end, "WindowProfilesCtx")
    end
    AIP.Utils.Events.Register("PLAYER_REGEN_ENABLED", function()
        if WP.pendingContext then WP.ScheduleContext() end
    end, "WindowProfilesCtx")
end

-- One-time tip shortly after login.
if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    AIP.Utils.Events.Register("PLAYER_LOGIN", function()
        if not (AIP.Utils.DelayedCall and AIP.db) or AIP.db.windowsTipShown then return end
        AIP.Utils.DelayedCall(5, function()
            if AIP.db and not AIP.db.windowsTipShown then
                AIP.db.windowsTipShown = true
                AIP.Print("Tip: tired of popups? /aip windows off, or Settings > Windows & Bars.")
            end
        end)
    end, "WindowProfiles")
end

-- AutoInvite Plus - ActivityLog
-- In-memory ring buffer (never saved) of what the addon did on the player's
-- behalf: invites, whispers, broadcasts, timers, queue/waitlist adds. Lets the
-- user answer "what did AIP just send?" without chat spam.
-- Viewer window: AL.ToggleWindow() (/aip activity window).
local AIP = AutoInvitePlus
AIP.ActivityLog = AIP.ActivityLog or {}
local AL = AIP.ActivityLog

AL.MAX = 200
AL.entries = AL.entries or {}
AL.rev = AL.rev or 0   -- bumped on every change so the window can skip no-op refreshes

local function now()
    if time then return time() end
    return 0
end

-- kind: short tag ("invite", "whisper", "broadcast", "timer", "queue", "waitlist")
function AL.Add(kind, text)
    local e = AL.entries
    e[#e + 1] = { t = now(), kind = tostring(kind or "?"), text = tostring(text or "") }
    if #e > AL.MAX then table.remove(e, 1) end
    AL.rev = AL.rev + 1
end

-- Last n entries, oldest first.
function AL.Recent(n)
    local e = AL.entries
    n = tonumber(n) or 20
    if n > #e then n = #e end
    local out = {}
    for i = #e - n + 1, #e do out[#out + 1] = e[i] end
    return out
end

function AL.Clear() AL.entries = {}; AL.rev = AL.rev + 1 end

-- Filter-chip -> the entry kinds it covers ("queue" also shows waitlist notices).
AL.KindGroups = { queue = { queue = true, waitlist = true } }

-- True when an entry of entryKind passes the filter (nil / "all" = everything).
function AL.Matches(kind, entryKind)
    if kind == nil or kind == "all" then return true end
    local g = AL.KindGroups[kind]
    if g then return g[entryKind] == true end
    return entryKind == kind
end

-- Newest-first list of at most n entries (default: all) passing the kind filter.
function AL.Filter(kind, n)
    local e = AL.entries
    n = tonumber(n) or #e
    local out = {}
    for i = #e, 1, -1 do
        if #out >= n then break end
        if AL.Matches(kind, e[i].kind) then out[#out + 1] = e[i] end
    end
    return out
end

function AL.Print(n)
    local list = AL.Recent(n or 20)
    if #list == 0 then AIP.Print("Activity log is empty.") return end
    AIP.Print("Activity (last " .. #list .. "):")
    for _, e in ipairs(list) do
        AIP.Print("  " .. date("%H:%M:%S", e.t) .. " [" .. e.kind .. "] " .. e.text)
    end
end

-- ============================================================================
-- Viewer window (created lazily; nothing here runs at load time)
-- ============================================================================
local KIND_COLORS = {
    invite = "FF4DE04D", whisper = "FF4DD2FF", broadcast = "FFFF9933",
    timer = "FFFFD100", queue = "FFC080FF", waitlist = "FFFF80C0",
}
AL.FILTERS = { "all", "invite", "whisper", "broadcast", "timer", "queue" }

-- One display line: "HH:MM:SS [kind] text" with colour codes.
function AL.FormatLine(e)
    local c = KIND_COLORS[e.kind] or "FFAAAAAA"
    return "|cFF888888" .. date("%H:%M:%S", e.t) .. "|r |c" .. c .. "[" .. e.kind .. "]|r " .. e.text
end

local W_WIDTH, W_HEIGHT = 430, 300

local function refresh(f)
    local list = AL.Filter(f.filter)
    local lines = {}
    for i, e in ipairs(list) do lines[i] = AL.FormatLine(e) end
    if #lines == 0 then
        f.text:SetText("|cFF888888Nothing logged yet.|r")
    else
        f.text:SetText(table.concat(lines, "\n"))
    end
    -- Elastic: the scroll child is as tall as the wrapped text, never a guess.
    local h = (f.text:GetStringHeight() or 0) + 6
    f.content:SetHeight(math.max(h, 1))
    local range = math.max(0, h - f.scroll:GetHeight())
    if f.scroll:GetVerticalScroll() > range then f.scroll:SetVerticalScroll(range) end
    f.seenRev, f.seenFilter = AL.rev, f.filter
    f.count:SetText(#list .. " / " .. #AL.entries)
end

local function styleChips(f)
    for _, b in ipairs(f.chips) do
        if (f.filter or "all") == b.kind then
            b:SetText("|cFFFFD100" .. b.kind .. "|r")
        else
            b:SetText(b.kind)
        end
    end
end

local function savePos(f)
    if not AIP.db then return end
    local point, _, relPoint, x, y = f:GetPoint()
    AIP.db.activityLogPos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function build()
    local f = CreateFrame("Frame", "AIPActivityLogWindow", UIParent)
    f:SetSize(W_WIDTH, W_HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.06, 0.07, 0.10, 0.95)
    f:SetBackdropBorderColor(0.24, 0.26, 0.34, 1)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Activity Log")

    local count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("LEFT", title, "RIGHT", 8, 0)
    f.count = count

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Filter chips + Clear
    f.filter = nil
    f.chips = {}
    local prev
    for _, k in ipairs(AL.FILTERS) do
        local b = AIP.UI and AIP.UI.FlatButton and AIP.UI.FlatButton(f, k, 52, 18)
        if not b then
            b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); b:SetSize(52, 18); b:SetText(k)
        end
        b.kind = k
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", 10, -28) end
        b:SetScript("OnClick", function()
            f.filter = (k ~= "all") and k or nil
            styleChips(f)
            refresh(f)
        end)
        f.chips[#f.chips + 1] = b
        prev = b
    end
    local clear = AIP.UI and AIP.UI.FlatButton and AIP.UI.FlatButton(f, "Clear", 48, 18)
    if not clear then
        clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        clear:SetSize(48, 18)
        clear:SetText("Clear")
    end
    clear:SetPoint("TOPRIGHT", -10, -28)
    clear:SetScript("OnClick", function() AL.Clear(); refresh(f) end)

    -- Plain (un-templated) scroll frame + mousewheel: no scrollbar template, so
    -- no unnamed-frame OnLoad trap.
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 10, -52)
    scroll:SetPoint("BOTTOMRIGHT", -10, 10)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, f.content:GetHeight() - self:GetHeight())
        local v = self:GetVerticalScroll() - delta * 36
        if v < 0 then v = 0 elseif v > range then v = range end
        self:SetVerticalScroll(v)
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(W_WIDTH - 20)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetWidth(W_WIDTH - 24)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    f.scroll, f.content, f.text = scroll, content, text

    -- Auto-refresh (throttled 1s) only while shown and only when something changed.
    f.acc = 0
    f:SetScript("OnUpdate", function(self, dt)
        self.acc = self.acc + dt
        if self.acc < 1 then return end
        self.acc = 0
        if self.seenRev ~= AL.rev or self.seenFilter ~= self.filter then refresh(self) end
    end)
    f:SetScript("OnShow", function(self) styleChips(self); refresh(self) end)

    if UISpecialFrames then table.insert(UISpecialFrames, "AIPActivityLogWindow") end

    -- Restore saved position (SetClampedToScreen keeps it reachable).
    local pos = AIP.db and AIP.db.activityLogPos
    f:ClearAllPoints()
    if pos and pos.point and pos.relPoint and pos.x and pos.y then
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    return f
end

function AL.ToggleWindow()
    if not AL.window then AL.window = build() end
    if AL.window:IsShown() then AL.window:Hide() else AL.window:Show() end
end

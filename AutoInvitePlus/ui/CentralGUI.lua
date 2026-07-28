-- AutoInvite Plus - Central GUI Module
-- Main window controller for the unified interface

local AIP = AutoInvitePlus
if not AIP then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r CentralGUI: AutoInvitePlus namespace not found!")
    return
end

AIP.CentralGUI = {}
local GUI = AIP.CentralGUI

-- Debug: confirm module loaded
-- DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[AIP Debug]|r CentralGUI module loaded")

-- Configuration
GUI.Config = {
    defaultWidth = 1000,
    defaultHeight = 760,   -- taller default so the Character paperdoll + detail + stats aren't cramped
    minWidth = 800,
    minHeight = 600,       -- keep enough vertical room for the paperdoll columns at min size
    minimizedHeight = 45,  -- Height when minimized (just title bar)
}

-- Tab definitions (v5.3 - added raid management and loot history)
GUI.Tabs = {
    {id = "lfm", name = "LFM Browser", tooltip = "LFM groups browser with message composer and queue"},
    {id = "favorites", name = "Favorites", tooltip = "Whitelist/priority players management"},
    {id = "blacklist", name = "Blacklist", tooltip = "Blocked players management"},
    {id = "composition", name = "Composition", tooltip = "Raid composition advisor with templates"},
    {id = "raidmgmt", name = "Raid Mgmt", tooltip = "Raid warnings, loot rules, buff checker, MS/OS tracking"},
    {id = "loothistory", name = "Loot History", tooltip = "Historical loot drops from raids and dungeons"},
    {id = "character", name = "Character", tooltip = "Gear upgrades, spec advisor, readiness and coaching"},
    {id = "settings", name = "Settings", tooltip = "Auto-invite and broadcast settings"},
}

-- State
GUI.Frame = nil
GUI.CurrentTab = "lfm"
GUI.TreeView = nil
GUI.InspectionPanel = nil
GUI.IsMinimized = false
GUI.IsMaximized = false
GUI.SavedSize = nil  -- Stores {width, height} before maximize
GUI.SavedPosition = nil  -- Stores {point, relPoint, x, y} before maximize

-- Elastic row sizing for the Queue/LFG/Waitlist sub-lists of the LFM Browser.
-- The row pools are created at QUEUE_MAX_ROWS; the number actually shown is
-- recomputed from each list's elastic content frame height on every refresh,
-- so the lists fill the panel and never overflow past its bottom edge.
GUI.QUEUE_MAX_ROWS = 40       -- generous pool size (cap on visible rows)
GUI.QUEUE_ROW_HEIGHT = 20     -- per-row height (matches ROW_HEIGHT below)
-- Vertical space above the first data row. The top strip holds the right-aligned
-- Search/+Add/Invite All cluster (~0..-18); the column-header labels sit on their
-- OWN row below it (QUEUE_HEADER_Y); data rows start below that. Keeping headers
-- on a separate row lets the columns span the full width without sliding under
-- the search cluster.
GUI.QUEUE_HEADER_Y = -24      -- y of the column-header label row
GUI.QUEUE_HEADER_INSET = 44   -- space reserved above the first data row

-- Compute how many rows fit in an elastic content frame without overflowing.
-- Derives height from the passed content frame, which is anchored with both
-- TOPLEFT and BOTTOMRIGHT (no SetSize), so GetHeight() is reliable. Clamped to
-- [1, QUEUE_MAX_ROWS] so the last row always fits fully.
function GUI.QueueVisibleRows(content)
    local h = (content and content:GetHeight()) or 0
    local n = math.floor((h - GUI.QUEUE_HEADER_INSET) / GUI.QUEUE_ROW_HEIGHT)
    if n < 1 then n = 1 end
    if n > GUI.QUEUE_MAX_ROWS then n = GUI.QUEUE_MAX_ROWS end
    return n
end

-- ===========================================================================
-- Dynamic column layout for the Queue/LFG/Waitlist listings.
-- Columns are FIXED (leading "#", Time/Added, BL flag, GS) or FLEXIBLE (Player,
-- Class, Message/Note, Spec, Raid, Role). On resize the flexible columns share
-- the leftover width by weight, so columns fill a wide panel and shrink on a
-- narrow one. The action-button group (Inv/Rej/Block/Whisper/W/X/...) is pinned
-- flush to the right edge. Header labels are re-anchored to match their column.
-- ===========================================================================
local QUEUE_COLS = {
    {field = "numText",   kind = "fixed", w = 20},
    {field = "nameText",  kind = "flex",  weight = 2.2},
    {field = "classText", kind = "flex",  weight = 1.3},
    {field = "msgText",   kind = "flex",  weight = 3.2},
    {field = "timeText",  kind = "fixed", w = 35},
    {field = "blText",    kind = "fixed", w = 25},
}
local QUEUE_ACTIONS = {
    {field = "invBtn", w = 28}, {field = "rejBtn", w = 28}, {field = "waitBtn", w = 18},
    {field = "blBtn", w = 18},  {field = "remBtn", w = 18}, {field = "whisperBtn", w = 22},
}
local LFG_COLS = {
    {field = "numText",  kind = "fixed", w = 20},
    {field = "nameText", kind = "flex",  weight = 2.0},
    {field = "specText", kind = "flex",  weight = 2.0},
    {field = "raidText", kind = "flex",  weight = 2.2},
    {field = "gsText",   kind = "fixed", w = 45},
}
local LFG_ACTIONS = {
    {field = "invBtn", w = 50}, {field = "whisperBtn", w = 40},
    {field = "queueBtn", w = 40}, {field = "waitlistBtn", w = 40},
}
local WAITLIST_COLS = {
    {field = "numText",  kind = "fixed", w = 20},
    {field = "nameText", kind = "flex",  weight = 2.0},
    {field = "roleText", kind = "flex",  weight = 1.1},
    {field = "gsText",   kind = "fixed", w = 45},
    {field = "noteText", kind = "flex",  weight = 3.2},
    {field = "timeText", kind = "fixed", w = 45},
}
local WAITLIST_ACTIONS = {
    {field = "invBtn", w = 35}, {field = "upBtn", w = 22}, {field = "downBtn", w = 22},
    {field = "remBtn", w = 22}, {field = "whisperBtn", w = 22},
}

-- Position one list's columns from the elastic content frame's current width.
-- content      : the elastic *Content frame (reliable GetWidth, never SetSize'd)
-- rows         : the row pool (each row[field] holds the cell/button)
-- headerLabels : array of header FontStrings; [#cols+1] is the "Actions" header
-- cols, actions: the layout spec (see tables above)
function GUI.ApplyColumnLayout(content, rows, headerLabels, cols, actions)
    if not content then return end
    local W = content:GetWidth() or 0
    if W < 120 then return end  -- too small / not laid out yet

    local LPAD, RPAD, COLGAP, BGAP = 5, 8, 6, 2
    local nCols = #cols

    -- Width of the right-pinned action-button group (incl. inter-button gaps).
    local actionTotal = 0
    for ai = 1, #actions do actionTotal = actionTotal + actions[ai].w end
    if #actions > 1 then actionTotal = actionTotal + BGAP * (#actions - 1) end

    -- Sum of fixed column widths + total flex weight.
    local fixedSum, weightSum = 0, 0
    for ci = 1, nCols do
        local c = cols[ci]
        if c.kind == "flex" then
            weightSum = weightSum + (c.weight or 1)
        else
            fixedSum = fixedSum + (c.w or 0)
        end
    end

    local reserved = LPAD + RPAD + fixedSum + actionTotal + COLGAP * (nCols + 1)
    local flexAvail = W - reserved
    if flexAvail < 0 then flexAvail = 0 end
    local perUnit = (weightSum > 0) and (flexAvail / weightSum) or 0
    local MINFLEX = 24

    -- Resolve each column's x position and width left-to-right.
    local xs, ws = {}, {}
    local cursor = LPAD
    for ci = 1, nCols do
        local c = cols[ci]
        local cw
        if c.kind == "flex" then
            cw = math.floor(perUnit * (c.weight or 1))
            if cw < MINFLEX then cw = MINFLEX end
        else
            cw = c.w or 0
        end
        xs[ci] = cursor
        ws[ci] = cw
        cursor = cursor + cw + COLGAP
    end

    -- Action group flush to the right edge.
    local actionLeft = W - RPAD - actionTotal
    if actionLeft < cursor then actionLeft = cursor end

    -- Re-anchor the column-header labels to match.
    if headerLabels then
        for ci = 1, nCols do
            local lbl = headerLabels[ci]
            if lbl then
                lbl:ClearAllPoints()
                lbl:SetPoint("TOPLEFT", xs[ci], GUI.QUEUE_HEADER_Y)
                lbl:SetWidth(ws[ci])
            end
        end
        local actHeader = headerLabels[nCols + 1]
        if actHeader then
            actHeader:ClearAllPoints()
            actHeader:SetPoint("TOPLEFT", actionLeft, GUI.QUEUE_HEADER_Y)
            actHeader:SetWidth(actionTotal)
        end
    end

    -- Re-anchor every row's cells + action buttons.
    for ri = 1, #rows do
        local row = rows[ri]
        if row then
            row:SetWidth(W - RPAD)  -- explicit width => not stale
            for ci = 1, nCols do
                local cell = row[cols[ci].field]
                if cell then
                    cell:ClearAllPoints()
                    cell:SetPoint("LEFT", xs[ci], 0)
                    cell:SetWidth(ws[ci])
                end
            end
            local bx = actionLeft
            for ai = 1, #actions do
                local btn = row[actions[ai].field]
                if btn then
                    btn:ClearAllPoints()
                    btn:SetPoint("LEFT", bx, 0)
                end
                bx = bx + actions[ai].w + BGAP
            end
        end
    end
end

-- Re-flow all three sub-lists' columns from their elastic content widths.
function GUI.LayoutQueueColumns(container)
    if not container then return end
    GUI.ApplyColumnLayout(container.queueContent, container.queueRows or {},
        container.queueHeaderLabels, QUEUE_COLS, QUEUE_ACTIONS)
    GUI.ApplyColumnLayout(container.lfgContent, container.lfgRows or {},
        container.lfgHeaderLabels, LFG_COLS, LFG_ACTIONS)
    GUI.ApplyColumnLayout(container.waitlistContent, container.waitlistRows or {},
        container.waitlistHeaderLabels, WAITLIST_COLS, WAITLIST_ACTIONS)
end

-- Recompute and refresh the elastic Queue/LFG/Waitlist lists (called on
-- window resize / maximize / restore / minimize-expand): both the column
-- widths (LayoutQueueColumns) and the visible row count (UpdateQueuePanel).
function GUI.RefreshQueueLayout()
    local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
    if container then
        GUI.LayoutQueueColumns(container)
        GUI.UpdateQueuePanel(container)
    end
end

-- LFG Enrollment tracking (other players looking for groups)
GUI.LfgEnrollments = {}  -- {playerName = {name, class, spec, role, gs, ilvl, raid, time}}
GUI.FitCache = setmetatable({}, { __mode = "k" })  -- render-time fit verdicts, keyed by entry (weak: never persisted)
GUI.MyEnrollment = nil   -- Our own enrollment data
GUI.MyGroup = nil        -- Our active LFM data (for matching incoming LFG players)

-- Custom channels for addon communication
GUI.CustomChannels = {
    LFM = "AIPLookingForMore",
    LFG = "AIPLookingForGroup",
}

-- Use AIP.Utils.DelayedCall for WotLK-compatible timers
-- (defined in core/Utils.lua, no need for local fallback)

-- Standardized backdrop templates for consistent appearance
GUI.Backdrops = {
    -- Main panel backdrop (dark, solid)
    Panel = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 5, right = 5, top = 5, bottom = 5}
    },
    -- Sub-panel backdrop (slightly lighter)
    SubPanel = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    },
    -- Input field backdrop
    Input = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    },
    -- Small inset panel
    Inset = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    },
}

-- Helper: Apply standard backdrop to frame
function GUI.ApplyBackdrop(frame, backdropType, bgAlpha, borderAlpha)
    local bd = GUI.Backdrops[backdropType] or GUI.Backdrops.Panel
    frame:SetBackdrop(bd)
    -- Cohesive theme: subtle dark-navy fill + soft slate border (was flat grey).
    frame:SetBackdropColor(0.045, 0.05, 0.072, bgAlpha or 0.95)
    frame:SetBackdropBorderColor(0.34, 0.37, 0.46, borderAlpha or 1)
end

-- Beautify a popup dialog to match the main window: dark-navy fill, soft slate
-- border, and a gold-accented title strip. Cosmetic only; idempotent.
function GUI.StylePopup(popup, titleHeight)
    if not popup then return end
    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    popup:SetBackdropColor(0.05, 0.055, 0.085, 1)
    popup:SetBackdropBorderColor(0.4, 0.42, 0.52, 1)
    if not popup._aipBg then
        -- Solid backing layer so nothing behind the popup bleeds through (the dark
        -- dialog texture alone is semi-transparent).
        local bg = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetPoint("TOPLEFT", 5, -5); bg:SetPoint("BOTTOMRIGHT", -5, 5)
        bg:SetTexture(0.045, 0.05, 0.072, 1)
        popup._aipBg = bg
    end
    if not popup._aipStrip then
        local strip = popup:CreateTexture(nil, "BORDER")
        strip:SetPoint("TOPLEFT", 6, -6); strip:SetPoint("TOPRIGHT", -6, -6)
        strip:SetHeight(titleHeight or 28)
        strip:SetTexture(0.11, 0.12, 0.18, 0.95)
        local div = popup:CreateTexture(nil, "ARTWORK")
        div:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
        div:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
        div:SetHeight(2); div:SetTexture(1, 0.82, 0, 0.5)
        popup._aipStrip = strip
    end
end

-- Helper: Create properly styled edit box for WotLK
function GUI.CreateStyledEditBox(parent, width, height, isNumeric)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width + 10, height + 8)
    container:SetBackdrop(GUI.Backdrops.Input)
    container:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetSize(width, height)
    editBox:SetPoint("CENTER", 0, 0)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:EnableKeyboard(true)

    if isNumeric then
        editBox:SetNumeric(true)
    else
        editBox:SetMaxLetters(255)
        -- Allow shift-clicking items/quests/etc. into text fields.
        if AIP.UI and AIP.UI.MakeEditBoxLinkable then
            AIP.UI.MakeEditBoxLinkable(editBox)
        end
    end

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        container:SetBackdropBorderColor(0.6, 0.6, 0.3, 1)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        container:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    editBox.container = container
    return editBox, container
end

-- Helper: Fix UIDropDownMenu strata issues in WotLK
-- The dropdown list frames need higher strata when parent is HIGH
function GUI.FixDropdownStrata(dropdown)
    if not dropdown then return end
    -- Hook the dropdown button click to set proper strata on the list frame
    local button = _G[dropdown:GetName() .. "Button"]
    if button then
        button:HookScript("OnClick", function()
            -- DropDownList1 is the main dropdown list frame
            for i = 1, UIDROPDOWNMENU_MAXLEVELS or 2 do
                local listFrame = _G["DropDownList" .. i]
                if listFrame then
                    listFrame:SetFrameStrata("TOOLTIP")
                end
            end
        end)
    end
end

-- ============================================================================
-- ACHIEVEMENT TOOLTIP HELPERS
-- ============================================================================

-- Extract achievement ID from an achievement link
-- Format: |cffffff00|Hachievement:ID:...|h[Name]|h|r
function GUI.ExtractAchievementId(link)
    if not link then return nil end
    local id = link:match("|Hachievement:(%d+):")
    return id and tonumber(id)
end

-- Extract all achievement IDs from a text string
function GUI.ExtractAllAchievementIds(text)
    if not text then return {} end
    local ids = {}
    for id in text:gmatch("|Hachievement:(%d+):") do
        local numId = tonumber(id)
        if numId then
            table.insert(ids, numId)
        end
    end
    return ids
end

-- Show achievement tooltip for a given achievement ID
function GUI.ShowAchievementTooltip(achievementId, owner, anchor)
    if not achievementId then return end
    GameTooltip:SetOwner(owner or UIParent, anchor or "ANCHOR_RIGHT")

    -- Try to set the hyperlink directly (this works in WotLK)
    local link = GetAchievementLink(achievementId)
    if link then
        GameTooltip:SetHyperlink(link)
        return true
    end

    -- Fallback: Build tooltip manually from achievement info
    local id, name, points, completed, month, day, year, description, flags, icon = GetAchievementInfo(achievementId)
    if name then
        GameTooltip:AddLine(name, 1, 0.82, 0)
        if description then
            GameTooltip:AddLine(description, 1, 1, 1, true)
        end
        if points and points > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Points:", tostring(points), 0.7, 0.7, 0.7, 0, 1, 0)
        end
        if completed then
            local dateStr = ""
            if month and day and year and year > 0 then
                dateStr = string.format("%d/%d/%d", month, day, year)
            end
            GameTooltip:AddLine("|cFF00FF00Completed|r " .. dateStr, 0, 1, 0)
        else
            GameTooltip:AddLine("|cFFFF6666Not completed|r", 1, 0.4, 0.4)
        end
        GameTooltip:Show()
        return true
    end

    return false
end

-- Create a hyperlink-aware text display that shows achievement tooltips on hover
-- This creates an invisible button overlay that detects achievement link clicks
function GUI.CreateAchievementAwareText(parent, fontString, textContent)
    if not parent or not fontString then return end

    -- Store the text content and achievement IDs
    fontString.achievementIds = GUI.ExtractAllAchievementIds(textContent)

    -- If no achievements, just set text and return
    if #fontString.achievementIds == 0 then
        fontString:SetText(textContent)
        return
    end

    fontString:SetText(textContent)

    -- Enable hyperlinks if the font string supports it
    if fontString.SetHyperlinksEnabled then
        fontString:SetHyperlinksEnabled(true)
    end
end

-- Setup message box to show achievement tooltips on hover
-- Call this when creating a message display area
function GUI.SetupMessageBoxAchievementTooltips(msgFrame, msgFontString)
    if not msgFrame then return end

    -- Track if we're hovering over an achievement
    msgFrame.hoveredAchievement = nil

    msgFrame:EnableMouse(true)
    msgFrame:SetScript("OnEnter", function(self)
        local text = msgFontString and msgFontString:GetText() or ""
        local achievementIds = GUI.ExtractAllAchievementIds(text)

        if #achievementIds > 0 then
            -- Show tooltip for the first achievement found
            GUI.ShowAchievementTooltip(achievementIds[1], self, "ANCHOR_RIGHT")
            self.hoveredAchievement = achievementIds[1]
        end
    end)

    msgFrame:SetScript("OnLeave", function(self)
        if self.hoveredAchievement then
            GameTooltip:Hide()
            self.hoveredAchievement = nil
        end
    end)
end

-- Transient notification popup near the minimap icon (e.g. "VOA Listed").
-- Created lazily; reused across calls. Shows for a few seconds then hides.
function GUI.ShowMinimapBubble(text)
    local b = GUI.MinimapBubble
    if not b then
        b = CreateFrame("Frame", "AIPMinimapBubble", UIParent)
        b:SetFrameStrata("DIALOG")
        b:SetSize(150, 28)  -- solid default size so it never collapses to a square
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        b:SetBackdropColor(0, 0, 0, 0.9)
        b:SetBackdropBorderColor(1, 0.82, 0)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER")
        fs:SetTextColor(1, 0.82, 0)
        b.textFS = fs
        b:Hide()
        GUI.MinimapBubble = b
    end

    -- Re-anchor under the (movable) minimap button each time.
    b:ClearAllPoints()
    b:SetPoint("TOP", GUI.MinimapButton or Minimap, "BOTTOM", 0, -6)

    b.textFS:SetText(text)
    -- Fit width to the text with a sane minimum (GetStringWidth can be 0 the
    -- very first frame, so never trust it alone).
    local tw = b.textFS:GetStringWidth() or 0
    b:SetWidth(math.max(100, tw + 28))
    b:SetHeight(28)
    b:SetAlpha(1)
    b:Show()

    -- Hold ~3s at full opacity, then hide. No per-frame alpha changes (that
    -- flicker read as an "odd flashing square").
    b.life = 0
    b:SetScript("OnUpdate", function(self, e)
        self.life = self.life + (e or 0)
        if self.life >= 3 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
end

-- Create minimap button
function GUI.CreateMinimapButton()
    local button = CreateFrame("Button", "AIPMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)

    -- Icon texture (centered in the bezel)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\ICONS\\Ability_Warrior_RallyingCry")
    button.icon = icon

    -- Border texture (the MiniMap-TrackingBorder has built-in offset, adjust positioning)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border = border

    -- Highlight texture
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- VOA alert glow (pulses when VOA listings are available). A ROUND additive
    -- gold halo sized to the button (not the old square proc-border, which read
    -- as an odd flashing square on the round minimap). Hidden until VOA is found.
    local voaGlow = button:CreateTexture(nil, "OVERLAY")
    voaGlow:SetSize(52, 52)
    voaGlow:SetPoint("CENTER", 0, 0)
    voaGlow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    voaGlow:SetBlendMode("ADD")
    voaGlow:SetVertexColor(1, 0.82, 0)
    voaGlow:Hide()
    button.voaGlow = voaGlow

    -- Position around minimap
    local angle = AIP.db and AIP.db.minimapAngle or 220
    local rad = math.rad(angle)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)

    -- Drag to reposition
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale

        local dx = cx - mx
        local dy = cy - my
        local angle = math.deg(math.atan2(dy, dx))

        if AIP.db then
            AIP.db.minimapAngle = angle
        end

        local rad = math.rad(angle)
        local x = math.cos(rad) * 80
        local y = math.sin(rad) * 80
        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end)

    button:SetScript("OnUpdate", function(self, elapsed)
        if self.dragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            local dx = cx - mx
            local dy = cy - my
            local angle = math.atan2(dy, dx)

            local x = math.cos(angle) * 80
            local y = math.sin(angle) * 80
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", x, y)
        end

        -- VOA alert: poll listing state (throttled) and pulse the glow
        self.voaPoll = (self.voaPoll or 0) + (elapsed or 0)
        self.voaClock = (self.voaClock or 0) + (elapsed or 0)
        if self.voaPoll >= 3 then
            self.voaPoll = 0
            local alertOn = AIP.db and AIP.db.voaAlert
            local CS = AIP.ChatScanner
            local listings = (alertOn and CS and CS.GetVOAListings) and CS.GetVOAListings() or {}
            self.voaCount = #listings

            -- Edge-triggered bubble popups: fire once when a category goes from
            -- none -> some (not every poll while they persist).
            local favCount = (CS and CS.GetFavoriteListings) and #CS.GetFavoriteListings() or 0
            if self.voaCount > 0 and (self.prevVoaCount or 0) == 0 then
                GUI.ShowMinimapBubble("VOA Listed")
            end
            if favCount > 0 and (self.prevFavCount or 0) == 0 then
                GUI.ShowMinimapBubble("Favorites Listed")
            end
            self.prevVoaCount = self.voaCount
            self.prevFavCount = favCount
        end

        if self.voaGlow then
            if (self.voaCount or 0) > 0 then
                -- Alpha oscillates ~0.25..1.0 for a soft pulse
                local a = 0.6 + 0.4 * math.sin(self.voaClock * 3)
                self.voaGlow:SetAlpha(a)
                if not self.voaGlow:IsShown() then self.voaGlow:Show() end
            elseif self.voaGlow:IsShown() then
                self.voaGlow:Hide()
            end
        end
    end)

    button:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            GUI.Toggle()
        elseif button == "RightButton" then
            -- Show quick menu
            GUI.ShowQuickMenu(self)
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("AutoInvite+ |cFF888888v" .. (AIP.Version or "?") .. "|r")
        GameTooltip:AddLine("|cFF888888by iuGames|r", 0.5, 0.5, 0.5)

        local CS = AIP.ChatScanner

        -- Tree summary: LFM listings broken down by raid (ICC, VOA, TOC, ...),
        -- plus LFG players and favorites. VOA shows here as one of the rows.
        local groupCount = (CS and CS.GetGroupCount) and CS.GetGroupCount() or 0
        local playerCount = (CS and CS.GetPlayerCount) and CS.GetPlayerCount() or 0
        local favListings = (CS and CS.GetFavoriteListings) and CS.GetFavoriteListings() or {}

        GameTooltip:AddLine(" ")
        if groupCount > 0 then
            GameTooltip:AddLine("LFM listings (" .. groupCount .. "):", 0.8, 0.8, 0.8)
            local counts = (CS and CS.GetCountsByRaid) and CS.GetCountsByRaid() or {}
            local hierarchy = AIP.Parsers and AIP.Parsers.RaidHierarchy or {}
            for _, cat in ipairs(hierarchy) do
                local c = counts[cat.id] or 0
                if c > 0 then
                    GameTooltip:AddDoubleLine("  " .. (cat.shortName or cat.name or cat.id), tostring(c), 0.7, 0.7, 0.7, 1, 1, 1)
                end
            end
        else
            GameTooltip:AddLine("No LFM listings", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddDoubleLine("LFG players:", tostring(playerCount), 0.7, 0.7, 0.7, 1, 1, 1)
        if #favListings > 0 then
            GameTooltip:AddDoubleLine("From favorites:", tostring(#favListings), 0.7, 0.7, 0.7, 1, 0.82, 0)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFFFFFFFLeft-click:|r Open main window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cFFFFFFFFRight-click:|r Quick menu", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Ensure button is visible
    button:Show()

    -- Store reference for later access
    GUI.MinimapButton = button

    return button
end

-- Quick menu for minimap button
function GUI.ShowQuickMenu(anchor)
    local menu = CreateFrame("Frame", "AIPQuickMenu", UIParent, "UIDropDownMenuTemplate")

    local menuList = {
        {text = "AutoInvite+", isTitle = true, notCheckable = true},
        {text = "Open Main Window", func = function() GUI.Toggle() end, notCheckable = true},
        {text = "Toggles", isTitle = true, notCheckable = true},
        -- Both toggles are checkable so the check column is consistent (no lone
        -- checkmark among plain rows). Their checks reflect the current state.
        {
            text = "Auto-Invite",
            isNotRadio = true,
            checked = (AIP.db and AIP.db.enabled) and true or false,
            func = function()
                if AIP.db then
                    AIP.db.enabled = not AIP.db.enabled
                    AIP.Print("Auto-invite " .. (AIP.db.enabled and "ENABLED" or "DISABLED"))
                end
            end,
        },
        {
            text = "Raid Tools Bar",
            isNotRadio = true,
            checked = (AIP.db and AIP.db.floatingBarEnabled) and true or false,
            func = function()
                if AIP.RaidTools and AIP.RaidTools.ToggleBar then
                    AIP.RaidTools.ToggleBar()
                else
                    AIP.Print("Raid Tools not available.")
                end
            end,
        },
        {text = "Actions", isTitle = true, notCheckable = true},
        {text = "Spam Invite Message", func = function() AIP.SpamInvite() end, notCheckable = true},
        {text = "Invite Guild", func = function() AIP.InviteGuild() end, notCheckable = true},
        {text = "Invite Friends", func = function() AIP.InviteFriends() end, notCheckable = true},
        {text = " ", disabled = true, notCheckable = true},
        {text = "Cancel", notCheckable = true},
    }

    EasyMenu(menuList, menu, anchor, 0, 0, "MENU")
end

-- Create the main frame
function GUI.CreateFrame()
    if GUI.Frame then return GUI.Frame end

    local frame = CreateFrame("Frame", "AIPCentralGUI", UIParent)
    frame:SetSize(GUI.Config.defaultWidth, GUI.Config.defaultHeight)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Opacity and focus handling
    frame.isFocused = true
    local function UpdateFrameOpacity()
        if not AIP.db then return end
        local baseOpacity = AIP.db.guiOpacity or 1.0
        if AIP.db.guiUnfocusedEnabled and not frame.isFocused then
            frame:SetAlpha(AIP.db.guiUnfocusedOpacity or 0.6)
        else
            frame:SetAlpha(baseOpacity)
        end
    end

    frame:SetScript("OnShow", function(self)
        self.isFocused = true
        UpdateFrameOpacity()
    end)

    frame:HookScript("OnEnter", function(self)
        if not self.isFocused then
            self.isFocused = true
            UpdateFrameOpacity()
        end
    end)

    frame:HookScript("OnLeave", function(self)
        -- Check if mouse is over any child frame
        if not MouseIsOver(self) then
            self.isFocused = false
            UpdateFrameOpacity()
        end
    end)

    -- Expose the update function
    GUI.UpdateFrameOpacity = UpdateFrameOpacity

    -- Make closeable with Escape
    tinsert(UISpecialFrames, frame:GetName())

    -- Background - solid black backdrop to prevent character showing through
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11}
    })
    frame:SetBackdropColor(0, 0, 0, 1)

    -- Add an additional solid background layer for guaranteed opacity (dark navy).
    local solidBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetPoint("TOPLEFT", 11, -11)
    solidBg:SetPoint("BOTTOMRIGHT", -11, 11)
    solidBg:SetTexture(0.045, 0.05, 0.072, 1)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(30)
    titleBar:SetPoint("TOPLEFT", 10, -10)
    titleBar:SetPoint("TOPRIGHT", -10, -10)

    -- Title strip + gold accent divider (visual polish; purely cosmetic).
    local titleStrip = titleBar:CreateTexture(nil, "BACKGROUND")
    titleStrip:SetAllPoints(); titleStrip:SetTexture(0.10, 0.11, 0.17, 0.92)
    local titleDivider = titleBar:CreateTexture(nil, "ARTWORK")
    titleDivider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 2, -1)
    titleDivider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -2, -1)
    titleDivider:SetHeight(2); titleDivider:SetTexture(1, 0.82, 0, 0.5)

    -- Main title
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 8, 1)
    titleText:SetText("AutoInvite+")
    titleText:SetTextColor(1, 0.82, 0)

    -- Subtitle (author)
    local subtitleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleText, "RIGHT", 8, -1)
    subtitleText:SetText("by iuGames")
    subtitleText:SetTextColor(0.6, 0.6, 0.6)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Maximize/Restore button
    local maxBtn = CreateFrame("Button", nil, frame)
    maxBtn:SetSize(20, 20)
    maxBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    maxBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    maxBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    maxBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    frame.maxBtn = maxBtn

    maxBtn:SetScript("OnClick", function()
        GUI.ToggleMaximize()
    end)
    maxBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(GUI.IsMaximized and "Restore" or "Maximize")
        GameTooltip:Show()
    end)
    maxBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Minimize button
    local minBtn = CreateFrame("Button", nil, frame)
    minBtn:SetSize(20, 20)
    minBtn:SetPoint("RIGHT", maxBtn, "LEFT", -2, 0)
    minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
    minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Down")
    minBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    frame.minBtn = minBtn

    minBtn:SetScript("OnClick", function()
        GUI.ToggleMinimize()
    end)
    minBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(GUI.IsMinimized and "Expand" or "Minimize")
        GameTooltip:Show()
    end)
    minBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Quick raid buttons in the title bar - stay visible even when minimized.
    local function titleBtn(text, w, ref, ofs, onClick, tip)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(w, 18); b:SetText(text)
        b:SetPoint("RIGHT", ref, "LEFT", ofs, 0)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    local qTools = titleBtn("Tools", 46, minBtn, -8,
        function() if AIP.RaidTools and AIP.RaidTools.ToggleRollWindow then AIP.RaidTools.ToggleRollWindow() end end,
        "Raid Tools (roll window)")
    local qBreak = titleBtn("Break", 44, qTools, -3,
        function() if AIP.DBMBridge then AIP.DBMBridge.SendBreak(5) end end, "5-minute break timer")
    local qPull = titleBtn("Pull", 40, qBreak, -3,
        function() if AIP.DBMBridge then AIP.DBMBridge.SendPull(10) end end, "Pull timer (10s, DBM-synced)")
    local qRDF = titleBtn("RDF", 40, qPull, -3,
        function() if AIP.LFGWatch and AIP.LFGWatch.Toggle then AIP.LFGWatch.Toggle() end end,
        "Toggle the Dungeon Finder queue window")
    local qBar = titleBtn("Bar", 38, qRDF, -3,
        function() if AIP.RaidTools and AIP.RaidTools.ToggleBar then AIP.RaidTools.ToggleBar() end end,
        "Toggle the floating announcement bar")
    titleBtn("Ready", 52, qBar, -3,
        function() if AIP.RaidTools and AIP.RaidTools.StartReadyCheck then AIP.RaidTools.StartReadyCheck() end end,
        "Start a ready check")

    -- Drag to move
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        if AIP.db then
            local point, _, relPoint, x, y = self:GetPoint()
            AIP.db.guiPosition = {point = point, relPoint = relPoint, x = x, y = y}
        end
    end)

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetHeight(30)
    tabBar:SetPoint("TOPLEFT", 10, -40)
    tabBar:SetPoint("TOPRIGHT", -10, -40)
    frame.tabBar = tabBar

    -- Tab bar background
    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints()
    tabBarBg:SetTexture(0.1, 0.1, 0.1, 1)

    -- Create tab buttons (custom simple buttons for WotLK compatibility)
    frame.tabButtons = {}
    local tabX = 5
    local firstTab = true
    -- Custom widths for each tab to fit text properly with consistent spacing
    local tabWidths = {
        lfm = 90,        -- "LFM Browser"
        favorites = 70,  -- "Favorites"
        blacklist = 68,  -- "Blacklist"
        composition = 85, -- "Composition"
        raidmgmt = 78,   -- "Raid Mgmt"
        loothistory = 82, -- "Loot History"
        character = 72,  -- "Character"
        settings = 62,   -- "Settings"
    }
    local tabSpacing = 6  -- Gap between tabs (increased for better visual separation)

    for i, tab in ipairs(GUI.Tabs) do
        local tabWidth = tabWidths[tab.id] or 90
        local tabBtn = CreateFrame("Button", "AIPTab" .. tab.id, tabBar)
        tabBtn:SetSize(tabWidth, 24)
        tabBtn:SetPoint("TOPLEFT", tabX, -3)
        tabBtn.tabId = tab.id

        -- Tab background
        local tabBg = tabBtn:CreateTexture(nil, "BACKGROUND")
        tabBg:SetAllPoints()
        -- First tab starts selected - SAME colors SelectTab uses, so the
        -- initial render matches the post-click restyle exactly
        if firstTab then
            tabBg:SetTexture(0.30, 0.26, 0.12, 1)   -- selected: warm gold-tinted
        else
            tabBg:SetTexture(0.11, 0.12, 0.17, 0.9) -- unselected: dark navy
        end
        tabBtn.bg = tabBg

        -- Tab border
        local tabBorder = tabBtn:CreateTexture(nil, "BORDER")
        tabBorder:SetPoint("TOPLEFT", -1, 1)
        tabBorder:SetPoint("BOTTOMRIGHT", 1, -1)
        tabBorder:SetTexture(0.4, 0.4, 0.4, 1)
        tabBtn.border = tabBorder

        -- Tab text
        local tabText = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER", 0, 0)
        tabText:SetText(tab.name)
        -- First tab starts selected with gold text
        if firstTab then
            tabText:SetTextColor(1, 0.82, 0)
            firstTab = false
        else
            tabText:SetTextColor(0.8, 0.8, 0.8)
        end
        tabBtn.text = tabText
        tabBtn:SetFontString(tabText)

        -- Highlight texture
        local highlight = tabBtn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.15)

        tabBtn:SetScript("OnClick", function(self)
            GUI.SelectTab(self.tabId)
        end)

        tabBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tab.tooltip)
            GameTooltip:Show()
        end)

        tabBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        frame.tabButtons[tab.id] = tabBtn
        tabX = tabX + tabWidth + tabSpacing
    end

    -- Content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 10, -75)
    content:SetPoint("BOTTOMRIGHT", -10, 40)
    frame.content = content

    -- Create content containers for each tab
    frame.tabContents = {}
    for _, tab in ipairs(GUI.Tabs) do
        local container = CreateFrame("Frame", "AIPContent" .. tab.id, content)
        container:SetAllPoints()

        -- Add background to content area for visibility (dark navy, theme-matched)
        local contentBg = container:CreateTexture(nil, "BACKGROUND")
        contentBg:SetAllPoints()
        contentBg:SetTexture(0.045, 0.05, 0.072, 1)

        container:Hide()
        frame.tabContents[tab.id] = container
    end

    -- Status bar
    local statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetHeight(30)
    statusBar:SetPoint("BOTTOMLEFT", 10, 5)
    statusBar:SetPoint("BOTTOMRIGHT", -10, 5)
    frame.statusBar = statusBar

    -- Status bar background + a subtle accent divider along its top edge.
    local statusBarBg = statusBar:CreateTexture(nil, "BACKGROUND")
    statusBarBg:SetAllPoints()
    statusBarBg:SetTexture(0.10, 0.11, 0.16, 0.92)
    local statusDivider = statusBar:CreateTexture(nil, "ARTWORK")
    statusDivider:SetPoint("TOPLEFT", 0, 1); statusDivider:SetPoint("TOPRIGHT", 0, 1)
    statusDivider:SetHeight(1); statusDivider:SetTexture(1, 0.82, 0, 0.35)

    local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT", 5, 0)
    statusText:SetTextColor(0.7, 0.7, 0.7)
    frame.statusText = statusText

    -- GearScore/iLevel display (left side, after status)
    local gsDisplay = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gsDisplay:SetPoint("LEFT", statusText, "RIGHT", 20, 0)
    gsDisplay:SetText("")
    statusBar.gsDisplay = gsDisplay

    -- Chat ban status (center-right of footer)
    local chatBanStatus = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatBanStatus:SetPoint("CENTER", 100, 0)
    chatBanStatus:SetWidth(160)       -- clip: overlaps the right-side strings on narrow windows otherwise
    chatBanStatus:SetJustifyH("CENTER")
    chatBanStatus:SetText("")
    statusBar.chatBanStatus = chatBanStatus

    -- Mode indicator (left of broadcast status)
    local modeIndicator = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeIndicator:SetPoint("RIGHT", -200, 0)
    modeIndicator:SetText("")
    statusBar.modeIndicator = modeIndicator

    -- Peer count display (left of mode indicator)
    local peerCountDisplay = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    peerCountDisplay:SetPoint("RIGHT", modeIndicator, "LEFT", -15, 0)
    peerCountDisplay:SetText("")
    statusBar.peerCountDisplay = peerCountDisplay

    -- Broadcast status (right side of footer)
    local broadcastStatus = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    broadcastStatus:SetPoint("RIGHT", -25, 0)
    broadcastStatus:SetWidth(230)     -- clip: grows leftward into the mode indicator otherwise
    broadcastStatus:SetJustifyH("RIGHT")
    broadcastStatus:SetText("")
    statusBar.broadcastStatus = broadcastStatus

    -- Resize grip
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -5, 5)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeGrip:SetScript("OnMouseDown", function(self)
        frame:StartSizing("BOTTOMRIGHT")
    end)

    resizeGrip:SetScript("OnMouseUp", function(self)
        frame:StopMovingOrSizing()
        -- Save size
        if AIP.db then
            AIP.db.guiWidth = frame:GetWidth()
            AIP.db.guiHeight = frame:GetHeight()
        end
        -- Force refresh active panel after resize completes
        if GUI.CurrentTab then
            GUI.SelectTab(GUI.CurrentTab)
        end
    end)

    -- Handle frame resize to update tab bar and content
    frame:SetScript("OnSizeChanged", function(self, width, height)
        -- Update tab bar width if needed (tabs stay fixed-position)
        if frame.tabBar then
            -- Tab bar is already using SetPoint anchors, so it auto-resizes
        end
        -- Content panels auto-resize via SetAllPoints
        -- But we should trigger a refresh of the active panel
        if GUI.CurrentTab and AIP.Panels then
            -- Let child frames handle their own OnSizeChanged
        end
        -- Recompute elastic Queue/LFG/Waitlist row counts on window resize.
        GUI.RefreshQueueLayout()
    end)

    frame:SetMinResize(GUI.Config.minWidth, GUI.Config.minHeight)

    -- Initialize tab contents
    GUI.InitializeTabs(frame)

    GUI.Frame = frame
    return frame
end

-- Toggle minimize state
function GUI.ToggleMinimize()
    if not GUI.Frame then return end

    GUI.IsMinimized = not GUI.IsMinimized

    if GUI.IsMinimized then
        -- Save current size before minimizing
        GUI.PreMinimizeWidth = GUI.Frame:GetWidth()
        GUI.PreMinimizeHeight = GUI.Frame:GetHeight()

        -- Hide content areas (with nil checks)
        if GUI.Frame.content then GUI.Frame.content:Hide() end
        if GUI.Frame.tabBar then GUI.Frame.tabBar:Hide() end
        if GUI.Frame.statusBar then GUI.Frame.statusBar:Hide() end

        -- Shrink to title bar only
        GUI.Frame:SetHeight(GUI.Config.minimizedHeight)
        GUI.Frame:SetResizable(false)

        -- Update button texture to expand
        if GUI.Frame.minBtn then
            GUI.Frame.minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
            GUI.Frame.minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Down")
        end
    else
        -- Restore size
        GUI.Frame:SetHeight(GUI.PreMinimizeHeight or GUI.Config.defaultHeight)
        GUI.Frame:SetResizable(true)

        -- Show content areas (with nil checks)
        if GUI.Frame.content then GUI.Frame.content:Show() end
        if GUI.Frame.tabBar then GUI.Frame.tabBar:Show() end
        if GUI.Frame.statusBar then GUI.Frame.statusBar:Show() end

        -- Update button texture to collapse
        if GUI.Frame.minBtn then
            GUI.Frame.minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
            GUI.Frame.minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Down")
        end

        -- Recompute elastic list row counts after expanding back to full size.
        if AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(0.05, GUI.RefreshQueueLayout)
        else
            GUI.RefreshQueueLayout()
        end
    end
end

-- Toggle maximize state
function GUI.ToggleMaximize()
    if not GUI.Frame then return end

    -- If minimized, restore first
    if GUI.IsMinimized then
        GUI.ToggleMinimize()
    end

    GUI.IsMaximized = not GUI.IsMaximized

    if GUI.IsMaximized then
        -- Save current size and position
        GUI.SavedSize = {
            width = GUI.Frame:GetWidth(),
            height = GUI.Frame:GetHeight()
        }
        local point, relativeTo, relativePoint, x, y = GUI.Frame:GetPoint()
        GUI.SavedPosition = {point = point, relPoint = relativePoint, x = x, y = y}

        -- Get screen dimensions
        local screenWidth = GetScreenWidth()
        local screenHeight = GetScreenHeight()

        -- Maximize to screen size (with small margin)
        GUI.Frame:ClearAllPoints()
        GUI.Frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        GUI.Frame:SetSize(screenWidth - 40, screenHeight - 40)

        -- Update button texture to restore
        if GUI.Frame.maxBtn then
            GUI.Frame.maxBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
            GUI.Frame.maxBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Down")
        end
    else
        -- Restore saved size and position
        if GUI.SavedSize then
            GUI.Frame:SetSize(GUI.SavedSize.width, GUI.SavedSize.height)
        end
        if GUI.SavedPosition then
            GUI.Frame:ClearAllPoints()
            GUI.Frame:SetPoint(GUI.SavedPosition.point, UIParent, GUI.SavedPosition.relPoint,
                              GUI.SavedPosition.x, GUI.SavedPosition.y)
        else
            GUI.Frame:ClearAllPoints()
            GUI.Frame:SetPoint("CENTER")
        end

        -- Update button texture to maximize
        if GUI.Frame.maxBtn then
            GUI.Frame.maxBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
            GUI.Frame.maxBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
        end
    end

    -- Recompute elastic list row counts after the layout settles.
    if AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(0.05, GUI.RefreshQueueLayout)
    else
        GUI.RefreshQueueLayout()
    end
end

-- Create placeholder content for missing panels
local function CreatePlaceholder(parent, message)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetText(message or "Content not available")
    text:SetTextColor(0.5, 0.5, 0.5)
end

-- Initialize tab content panels (v4.1 - redesigned)
function GUI.InitializeTabs(frame)
    -- Ensure AIP.Panels exists
    AIP.Panels = AIP.Panels or {}

    -- Debug: log panel availability
    AIP.Debug("Initializing tabs - Panels: Favorites=" .. tostring(AIP.Panels.Favorites ~= nil) ..
              ", Blacklist=" .. tostring(AIP.Panels.Blacklist ~= nil) ..
              ", RaidMgmt=" .. tostring(AIP.Panels.RaidMgmt ~= nil) ..
              ", LootHistory=" .. tostring(AIP.Panels.LootHistory ~= nil) ..
              ", Settings=" .. tostring(AIP.Panels.Settings ~= nil))

    -- LFM Tab (v4.3: tree view + message composer + 3-tab queue system).
    -- CreateBrowserTab lives in ui/CentralGUIBrowser.lua (a NEW .toc entry):
    -- 3.3.5a does not pick up newly-listed files on /reload, so guard with a
    -- relog hint instead of hard-erroring after an in-place update.
    local lfmContainer = frame.tabContents["lfm"]
    if GUI.CreateBrowserTab then
        GUI.CreateBrowserTab(lfmContainer, "lfm")
    else
        local info = lfmContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("AutoInvite+ was updated.\n\nLog out and back in (a /reload is not enough)\nto load the new browser module.")
        info:SetTextColor(0.6, 0.6, 0.6)
    end

    -- Favorites Tab (v5.2: whitelist/priority players)
    local favoritesContainer = frame.tabContents["favorites"]
    if AIP.Panels.Favorites and type(AIP.Panels.Favorites.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.Favorites.Create(favoritesContainer)
        end)
        if not success then
            AIP.Debug("Favorites panel creation failed: " .. tostring(err))
        end
    else
        local title = favoritesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Favorites")

        local info = favoritesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Favorites list is empty\n\nAdd players to give them priority in queue")
        info:SetTextColor(0.6, 0.6, 0.6)
    end

    -- Blacklist Tab (v4.1: enhanced with search/filter)
    local blacklistContainer = frame.tabContents["blacklist"]
    if AIP.Panels.Blacklist and type(AIP.Panels.Blacklist.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.Blacklist.Create(blacklistContainer)
        end)
        if not success then
            AIP.Debug("Blacklist panel creation failed: " .. tostring(err))
        end
    else
        local title = blacklistContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Blacklist")

        local info = blacklistContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Blacklist is empty\n\nAdd players to prevent them from being auto-invited")
        info:SetTextColor(0.6, 0.6, 0.6)
    end

    -- Composition Tab (v4.1: enhanced with categories)
    GUI.CreateCompositionTab(frame.tabContents["composition"])

    -- Raid Management Tab (v5.3: raid warnings, loot rules, buff checker)
    local raidMgmtContainer = frame.tabContents["raidmgmt"]
    if AIP.Panels.RaidMgmt and type(AIP.Panels.RaidMgmt.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.RaidMgmt.Create(raidMgmtContainer)
        end)
        if not success then
            AIP.Debug("RaidMgmt panel creation failed: " .. tostring(err))
            -- Show error to user
            local errorText = raidMgmtContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            errorText:SetPoint("CENTER")
            errorText:SetText("|cFFFF4444Panel Error:|r " .. tostring(err))
        end
    else
        AIP.Debug("RaidMgmt panel not found - AIP.Panels.RaidMgmt=" .. tostring(AIP.Panels.RaidMgmt))
        local title = raidMgmtContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Raid Management")

        local info = raidMgmtContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Panel not loaded.\nCheck that RaidManagementPanel.lua is in the addon folder.")
        info:SetTextColor(1, 0.4, 0.4)
    end

    -- Loot History Tab (v5.3: track loot drops)
    local lootHistoryContainer = frame.tabContents["loothistory"]
    if AIP.Panels.LootHistory and type(AIP.Panels.LootHistory.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.LootHistory.Create(lootHistoryContainer)
        end)
        if not success then
            AIP.Debug("LootHistory panel creation failed: " .. tostring(err))
            -- Show error to user
            local errorText = lootHistoryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            errorText:SetPoint("CENTER")
            errorText:SetText("|cFFFF4444Panel Error:|r " .. tostring(err))
        end
    else
        AIP.Debug("LootHistory panel not found - AIP.Panels.LootHistory=" .. tostring(AIP.Panels.LootHistory))
        local title = lootHistoryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Loot History")

        local info = lootHistoryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Panel not loaded.\nCheck that LootHistoryPanel.lua is in the addon folder.")
        info:SetTextColor(1, 0.4, 0.4)
    end

    -- Character Tab (gear/upgrade/spec/coaching)
    local characterContainer = frame.tabContents["character"]
    if AIP.Panels.Character and type(AIP.Panels.Character.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.Character.Create(characterContainer)
        end)
        if not success then
            AIP.Debug("Character panel creation failed: " .. tostring(err))
            local errorText = characterContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            errorText:SetPoint("CENTER")
            errorText:SetText("|cFFFF4444Panel Error:|r " .. tostring(err))
        end
    else
        -- Panel file not registered: on 3.3.5a, newly ADDED addon files are only
        -- loaded on a fresh login, not by /reload. Tell the user instead of blank.
        local title = characterContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -40)
        title:SetText("Character")
        local info = characterContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("|cFFFFCC00Character panel not loaded yet.|r\n\nNewly added addon files aren't picked up by /reload on 3.3.5a.\nLog out to the character-selection screen and back in\n(or restart the client) once, then reopen this tab.")
        info:SetTextColor(0.85, 0.85, 0.85)
        info:SetJustifyH("CENTER")
    end

    -- Settings Tab
    local settingsContainer = frame.tabContents["settings"]
    if AIP.Panels.Settings and type(AIP.Panels.Settings.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.Settings.Create(settingsContainer)
        end)
        if not success then
            AIP.Debug("Settings panel creation failed: " .. tostring(err))
        end
    else
        local title = settingsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Settings")

        local info = settingsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Settings panel not available\n\nUse /aip commands to configure")
        info:SetTextColor(0.6, 0.6, 0.6)
    end
end

-- Create composition tab (RaidComp-style layout)
function GUI.CreateCompositionTab(container)
    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 10, -10)
    header:SetText("Raid Composition Advisor")
    header:SetTextColor(1, 0.82, 0)

    -- Template category dropdown
    local catLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catLabel:SetPoint("TOPLEFT", 10, -38)
    catLabel:SetText("Category:")

    local catDropdown = CreateFrame("Frame", "AIPCompCategory", container, "UIDropDownMenuTemplate")
    catDropdown:SetPoint("LEFT", catLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(catDropdown, 100)
    UIDropDownMenu_SetText(catDropdown, "WotLK")
    container.selectedCategory = "WOTLK"

    -- Template selector
    local templateLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    templateLabel:SetPoint("LEFT", catDropdown, "RIGHT", 10, 2)
    templateLabel:SetText("Template:")

    local templateDropdown = CreateFrame("Frame", "AIPCompTemplate", container, "UIDropDownMenuTemplate")
    templateDropdown:SetPoint("LEFT", templateLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(templateDropdown, 150)
    container.templateDropdown = templateDropdown

    local scanBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    scanBtn:SetSize(90, 22)
    scanBtn:SetPoint("LEFT", templateDropdown, "RIGHT", 10, 2)
    scanBtn:SetText("Scan Raid")
    scanBtn:SetScript("OnClick", function()
        if AIP.Composition then
            AIP.Composition.ScanRaid()
            GUI.UpdateCompositionTab()
        end
    end)

    local autoScanCheck = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    autoScanCheck:SetSize(22, 22)
    autoScanCheck:SetPoint("LEFT", scanBtn, "RIGHT", 5, 0)
    autoScanCheck:SetChecked(true)
    local autoScanLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoScanLabel:SetPoint("LEFT", autoScanCheck, "RIGHT", 0, 0)
    autoScanLabel:SetText("Auto")

    -- Composition variation buttons (numbered alternates for the selected template)
    local varLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    varLabel:SetPoint("LEFT", autoScanLabel, "RIGHT", 12, 0)
    varLabel:SetText("Comp:")
    varLabel:SetTextColor(0.8, 0.8, 0.8)
    container.variationLabel = varLabel
    container.variationButtons = {}

    -- Smart recommendations button
    local recommendBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    recommendBtn:SetSize(95, 22)
    recommendBtn:SetText("Recommend")
    recommendBtn:SetScript("OnClick", function() GUI.ShowRecommendations() end)
    recommendBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Smart Recommendations", 1, 0.82, 0)
        GameTooltip:AddLine("Analyzes the current raid against the selected", 1, 1, 1, true)
        GameTooltip:AddLine("template/variation and suggests which classes to", 1, 1, 1, true)
        GameTooltip:AddLine("recruit, prioritizing missing roles and raid buffs.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    recommendBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.recommendBtn = recommendBtn

    -- Save the CURRENT group's composition as a custom template (works as a
    -- raid member too - "emulate the comp of a raid I joined")
    local saveTplBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    saveTplBtn:SetSize(85, 22)
    saveTplBtn:SetPoint("LEFT", recommendBtn, "RIGHT", 5, 0)
    saveTplBtn:SetText("Save Group")
    saveTplBtn:SetScript("OnClick", function()
        StaticPopup_Show("AIP_SAVE_COMP_TEMPLATE")
    end)
    saveTplBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Save Group as Template", 1, 0.82, 0)
        GameTooltip:AddLine("Snapshots the current group's size and role split", 1, 1, 1, true)
        GameTooltip:AddLine("as a reusable Custom Template (works as a member of", 1, 1, 1, true)
        GameTooltip:AddLine("someone else's raid too).", 1, 1, 1, true)
        GameTooltip:AddLine("Delete via /aip comp deltpl <name>", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    saveTplBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.saveTplBtn = saveTplBtn

    StaticPopupDialogs["AIP_SAVE_COMP_TEMPLATE"] = StaticPopupDialogs["AIP_SAVE_COMP_TEMPLATE"] or {
        text = "Save current group composition as template:",
        button1 = "Save",
        button2 = "Cancel",
        hasEditBox = true,
        maxLetters = 32,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function(self)
            -- 3.3.5a: the dialog's editbox is a named global child, not .editBox
            local eb = (self.editBox) or (self.GetName and _G[self:GetName() .. "EditBox"])
            local name = eb and eb:GetText() or ""
            local Comp = AIP.Composition
            if Comp and Comp.SaveCurrentAsTemplate then
                local key, err = Comp.SaveCurrentAsTemplate(name)
                if key then
                    local t = Comp.RaidTemplates[key]
                    AIP.Print(string.format("Saved custom template |cFF00FF00%s|r: %d players (%dT/%dH/%dD)",
                        t.name, t.size, t.tanks, t.healers, t.dps))
                    if GUI.UpdateCompositionTab then GUI.UpdateCompositionTab() end
                else
                    AIP.Print(err or "Could not save the template.")
                end
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            StaticPopupDialogs["AIP_SAVE_COMP_TEMPLATE"].OnAccept(parent)
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }

    GUI.RebuildVariationButtons(container)

    -- Helper to update template dropdown when category changes
    local function UpdateTemplateDropdown()
        UIDropDownMenu_Initialize(templateDropdown, function()
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Select Template"
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)

            if AIP.Composition and AIP.Composition.RaidTemplates then
                for key, data in pairs(AIP.Composition.RaidTemplates) do
                    if data.category == container.selectedCategory then
                        info = UIDropDownMenu_CreateInfo()
                        info.text = data.name
                        info.value = key
                        info.func = function()
                            UIDropDownMenu_SetText(templateDropdown, data.name)
                            if AIP.Composition then
                                AIP.Composition.SetTemplate(key)
                                GUI.UpdateCompositionTab()
                                -- Tandem binding: re-point the LFM popup too
                                if GUI.SyncPopupToTemplate then
                                    GUI.SyncPopupToTemplate(key)
                                end
                            end
                        end
                        info.notCheckable = true
                        UIDropDownMenu_AddButton(info)
                    end
                end
            end
        end)
    end

    -- Initialize category dropdown (from the registry so Custom Templates and
    -- any future category appear automatically)
    UIDropDownMenu_Initialize(catDropdown, function()
        local categories = (AIP.Composition and AIP.Composition.TemplateCategories) or {
            {id = "WOTLK", name = "WotLK Raids"},
            {id = "WOTLK_DUNGEON", name = "WotLK Dungeons"},
            {id = "TBC", name = "TBC Raids"},
            {id = "CLASSIC", name = "Classic Raids"},
            {id = "WEEKLY", name = "Weekly/Daily"},
        }
        for _, cat in ipairs(categories) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = cat.name
            info.value = cat.id
            info.func = function()
                container.selectedCategory = cat.id
                UIDropDownMenu_SetText(catDropdown, cat.name)
                UpdateTemplateDropdown()
            end
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)
        end
    end)
    GUI.FixDropdownStrata(catDropdown)
    GUI.FixDropdownStrata(templateDropdown)

    UpdateTemplateDropdown()

    -- ========================================================================
    -- LEFT PANEL: Role Composition Bars (30% width)
    -- ========================================================================
    local leftPanel = CreateFrame("Frame", nil, container)
    leftPanel:SetPoint("TOPLEFT", 10, -70)
    leftPanel:SetPoint("BOTTOM", 0, 10)
    -- Use percentage-based width (30% of container)
    local function UpdateLeftPanelWidth()
        local containerWidth = container:GetWidth()
        if containerWidth and containerWidth > 100 then
            leftPanel:SetWidth(math.floor(containerWidth * 0.30) - 10)
        else
            leftPanel:SetWidth(250)  -- Fallback
        end
    end
    UpdateLeftPanelWidth()
    container:SetScript("OnSizeChanged", function(self, width, height)
        UpdateLeftPanelWidth()
        -- Also update other panels
        if container.UpdatePanelWidths then
            container.UpdatePanelWidths()
        end
    end)
    GUI.ApplyBackdrop(leftPanel, "SubPanel", 0.9)
    container.leftPanel = leftPanel

    local leftTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 8, -6)
    leftTitle:SetText("Composition Status")
    leftTitle:SetTextColor(1, 0.82, 0)

    -- Template name display (inline with title)
    local templateDisplay = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    templateDisplay:SetPoint("LEFT", leftTitle, "RIGHT", 8, 0)
    templateDisplay:SetText("- No template")
    templateDisplay:SetTextColor(0.6, 0.6, 0.6)
    container.templateDisplay = templateDisplay

    -- Role bars - more compact layout
    local roleBarY = -26
    container.roleBars = {}

    local function CreateRoleBar(role, color, yOffset)
        local bar = CreateFrame("Frame", nil, leftPanel)
        bar:SetSize(300, 22)  -- Increased from 272
        bar:SetPoint("TOPLEFT", 8, yOffset)

        local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetText(role)
        label:SetWidth(50)
        label:SetTextColor(color.r, color.g, color.b)

        local bgBar = bar:CreateTexture(nil, "BACKGROUND")
        bgBar:SetSize(160, 14)
        bgBar:SetPoint("LEFT", 52, 0)
        bgBar:SetTexture(0.15, 0.15, 0.15, 1)

        local fillBar = bar:CreateTexture(nil, "ARTWORK")
        fillBar:SetSize(0, 14)
        fillBar:SetPoint("LEFT", bgBar, "LEFT", 0, 0)
        fillBar:SetTexture(color.r, color.g, color.b, 0.8)
        bar.fillBar = fillBar
        bar.bgBar = bgBar

        local countText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("LEFT", bgBar, "RIGHT", 6, 0)
        countText:SetText("0/0")
        bar.countText = countText

        return bar
    end

    container.roleBars.TANK = CreateRoleBar("Tanks", {r=0.4, g=0.6, b=1}, roleBarY)
    roleBarY = roleBarY - 24
    container.roleBars.HEALER = CreateRoleBar("Healers", {r=0.4, g=1, b=0.4}, roleBarY)
    roleBarY = roleBarY - 24
    container.roleBars.DPS = CreateRoleBar("DPS", {r=1, g=0.4, b=0.4}, roleBarY)
    roleBarY = roleBarY - 24
    container.roleBars.TOTAL = CreateRoleBar("Total", {r=0.8, g=0.8, b=0.8}, roleBarY)
    roleBarY = roleBarY - 30

    -- ========================================================================
    -- BUFF/DEBUFF SECTION (Tabbed with categories) - Compact Layout
    -- ========================================================================

    -- Buff section container with border for visual separation
    local buffSection = CreateFrame("Frame", nil, leftPanel)
    buffSection:SetPoint("TOPLEFT", 4, roleBarY)
    buffSection:SetPoint("BOTTOMRIGHT", -4, 4)
    GUI.ApplyBackdrop(buffSection, "SubPanel", 0.6)
    container.buffSection = buffSection

    local buffSectionLabel = buffSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    buffSectionLabel:SetPoint("TOPLEFT", 6, -4)
    buffSectionLabel:SetText("Raid Buffs & Debuffs")
    buffSectionLabel:SetTextColor(1, 0.82, 0)

    -- Buff category tabs - horizontal row below title (8 tabs)
    local buffTabFrame = CreateFrame("Frame", nil, buffSection)
    buffTabFrame:SetSize(304, 18)  -- Increased from 270 to fit 8 tabs
    buffTabFrame:SetPoint("TOPLEFT", 4, -20)
    container.buffTabFrame = buffTabFrame

    -- Use categories from RaidComposition.lua (full 8 tabs)
    local buffCategories = {"CRITICAL", "STATS", "ATTACK", "SPELLPOWER", "HASTE", "CRIT", "HEALING", "DEBUFFS", "UTILITY"}
    local buffCategoryNames = {
        CRITICAL = "Crit",
        STATS = "Stats",
        ATTACK = "AP",
        SPELLPOWER = "SP",
        HASTE = "Haste",
        CRIT = "Crit%",
        HEALING = "Heal",
        DEBUFFS = "Debuff",
        UTILITY = "Util",
    }
    local buffCategoryColors = {
        CRITICAL = {r=1, g=0.4, b=0.4},
        STATS = {r=0.4, g=0.8, b=1},
        ATTACK = {r=1, g=0.6, b=0.2},
        SPELLPOWER = {r=0.8, g=0.4, b=1},
        HASTE = {r=0.2, g=0.8, b=0.6},
        CRIT = {r=1, g=0.8, b=0.2},
        HEALING = {r=0.4, g=1, b=0.4},
        DEBUFFS = {r=0.9, g=0.3, b=0.9},
        UTILITY = {r=0.7, g=0.7, b=0.7},
    }
    container.buffCategoryTabs = {}
    container.selectedBuffCategory = "CRITICAL"

    local tabX = 0
    local tabWidth = 31  -- Fits 9 tabs (9*31 + 8*2 = 295 <= 304)
    for _, catId in ipairs(buffCategories) do
        local tabBtn = CreateFrame("Button", nil, buffTabFrame)
        tabBtn:SetSize(tabWidth, 18)
        tabBtn:SetPoint("LEFT", tabX, 0)

        local tabBg = tabBtn:CreateTexture(nil, "BACKGROUND")
        tabBg:SetAllPoints()
        tabBg:SetTexture(0.12, 0.12, 0.12, 1)
        tabBtn.bg = tabBg

        -- Color indicator line at bottom of tab
        local colorLine = tabBtn:CreateTexture(nil, "ARTWORK")
        colorLine:SetSize(tabWidth - 4, 2)
        colorLine:SetPoint("BOTTOM", 0, 1)
        local catColor = buffCategoryColors[catId]
        colorLine:SetTexture(catColor.r, catColor.g, catColor.b, 0.8)
        tabBtn.colorLine = colorLine

        local tabText = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER", 0, 1)
        tabText:SetText(buffCategoryNames[catId])
        tabBtn.text = tabText

        tabBtn:SetScript("OnClick", function()
            container.selectedBuffCategory = catId
            GUI.UpdateCompositionBuffDisplay(container)
            -- Update tab appearance
            for cid, btn in pairs(container.buffCategoryTabs) do
                local color = buffCategoryColors[cid]
                if cid == catId then
                    btn.bg:SetTexture(0.2, 0.2, 0.25, 1)
                    btn.text:SetTextColor(1, 0.82, 0)
                    btn.colorLine:SetTexture(color.r, color.g, color.b, 1)
                else
                    btn.bg:SetTexture(0.12, 0.12, 0.12, 1)
                    btn.text:SetTextColor(0.6, 0.6, 0.6)
                    btn.colorLine:SetTexture(color.r, color.g, color.b, 0.4)
                end
            end
        end)

        tabBtn:SetScript("OnEnter", function(self)
            if catId ~= container.selectedBuffCategory then
                self.bg:SetTexture(0.18, 0.18, 0.2, 1)
            end
        end)
        tabBtn:SetScript("OnLeave", function(self)
            if catId ~= container.selectedBuffCategory then
                self.bg:SetTexture(0.12, 0.12, 0.12, 1)
            end
        end)

        container.buffCategoryTabs[catId] = tabBtn
        tabX = tabX + tabWidth + 2
    end

    -- Set initial selected tab
    container.buffCategoryTabs["CRITICAL"].bg:SetTexture(0.2, 0.2, 0.25, 1)
    container.buffCategoryTabs["CRITICAL"].text:SetTextColor(1, 0.82, 0)

    -- Buff display frame (shows buffs for selected category) - inside the buff section
    local buffFrame = CreateFrame("Frame", nil, buffSection)
    buffFrame:SetPoint("TOPLEFT", 4, -40)
    buffFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    GUI.ApplyBackdrop(buffFrame, "Inset", 0.4)
    container.buffFrame = buffFrame

    -- Create buff display rows (icon + status + name + provider count).
    -- Pre-create a generous pool; the number shown adapts to the frame height,
    -- and wheel paging reaches categories with more buffs than fit.
    container.buffRows = {}
    container.buffOffset = 0
    local NUM_BUFF_ROWS = 20
    local BUFF_ROW_HEIGHT = 16
    buffFrame:EnableMouseWheel(true)
    buffFrame:SetScript("OnMouseWheel", function(_, delta)
        container.buffOffset = (container.buffOffset or 0) - delta
        GUI.UpdateCompositionBuffDisplay(container)
    end)
    buffFrame:SetScript("OnSizeChanged", function()
        GUI.UpdateCompositionBuffDisplay(container)
    end)
    for i = 1, NUM_BUFF_ROWS do
        local row = CreateFrame("Frame", nil, buffFrame)
        row:SetSize(296, BUFF_ROW_HEIGHT)  -- Increased from 268
        row:SetPoint("TOPLEFT", 2, -1 - (i-1) * BUFF_ROW_HEIGHT)

        -- Alternating row background
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if i % 2 == 0 then
            rowBg:SetTexture(0.08, 0.08, 0.08, 0.5)
        else
            rowBg:SetTexture(0.12, 0.12, 0.12, 0.3)
        end
        row.bg = rowBg

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", 2, 0)
        row.icon = icon

        local statusIcon = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusIcon:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        statusIcon:SetWidth(14)
        row.statusIcon = statusIcon

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", statusIcon, "RIGHT", 2, 0)
        nameText:SetWidth(190)  -- Increased from 165
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local providerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        providerText:SetPoint("RIGHT", -4, 0)
        providerText:SetWidth(45)
        providerText:SetJustifyH("RIGHT")
        providerText:SetTextColor(0.5, 0.5, 0.5)
        row.providerText = providerText

        -- Hover highlight and tooltip
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self.bg:SetTexture(0.25, 0.25, 0.3, 0.6)
            if self.buffData then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.buffData.name, 1, 0.82, 0)
                if self.buffData.info.description then
                    GameTooltip:AddLine(self.buffData.info.description, 1, 1, 1, true)
                end
                if self.buffData.info.classes and #self.buffData.info.classes > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Provided by:", 0.7, 0.7, 0.7)
                    GameTooltip:AddLine("  " .. table.concat(self.buffData.info.classes, ", "), 0.6, 0.6, 0.6)
                end
                -- Show required specs if this buff is spec-specific
                if self.buffData.info.specs and #self.buffData.info.specs > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Requires spec:", 1, 0.5, 0.5)
                    GameTooltip:AddLine("  " .. table.concat(self.buffData.info.specs, ", "), 0.8, 0.6, 0.6)
                end
                if self.buffData.info.alternatesWith then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Alternates with:", 0.7, 0.7, 0.7)
                    for _, alt in ipairs(self.buffData.info.alternatesWith) do
                        GameTooltip:AddLine("  " .. alt, 0.5, 0.7, 0.5)
                    end
                end
                -- Show confirmed providers with spec info
                if self.buffData.providerDetails and #self.buffData.providerDetails > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("In raid (confirmed):", 0.4, 1, 0.4)
                    for _, prov in ipairs(self.buffData.providerDetails) do
                        local specStr = prov.spec and (" (" .. prov.spec .. ")") or ""
                        GameTooltip:AddLine("  " .. prov.name .. specStr, 0.4, 0.8, 0.4)
                    end
                elseif #self.buffData.providers > 0 then
                    -- Fallback to simple provider list
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("In raid (" .. #self.buffData.providers .. "):", 0.4, 1, 0.4)
                    for _, name in ipairs(self.buffData.providers) do
                        GameTooltip:AddLine("  " .. name, 0.4, 0.8, 0.4)
                    end
                end
                -- Show potential providers (class match but spec unknown/wrong)
                if self.buffData.potentialProviders and #self.buffData.potentialProviders > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Potential providers:", 1, 0.8, 0.4)
                    for _, pot in ipairs(self.buffData.potentialProviders) do
                        local reason = ""
                        if pot.reason == "wrong_spec" then
                            reason = " (wrong spec: " .. (pot.spec or "?") .. ")"
                        elseif pot.reason == "spec_unknown" then
                            reason = " (spec unknown)"
                        end
                        GameTooltip:AddLine("  " .. pot.name .. reason, 0.8, 0.6, 0.4)
                    end
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if i % 2 == 0 then
                self.bg:SetTexture(0.08, 0.08, 0.08, 0.5)
            else
                self.bg:SetTexture(0.12, 0.12, 0.12, 0.3)
            end
            GameTooltip:Hide()
        end)

        container.buffRows[i] = row
        row:Hide()
    end

    -- ========================================================================
    -- MIDDLE PANEL: Classes + Raid Groups (50% width)
    -- ========================================================================
    local classPanel = CreateFrame("Frame", nil, container)
    classPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 8, 0)
    classPanel:SetPoint("BOTTOM", 0, 10)
    -- Use percentage-based width (50% of container)
    local function UpdateClassPanelWidth()
        local containerWidth = container:GetWidth()
        if containerWidth and containerWidth > 100 then
            classPanel:SetWidth(math.floor(containerWidth * 0.50) - 10)
        else
            classPanel:SetWidth(370)  -- Fallback
        end
    end
    UpdateClassPanelWidth()
    GUI.ApplyBackdrop(classPanel, "SubPanel", 0.9)
    container.classPanel = classPanel

    local classTitle = classPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classTitle:SetPoint("TOPLEFT", 6, -4)
    classTitle:SetText("Classes")
    classTitle:SetTextColor(1, 0.82, 0)

    -- Class icons with counts (single row across top)
    container.classDisplays = {}
    local classOrder = {"WARRIOR", "PALADIN", "DEATHKNIGHT", "DRUID", "PRIEST",
                        "SHAMAN", "MAGE", "WARLOCK", "HUNTER", "ROGUE"}
    local classIcons = {
        WARRIOR = "Interface\\Icons\\ClassIcon_Warrior",
        PALADIN = "Interface\\Icons\\ClassIcon_Paladin",
        DEATHKNIGHT = "Interface\\Icons\\ClassIcon_DeathKnight",
        DRUID = "Interface\\Icons\\ClassIcon_Druid",
        PRIEST = "Interface\\Icons\\ClassIcon_Priest",
        SHAMAN = "Interface\\Icons\\ClassIcon_Shaman",
        MAGE = "Interface\\Icons\\ClassIcon_Mage",
        WARLOCK = "Interface\\Icons\\ClassIcon_Warlock",
        HUNTER = "Interface\\Icons\\ClassIcon_Hunter",
        ROGUE = "Interface\\Icons\\ClassIcon_Rogue",
    }

    local classX = 6
    for i, class in ipairs(classOrder) do
        local classFrame = CreateFrame("Frame", nil, classPanel)
        classFrame:SetSize(34, 14)
        classFrame:SetPoint("TOPLEFT", classX, -18)

        local icon = classFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("LEFT", 0, 0)
        icon:SetTexture(classIcons[class] or "Interface\\Icons\\INV_Misc_QuestionMark")

        local classColor = AIP.Composition and AIP.Composition.ClassColors[class] or {r=1, g=1, b=1}

        local countText = classFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("LEFT", icon, "RIGHT", 1, 0)
        countText:SetText("0")
        countText:SetTextColor(classColor.r, classColor.g, classColor.b)

        classFrame:EnableMouse(true)
        classFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(class:sub(1,1) .. class:sub(2):lower():gsub("knight", " Knight"), classColor.r, classColor.g, classColor.b)
            GameTooltip:Show()
        end)
        classFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        container.classDisplays[class] = {count = countText, icon = icon, frame = classFrame}
        classX = classX + 36
    end

    -- RAID GROUPS (Blizzard style: 8 groups of 5 members, arranged in 2 rows of 4)
    local groupsLabel = classPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupsLabel:SetPoint("TOPLEFT", 6, -36)
    groupsLabel:SetText("Raid Groups")
    groupsLabel:SetTextColor(1, 0.82, 0)

    local groupsFrame = CreateFrame("Frame", nil, classPanel)
    groupsFrame:SetPoint("TOPLEFT", 4, -50)
    groupsFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    GUI.ApplyBackdrop(groupsFrame, "Inset", 0.5)
    container.groupsFrame = groupsFrame

    -- Create 8 group frames (2 rows x 4 columns)
    container.raidGroups = {}
    local GROUP_WIDTH = 88
    local GROUP_HEIGHT = 90
    local MEMBER_HEIGHT = 24  -- Increased for 2-row display (name + spec)

    -- Dynamic resizing function for group frames
    local function RecalculateGroupLayouts()
        local frameWidth = groupsFrame:GetWidth()
        local frameHeight = groupsFrame:GetHeight()
        if not frameWidth or frameWidth < 50 or not frameHeight or frameHeight < 50 then return end

        -- Calculate dynamic sizes (4 columns, 2 rows)
        local padding = 4
        local hGap = 4
        local vGap = 6
        local dynWidth = math.floor((frameWidth - padding * 2 - hGap * 3) / 4)
        local dynHeight = math.floor((frameHeight - padding * 2 - vGap) / 2)
        local dynMemberHeight = math.floor((dynHeight - 14) / 5)  -- 14px for header

        for g = 1, 8 do
            local gf = container.raidGroups[g]
            if gf then
                local col = (g - 1) % 4
                local row = math.floor((g - 1) / 4)

                gf:ClearAllPoints()
                gf:SetSize(dynWidth, dynHeight)
                gf:SetPoint("TOPLEFT", padding + col * (dynWidth + hGap), -padding - row * (dynHeight + vGap))

                -- Resize member slots
                for m = 1, 5 do
                    local slot = gf.slots[m]
                    if slot then
                        slot:SetSize(dynWidth - 4, dynMemberHeight)
                        slot:ClearAllPoints()
                        slot:SetPoint("TOPLEFT", 2, -14 - (m - 1) * dynMemberHeight)
                        if slot.nameText then
                            slot.nameText:SetWidth(dynWidth - 8)
                        end
                        if slot.specText then
                            slot.specText:SetWidth(dynWidth - 8)
                        end
                    end
                end
            end
        end
    end
    container.RecalculateGroupLayouts = RecalculateGroupLayouts

    -- Register resize handler
    groupsFrame:SetScript("OnSizeChanged", RecalculateGroupLayouts)

    for g = 1, 8 do
        local col = (g - 1) % 4
        local row = math.floor((g - 1) / 4)

        local groupFrame = CreateFrame("Frame", nil, groupsFrame)
        groupFrame:SetSize(GROUP_WIDTH, GROUP_HEIGHT)
        groupFrame:SetPoint("TOPLEFT", 2 + col * (GROUP_WIDTH + 2), -2 - row * (GROUP_HEIGHT + 4))

        -- Group header
        local groupBg = groupFrame:CreateTexture(nil, "BACKGROUND")
        groupBg:SetAllPoints()
        groupBg:SetTexture(0.1, 0.1, 0.15, 0.8)
        groupFrame.bg = groupBg

        local groupHeader = groupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        groupHeader:SetPoint("TOPLEFT", 2, -1)
        groupHeader:SetText("Group " .. g)
        groupHeader:SetTextColor(0.8, 0.8, 0.4)
        groupFrame.header = groupHeader

        -- 5 member slots per group
        groupFrame.slots = {}
        for m = 1, 5 do
            local slot = CreateFrame("Button", nil, groupFrame)
            slot:SetSize(GROUP_WIDTH - 4, MEMBER_HEIGHT)
            slot:SetPoint("TOPLEFT", 2, -12 - (m - 1) * MEMBER_HEIGHT)
            slot.groupNum = g
            slot.slotNum = m

            local slotBg = slot:CreateTexture(nil, "BACKGROUND")
            slotBg:SetAllPoints()
            slotBg:SetTexture(0.15, 0.15, 0.15, 0.5)
            slot.bg = slotBg

            -- Row 1: Name with role indicator
            local nameText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameText:SetPoint("TOPLEFT", 2, -1)
            nameText:SetWidth(GROUP_WIDTH - 8)
            nameText:SetHeight(11)
            nameText:SetJustifyH("LEFT")
            nameText:SetText("")
            slot.nameText = nameText

            -- Row 2: Spec info (smaller font)
            local specText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            specText:SetPoint("TOPLEFT", 2, -12)
            specText:SetWidth(GROUP_WIDTH - 8)
            specText:SetHeight(10)
            specText:SetJustifyH("LEFT")
            specText:SetFont("Fonts\\FRIZQT__.TTF", 8)
            specText:SetTextColor(0.6, 0.6, 0.6)
            specText:SetText("")
            slot.specText = specText

            -- Drag highlight overlay
            local dragHighlight = slot:CreateTexture(nil, "OVERLAY")
            dragHighlight:SetAllPoints()
            dragHighlight:SetTexture(0.3, 0.6, 1, 0.4)
            dragHighlight:Hide()
            slot.dragHighlight = dragHighlight

            -- Enable drag-and-drop for member movement
            slot:RegisterForDrag("LeftButton")
            slot:SetMovable(false)

            slot:SetScript("OnDragStart", function(self)
                if self.memberData and self.memberData.raidIndex then
                    -- Store drag source info
                    container.dragSource = self
                    container.dragSourceIndex = self.memberData.raidIndex
                    container.dragSourceGroup = self.groupNum
                    -- Visual feedback
                    self.bg:SetTexture(0.5, 0.3, 0.1, 0.8)
                    -- Show drag cursor
                    SetCursor("Interface\\CURSOR\\UI-Cursor-Move")
                end
            end)

            slot:SetScript("OnDragStop", function(self)
                -- Reset visual
                self.bg:SetTexture(0.15, 0.15, 0.15, 0.5)
                ResetCursor()

                -- Find what slot the cursor is over
                local targetSlot = nil
                local targetGroup = nil

                if container.dragSourceIndex then
                    -- Check all slots to find which one the cursor is over
                    for gNum = 1, 8 do
                        local gf = container.raidGroups[gNum]
                        if gf and gf.slots then
                            for sNum = 1, 5 do
                                local s = gf.slots[sNum]
                                if s and s:IsMouseOver() then
                                    targetSlot = s
                                    targetGroup = gNum
                                    break
                                end
                            end
                        end
                        if targetSlot then break end
                    end

                    -- Perform the move if we found a valid target
                    if targetGroup and targetGroup ~= container.dragSourceGroup then
                        local sourceIndex = container.dragSourceIndex
                        if IsRaidLeader() or IsRaidOfficer() then
                            SetRaidSubgroup(sourceIndex, targetGroup)
                            -- Refresh after delay
                            AIP.Utils.DelayedCall(0.3, function()
                                if AIP.Composition then
                                    AIP.Composition.ScanRaid()
                                end
                                GUI.UpdateCompositionTab()
                            end)
                        else
                            AIP.Print("You must be raid leader or assistant to move players.")
                        end
                    end
                end

                -- Clear drag state
                container.dragSource = nil
                container.dragSourceIndex = nil
                container.dragSourceGroup = nil

                -- Hide all drop highlights
                for gNum = 1, 8 do
                    if container.raidGroups[gNum] then
                        for sNum = 1, 5 do
                            local s = container.raidGroups[gNum].slots[sNum]
                            if s and s.dragHighlight then
                                s.dragHighlight:Hide()
                            end
                        end
                    end
                end
            end)

            -- Hover tooltip and drop target highlight
            slot:SetScript("OnEnter", function(self)
                -- Show drop highlight if dragging
                if container.dragSource and container.dragSource ~= self then
                    self.dragHighlight:Show()
                else
                    self.bg:SetTexture(0.3, 0.3, 0.4, 0.6)
                end
                -- Show tooltip
                if self.memberData then
                    local md = self.memberData
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local classColor = AIP.Composition and AIP.Composition.ClassColors[md.class] or {r=1, g=1, b=1}
                    local colorCode = string.format("|cFF%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
                    GameTooltip:AddLine(colorCode .. (md.name or "Unknown") .. "|r", 1, 1, 1)
                    GameTooltip:AddLine("Class: " .. colorCode .. (md.class or "Unknown") .. "|r", 0.7, 0.7, 0.7)
                    if md.spec then
                        GameTooltip:AddLine("Spec: |cFF00FF00" .. md.spec .. "|r", 0.7, 0.7, 0.7)
                    end
                    GameTooltip:AddLine("Role: " .. (md.role or "DPS"), 0.7, 0.7, 0.7)
                    if md.gs and md.gs > 0 then
                        GameTooltip:AddLine("GearScore: " .. md.gs, 0.7, 0.7, 0.7)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF888888Drag to move to another group|r", 0.5, 0.5, 0.5)
                    GameTooltip:Show()
                end
            end)
            slot:SetScript("OnLeave", function(self)
                self.bg:SetTexture(0.15, 0.15, 0.15, 0.5)
                self.dragHighlight:Hide()
                GameTooltip:Hide()
            end)

            groupFrame.slots[m] = slot
        end

        container.raidGroups[g] = groupFrame
    end

    -- Keep memberRows for compatibility with existing update functions
    container.memberRows = {}
    container.memberRowHeight = MEMBER_HEIGHT
    container.numMemberRows = 40  -- 8 groups x 5 members

    -- ========================================================================
    -- RIGHT PANEL: Raid Benefits Stats (20% width)
    -- ========================================================================
    local benefitsSection = CreateFrame("Frame", nil, container)
    benefitsSection:SetPoint("TOPLEFT", classPanel, "TOPRIGHT", 8, 0)
    benefitsSection:SetPoint("BOTTOM", 0, 10)
    -- Use percentage-based width (20% of container)
    local function UpdateBenefitsPanelWidth()
        local containerWidth = container:GetWidth()
        if containerWidth and containerWidth > 100 then
            benefitsSection:SetWidth(math.floor(containerWidth * 0.20) - 15)
        else
            benefitsSection:SetWidth(160)  -- Fallback
        end
    end
    UpdateBenefitsPanelWidth()
    GUI.ApplyBackdrop(benefitsSection, "SubPanel", 0.9)
    container.benefitsSection = benefitsSection

    -- Function to update all panel widths
    container.UpdatePanelWidths = function()
        UpdateLeftPanelWidth()
        UpdateClassPanelWidth()
        UpdateBenefitsPanelWidth()
        -- Trigger group layout recalculation
        if container.RecalculateGroupLayouts then
            container.RecalculateGroupLayouts()
        end
    end

    local benefitsTitle = benefitsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    benefitsTitle:SetPoint("TOPLEFT", 6, -4)
    benefitsTitle:SetText("Raid Benefits")
    benefitsTitle:SetTextColor(1, 0.82, 0)

    -- Benefits scroll frame
    local benefitsFrame = CreateFrame("Frame", nil, benefitsSection)
    benefitsFrame:SetPoint("TOPLEFT", 4, -18)
    benefitsFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    GUI.ApplyBackdrop(benefitsFrame, "Inset", 0.4)
    container.benefitsFrame = benefitsFrame

    -- Create benefit stat rows
    container.benefitRows = {}
    local BENEFIT_CATEGORIES = {
        {id = "STATS", name = "Stats", color = {r=0.4, g=0.8, b=1}},
        {id = "ATTACK", name = "Attack", color = {r=1, g=0.6, b=0.2}},
        {id = "SPELL", name = "Spell", color = {r=0.8, g=0.4, b=1}},
        {id = "HASTE", name = "Haste", color = {r=0.2, g=0.8, b=0.6}},
        {id = "CRIT", name = "Crit", color = {r=1, g=0.8, b=0.2}},
        {id = "DEBUFF", name = "Debuffs", color = {r=0.9, g=0.3, b=0.9}},
        {id = "UTIL", name = "Utility", color = {r=0.7, g=0.7, b=0.7}},
    }
    container.benefitCategories = BENEFIT_CATEGORIES

    local benefitY = -4
    for _, cat in ipairs(BENEFIT_CATEGORIES) do
        -- Category header
        local catHeader = benefitsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catHeader:SetPoint("TOPLEFT", 4, benefitY)
        catHeader:SetText(cat.name)
        catHeader:SetTextColor(cat.color.r, cat.color.g, cat.color.b)
        benefitY = benefitY - 12

        -- Stats container for this category
        local catFrame = CreateFrame("Frame", nil, benefitsFrame)
        catFrame:SetPoint("TOPLEFT", 4, benefitY)
        catFrame:SetPoint("RIGHT", -4, 0)
        catFrame:SetHeight(36)

        -- Create stat display rows (2 columns)
        catFrame.statRows = {}
        for j = 1, 4 do
            local col = (j - 1) % 2
            local rowNum = math.floor((j - 1) / 2)

            local statRow = CreateFrame("Frame", nil, catFrame)
            statRow:SetSize(80, 12)
            statRow:SetPoint("TOPLEFT", col * 82, -rowNum * 12)

            local statIcon = statRow:CreateTexture(nil, "ARTWORK")
            statIcon:SetSize(10, 10)
            statIcon:SetPoint("LEFT", 0, 0)
            statRow.icon = statIcon

            local statText = statRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statText:SetPoint("LEFT", statIcon, "RIGHT", 2, 0)
            statText:SetWidth(66)
            statText:SetJustifyH("LEFT")
            statRow.text = statText

            -- Tooltip
            statRow:EnableMouse(true)
            statRow:SetScript("OnEnter", function(self)
                if self.tooltipText then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.tooltipTitle or "Buff", 1, 0.82, 0)
                    GameTooltip:AddLine(self.tooltipText, 1, 1, 1, true)
                    if self.tooltipProviders then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Provided by:", 0.5, 0.5, 0.5)
                        GameTooltip:AddLine(self.tooltipProviders, 0.4, 0.8, 0.4)
                    end
                    GameTooltip:Show()
                end
            end)
            statRow:SetScript("OnLeave", function() GameTooltip:Hide() end)

            catFrame.statRows[j] = statRow
            statRow:Hide()
        end

        container.benefitRows[cat.id] = catFrame
        benefitY = benefitY - 28
    end

    -- Summary section at bottom
    local summaryFrame = CreateFrame("Frame", nil, benefitsSection)
    summaryFrame:SetPoint("BOTTOMLEFT", 4, 4)
    summaryFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    summaryFrame:SetHeight(40)
    GUI.ApplyBackdrop(summaryFrame, "Inset", 0.3)
    container.summaryFrame = summaryFrame

    local summaryTitle = summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryTitle:SetPoint("TOPLEFT", 4, -2)
    summaryTitle:SetText("Coverage")
    summaryTitle:SetTextColor(1, 0.82, 0)

    local summaryText = summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryText:SetPoint("TOPLEFT", 4, -14)
    summaryText:SetPoint("BOTTOMRIGHT", -4, 2)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetJustifyV("TOP")
    summaryText:SetText("")
    container.summaryText = summaryText

    -- Composition frame reference for text update
    container.compFrame = leftPanel
    container.compText = templateDisplay
end

-- Calculate and display raid benefits based on available buffs
function GUI.UpdateRaidBenefits(container)
    if not container or not container.benefitRows then return end
    if not AIP.Composition then return end

    local raid = AIP.Composition.CurrentRaid
    local buffs = raid.buffsAvailable or {}
    local providers = raid.buffProviders or {}

    -- Define benefit mappings
    local benefits = {
        STATS = {
            {buff = "Blessing of Kings", short = "+10% Stats", icon = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings"},
            {buff = "Power Word: Fortitude", short = "+165 Stam", icon = "Interface\\Icons\\Spell_Holy_WordFortitude"},
            {buff = "Gift of the Wild", short = "+51 Stats", icon = "Interface\\Icons\\Spell_Nature_Regeneration"},
            {buff = "Arcane Intellect", short = "+60 Int", icon = "Interface\\Icons\\Spell_Holy_ArcaneIntellect"},
        },
        ATTACK = {
            {buff = "Trueshot Aura", alt = {"Abomination's Might", "Unleashed Rage"}, short = "+10% AP", icon = "Interface\\Icons\\Ability_TrueShot"},
            {buff = "Battle Shout", alt = {"Blessing of Might"}, short = "+550 AP", icon = "Interface\\Icons\\Ability_Warrior_BattleShout"},
            {buff = "Ferocious Inspiration", alt = {"Arcane Empowerment", "Sanctified Retribution"}, short = "+3% Dmg", icon = "Interface\\Icons\\Ability_Hunter_FerociousInspiration"},
            {buff = "Horn of Winter", alt = {"Strength of Earth Totem"}, short = "+155 Str/Agi", icon = "Interface\\Icons\\INV_Misc_Horn_02"},
        },
        SPELL = {
            {buff = "Totem of Wrath", alt = {"Flametongue Totem"}, short = "+280 SP", icon = "Interface\\Icons\\Spell_Fire_TotemOfWrath"},
            {buff = "Demonic Pact", short = "+10% SP", icon = "Interface\\Icons\\Spell_Shadow_DemonicPact"},
            {buff = "Focus Magic", short = "+3% Crit", icon = "Interface\\Icons\\Spell_Arcane_StudentOfMagic"},
            {buff = "Moonkin Aura", alt = {"Elemental Oath"}, short = "+5% Crit", icon = "Interface\\Icons\\Spell_Nature_MoonkinForm"},
        },
        HASTE = {
            {buff = "Bloodlust/Heroism", short = "+30% (CD)", icon = "Interface\\Icons\\Spell_Nature_Bloodlust"},
            {buff = "Windfury Totem", alt = {"Icy Talons"}, short = "+16-20% Melee", icon = "Interface\\Icons\\Spell_Nature_Windfury"},
            {buff = "Wrath of Air Totem", short = "+5% Spell", icon = "Interface\\Icons\\Spell_Nature_SlowingTotem"},
            {buff = "Swift Retribution", alt = {"Improved Moonkin Form"}, short = "+3% All", icon = "Interface\\Icons\\Ability_Paladin_SwiftRetribution"},
        },
        CRIT = {
            {buff = "Leader of the Pack", alt = {"Rampage"}, short = "+5% Melee", icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina"},
            {buff = "Moonkin Aura", alt = {"Elemental Oath"}, short = "+5% Spell", icon = "Interface\\Icons\\Spell_Nature_MoonkinForm"},
            {buff = "Improved Scorch", alt = {"Winter's Chill", "Shadow Mastery"}, short = "+5% Target", icon = "Interface\\Icons\\Spell_Fire_SoulBurn"},
            {buff = "Heart of the Crusader", alt = {"Master Poisoner"}, short = "+3% Target", icon = "Interface\\Icons\\Spell_Holy_HolySmite"},
        },
        DEBUFF = {
            {buff = "Sunder Armor", alt = {"Expose Armor", "Acid Spit"}, short = "-20% Armor", icon = "Interface\\Icons\\Ability_Warrior_Sunder"},
            {buff = "Curse of Elements", alt = {"Earth and Moon", "Ebon Plaguebringer"}, short = "+13% Magic", icon = "Interface\\Icons\\Spell_Shadow_ChillTouch"},
            {buff = "Blood Frenzy", alt = {"Savage Combat"}, short = "+4% Phys", icon = "Interface\\Icons\\Ability_Warrior_BloodFrenzy"},
            {buff = "Misery", alt = {"Improved Faerie Fire"}, short = "+3% Hit", icon = "Interface\\Icons\\Spell_Shadow_MiseryBuff"},
        },
        UTIL = {
            {buff = "Replenishment", short = "Mana Regen", icon = "Interface\\Icons\\Spell_Magic_ManaGain"},
            {buff = "Rebirth", short = "Combat Res", icon = "Interface\\Icons\\Spell_Nature_Reincarnation"},
            {buff = "Misdirection", alt = {"Tricks of the Trade"}, short = "Threat", icon = "Interface\\Icons\\Ability_Hunter_Misdirection"},
            {buff = "Blessing of Wisdom", alt = {"Mana Spring Totem"}, short = "+92 mp5", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom"},
        },
    }

    local totalBuffs = 0
    local availableBuffs = 0

    for catId, catFrame in pairs(container.benefitRows) do
        local catBenefits = benefits[catId] or {}
        for j, statRow in ipairs(catFrame.statRows) do
            local benefit = catBenefits[j]
            if benefit then
                local hasIt = buffs[benefit.buff]
                local provider = benefit.buff

                -- Check alternates
                if not hasIt and benefit.alt then
                    for _, altBuff in ipairs(benefit.alt) do
                        if buffs[altBuff] then
                            hasIt = true
                            provider = altBuff
                            break
                        end
                    end
                end

                statRow.icon:SetTexture(benefit.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                if hasIt then
                    statRow.text:SetText("|cFF00FF00" .. benefit.short .. "|r")
                    statRow.icon:SetDesaturated(false)
                    availableBuffs = availableBuffs + 1
                else
                    statRow.text:SetText("|cFF666666" .. benefit.short .. "|r")
                    statRow.icon:SetDesaturated(true)
                end

                statRow.tooltipTitle = provider
                statRow.tooltipText = AIP.Composition.RaidBuffs[provider] and AIP.Composition.RaidBuffs[provider].description or ""
                local provList = providers[provider]
                if provList and #provList > 0 then
                    local names = {}
                    for _, p in ipairs(provList) do
                        table.insert(names, type(p) == "table" and p.name or p)
                    end
                    statRow.tooltipProviders = table.concat(names, ", ")
                else
                    statRow.tooltipProviders = nil
                end

                statRow:Show()
                totalBuffs = totalBuffs + 1
            else
                statRow:Hide()
            end
        end
    end

    -- Update summary
    local coverage = totalBuffs > 0 and math.floor((availableBuffs / totalBuffs) * 100) or 0
    local coverageColor = coverage >= 80 and "|cFF00FF00" or (coverage >= 50 and "|cFFFFFF00" or "|cFFFF4444")
    container.summaryText:SetText(coverageColor .. coverage .. "%|r buffs active\n" ..
        availableBuffs .. "/" .. totalBuffs .. " raid benefits")
end

-- Update buff display for selected category
function GUI.UpdateCompositionBuffDisplay(container)
    if not container or not container.buffRows then return end
    if not AIP.Composition then return end

    local buffsByCategory = AIP.Composition.GetBuffsByCategory()
    local catData = buffsByCategory[container.selectedBuffCategory]

    -- Hide all rows first
    for i = 1, #container.buffRows do
        container.buffRows[i]:Hide()
    end

    if not catData or not catData.buffs then return end

    -- Show as many rows as fit the frame height (capped by the pool), and page
    -- the rest with the mouse wheel via container.buffOffset.
    local buffs = catData.buffs
    local total = #buffs
    local visible = #container.buffRows
    if container.buffFrame then
        local h = container.buffFrame:GetHeight()
        if h and h > 0 then visible = math.floor((h - 2) / 16) end
    end
    if visible < 1 then visible = 1 end
    if visible > #container.buffRows then visible = #container.buffRows end
    local maxOff = math.max(0, total - visible)
    local off = container.buffOffset or 0
    if off > maxOff then off = maxOff end
    if off < 0 then off = 0 end
    container.buffOffset = off

    local rowIndex = 1
    for srcIndex = off + 1, total do
        if rowIndex > visible then break end
        local buffData = buffs[srcIndex]

        local row = container.buffRows[rowIndex]
        row.buffData = buffData

        -- Set icon
        row.icon:SetTexture(buffData.info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Set status icon based on availability
        -- Green = confirmed available
        -- Yellow = alternate available
        -- Orange = potential provider (class matches but spec unknown/wrong)
        -- Red = not available
        if buffData.available then
            row.statusIcon:SetText("|cFF00FF00✓|r")
        elseif buffData.hasAlternate then
            row.statusIcon:SetText("|cFFFFFF00~|r")  -- Has alternate available
        elseif buffData.hasPotential then
            row.statusIcon:SetText("|cFFFF8800?|r")  -- Has class but spec uncertain
        else
            row.statusIcon:SetText("|cFFFF0000✗|r")
        end

        -- Set name with importance highlight
        local nameColor = buffData.info.important and "|cFFFFD700" or "|cFFFFFFFF"
        -- Add spec indicator for spec-specific buffs
        local specIndicator = ""
        if buffData.requiresSpec then
            specIndicator = "|cFF888888*|r"  -- Asterisk for spec-specific buffs
        end
        row.nameText:SetText(nameColor .. buffData.name .. specIndicator .. "|r")

        -- Show provider count or potential/class hint
        if #buffData.providers > 0 then
            row.providerText:SetText("|cFF00FF00" .. #buffData.providers .. "x|r")
        elseif buffData.potentialProviders and #buffData.potentialProviders > 0 then
            -- Show potential count with orange color
            row.providerText:SetText("|cFFFF8800" .. #buffData.potentialProviders .. "?|r")
        else
            -- Show which classes can provide this
            local classHint = ""
            if buffData.info.classes and #buffData.info.classes > 0 then
                classHint = buffData.info.classes[1]:sub(1, 3)
            end
            row.providerText:SetText("|cFF666666" .. classHint .. "|r")
        end

        row:Show()
        rowIndex = rowIndex + 1
    end
end

-- Update raid groups display (Blizzard-style: 8 groups of 5 members)
function GUI.UpdateCompositionMemberTable(container)
    if not container then return end
    if not AIP.Composition then return end

    local raid = AIP.Composition.CurrentRaid
    local members = raid.members or {}

    -- Clear all group slots first
    if container.raidGroups then
        for g = 1, 8 do
            local groupFrame = container.raidGroups[g]
            if groupFrame and groupFrame.slots then
                for m = 1, 5 do
                    local slot = groupFrame.slots[m]
                    if slot then
                        slot.nameText:SetText("")
                        if slot.specText then
                            slot.specText:SetText("")
                        end
                        slot.memberData = nil
                        slot.bg:SetTexture(0.15, 0.15, 0.15, 0.3)
                    end
                end
            end
        end
    end

    -- Organize members by subgroup (GetRaidRosterInfo returns subgroup)
    local groups = {}
    for i = 1, 8 do groups[i] = {} end

    -- Get actual raid subgroups if in raid, otherwise distribute evenly
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
            if name and subgroup and subgroup >= 1 and subgroup <= 8 then
                -- Find matching member data
                local memberData = nil
                for _, m in ipairs(members) do
                    if m.name == name then
                        memberData = m
                        break
                    end
                end
                if memberData then
                    -- Include raid index for drag-and-drop
                    memberData.raidIndex = i
                    table.insert(groups[subgroup], memberData)
                else
                    -- Create basic member data with raid index
                    table.insert(groups[subgroup], {
                        name = name,
                        class = fileName or "UNKNOWN",
                        role = role or "DPS",
                        gs = 0,
                        raidIndex = i
                    })
                end
            end
        end
    else
        -- Not in raid - distribute members evenly into groups
        for i, member in ipairs(members) do
            local groupNum = math.ceil(i / 5)
            if groupNum > 8 then groupNum = 8 end
            table.insert(groups[groupNum], member)
        end
    end

    -- Populate group frames
    if container.raidGroups then
        for g = 1, 8 do
            local groupFrame = container.raidGroups[g]
            if groupFrame and groupFrame.slots then
                local groupMembers = groups[g] or {}
                local memberCount = #groupMembers

                -- Update group header with count
                if groupFrame.header then
                    if memberCount > 0 then
                        groupFrame.header:SetText("Group " .. g .. " (" .. memberCount .. ")")
                        groupFrame.header:SetTextColor(0.9, 0.9, 0.6)
                    else
                        groupFrame.header:SetText("Group " .. g)
                        groupFrame.header:SetTextColor(0.5, 0.5, 0.4)
                    end
                end

                -- Fill slots
                for m = 1, 5 do
                    local slot = groupFrame.slots[m]
                    if slot then
                        local member = groupMembers[m]
                        if member then
                            slot.memberData = member

                            local classColor = AIP.Composition and AIP.Composition.ClassColors[member.class] or {r=1, g=1, b=1}
                            local colorStr = string.format("|cFF%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)

                            -- Display name with role indicator
                            local displayName = member.name or "Unknown"
                            if #displayName > 8 then
                                displayName = displayName:sub(1, 7) .. "."
                            end

                            local roleChar = ""
                            if member.role == "TANK" then
                                roleChar = "|cFF4499FF[T]|r "
                            elseif member.role == "HEALER" then
                                roleChar = "|cFF44FF44[H]|r "
                            end

                            -- Row 1: Name with role indicator
                            slot.nameText:SetText(roleChar .. colorStr .. displayName .. "|r")

                            -- Row 2: Class - Spec (or just Class if no spec)
                            local className = member.class and (member.class:sub(1,1) .. member.class:sub(2):lower():gsub("knight", " Knight")) or ""
                            local specName = member.spec or ""
                            local specLine = className
                            if specName ~= "" then
                                specLine = className .. " - " .. specName
                            end
                            if slot.specText then
                                slot.specText:SetText(specLine)
                            end

                            slot.bg:SetTexture(0.2, 0.2, 0.25, 0.6)
                        else
                            slot.nameText:SetText("")
                            if slot.specText then
                                slot.specText:SetText("")
                            end
                            slot.memberData = nil
                            slot.bg:SetTexture(0.1, 0.1, 0.1, 0.3)
                        end
                    end
                end
            end
        end
    end
end

-- Update filter dropdown with detected raids from tree data
function GUI.UpdateFilterDropdownOptions(container, treeData)
    if not container or not container.filterDropdown then return end

    -- Skip if any dropdown is currently open (prevents closing while user has dropdown open)
    local dropdownList = _G["DropDownList1"]
    if dropdownList and dropdownList:IsShown() then
        return  -- Don't re-init while user has dropdown open
    end

    -- Collect detected raids from tree data
    container.detectedRaids = container.detectedRaids or {}
    local detectedRaids = {}
    detectedRaids["ALL"] = {id = "ALL", name = "All"}

    for _, catNode in ipairs(treeData or {}) do
        if catNode.data and catNode.data.id then
            detectedRaids[catNode.data.id] = {id = catNode.data.id, name = catNode.data.name or catNode.data.id}
        elseif catNode.id then
            -- Extract raid id from node id (e.g., "lfm_ICC" -> "ICC")
            local raidId = catNode.id:match("^lfm_(.+)$") or catNode.id:match("^lfg_(.+)$")
            if raidId and raidId ~= "other" then
                detectedRaids[raidId] = {id = raidId, name = raidId}
            end
        end
    end

    -- Store for dropdown initialization
    container.detectedRaids = detectedRaids

    -- Re-initialize dropdown with new options
    local filterDropdown = container.filterDropdown
    UIDropDownMenu_Initialize(filterDropdown, function()
        local info = UIDropDownMenu_CreateInfo()

        -- Always add "All" first
        info.text = "All"
        info.value = "ALL"
        info.func = function()
            container.raidFilter = "ALL"
            UIDropDownMenu_SetText(filterDropdown, "All")
            GUI.RefreshBrowserTab(container.tabType)
        end
        info.checked = (container.raidFilter == "ALL")
        UIDropDownMenu_AddButton(info)

        -- Add detected raids
        local sortedRaids = {}
        for id, data in pairs(detectedRaids) do
            if id ~= "ALL" then
                table.insert(sortedRaids, data)
            end
        end
        table.sort(sortedRaids, function(a, b) return (a.name or "") < (b.name or "") end)

        for _, raid in ipairs(sortedRaids) do
            info = UIDropDownMenu_CreateInfo()
            info.text = raid.name
            info.value = raid.id
            info.func = function()
                container.raidFilter = raid.id
                UIDropDownMenu_SetText(filterDropdown, raid.name)
                GUI.RefreshBrowserTab(container.tabType)
            end
            info.checked = (container.raidFilter == raid.id)
            UIDropDownMenu_AddButton(info)
        end
    end)
end

-- Filter tree data based on search and raid filter
local function FilterTreeData(treeData, searchFilter, raidFilter)
    if (not searchFilter or searchFilter == "") and (not raidFilter or raidFilter == "ALL") then
        return treeData
    end

    local filtered = {}
    for _, catNode in ipairs(treeData) do
        -- Check if category matches raid filter
        local catMatches = (not raidFilter or raidFilter == "ALL")
        if not catMatches and catNode.data and catNode.data.id then
            catMatches = catNode.data.id == raidFilter or
                         (catNode.id and catNode.id:find(raidFilter))
        end
        -- For "Other" category, always include if no specific raid filter
        if catNode.id and catNode.id:find("other") then
            catMatches = (raidFilter == "ALL")
        end

        if catMatches and catNode.children then
            local filteredChildren = {}
            for _, child in ipairs(catNode.children) do
                local childMatches = true

                -- Apply search filter to player/group name and message
                if searchFilter and searchFilter ~= "" then
                    local searchText = (child.text or ""):lower()
                    local msgText = (child.data and child.data.message or ""):lower()
                    childMatches = searchText:find(searchFilter, 1, true) or
                                   msgText:find(searchFilter, 1, true)
                end

                if childMatches then
                    table.insert(filteredChildren, child)
                end
            end

            -- Only add category if it has children after filtering
            if #filteredChildren > 0 then
                local newCatNode = {}
                for k, v in pairs(catNode) do
                    newCatNode[k] = v
                end
                newCatNode.children = filteredChildren
                newCatNode.text = catNode.data and catNode.data.name or catNode.text:match("^(.-)%s*%(") or catNode.text
                newCatNode.text = newCatNode.text .. " (" .. #filteredChildren .. ")"
                table.insert(filtered, newCatNode)
            end
        end
    end
    return filtered
end

-- Refresh browser tab (preserves scroll position and expand/collapse state)
function GUI.RefreshBrowserTab(tabType, forceReset)
    if not GUI.Frame or not GUI.Frame.tabContents then return end
    -- LFM and LFG both render into the single "lfm" browser container.
    local container = GUI.Frame.tabContents[tabType == "lfg" and "lfm" or tabType]
    if not container then return end

    -- Save current scroll position before refresh
    local savedScrollOffset = 0
    if container.treeView and container.treeView.GetScrollOffset then
        savedScrollOffset = container.treeView:GetScrollOffset()
    end

    -- Build tree data with state preservation (don't auto-expand new categories)
    local treeData
    if tabType == "lfm" then
        treeData = AIP.TreeBrowser and AIP.TreeBrowser.BuildLFMTree(not forceReset) or {}
    else
        treeData = AIP.TreeBrowser and AIP.TreeBrowser.BuildLFGTree(not forceReset) or {}
    end

    -- Update filter dropdown with detected raids
    GUI.UpdateFilterDropdownOptions(container, treeData)

    -- Apply search and raid filters
    local searchFilter = container.searchFilter or ""
    local raidFilter = container.raidFilter or "ALL"
    treeData = FilterTreeData(treeData, searchFilter, raidFilter)

    if container.treeView then
        -- Preserve scroll position during update
        container.treeView:SetTreeData(treeData, not forceReset)
    end

    -- Update counts
    local lfmCount, lfgCount = 0, 0
    if AIP.TreeBrowser then
        lfmCount, lfgCount = AIP.TreeBrowser.GetTotalCounts()
    end

    local count = (tabType == "lfm") and lfmCount or lfgCount

    -- Count filtered items (recurse - the LFM tree now nests size sub-groups under
    -- each category, so leaves can be one level deeper than before).
    local function countLeaves(nodes)
        local n = 0
        for _, node in ipairs(nodes or {}) do
            if node.isLeaf then n = n + 1
            elseif node.children then n = n + countLeaves(node.children) end
        end
        return n
    end
    local filteredCount = countLeaves(treeData)

    -- Show/hide empty state message
    if container.emptyTreeText then
        if count == 0 or filteredCount == 0 then
            container.emptyTreeText:Show()
            if count > 0 and filteredCount == 0 then
                container.emptyTreeText:SetText("No matches for current filter\n\nTotal " .. (tabType == "lfm" and "groups" or "players") .. ": " .. count)
            elseif tabType == "lfm" then
                container.emptyTreeText:SetText("No group listings yet\n\nListings appear from chat scanning\nand AIP peers.\n\n|cFF33CCFFTip:|r enable channels in Settings,\nor click + Post Group to start your own.")
            else
                container.emptyTreeText:SetText("No players looking for group yet\n\nLFG players from chat and AIP peers\nshow here with their fit for your listing.\n\n|cFF33CCFFTip:|r click Find Group to enroll yourself.")
            end
        else
            container.emptyTreeText:Hide()
        end
    end

    if container.countsText then
        local filterNote = (searchFilter ~= "" or raidFilter ~= "ALL") and " (filtered)" or ""
        if tabType == "lfm" then
            container.countsText:SetText("Groups: " .. filteredCount .. "/" .. lfmCount .. filterNote)
        else
            container.countsText:SetText("Players: " .. filteredCount .. "/" .. lfgCount .. filterNote)
        end
    end

    -- Update queue panel
    GUI.UpdateQueuePanel(container)
end

-- Update queue panel display (handles both tabs)
function GUI.UpdateQueuePanel(container)
    if not container then return end

    -- One-time mouse-wheel paging for the Queue/LFG/Waitlist lists. Each list
    -- shows a fixed number of rows; wheel scrolling reaches entries beyond the
    -- visible rows (previously anything past row 5 was unreachable).
    local function HookWheel(frame, offsetKey)
        if frame and not frame._wheelHooked then
            frame._wheelHooked = true
            frame:EnableMouseWheel(true)
            frame:SetScript("OnMouseWheel", function(_, delta)
                container[offsetKey] = (container[offsetKey] or 0) - delta
                GUI.UpdateQueuePanel(container)
            end)
        end
    end
    HookWheel(container.queueContent, "queueOffset")
    HookWheel(container.lfgContent, "lfgOffset")
    HookWheel(container.waitlistContent, "waitlistOffset")

    -- Refresh saved instances for lockout checks
    if AIP.TreeBrowser and AIP.TreeBrowser.UpdateSavedInstances then
        AIP.TreeBrowser.UpdateSavedInstances()
    end

    -- Clean up old LFG enrollments
    GUI.CleanupLfgEnrollments()

    local queue = AIP.db and AIP.db.queue or {}
    local waitlistCount = AIP.GetWaitlistCount and AIP.GetWaitlistCount() or 0

    -- Separate queue entries and LFG enrollments
    local queueEntries = {}
    local lfgEntries = {}
    for _, entry in ipairs(queue) do
        if entry.isLfgEnrollment then
            table.insert(lfgEntries, entry)
        else
            table.insert(queueEntries, entry)
        end
    end

    -- Also add LFG enrollments from our tracking table
    for name, enrollment in pairs(GUI.LfgEnrollments or {}) do
        local found = false
        for _, e in ipairs(lfgEntries) do
            if e.name == name then found = true break end
        end
        if not found then
            table.insert(lfgEntries, enrollment)
        end
    end

    -- And LFG players scanned from PUBLIC channels (ChatScanner store). These
    -- previously only appeared in the browser tree, never here - the panel
    -- showed AIP-peer enrollments but was blind to real chat LFG players.
    if AIP.ChatScanner and AIP.ChatScanner.Players then
        for name, player in pairs(AIP.ChatScanner.Players) do
            if player.isLFG then
                local found = false
                for _, e in ipairs(lfgEntries) do
                    if e.name == name then found = true break end
                end
                if not found then
                    table.insert(lfgEntries, {
                        name = name,
                        class = player.class,
                        spec = player.spec,
                        role = player.role,
                        gs = player.gs,
                        ilvl = player.ilvl,
                        raid = player.raids and player.raids[1] or player.raid,
                        weekly = player.weekly,
                        time = player.time,
                        message = player.message,
                        isLfgEnrollment = true,
                        fromChatScan = true,
                    })
                end
            end
        end
    end

    -- Apply search filters
    local queueSearchFilter = container.queueSearchFilter or ""
    local lfgSearchFilter = container.lfgSearchFilter or ""
    local waitlistSearchFilter = container.waitlistSearchFilter or ""

    -- Store totals before filtering (for filtered/total display)
    local totalQueue = #queueEntries
    local totalLfg = #lfgEntries
    local totalWaitlist = #(AIP.db and AIP.db.waitlist or {})

    -- Filter queue entries
    if queueSearchFilter ~= "" then
        local filtered = {}
        for _, entry in ipairs(queueEntries) do
            local name = (entry.name or ""):lower()
            local msg = (entry.message or ""):lower()
            local class = (entry.class or ""):lower()
            if name:find(queueSearchFilter, 1, true) or msg:find(queueSearchFilter, 1, true) or class:find(queueSearchFilter, 1, true) then
                table.insert(filtered, entry)
            end
        end
        queueEntries = filtered
    end

    -- Filter LFG entries
    if lfgSearchFilter ~= "" then
        local filtered = {}
        for _, entry in ipairs(lfgEntries) do
            local name = (entry.name or ""):lower()
            local spec = (entry.spec or ""):lower()
            local raid = (entry.raid or ""):lower()
            local role = (entry.role or ""):lower()
            local class = (entry.class or ""):lower()
            if name:find(lfgSearchFilter, 1, true) or spec:find(lfgSearchFilter, 1, true) or
               raid:find(lfgSearchFilter, 1, true) or role:find(lfgSearchFilter, 1, true) or
               class:find(lfgSearchFilter, 1, true) then
                table.insert(filtered, entry)
            end
        end
        lfgEntries = filtered
    end

    -- While a listing is active, sort both lists best-fit first (the LFG
    -- sub-tab doubles as the "who should I recruit" suggestion list).
    -- Verdicts live in a weak-keyed side table, NEVER on the entries: queue
    -- entries are persisted SavedVariables tables, and a nested verdict
    -- written onto them would be serialized to disk every logout.
    if AIP.FitEngine and GUI.MyGroup then
        local function fitScore(entry)
            if entry.isSelf then return -1 end
            GUI.FitCache[entry] = AIP.FitEngine.ScoreApplicant(entry, GUI.MyGroup)
            return GUI.FitCache[entry].score
        end
        local function byFit(a, b)
            local sa, sb = fitScore(a), fitScore(b)
            if sa ~= sb then return sa > sb end
            return (a.time or 0) > (b.time or 0)
        end
        table.sort(queueEntries, byFit)
        table.sort(lfgEntries, byFit)
    end

    -- Update Queue rows (whisper requests)
    if container.queueRows then
        local numRows = #container.queueRows
        local vis = GUI.QueueVisibleRows(container.queueContent)
        local qOff = math.min(math.max(0, container.queueOffset or 0), math.max(0, #queueEntries - vis))
        container.queueOffset = qOff
        for i = 1, numRows do
            local row = container.queueRows[i]
            local dataIdx = qOff + i
            local entry = queueEntries[dataIdx]

            row.invBtn.index = dataIdx
            row.rejBtn.index = dataIdx
            row.waitBtn.index = dataIdx
            row.blBtn.index = dataIdx
            if row.remBtn then row.remBtn.index = dataIdx end

            if entry and i <= vis then
                row.numText:SetText(dataIdx)

                -- Time since added (seconds display)
                if row.timeText and entry.time then
                    local elapsed = time() - entry.time
                    local timeStr
                    if elapsed < 60 then
                        timeStr = elapsed .. "s"
                    elseif elapsed < 3600 then
                        timeStr = math.floor(elapsed / 60) .. "m"
                    else
                        timeStr = math.floor(elapsed / 3600) .. "h"
                    end
                    row.timeText:SetText(timeStr)
                    -- Color based on wait time
                    if elapsed < 120 then
                        row.timeText:SetTextColor(0.4, 0.8, 0.4)  -- Green (recent)
                    elseif elapsed < 300 then
                        row.timeText:SetTextColor(0.8, 0.8, 0.4)  -- Yellow
                    else
                        row.timeText:SetTextColor(0.8, 0.4, 0.4)  -- Red (waiting long)
                    end
                elseif row.timeText then
                    row.timeText:SetText("-")
                end

                -- Show name with favorite/guild indicators
                local displayName = entry.name or "-"
                if entry.isFavorite then
                    displayName = "|cFFFFD100*|r" .. displayName  -- Gold star for favorite (matches tree)
                    row.nameText:SetTextColor(0, 1, 0.5)  -- Greenish
                elseif entry.isGuildMember then
                    displayName = "|cFF33CCFF+|r" .. displayName  -- Accent plus for guild
                    row.nameText:SetTextColor(0.4, 0.8, 1)  -- Light blue
                else
                    row.nameText:SetTextColor(1, 1, 1)  -- Default white
                end
                -- Fit chip while a listing is active (live verdict per render;
                -- weak side table, never written onto the persisted entry)
                GUI.FitCache[entry] = nil
                if AIP.FitEngine and GUI.MyGroup then
                    GUI.FitCache[entry] = AIP.FitEngine.ScoreApplicant(entry, GUI.MyGroup)
                    displayName = AIP.FitEngine.Chip(GUI.FitCache[entry]) .. " " .. displayName
                end
                row.nameText:SetText(displayName)

                local class = entry.class or "UNKNOWN"
                local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class:upper()]
                if classColor then
                    row.classText:SetText(class)
                    row.classText:SetTextColor(classColor.r, classColor.g, classColor.b)
                else
                    row.classText:SetText(class)
                    row.classText:SetTextColor(1, 1, 1)
                end

                row.msgText:SetText((entry.message or ""):sub(1, 25))

                if entry.isBlacklisted then
                    row.blText:SetText("YES")
                    row.blText:SetTextColor(1, 0.3, 0.3)
                else
                    row.blText:SetText("-")
                    row.blText:SetTextColor(0.5, 0.5, 0.5)
                end

                -- Store entry for tooltip and enable mouse
                row.entryData = entry
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    local e = self.entryData
                    if not e then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(e.name or "Unknown", 1, 0.82, 0)
                    if e.class then GameTooltip:AddLine("Class: " .. e.class, 1, 1, 1) end
                    if e.gs then GameTooltip:AddDoubleLine("GearScore:", tostring(e.gs), 0.7, 0.7, 0.7, 0, 1, 0) end
                    if e.ilvl then GameTooltip:AddDoubleLine("Item Level:", tostring(e.ilvl), 0.7, 0.7, 0.7, 0, 1, 0) end
                    if e.message and e.message ~= "" then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Message:", 0.7, 0.7, 0.7)
                        GameTooltip:AddLine(e.message, 1, 1, 1, true)
                    end
                    if e.isFavorite then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFF00FF00FAVORITE|r - Priority player", 0, 1, 0)
                    end
                    if e.isGuildMember then
                        GameTooltip:AddLine("|cFF33CCFFGUILD MEMBER|r", 0.2, 0.8, 1)
                    end
                    if e.isBlacklisted then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFFFF4444BLACKLISTED|r", 1, 0.27, 0.27)
                        if e.blacklistReason then GameTooltip:AddLine(e.blacklistReason, 1, 0.5, 0.5) end
                    end
                    local eFit = GUI.FitCache[e]
                    if eFit and AIP.FitEngine then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(AIP.FitEngine.Chip(eFit) .. " Fit for your listing:", 1, 0.82, 0)
                        for _, reason in ipairs(eFit.reasons) do
                            GameTooltip:AddLine("  - " .. reason, 0.8, 0.8, 0.8, true)
                        end
                    end
                    if e.isApplication then
                        GameTooltip:AddLine("|cFF33CCFFStructured application (AIP peer)|r", 0.2, 0.8, 1)
                    end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Update LFG rows (enrollment broadcasts)
    container.lfgData = lfgEntries  -- Store for button callbacks
    if container.lfgRows then
        local numRows = #container.lfgRows
        local vis = GUI.QueueVisibleRows(container.lfgContent)
        local lOff = math.min(math.max(0, container.lfgOffset or 0), math.max(0, #lfgEntries - vis))
        container.lfgOffset = lOff
        for i = 1, numRows do
            local row = container.lfgRows[i]
            local dataIdx = lOff + i
            local entry = lfgEntries[dataIdx]

            row.invBtn.index = dataIdx
            row.whisperBtn.index = dataIdx
            row.queueBtn.index = dataIdx
            row.waitlistBtn.index = dataIdx

            if entry and i <= vis then
                row.numText:SetText(dataIdx)

                local class = entry.class or "UNKNOWN"
                local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class:upper()]
                -- Fit chip while a listing is active (live verdict per render;
                -- weak side table, never written onto the persisted entry)
                local lfgDisplayName = entry.name or "-"
                GUI.FitCache[entry] = nil
                if AIP.FitEngine and GUI.MyGroup and not entry.isSelf then
                    GUI.FitCache[entry] = AIP.FitEngine.ScoreApplicant(entry, GUI.MyGroup)
                    lfgDisplayName = AIP.FitEngine.Chip(GUI.FitCache[entry]) .. " " .. lfgDisplayName
                end
                if classColor then
                    row.nameText:SetText(lfgDisplayName)
                    row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
                else
                    row.nameText:SetText(lfgDisplayName)
                    row.nameText:SetTextColor(1, 1, 1)
                end

                row.specText:SetText(entry.spec or entry.role or "-")
                -- Check lockout status for the raid
                local isLocked = false
                if AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and entry.raid then
                    isLocked = AIP.TreeBrowser.IsLockedToInstance(entry.raid)
                end

                if isLocked then
                    row.raidText:SetText("|cFFFF4444" .. (entry.raid or "-") .. "|r")
                else
                    row.raidText:SetText(entry.raid or "-")
                end
                row.gsText:SetText(entry.gs and tostring(entry.gs) or "-")

                -- Store entry for tooltip and enable mouse
                row.entryData = entry
                row.isLocked = isLocked
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    local e = self.entryData
                    if not e then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(e.name or "Unknown", 1, 0.82, 0)
                    if e.class then GameTooltip:AddLine("Class: " .. e.class, 1, 1, 1) end
                    if e.spec then GameTooltip:AddLine("Spec: " .. e.spec, 0.8, 0.8, 0.8) end
                    if e.role then GameTooltip:AddLine("Role: " .. e.role, 0.6, 0.8, 1) end
                    GameTooltip:AddLine(" ")
                    if e.gs then GameTooltip:AddDoubleLine("GearScore:", tostring(e.gs), 0.7, 0.7, 0.7, 0, 1, 0) end
                    if e.ilvl then GameTooltip:AddDoubleLine("Item Level:", tostring(e.ilvl), 0.7, 0.7, 0.7, 0, 1, 0) end
                    if e.raid then
                        if self.isLocked then
                            GameTooltip:AddDoubleLine("Looking for:", e.raid .. " |cFFFF4444[LOCKED]|r", 0.7, 0.7, 0.7, 1, 0.27, 0.27)
                        else
                            GameTooltip:AddDoubleLine("Looking for:", e.raid, 0.7, 0.7, 0.7, 1, 0.82, 0)
                        end
                    end
                    if e.message and e.message ~= "" then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Full Message:", 0.7, 0.7, 0.7)
                        GameTooltip:AddLine(e.message, 1, 1, 1, true)
                    end
                    if e.isSelf then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFF00FF00This is your enrollment|r", 0, 1, 0)
                    end
                    if self.isLocked then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFFFF4444You are saved to this instance|r", 1, 0.27, 0.27)
                    end
                    local eFit = GUI.FitCache[e]
                    if eFit and AIP.FitEngine then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(AIP.FitEngine.Chip(eFit) .. " Fit for your listing:", 1, 0.82, 0)
                        for _, reason in ipairs(eFit.reasons) do
                            GameTooltip:AddLine("  - " .. reason, 0.8, 0.8, 0.8, true)
                        end
                    end
                    -- Full shared character card (gear + achievements) if broadcast / self.
                    if AIP.CharCard and AIP.CharCard.AppendToTooltip then
                        AIP.CharCard.AppendToTooltip(GameTooltip, e.name, e.isSelf)
                    end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Update Waitlist rows
    local rawWaitlist = AIP.db and AIP.db.waitlist or {}
    local waitlistEntries = {}

    -- Build waitlist entries with original indices for filtering support
    for origIdx, entry in ipairs(rawWaitlist) do
        local wlEntry = {
            entry = entry,
            origIndex = origIdx,
        }
        if waitlistSearchFilter ~= "" then
            local name = (entry.name or ""):lower()
            local role = (entry.role or ""):lower()
            local note = (entry.note or ""):lower()
            local class = (entry.class or ""):lower()
            if name:find(waitlistSearchFilter, 1, true) or role:find(waitlistSearchFilter, 1, true) or
               note:find(waitlistSearchFilter, 1, true) or class:find(waitlistSearchFilter, 1, true) then
                table.insert(waitlistEntries, wlEntry)
            end
        else
            table.insert(waitlistEntries, wlEntry)
        end
    end

    if container.waitlistRows then
        local numRows = #container.waitlistRows
        local vis = GUI.QueueVisibleRows(container.waitlistContent)
        local wOff = math.min(math.max(0, container.waitlistOffset or 0), math.max(0, #waitlistEntries - vis))
        container.waitlistOffset = wOff
        for i = 1, numRows do
            local row = container.waitlistRows[i]
            local wlEntry = waitlistEntries[wOff + i]
            local entry = wlEntry and wlEntry.entry or nil
            local origIndex = wlEntry and wlEntry.origIndex or (wOff + i)
            row.entryData = entry

            row.invBtn.index = origIndex
            row.upBtn.index = origIndex
            row.downBtn.index = origIndex
            row.remBtn.index = origIndex
            if row.whisperBtn then row.whisperBtn.index = origIndex end

            if entry and i <= vis then
                row.numText:SetText(origIndex)

                -- Fit chip for protocol applicants (parity with the queue rows:
                -- the leader can scan verdicts without hovering every row)
                local displayName = entry.name or "-"
                if entry.isApplication and AIP.FitEngine and AIP.FitEngine.ScoreApplicant and GUI.MyGroup then
                    local fit = AIP.FitEngine.ScoreApplicant(entry, GUI.MyGroup)
                    displayName = AIP.FitEngine.Chip(fit) .. " " .. displayName
                end
                row.nameText:SetText(displayName)

                -- Class-colored name when the class is known
                local classColor = entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class:upper()]
                if classColor then
                    row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
                else
                    row.nameText:SetTextColor(1, 1, 1)
                end

                -- Color role text (shared role palette)
                local roleColors = (AIP.UI and AIP.UI.Colors and AIP.UI.Colors.roleRGB) or {}
                local color = roleColors[entry.role] or {1, 1, 1}
                row.roleText:SetText(entry.role or "DPS")
                row.roleText:SetTextColor(color[1], color[2], color[3])

                if row.gsText then
                    row.gsText:SetText(entry.gs and tostring(entry.gs) or "-")
                end
                row.noteText:SetText((entry.note or ""):sub(1, 20))
                row.timeText:SetText(AIP.FormatTimeAgo and AIP.FormatTimeAgo(entry.addedTime) or "-")

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Update tab button counts (show filtered/total when filter is active)
    -- Note: totalQueue, totalLfg, totalWaitlist were calculated before filtering

    if container.queueTabBtn and container.queueTabBtn.text then
        if queueSearchFilter ~= "" then
            container.queueTabBtn.text:SetText("Queue (" .. #queueEntries .. "/" .. totalQueue .. ")")
        else
            container.queueTabBtn.text:SetText("Queue (" .. #queueEntries .. ")")
        end
    end
    if container.lfgTabBtn and container.lfgTabBtn.text then
        if lfgSearchFilter ~= "" then
            container.lfgTabBtn.text:SetText("LFG (" .. #lfgEntries .. "/" .. totalLfg .. ")")
        else
            container.lfgTabBtn.text:SetText("LFG (" .. #lfgEntries .. ")")
        end
    end
    if container.waitlistTabBtn and container.waitlistTabBtn.text then
        if waitlistSearchFilter ~= "" then
            container.waitlistTabBtn.text:SetText("Waitlist (" .. #waitlistEntries .. "/" .. totalWaitlist .. ")")
        else
            container.waitlistTabBtn.text:SetText("Waitlist (" .. #waitlistEntries .. ")")
        end
    end

    -- Empty-state hints (each parented to its sub-tab content frame, so
    -- they inherit the sub-tab's visibility automatically)
    if container.queueEmptyText then
        if #queueEntries == 0 then container.queueEmptyText:Show() else container.queueEmptyText:Hide() end
    end
    if container.lfgEmptyText then
        if #lfgEntries == 0 then container.lfgEmptyText:Show() else container.lfgEmptyText:Hide() end
    end
    if container.waitlistEmptyText then
        if #waitlistEntries == 0 then
            -- Distinguish "no matches for the filter" from a truly empty list
            if waitlistSearchFilter ~= "" and totalWaitlist > 0 then
                container.waitlistEmptyText:SetText("No matches for '" .. waitlistSearchFilter .. "'\n\n|cFF888888"
                    .. totalWaitlist .. " player" .. (totalWaitlist ~= 1 and "s" or "") .. " on the waitlist - clear the search to see them.|r")
            else
                container.waitlistEmptyText:SetText("Waitlist is empty\n\n|cFF888888Park overflow players here - they are\nwhispered when their turn comes.|r")
            end
            container.waitlistEmptyText:Show()
        else
            container.waitlistEmptyText:Hide()
        end
    end

    -- Update status footer (single source: counts + mode + needs strip)
    GUI.UpdateEnrollmentStatus()
end

-- Refresh the details panel's application-status line for the selected group
function GUI.UpdateApplyStatus(container, data)
    if not container or not container.applyStatus then return end
    local status = data and data.leader and AIP.Apply and AIP.Apply.StatusFor
        and AIP.Apply.StatusFor(data.leader) or nil
    container.applyStatus:SetText(status or "")
end

-- Update details panel when a group is selected
function GUI.UpdateDetailsPanel(container, data)
    if not container then return end
    GUI.UpdateApplyStatus(container, data)

    container.selectedGroupData = data
    -- Set currentLeader for whisper button
    container.currentLeader = data and (data.leader or data.name) or nil

    if not data then
        if container.detContent then container.detContent:Hide() end
        if container.noSelectText then container.noSelectText:Show() end
        return
    end

    if container.noSelectText then container.noSelectText:Hide() end
    if container.detContent then container.detContent:Show() end

    -- Reflect exclusion state on the Hide/Unhide button
    if container.hideBtn then
        local leader = data.leader or data.name
        local hidden = leader and AIP.ChatScanner and AIP.ChatScanner.IsExcluded
            and AIP.ChatScanner.IsExcluded(leader)
        container.hideBtn:SetText(hidden and "Unhide" or "Hide")
    end

    -- Reflect favorite state on the Fav/Unfav button
    if container.favBtn then
        local name = data.leader or data.name
        local isFav = name and AIP.IsPlayerFavorite and AIP.IsPlayerFavorite(name)
        container.favBtn:SetText(isFav and "Unfav" or "Fav")
    end

    if container.leaderValue then
        container.leaderValue:SetText(data.leader or data.name or "-")
    end
    if container.raidValue then
        container.raidValue:SetText(data.raid or "-")
        -- Update lockout indicator
        if container.lockoutIndicator then
            local isLocked = false
            if AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and data.raid then
                AIP.TreeBrowser.UpdateSavedInstances()
                isLocked = AIP.TreeBrowser.IsLockedToInstance(data.raid)
            end
            if isLocked then
                container.lockoutIndicator:Show()
            else
                container.lockoutIndicator:Hide()
            end
        end
        -- Update weekly badge: green if YOU still need this weekly, blue otherwise
        if container.weeklyIndicator then
            if data.weekly then
                local q = AIP.Weekly and AIP.Weekly.ForToken(data.weekly)
                local bossName = q and q.boss or data.weekly
                local wanted = AIP.Weekly and AIP.Weekly.IsWanted(data.weekly)
                if wanted then
                    container.weeklyIndicator:SetText("|cFF00FF00[W] Weekly: " .. bossName .. " (you need this!)|r")
                else
                    container.weeklyIndicator:SetText("|cFF33CCFF[W] Weekly: " .. bossName .. "|r")
                end
                container.weeklyIndicator:Show()
            else
                container.weeklyIndicator:Hide()
            end
        end
    end
    if container.msgValue then
        container.msgValue:SetText(data.message or "-")
    end

    local gsText = "-"
    if data.gsMin and data.gsMin > 0 then
        gsText = tostring(data.gsMin) .. "+"
    elseif data.gs and data.gs > 0 then
        gsText = tostring(data.gs)
    end
    if container.gsValue then
        container.gsValue:SetText(gsText)
    end

    local ilvlText = "-"
    if data.ilvlMin and data.ilvlMin > 0 then
        ilvlText = tostring(data.ilvlMin) .. "+"
    elseif data.ilvl and data.ilvl > 0 then
        ilvlText = tostring(data.ilvl) .. "+"
    end
    if container.ilvlValue then
        container.ilvlValue:SetText(ilvlText)
    end

    local compText = "-"
    if data.tanks or data.healers or data.mdps or data.rdps or data.dps then
        local parts = {}
        if data.tanks then
            table.insert(parts, string.format("T:%d/%d", data.tanks.current or 0, data.tanks.needed or 0))
        end
        if data.healers then
            table.insert(parts, string.format("H:%d/%d", data.healers.current or 0, data.healers.needed or 0))
        end
        if data.mdps then
            table.insert(parts, string.format("M:%d/%d", data.mdps.current or 0, data.mdps.needed or 0))
        end
        if data.rdps then
            table.insert(parts, string.format("R:%d/%d", data.rdps.current or 0, data.rdps.needed or 0))
        end
        -- Backwards compatibility for old dps field
        if not data.mdps and not data.rdps and data.dps then
            table.insert(parts, string.format("D:%d/%d", data.dps.current or 0, data.dps.needed or 0))
        end
        compText = table.concat(parts, " ")
    end
    if container.compValue then
        container.compValue:SetText(compText)
    end

    -- Achievement requirement
    local achieveText = "-"
    if data.achievementId then
        local _, achName = GetAchievementInfo(data.achievementId)
        if achName then
            achieveText = achName
        else
            achieveText = "ID: " .. tostring(data.achievementId)
        end
    elseif data.achievement and data.achievement ~= "" then
        -- Parsed achievement name from message text
        achieveText = data.achievement
    end
    if container.achieveValue then
        container.achieveValue:SetText(achieveText)
    end

    -- Invite keyword
    local keywordText = "-"
    if data.inviteKeyword and data.inviteKeyword ~= "" then
        keywordText = '"' .. data.inviteKeyword .. '"'
    elseif data.triggerKey and data.triggerKey ~= "" then
        keywordText = '"' .. data.triggerKey .. '"'
    end
    if container.keywordValue then
        container.keywordValue:SetText(keywordText)
    end

    -- Looking For: four fixed role sections (Tanks/Heals/Melee/Ranged), each
    -- rendering the wanted classes for that role as a colored array. Empty
    -- role -> dimmed "-". Class needs (counts) prefix a class when known.
    if container.lookingForRoleLines and container.lookingForRoleMeta then
        -- Optional per-class counts from the tandem listing (leader side)
        local needCount = {}   -- needCount[role][class] = n  (DPS applies to both M/R rows)
        for _, row in ipairs(data.classNeeds or {}) do
            if row.class and (row.count or 0) > 0 then
                needCount[row.role] = needCount[row.role] or {}
                needCount[row.role][row.class] = (needCount[row.role][row.class] or 0) + row.count
            end
        end

        -- A "DPS" need count covers melee AND ranged; show it only on the
        -- FIRST DPS row a class appears in (meta order: MDPS before RDPS) so
        -- "2x Druid" never reads as 4 across the two rows.
        -- A class present ONLY in classNeeds (no spec codes - e.g. the peer's
        -- chat [T:] block was trimmed, or the DataBus need field survived a
        -- trim that dropped specs) still gets a row entry, on the DPS row its
        -- class actually plays from (pure-ranged classes -> Ranged).
        local needOnlyDpsRow = {
            WARRIOR = "MDPS", DEATHKNIGHT = "MDPS", ROGUE = "MDPS",
            PALADIN = "MDPS", SHAMAN = "MDPS", DRUID = "MDPS",
            MAGE = "RDPS", WARLOCK = "RDPS", HUNTER = "RDPS", PRIEST = "RDPS",
        }
        local dpsCountShown = {}
        local roleDicts = {TANK = data.tanks, HEALER = data.healers, MDPS = data.mdps, RDPS = data.rdps}

        -- Classes that already have spec codes on EITHER DPS row: their need
        -- count attaches to that real spec row - never appended as need-only
        -- (else "2x Ele Shaman" would render on the Melee row)
        local dpsSpecClasses = {}
        if data.roleSpecs and AIP.Parsers and AIP.Parsers.SpecCodeInfo then
            for _, dk in ipairs({"MDPS", "RDPS"}) do
                for _, code in ipairs(data.roleSpecs[dk] or {}) do
                    local si = AIP.Parsers.SpecCodeInfo[code]
                    if si and si.class then dpsSpecClasses[si.class] = true end
                end
            end
        end
        for _, r in ipairs(container.lookingForRoleMeta) do
            local line = container.lookingForRoleLines[r.key]
            if line then
                local head = "|cFF" .. r.hex .. r.label .. ":|r "
                local isDps = (r.key == "MDPS" or r.key == "RDPS")
                local needRole = isDps and "DPS" or r.key
                local specs = data.roleSpecs and data.roleSpecs[r.key]

                -- Group spec codes by class -> ordered class array
                local classCodes, order = {}, {}
                if specs and #specs > 0 and AIP.Parsers then
                    for _, code in ipairs(specs) do
                        local info = AIP.Parsers.SpecCodeInfo and AIP.Parsers.SpecCodeInfo[code]
                        local className = info and info.class or "UNKNOWN"
                        if not classCodes[className] then
                            classCodes[className] = {shortClass = (info and info.shortClass) or code}
                            table.insert(order, className)
                        end
                    end
                    table.sort(order)
                end

                -- Append classes that only appear in the need counts
                for className in pairs(needCount[needRole] or {}) do
                    if not classCodes[className] and not (isDps and dpsSpecClasses[className]) then
                        local wantRow = isDps and (needOnlyDpsRow[className] or "MDPS") or r.key
                        if wantRow == r.key and not (isDps and dpsCountShown[className]) then
                            local short = AIP.LFMFormat and AIP.LFMFormat.NeedCode
                                and AIP.LFMFormat.NeedCode(className, needRole)
                                or className:sub(1, 1) .. className:sub(2, 3):lower()
                            classCodes[className] = {shortClass = short}
                            table.insert(order, className)
                        end
                    end
                end

                if #order > 0 then
                    local parts = {}
                    for _, className in ipairs(order) do
                        local color = AIP.Parsers and AIP.Parsers.ClassColors and AIP.Parsers.ClassColors[className]
                        local hex = color and color.hex or "FFFFFF"
                        local n = needCount[needRole] and needCount[needRole][className]
                        if n and isDps then
                            if dpsCountShown[className] then
                                n = nil
                            else
                                dpsCountShown[className] = true
                            end
                        end
                        local prefix = n and (n .. "x ") or ""
                        table.insert(parts, prefix .. "|cFF" .. hex .. classCodes[className].shortClass .. "|r")
                    end
                    line:SetText(head .. table.concat(parts, ", "))
                else
                    -- No class detail for this role (vague/compact listing, or
                    -- an untargeted role): fall back to the truthful role
                    -- count so the row still says how many slots are open
                    local dict = roleDicts[r.key]
                    local open = dict and ((dict.needed or 0) - (dict.current or 0)) or nil
                    if open and open > 0 then
                        line:SetText(head .. "|cFFFFD100" .. open .. " more|r")
                    elseif dict and (dict.needed or 0) > 0 then
                        line:SetText(head .. "|cFF666666full|r")
                    else
                        line:SetText(head .. "|cFF666666-|r")
                    end
                end
            end
        end
    elseif container.lookingForValue then
        -- Legacy single-line fallback (pre-split UI still loaded)
        local lookingForText = "-"
        if data.lookingForSpecs and #data.lookingForSpecs > 0 then
            local coloredSpecs = {}
            for _, code in ipairs(data.lookingForSpecs) do
                local info = AIP.Parsers and AIP.Parsers.SpecCodeInfo and AIP.Parsers.SpecCodeInfo[code]
                if info then
                    local color = AIP.Parsers.ClassColors and AIP.Parsers.ClassColors[info.class]
                    local hex = color and color.hex or "FFFFFF"
                    table.insert(coloredSpecs, "|cFF" .. hex .. code .. "|r")
                else
                    table.insert(coloredSpecs, code)
                end
            end
            lookingForText = table.concat(coloredSpecs, ", ")
        end
        container.lookingForValue:SetText(lookingForText)
    end

    -- Store roleSpecs for tooltip access
    container.currentRoleSpecs = data.roleSpecs

    -- Set up tooltip for lookingForFrame
    if container.lookingForFrame then
        container.lookingForFrame:EnableMouse(true)
        container.lookingForFrame:SetScript("OnEnter", function(self)
            if not container.currentRoleSpecs then return end
            local roleSpecs = container.currentRoleSpecs

            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:AddLine("Looking For - Specs Needed", 1, 0.82, 0)
            GameTooltip:AddLine(" ")

            local roleLabels = {
                TANK = {label = "Tanks", r = 0, g = 1, b = 1},
                HEALER = {label = "Healers", r = 0, g = 1, b = 0},
                MDPS = {label = "Melee DPS", r = 1, g = 0.4, b = 0.4},
                RDPS = {label = "Ranged DPS", r = 1, g = 1, b = 0},
            }
            local roleOrder = {"TANK", "HEALER", "MDPS", "RDPS"}

            for _, role in ipairs(roleOrder) do
                local specs = roleSpecs[role]
                if specs and #specs > 0 then
                    local roleInfo = roleLabels[role]
                    GameTooltip:AddLine(roleInfo.label .. ":", roleInfo.r, roleInfo.g, roleInfo.b)

                    for _, code in ipairs(specs) do
                        local info = AIP.Parsers and AIP.Parsers.SpecCodeInfo and AIP.Parsers.SpecCodeInfo[code]
                        if info then
                            local color = AIP.Parsers.ClassColors and AIP.Parsers.ClassColors[info.class]
                            local r, g, b = color and color.r or 1, color and color.g or 1, color and color.b or 1
                            GameTooltip:AddLine("  " .. info.shortClass .. " - " .. info.spec, r, g, b)
                        else
                            GameTooltip:AddLine("  " .. code, 0.7, 0.7, 0.7)
                        end
                    end
                end
            end

            GameTooltip:Show()
        end)
        container.lookingForFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Total filled - prefer parsed [current/max] format, fall back to composition calculation
    local totalFilledText = "-"
    if data.filledCurrent and data.filledMax then
        -- Use parsed filled count from [current/max] format
        local color = data.filledCurrent >= data.filledMax and "|cFF00FF00" or "|cFFFFFF00"
        totalFilledText = color .. data.filledCurrent .. "/" .. data.filledMax .. "|r"
    elseif data.tanks or data.healers or data.mdps or data.rdps then
        -- Calculate from role composition
        local current = (data.tanks and data.tanks.current or 0) +
                       (data.healers and data.healers.current or 0) +
                       (data.mdps and data.mdps.current or 0) +
                       (data.rdps and data.rdps.current or 0)
        local needed = (data.tanks and data.tanks.needed or 0) +
                      (data.healers and data.healers.needed or 0) +
                      (data.mdps and data.mdps.needed or 0) +
                      (data.rdps and data.rdps.needed or 0)
        if needed > 0 then
            local color = current >= needed and "|cFF00FF00" or "|cFFFFFF00"
            totalFilledText = color .. current .. "/" .. needed .. "|r"
        end
    end
    if container.totalFilledValue then
        container.totalFilledValue:SetText(totalFilledText)
    end
end

-- ============================================================================
-- AUTO-BROADCAST SYSTEM (round-robin rotor)
-- One channel per tick, rotating through the enabled targets. Enabling more
-- channels spreads the sends - it NEVER multiplies them. Every send goes
-- through AIP.ChatGate, which enforces the global chat budget on top.
-- ============================================================================
GUI.Broadcast = {
    active = false,
    mode = nil,          -- "lfm" or "lfg"
    message = "",
    interval = 90,       -- per-channel repost period (seconds)
    tickSpacing = 30,    -- seconds between rotor sends (interval / #targets)
    nextSendAt = 0,      -- GetTime() of the next rotor tick
    startedAt = 0,
    rotor = {},          -- ordered targets: {kind="CHANNEL", name=..} | {kind="SAY"|"YELL"|"GUILD"}
    rotorIndex = 0,
    lastDataBus = 0,
    timer = nil,
    dryRunUntil = 0,     -- /aip broadcast dryrun: log instead of send until this time
}

-- Join/create our custom channels
function GUI.SetupCustomChannels()
    -- Join LFM channel
    local lfmIndex = GetChannelName(GUI.CustomChannels.LFM)
    if lfmIndex == 0 then
        JoinChannelByName(GUI.CustomChannels.LFM)
    end

    -- Join LFG channel
    local lfgIndex = GetChannelName(GUI.CustomChannels.LFG)
    if lfgIndex == 0 then
        JoinChannelByName(GUI.CustomChannels.LFG)
    end
end

-- Get channel ID for our custom channels
function GUI.GetCustomChannelId(channelName)
    local id = GetChannelName(channelName)
    if id and id > 0 then
        return id
    end
    return nil
end

-- Parse LFG enrollment message from other addon users
-- Current format: "LFG <RAID> - <Class> (<Spec>) <Role> - GS:<gs> iL:<ilvl> Lv:<level> {AIP:5.2}"
-- Legacy format with |: "LFG <RAID> - <Class> (<Spec>) <Role> | GS:<gs> iL:<ilvl> Lv:<level> {AIP:5.2}"
-- Old format: "LFG <RAID> - <Class> (<Spec>) <Role>, GS: <gs>, iLvl: <ilvl> {AIP:<version>}"
function GUI.ParseLfgEnrollment(message, author)
    -- Try current format first: "LFG ICC25H - War (Arms) DPS - GS:5500 iL:264 Lv:80 {AIP:5.2}"
    local raid, classDisplay, spec, role, gs, ilvl, level = message:match("LFG%s+(%S+)%s+%-%s+(%S+)%s+%(([^)]+)%)%s+(%a+)%s+%-%s*GS:(%d+)%s+iL:(%d+)%s+Lv:(%d+)")

    -- Try legacy format with |
    if not raid then
        raid, classDisplay, spec, role, gs, ilvl, level = message:match("LFG%s+(%S+)%s+%-%s+(%S+)%s+%(([^)]+)%)%s+(%a+)%s+|%s*GS:(%d+)%s+iL:(%d+)%s+Lv:(%d+)")
    end

    -- Fallback to old format if new format doesn't match
    if not raid then
        raid, classDisplay, spec, role, gs, ilvl = message:match("LFG%s+(%S+)%s+%-%s+(%a+)%s+%(([^)]+)%)%s+(%a+),%s+GS:%s*(%d+),%s+iLvl:%s*(%d+)")
    end

    if raid and classDisplay and author then
        -- Map short class names back to full class names
        local classNameMap = {
            WAR = "WARRIOR", PAL = "PALADIN", DK = "DEATHKNIGHT", DRU = "DRUID",
            PRI = "PRIEST", SHA = "SHAMAN", MAG = "MAGE", LOC = "WARLOCK",
            HUN = "HUNTER", ROG = "ROGUE",
            -- Also handle full names
            WARRIOR = "WARRIOR", PALADIN = "PALADIN", DEATHKNIGHT = "DEATHKNIGHT",
            DRUID = "DRUID", PRIEST = "PRIEST", SHAMAN = "SHAMAN", MAGE = "MAGE",
            WARLOCK = "WARLOCK", HUNTER = "HUNTER", ROGUE = "ROGUE"
        }
        local classKey = classDisplay:upper()
        local fullClass = classNameMap[classKey] or classKey

        local enrollment = {
            name = author,
            raid = raid,
            class = fullClass,
            classShort = classDisplay,
            spec = spec or "Unknown",
            role = role or "DPS",
            gs = tonumber(gs) or 0,
            ilvl = tonumber(ilvl) or 0,
            level = tonumber(level) or 0,
            weekly = message:match("WQ:(%w+)"),  -- weekly quest tag (after {AIP:x})
            time = time(),
            message = message,
            isLfgEnrollment = true,  -- Flag to distinguish from regular queue entries
        }

        -- Add/update in our enrollment tracking
        GUI.LfgEnrollments[author] = enrollment

        -- Also add to queue if not already present
        if AIP.db and AIP.db.queue then
            local found = false
            for _, entry in ipairs(AIP.db.queue) do
                if entry.name == author and entry.isLfgEnrollment then
                    -- Update existing
                    for k, v in pairs(enrollment) do entry[k] = v end
                    found = true
                    break
                end
            end
            if not found then
                table.insert(AIP.db.queue, enrollment)
            end
            if AIP.UpdateQueueUI then AIP.UpdateQueueUI() end
        end

        return enrollment
    end
    return nil
end

-- Chat event handler for custom LFG channel
local lfgChatFrame = CreateFrame("Frame")
lfgChatFrame:RegisterEvent("CHAT_MSG_CHANNEL")
lfgChatFrame:SetScript("OnEvent", function(self, event, message, author, _, _, _, _, _, channelNumber, channelName)
    if not channelName then return end

    -- Check if this is our LFG channel
    if channelName == GUI.CustomChannels.LFG then
        -- Don't process our own messages
        if author == UnitName("player") then return end

        -- Parse and track the enrollment
        GUI.ParseLfgEnrollment(message, author)
    end
end)

-- Clean up old LFG enrollments (older than 15 minutes)
function GUI.CleanupLfgEnrollments()
    local now = time()
    local expireTime = 15 * 60  -- 15 minutes

    for name, enrollment in pairs(GUI.LfgEnrollments) do
        if now - enrollment.time > expireTime then
            GUI.LfgEnrollments[name] = nil
            -- Also remove from queue
            if AIP.db and AIP.db.queue then
                for i = #AIP.db.queue, 1, -1 do
                    if AIP.db.queue[i].name == name and AIP.db.queue[i].isLfgEnrollment then
                        table.remove(AIP.db.queue, i)
                    end
                end
            end
        end
    end
end

-- Build the ordered rotor target list from settings. Channel targets carry
-- NAMES, never numeric ids - ChatGate re-resolves the id at send time (ids
-- shift when the user joins/leaves channels).
function GUI.BuildBroadcastTargets(mode)
    local targets = {}
    local function addChannel(name)
        if name and name ~= "" then
            table.insert(targets, { kind = "CHANNEL", name = name })
        end
    end

    -- Own AIP channel first (peers parse enrollments/listings from it)
    addChannel(mode == "lfm" and GUI.CustomChannels.LFM or GUI.CustomChannels.LFG)
    -- Standard LookingForGroup channel (fuzzy-resolved by the gate)
    addChannel("LookingForGroup")

    if AIP.db then
        if AIP.db.spamTrade then addChannel("Trade") end
        if AIP.db.spamGeneral then addChannel("General") end
        if AIP.db.spamGlobal then addChannel("global") end
        if AIP.db.spamWorld then addChannel("world") end
        if AIP.db.spamDefense then addChannel("LocalDefense") end
        if AIP.db.spamSay then table.insert(targets, { kind = "SAY" }) end
        if AIP.db.spamYell then table.insert(targets, { kind = "YELL" }) end
        if AIP.db.spamGuild and IsInGuild() then table.insert(targets, { kind = "GUILD" }) end
    end
    return targets
end

-- Start auto-broadcasting
function GUI.StartBroadcast(mode, message, interval)
    -- Ensure custom channels exist (async join - first send is delayed below)
    GUI.SetupCustomChannels()

    local B = GUI.Broadcast
    B.active = true
    B.mode = mode
    B.message = message
    B.interval = math.max(60, interval or (AIP.db and AIP.db.autoSpamInterval) or 90)
    B.rotor = GUI.BuildBroadcastTargets(mode)
    B.rotorIndex = 0
    B.startedAt = GetTime()
    B.lastDataBus = 0
    -- Spread evenly: each channel reposts roughly every `interval`, so the
    -- rotor ticks every interval/#targets (floor 15s). ChatGate enforces the
    -- per-channel and global budgets on top - this is only the cadence.
    B.tickSpacing = math.max(15, math.floor(B.interval / math.max(1, #B.rotor)))
    -- First send ~2s out: JoinChannelByName is async and the custom channel
    -- id isn't resolvable for a few frames after joining (the very first
    -- LFM used to be silently lost to this).
    B.nextSendAt = GetTime() + 2

    if not B.timer then
        B.timer = CreateFrame("Frame")
    end
    B.statusElapsed = 0
    B.timer:SetScript("OnUpdate", function(self, elapsed)
        B.statusElapsed = (B.statusElapsed or 0) + elapsed
        if B.statusElapsed >= 1 then
            B.statusElapsed = 0
            GUI.UpdateBroadcastStatus()
            GUI.CheckBroadcastAutoStop()
        end
        if B.active and GetTime() >= B.nextSendAt then
            GUI.BroadcastTick()
        end
    end)

    GUI.UpdateBroadcastStatus()
    local chanCount = #B.rotor
    AIP.Print(string.format(
        "|cFF00FF00Broadcasting started|r - %s: one channel every %ds, each channel every ~%ds (%d target%s)",
        mode == "lfm" and "LFM" or "LFG",
        B.tickSpacing,
        math.max(B.interval, B.tickSpacing * math.max(1, chanCount)),
        chanCount, chanCount == 1 and "" or "s"))
end

-- Auto-stop conditions, checked once per second while broadcasting
function GUI.CheckBroadcastAutoStop()
    local B = GUI.Broadcast
    if not B.active then return end

    -- Hard time cap (a forgotten broadcast must not advertise forever)
    local maxMinutes = (AIP.db and AIP.db.broadcastMaxMinutes) or 60
    if maxMinutes > 0 and (GetTime() - B.startedAt) > maxMinutes * 60 then
        AIP.Print("|cFFFFFF00Broadcast auto-stopped|r after " .. maxMinutes .. " minutes (set in broadcastMaxMinutes).")
        GUI.StopBroadcast()
        return
    end

    -- LFM: stop when the group is full
    if B.mode == "lfm" and GUI.MyGroup then
        local g = GUI.MyGroup
        local function need(r) return (g[r] and g[r].needed) or 0 end
        local function cur(r) return (g[r] and g[r].current) or 0 end
        local total = need("tanks") + need("healers") + need("mdps") + need("rdps")
        local filled = cur("tanks") + cur("healers") + cur("mdps") + cur("rdps")
        if total > 0 and filled >= total then
            AIP.Print("|cFF00FF00Group is full! Stopping LFM broadcast.|r")
            GUI.StopBroadcast()
        end
    end
end

-- One rotor tick: post to exactly ONE eligible target, then advance.
function GUI.BroadcastTick()
    local B = GUI.Broadcast
    if not B.active or not B.message or B.message == "" then return end

    local CG = AIP.ChatGate
    local dryRun = B.dryRunUntil and B.dryRunUntil > 0 and GetTime() < B.dryRunUntil

    if #B.rotor == 0 then
        B.rotor = GUI.BuildBroadcastTargets(B.mode)
        if #B.rotor == 0 then
            B.nextSendAt = GetTime() + 10  -- idle; targets may appear later
            return
        end
    end

    -- Find the next target the gate will accept (at most one full pass;
    -- if everything is cooling down or blacked out, idle - never busy-spin)
    local picked, pickedIdx
    for offset = 1, #B.rotor do
        local idx = ((B.rotorIndex + offset - 1) % #B.rotor) + 1
        local t = B.rotor[idx]
        local eligible
        if not CG then
            eligible = false
        elseif t.kind == "CHANNEL" then
            eligible = CG.IsEligible("CHANNEL", t.name)
        else
            eligible = CG.IsEligible(t.kind)
        end
        if eligible then
            picked, pickedIdx = t, idx
            break
        end
    end

    if not picked then
        B.nextSendAt = GetTime() + 5
        return
    end

    B.rotorIndex = pickedIdx
    B.nextSendAt = GetTime() + B.tickSpacing

    local label = picked.kind == "CHANNEL" and picked.name or picked.kind
    if dryRun then
        AIP.Print("|cFF888888[dryrun]|r would send to |cFFFFFF00" .. label .. "|r now")
    else
        CG.Send(B.message, picked.kind == "CHANNEL" and "CHANNEL" or picked.kind, nil, {
            channelName = picked.name,
            owner = "broadcast",
            staleAfter = 30,
            validate = function() return GUI.Broadcast.active end,
        })
    end

    -- Companion DataBus broadcast once per repost period (own limiter,
    -- deliberately NOT gated - a public blackout must not freeze peer sync)
    GUI.MaybeDataBusBroadcast(dryRun)
end

-- DataBus LFM/LFG companion broadcast, at most once per repost period
function GUI.MaybeDataBusBroadcast(dryRun)
    local B = GUI.Broadcast
    local now = GetTime()
    if (now - (B.lastDataBus or 0)) < B.interval then return end
    B.lastDataBus = now
    if dryRun or not AIP.DataBus then return end

    if B.mode == "lfm" and GUI.MyGroup then
        -- Compact payload (LFMFormat wire codec): the old shape - four role
        -- dicts + a nested roleSpecs table - serialized past the 255-byte
        -- addon-message cap for any detailed listing, so peers received
        -- NOTHING. comp/specs/need strings carry the same data small; the
        -- legacy dicts ride along for old receivers and are the first thing
        -- BroadcastLFM sheds if the message is still too long. Empty
        -- optionals are omitted entirely (every serialized field costs cap).
        local MyG = GUI.MyGroup
        local LF = AIP.LFMFormat
        local detailed = (MyG.detailMode == "detailed")
        local specsStr = detailed and LF and LF.EncodeRoleSpecs(MyG.roleSpecs) or ""
        local needStr = detailed and LF and LF.EncodeNeeds(MyG.classNeeds) or ""
        local dmCode
        if MyG.detailMode == "detailed" then dmCode = "D"
        elseif MyG.detailMode == "minimal" then dmCode = "M"
        elseif MyG.detailMode then dmCode = "C"
        end
        AIP.DataBus.BroadcastLFM({
            raid = MyG.raid,
            comp = LF and LF.EncodeComp(MyG) or nil,
            tanks = MyG.tanks,
            healers = MyG.healers,
            mdps = MyG.mdps,
            rdps = MyG.rdps,
            gsMin = (MyG.gsMin and MyG.gsMin > 0) and MyG.gsMin or nil,
            ilvlMin = (MyG.ilvlMin and MyG.ilvlMin > 0) and MyG.ilvlMin or nil,
            triggerKey = MyG.inviteKeyword,
            specs = specsStr ~= "" and specsStr or nil,
            need = needStr ~= "" and needStr or nil,
            dm = dmCode,
            note = (MyG.note and MyG.note ~= "") and MyG.note or nil,
            weekly = (MyG.weekly and MyG.weekly ~= "") and MyG.weekly or nil,
        })
    elseif B.mode == "lfg" and GUI.MyEnrollment then
        AIP.DataBus.BroadcastLFG({
            raids = { GUI.MyEnrollment.raid },
            role = GUI.MyEnrollment.role,
            class = GUI.MyEnrollment.class,
            spec = GUI.MyEnrollment.spec,
            gs = GUI.MyEnrollment.gs,
            ilvl = GUI.MyEnrollment.ilvl,
            weekly = GUI.MyEnrollment.weekly,
        })
        -- Share the full character card so peers see gear/achievements with
        -- zero inspection (gated by the Share card toggle).
        if (not AIP.db or AIP.db.cardShare ~= false) and AIP.CharCard and AIP.CharCard.ShareMine then
            AIP.CharCard.ShareMine()
        end
    end
end

-- Stop auto-broadcasting. Single definition (this used to be two - a base
-- and a wrapper adding LFG cleanup - which was load-order fragile).
function GUI.StopBroadcast()
    local wasLfg = GUI.Broadcast.mode == "lfg"

    GUI.Broadcast.active = false
    GUI.Broadcast.mode = nil
    GUI.MyGroup = nil        -- Clear our active LFM data
    GUI.MyEnrollment = nil   -- Clear our active LFG enrollment

    if GUI.Broadcast.timer then
        GUI.Broadcast.timer:SetScript("OnUpdate", nil)
    end

    -- Cancel anything we already queued at the gate: a stale LFM must never
    -- fire after the user stopped (or joined a group).
    if AIP.ChatGate then
        AIP.ChatGate.CancelOwner("broadcast")
    end

    -- Reset player mode
    if AIP.SetPlayerMode then
        AIP.SetPlayerMode("none")
    end

    -- LFG enrollment cleanup
    if wasLfg then
        local playerName = UnitName("player")
        if playerName and GUI.LfgEnrollments then
            GUI.LfgEnrollments[playerName] = nil
        end
        GUI.UpdateEnrollmentStatus()
        local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
        if container then GUI.UpdateQueuePanel(container) end
    end

    GUI.UpdateBroadcastStatus()
    GUI.UpdateStatus()  -- Update footer to reflect mode change
    AIP.Print("|cFFFF0000Broadcasting stopped|r")
end

-- Update broadcast status display
function GUI.UpdateBroadcastStatus()
    -- Update the LFM browser tab controls if available
    local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
    if container then
        if container.stopBroadcastBtn then
            if GUI.Broadcast.active then
                container.stopBroadcastBtn:Show()
            else
                container.stopBroadcastBtn:Hide()
            end
        end
    end

    -- Update the main status bar (footer) with broadcast countdown
    if GUI.Frame and GUI.Frame.statusBar then
        local statusText = GUI.Frame.statusBar.broadcastStatus
        if statusText then
            if GUI.Broadcast.active then
                local remaining = math.max(0, (GUI.Broadcast.nextSendAt or 0) - GetTime())
                local modeStr = GUI.Broadcast.mode == "lfm" and "Group (LFM)" or "Enroll (LFG)"
                local raidInfo = ""
                -- Show what raid we're broadcasting for
                if GUI.Broadcast.mode == "lfg" and GUI.MyEnrollment then
                    raidInfo = " " .. (GUI.MyEnrollment.raid or "")
                elseif GUI.Broadcast.mode == "lfm" and GUI.MyGroup then
                    raidInfo = " " .. (GUI.MyGroup.raid or "")
                end
                local color = remaining < 5 and "|cFFFFFF00" or "|cFF00FF00"
                statusText:SetText(color .. "Broadcasting " .. modeStr .. raidInfo .. ":|r " .. math.floor(remaining) .. "s")
            else
                statusText:SetText("")
            end
        end

        -- Update chat ban status
        local chatBanStatus = GUI.Frame.statusBar.chatBanStatus
        if chatBanStatus then
            local statusMsg = ""

            -- Check if chat ban detected
            if AIP.ChatBan and AIP.ChatBan.detected then
                local now = time()
                local timeSinceBan = now - (AIP.ChatBan.lastBanTime or 0)
                if timeSinceBan < 300 then  -- Show for 5 minutes after ban
                    local remaining = 300 - timeSinceBan
                    local delayInfo = ""
                    if AIP.ChatBan.channelDelay and AIP.ChatBan.channelDelay > 2 then
                        delayInfo = " | Delay: " .. AIP.ChatBan.channelDelay .. "s"
                    end
                    statusMsg = "|cFFFF6666\226\154\160 THROTTLED|r (" .. math.floor(remaining) .. "s)" .. delayInfo
                end
            end

            -- If broadcasting and no ban, show channel delay info
            if statusMsg == "" and GUI.Broadcast.active then
                local delayIncrement = 2
                if AIP.ChatBan then
                    delayIncrement = AIP.ChatBan.channelDelay or 2
                end
                if delayIncrement > 2 then
                    statusMsg = "|cFFFFFF00Channel delay: " .. delayIncrement .. "s|r"
                end
            end

            chatBanStatus:SetText(statusMsg)
        end
    end
end

-- Update enrollment status display
function GUI.UpdateEnrollmentStatus()
    local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
    if not container then return end

    if container.queueStatus then
        local queue = AIP.db and AIP.db.queue or {}
        local waitlistCount = AIP.GetWaitlistCount and AIP.GetWaitlistCount() or 0

        local statusText = "Queue: " .. #queue .. " | Waitlist: " .. waitlistCount
        if GUI.MyEnrollment then
            statusText = statusText .. " | |cFF00FF00LFG: " .. GUI.MyEnrollment.raid .. "|r"
        end

        -- Needs strip: what my active listing still lacks + how many scanned
        -- LFG players would fit (the fit-sorted LFG sub-tab lists them)
        if GUI.MyGroup then
            local g = GUI.MyGroup
            statusText = statusText .. " | |cFF00FF00LFM: " .. (g.raid or "?") .. "|r"
            local needs = {}
            local function needOf(key, tag)
                local slot = g[key]
                if type(slot) == "table" then
                    local n = (slot.needed or 0) - (slot.current or 0)
                    if n > 0 then needs[#needs + 1] = n .. tag end
                end
            end
            needOf("tanks", "T"); needOf("healers", "H"); needOf("mdps", "M"); needOf("rdps", "R")
            if #needs > 0 then
                statusText = statusText .. " | |cFFFFD100Need: " .. table.concat(needs, " ") .. "|r"
                -- Tandem class needs (first few, colored) - the leader's
                -- at-a-glance view of WHICH classes to recruit next
                if g.classNeeds and #g.classNeeds > 0 then
                    local classParts, shown = {}, 0
                    for _, row in ipairs(g.classNeeds) do
                        if shown >= 3 then
                            classParts[#classParts + 1] = "|cFF888888+" .. (#g.classNeeds - shown) .. "|r"
                            break
                        end
                        local cls = (AIP.Composition and AIP.Composition.ColoredClassName)
                            and AIP.Composition.ColoredClassName(row.class) or row.class
                        classParts[#classParts + 1] = row.count .. "x" .. cls
                        shown = shown + 1
                    end
                    statusText = statusText .. " " .. table.concat(classParts, " ")
                end
                if AIP.FitEngine and AIP.ChatScanner and AIP.ChatScanner.Players then
                    local matching = 0
                    for _, player in pairs(AIP.ChatScanner.Players) do
                        if player.isLFG then
                            local fit = AIP.FitEngine.ScoreApplicant(player, g)
                            if fit.verdict ~= "RED" then matching = matching + 1 end
                        end
                    end
                    if matching > 0 then
                        statusText = statusText .. " |cFF00FF00(" .. matching .. " matching LFG)|r"
                    end
                end
            else
                statusText = statusText .. " | |cFF00FF00Group full!|r"
            end
        end
        container.queueStatus:SetText(statusText)
    end
end

-- ============================================================================
-- COMPOSITION DEPLETION SYSTEM
-- Updates the broadcast message when group composition changes
-- ============================================================================

-- Get the player's own LFM group listing
function GUI.GetOwnGroup()
    local playerName = UnitName("player")
    if not playerName then return nil end

    -- Check ChatScanner first
    if AIP.ChatScanner and AIP.ChatScanner.Groups then
        local group = AIP.ChatScanner.Groups[playerName]
        if group and group.isOwn then
            return group
        end
    end

    -- Fallback to GroupTracker
    if AIP.GroupTracker and AIP.GroupTracker.Groups then
        local group = AIP.GroupTracker.Groups[playerName]
        if group and group.isOwn then
            return group
        end
    end

    return nil
end

-- Get current raid composition from actual group members
-- Returns: tanks, healers, mdps, rdps
function GUI.GetCurrentGroupComposition()
    local tanks, healers, mdps, rdps = 0, 0, 0, 0
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    local function CountRole(name, unit)
        local roleGuess = GUI.GuessPlayerRole(name, unit)
        if roleGuess == "TANK" then
            tanks = tanks + 1
        elseif roleGuess == "HEALER" then
            healers = healers + 1
        elseif roleGuess == "MDPS" then
            mdps = mdps + 1
        else  -- RDPS or DPS (default to ranged)
            rdps = rdps + 1
        end
    end

    if numRaid > 0 then
        -- In a raid
        for i = 1, numRaid do
            local name, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
            if name then
                if role == "MAINTANK" or role == "maintank" then
                    tanks = tanks + 1
                else
                    CountRole(name, "raid" .. i)
                end
            end
        end
    elseif numParty > 0 then
        -- In a party (include self)
        for i = 1, numParty do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then
                CountRole(name, unit)
            end
        end
        -- Add self
        CountRole(UnitName("player"), "player")
    else
        -- Solo - add self
        CountRole(UnitName("player"), "player")
    end

    return tanks, healers, mdps, rdps
end

-- Melee DPS specs by class (for role detection)
GUI.MeleeDPSSpecs = {
    WARRIOR = {["Arms"] = true, ["Fury"] = true},
    PALADIN = {["Retribution"] = true},
    DEATHKNIGHT = {["Frost"] = true, ["Unholy"] = true},  -- DK DPS specs
    ROGUE = {["Assassination"] = true, ["Combat"] = true, ["Subtlety"] = true},
    SHAMAN = {["Enhancement"] = true},
    DRUID = {["Feral Combat"] = true, ["Feral"] = true},
}

-- Guess a player's role based on class/spec or queue data
-- Returns: TANK, HEALER, MDPS, or RDPS
function GUI.GuessPlayerRole(name, unit)
    if not name then return "RDPS" end

    -- Check queue for role info
    if AIP.db and AIP.db.queue then
        for _, entry in ipairs(AIP.db.queue) do
            if entry.name == name and entry.role then
                -- Convert old "DPS" role to MDPS/RDPS based on class
                if entry.role == "DPS" then
                    local class = entry.class
                    if class and GUI.MeleeDPSSpecs[class:upper()] then
                        return "MDPS"
                    end
                    return "RDPS"
                end
                return entry.role
            end
        end
    end

    -- Check inspection cache for role and spec
    if AIP.InspectionEngine and AIP.InspectionEngine.GetCachedData then
        local cached = AIP.InspectionEngine.GetCachedData(name)
        if cached then
            -- Local inspects expose role only under performanceEstimate;
            -- Addon-sourced data may carry a top-level role/spec.
            local role = cached.role
            if not role and cached.performanceEstimate then
                role = cached.performanceEstimate.role
            end
            local upper = role and role:upper() or nil
            if upper == "TANK" or upper == "HEALER" then
                return upper
            end
            if upper == "DPS" or upper == "MDPS" or upper == "RDPS" then
                local class = cached.class
                local spec = cached.spec
                if class and spec and GUI.MeleeDPSSpecs[class:upper()] then
                    if GUI.MeleeDPSSpecs[class:upper()][spec] then
                        return "MDPS"
                    end
                end
                return upper == "MDPS" and "MDPS" or "RDPS"
            end
        end
    end

    -- Try to guess from unit class
    if unit then
        local _, class = UnitClass(unit)
        if class then
            -- Pure melee classes default to MDPS
            if class == "ROGUE" then return "MDPS" end
            if class == "WARRIOR" then return "MDPS" end  -- Assume Arms/Fury, not tank without more info
        end
    end

    -- Default to ranged DPS
    return "RDPS"
end

-- Regenerate broadcast message with updated composition.
-- Uses the single-source LFMFormat builder so the regenerated message keeps
-- the SAME layout as the original ([x/y] block, spec array from roleSpecs,
-- reserved items, weekly token). The old inline builder here diverged: it
-- read `lookingForClasses` (a field nothing writes) and dropped the [x/y]
-- and [Res:] blocks the first time anyone joined the group.
function GUI.RegenerateBroadcastMessage()
    local ownGroup = GUI.GetOwnGroup()
    if not ownGroup then return nil end
    if not AIP.LFMFormat then return nil end

    -- Get current composition (tanks, healers, mdps, rdps)
    local currentTanks, currentHealers, currentMdps, currentRdps = GUI.GetCurrentGroupComposition()

    -- Update the scanner record's current counts
    if ownGroup.tanks then ownGroup.tanks.current = currentTanks end
    if ownGroup.healers then ownGroup.healers.current = currentHealers end
    if ownGroup.mdps then ownGroup.mdps.current = currentMdps end
    if ownGroup.rdps then ownGroup.rdps.current = currentRdps end

    -- Also sync GUI.MyGroup: it's a SEPARATE table that CS.MatchesMyLFM reads
    -- for auto-queue role-full checks (its .current counts were previously
    -- frozen at 0 forever, so already-full roles kept accepting).
    if GUI.MyGroup then
        if GUI.MyGroup.tanks then GUI.MyGroup.tanks.current = currentTanks end
        if GUI.MyGroup.healers then GUI.MyGroup.healers.current = currentHealers end
        if GUI.MyGroup.mdps then GUI.MyGroup.mdps.current = currentMdps end
        if GUI.MyGroup.rdps then GUI.MyGroup.rdps.current = currentRdps end
    end

    local achieveLink = ""
    if ownGroup.achievementId then
        achieveLink = GetAchievementLink(ownGroup.achievementId) or ""
    end

    -- Tandem: shrink the [Need:] counts as recruits join. The POSTED counts
    -- (classNeedsBase, from the popup's per-spec count boxes) are the truth -
    -- each newly-joined player of a needed class decrements that class's
    -- count (class-level approximation: spec of a joiner isn't inspectable).
    -- Falls back to the template recommendation engine for listings posted
    -- before the count boxes existed.
    local Comp = AIP.Composition
    local mode = ownGroup.detailMode or (GUI.MyGroup and GUI.MyGroup.detailMode)
    local notDetailed = (mode ~= "detailed")
    local base = GUI.MyGroup and GUI.MyGroup.classNeedsBase
    local snap = GUI.MyGroup and GUI.MyGroup.classCountsAtPost
    if notDetailed then
        -- Minimal/Compact listing: never inject class-level detail on
        -- regeneration (belt-and-braces: also clear any stale detailed
        -- fields on the record).
        ownGroup.classNeeds = nil
        ownGroup.roleSpecs = nil
        ownGroup.selectedClasses = nil
        if GUI.MyGroup then
            GUI.MyGroup.classNeeds = nil
            GUI.MyGroup.roleSpecs = nil
            GUI.MyGroup.selectedClasses = nil
        end
    elseif base and snap and Comp and Comp.ScanRaid then
        local raid = Comp.ScanRaid()
        local joined = {}
        for class, n in pairs((raid and raid.classCounts) or {}) do
            joined[class] = math.max(0, n - (snap[class] or 0))
        end
        local remaining = {}
        for _, row in ipairs(base) do
            local take = math.min(row.count or 0, joined[row.class] or 0)
            joined[row.class] = (joined[row.class] or 0) - take
            local left = (row.count or 0) - take
            if left > 0 then
                table.insert(remaining, {class = row.class, role = row.role, count = left})
            end
        end
        ownGroup.classNeeds = remaining
        if GUI.MyGroup then GUI.MyGroup.classNeeds = remaining end

        -- Detailed listings: the aggregate [x/y] role totals are derived
        -- from the SAME live-decremented list, not the frozen posted value,
        -- so the header count and the [Need:] breakdown can never disagree
        -- (and both shrink together as recruits join). `needed` here means
        -- "total target for the role", same as everywhere else in this
        -- function - it must be current + remaining, NOT remaining alone,
        -- or it double-counts joiners against `current` and can even go
        -- negative as the group fills (e.g. 1 filled would read [1/2]
        -- instead of the correct [1/3] for a 3-tank target with 2 left).
        local liveRemaining = {TANK = 0, HEALER = 0, DPS = 0}
        for _, row in ipairs(remaining) do
            liveRemaining[row.role] = (liveRemaining[row.role] or 0) + (row.count or 0)
        end
        local newTanksNeeded = currentTanks + liveRemaining.TANK
        local newHealersNeeded = currentHealers + liveRemaining.HEALER
        -- classNeeds folds MDPS/RDPS into "DPS" (see CollectRoleSpecs) - split
        -- the live DPS remainder back across mdps/rdps proportionally to the
        -- POSTED split (MyGroup.dpsSplitBase, stamped once at Post time and
        -- never mutated). Reading ownGroup.mdps/rdps.needed here instead
        -- would read back THIS function's own previous output, ratcheting
        -- the ratio toward whichever role happened to empty out first.
        local splitBase = GUI.MyGroup and GUI.MyGroup.dpsSplitBase
        local postedMdps = (splitBase and splitBase.mdps)
            or (ownGroup.mdps and ownGroup.mdps.needed) or 0
        local postedRdps = (splitBase and splitBase.rdps)
            or (ownGroup.rdps and ownGroup.rdps.needed) or 0
        local dpsSplitTotal = postedMdps + postedRdps
        local newMdpsNeeded, newRdpsNeeded = currentMdps, currentRdps
        if dpsSplitTotal > 0 then
            local mdpsRemainingShare = math.floor(liveRemaining.DPS * postedMdps / dpsSplitTotal + 0.5)
            newMdpsNeeded = currentMdps + mdpsRemainingShare
            newRdpsNeeded = currentRdps + (liveRemaining.DPS - mdpsRemainingShare)
        end
        if ownGroup.tanks then ownGroup.tanks.needed = newTanksNeeded end
        if ownGroup.healers then ownGroup.healers.needed = newHealersNeeded end
        if ownGroup.mdps then ownGroup.mdps.needed = newMdpsNeeded end
        if ownGroup.rdps then ownGroup.rdps.needed = newRdpsNeeded end
        -- Mirror into GUI.MyGroup too - it's a separate table (see the
        -- .current sync above) and DataBus broadcasts read straight from
        -- it, so leaving it stale would make the chat message and the
        -- DataBus payload disagree on the same listing.
        if GUI.MyGroup then
            if GUI.MyGroup.tanks then GUI.MyGroup.tanks.needed = newTanksNeeded end
            if GUI.MyGroup.healers then GUI.MyGroup.healers.needed = newHealersNeeded end
            if GUI.MyGroup.mdps then GUI.MyGroup.mdps.needed = newMdpsNeeded end
            if GUI.MyGroup.rdps then GUI.MyGroup.rdps.needed = newRdpsNeeded end
        end
    else
        -- Legacy/no-baseline fallback (posted before classNeedsBase existed,
        -- or a Detailed listing whose count boxes were all left at 0 so
        -- BuildConfig never set classNeeds): recomputes [Need:] fresh from
        -- the template's recommendation engine each call. Deliberately does
        -- NOT touch tanks/healers/mdps/rdps.needed - there is no posted
        -- baseline to derive current+remaining from here, so the frozen
        -- posted totals from BuildLFM's original values are left as-is
        -- rather than guessed at.
        local templateKey = ownGroup.templateKey or (GUI.MyGroup and GUI.MyGroup.templateKey)
        if Comp and Comp.GetClassNeeds and templateKey then
            local needs = Comp.GetClassNeeds(templateKey)
            if needs.ok then
                local list = GUI.FilterClassNeedsBySelection(needs.list, ownGroup.selectedClasses
                    or (GUI.MyGroup and GUI.MyGroup.selectedClasses))
                ownGroup.classNeeds = list
                if GUI.MyGroup then GUI.MyGroup.classNeeds = list end
            end
        end
    end

    -- Get needed counts AFTER the block above, which mutates
    -- ownGroup.tanks/healers/mdps/rdps.needed in place for Detailed listings.
    local neededTanks = ownGroup.tanks and ownGroup.tanks.needed or 2
    local neededHealers = ownGroup.healers and ownGroup.healers.needed or 6
    local neededMdps = ownGroup.mdps and ownGroup.mdps.needed or 8
    local neededRdps = ownGroup.rdps and ownGroup.rdps.needed or 9

    local msg = AIP.LFMFormat.BuildLFM({
        raidKey = ownGroup.raid or "?",
        weekly = ownGroup.weekly,
        tanks = { current = currentTanks, needed = neededTanks },
        healers = { current = currentHealers, needed = neededHealers },
        mdps = { current = currentMdps, needed = neededMdps },
        rdps = { current = currentRdps, needed = neededRdps },
        gsMin = ownGroup.gsMin,
        ilvlMin = ownGroup.ilvlMin,
        roleSpecs = ownGroup.roleSpecs,
        classNeeds = ownGroup.classNeeds,
        keyword = ownGroup.inviteKeyword or (AIP.db and AIP.db.triggers) or "inv",
        achievementLink = achieveLink,
        note = ownGroup.note,
        reservedItems = AIP.db and AIP.db.reservedItems,
    })

    return msg
end

-- Filter class-need rows to the classes actually selected in Looking-For
-- (selectedClasses = {TANK={{class,spec}..}, HEALER=.., MDPS=.., RDPS=..}),
-- so the [Need:] block, MyGroup.classNeeds and the FitEngine verdicts never
-- contradict the leader's manual spec selection. nil selection = no filter.
function GUI.FilterClassNeedsBySelection(list, selectedClasses)
    if not list then return nil end
    if not selectedClasses then return list end
    local checked = {TANK = {}, HEALER = {}, DPS = {}}
    local any = false
    for role, entries in pairs(selectedClasses) do
        local target = (role == "MDPS" or role == "RDPS") and "DPS" or role
        if checked[target] then
            for _, e in ipairs(entries) do
                if e.class then
                    checked[target][e.class:upper()] = true
                    any = true
                end
            end
        end
    end
    if not any then return list end  -- empty selection data: keep the needs
    local out = {}
    for _, row in ipairs(list) do
        local set = checked[row.role]
        if set and set[row.class] then
            table.insert(out, row)
        end
    end
    return out
end

-- Reverse of Comp.TemplateKeyForRaid: find the popup (raidType, size, heroic)
-- combo whose raid key resolves to the given template. Brute-forces the small
-- RaidSizeInfo space using the same key-building rules as GetRaidKey.
function GUI.RaidKeyForTemplate(templateKey)
    local Comp = AIP.Composition
    if not (templateKey and Comp and Comp.TemplateKeyForRaid) then return nil end
    for raidType, info in pairs(GUI.RaidSizeInfo or {}) do
        if raidType ~= "CUSTOM" then
            for _, size in ipairs(info.sizes or {}) do
                -- Normal first: templates without a distinct heroic entry
                -- (Ulduar, 5-mans) must reverse-map as NON-heroic
                local variants = info.hasHeroic and {false, true} or {false}
                for _, heroic in ipairs(variants) do
                    local key
                    if raidType == "TOC" and heroic then
                        key = "TOGC" .. size
                    else
                        key = raidType .. size .. (heroic and "H" or "N")
                    end
                    if Comp.TemplateKeyForRaid(key) == templateKey then
                        return raidType, size, heroic
                    end
                end
            end
        end
    end
    return nil
end

-- Composition tab/window -> LFM popup binding: selecting a template re-points
-- the popup's raid selection (only when the popup already exists). Custom
-- templates map to the CUSTOM raid type carrying the template's name.
function GUI.SyncPopupToTemplate(templateKey)
    local popup = GUI.AddGroupPopup
    if not popup then return end
    local Comp = AIP.Composition
    local t = Comp and Comp.RaidTemplates and Comp.RaidTemplates[templateKey]
    if not t then return end
    if popup.classNeedsMeta and popup.classNeedsMeta.templateKey == templateKey then
        return  -- already bound to this template
    end
    if t.custom then
        popup.raidType = "CUSTOM"
        popup.weeklyToken = nil
        if popup.customInput then popup.customInput:SetText(t.name or templateKey) end
    else
        local raidType, size, heroic = GUI.RaidKeyForTemplate(templateKey)
        if not raidType then return end  -- no popup equivalent (e.g. WEEKLY_RAID)
        popup.raidType = raidType
        popup.raidSize = size
        popup.weeklyToken = nil
        if popup.heroicCheck then popup.heroicCheck:SetChecked(heroic and true or false) end
        if popup.UpdateSizeDropdown then popup.UpdateSizeDropdown() end
        local sizeDD = _G["AIPAddGroupSize"]
        if sizeDD then UIDropDownMenu_SetText(sizeDD, size) end
    end
    if popup.UpdateRaidDropdownText then popup.UpdateRaidDropdownText() end
    if popup.ApplyTemplateDefaults then popup.ApplyTemplateDefaults() end
end

-- Update broadcast message after composition change
function GUI.UpdateBroadcastComposition()
    if not GUI.Broadcast.active or GUI.Broadcast.mode ~= "lfm" then
        return
    end

    local newMsg = GUI.RegenerateBroadcastMessage()
    if newMsg then
        GUI.Broadcast.message = newMsg
        AIP.db.spamMessage = newMsg

        -- Update own group's stored message
        local ownGroup = GUI.GetOwnGroup()
        if ownGroup then
            ownGroup.message = newMsg
        end

        -- Refresh the tree to show updated composition
        GUI.RefreshBrowserTab("lfm")
    end
end

-- Track previous group size to detect changes
GUI.PreviousGroupSize = 0

-- Check if player joined a group (to stop LFG broadcast) or if group composition changed (to update LFM)
local broadcastEventFrame = CreateFrame("Frame")
broadcastEventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
broadcastEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
broadcastEventFrame:SetScript("OnEvent", function(self, event)
    local numParty = GetNumPartyMembers() or 0
    local numRaid = GetNumRaidMembers() or 0
    local currentSize = numRaid > 0 and numRaid or numParty

    -- If broadcasting LFG and we joined a group, stop
    if GUI.Broadcast.active and GUI.Broadcast.mode == "lfg" then
        if numParty > 0 or numRaid > 0 then
            AIP.Print("|cFF00FF00You joined a group! Stopping LFG broadcast.|r")
            -- Remove our enrollment from LfgEnrollments
            local playerName = UnitName("player")
            if playerName and GUI.LfgEnrollments then
                GUI.LfgEnrollments[playerName] = nil
            end
            GUI.MyEnrollment = nil
            GUI.StopBroadcast()
            GUI.UpdateEnrollmentStatus()
            -- Update queue panel
            local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
            if container then GUI.UpdateQueuePanel(container) end
        end
    end

    -- If broadcasting LFM and group size changed, update composition in message
    if GUI.Broadcast.active and GUI.Broadcast.mode == "lfm" then
        if currentSize ~= GUI.PreviousGroupSize then
            -- Small delay to let group info update
            AIP.Utils.DelayedCall(0.5, function()
                GUI.UpdateBroadcastComposition()
            end)
        end
    end

    GUI.PreviousGroupSize = currentSize
end)

-- Show Add Group popup
function GUI.ShowAddGroupPopup()
    if not GUI.AddGroupPopup then
        GUI.CreateAddGroupPopup()
    end
    -- Update size dropdown for current raid selection
    if GUI.AddGroupPopup.UpdateSizeDropdown then
        GUI.AddGroupPopup.UpdateSizeDropdown()
    end
    -- Update raid dropdown text with lockout color
    if GUI.AddGroupPopup.UpdateRaidDropdownText then
        GUI.AddGroupPopup.UpdateRaidDropdownText()
    end
    -- Update reserved items display from DB (read-only)
    if GUI.AddGroupPopup.reservedDisplay then
        local reservedItems = AIP.db and AIP.db.reservedItems or ""
        if reservedItems and reservedItems ~= "" then
            -- Replace newlines with commas for display
            local displayText = reservedItems:gsub("\n", ", "):gsub(", $", "")
            GUI.AddGroupPopup.reservedDisplay:SetText(displayText)
        else
            GUI.AddGroupPopup.reservedDisplay:SetText("|cFF666666(none - edit in Raid Mgmt tab)|r")
        end
    end
    -- Refresh the Quick Post tiles (last-used / this week's weekly), the
    -- weekly status strip and the live message preview
    if GUI.AddGroupPopup.RefreshTiles and not GUI.AddGroupPopup.expanded then
        GUI.AddGroupPopup.RefreshTiles()
    end
    if GUI.AddGroupPopup.UpdateWeeklyStrip then
        GUI.AddGroupPopup.UpdateWeeklyStrip()
    end
    -- Recompute class needs against the CURRENT group (no auto-select): the
    -- roster may have changed since the popup was last open, and stale needs
    -- would otherwise be posted and broadcast
    if GUI.AddGroupPopup.UpdateClassNeeds then
        GUI.AddGroupPopup.UpdateClassNeeds(false)
    end
    if GUI.AddGroupPopup.RefreshPreview then
        GUI.AddGroupPopup.RefreshPreview()
    end
    GUI.AddGroupPopup:Show()
end

-- Raid achievements for WotLK content
GUI.RaidAchievements = {
    ICC25H = {
        {id = 4584, name = "The Frozen Throne (25H)"},
        {id = 4621, name = "Been Waiting a Long Time (25H)"},
        {id = 4620, name = "Portal Jockey (25H)"},
        {id = 4619, name = "Neck-Deep in Vile (25H)"},
    },
    ICC25N = {
        {id = 4532, name = "Fall of the Lich King (25)"},
        {id = 4530, name = "The Frostwing Halls (25)"},
        {id = 4528, name = "The Crimson Hall (25)"},
    },
    ICC10H = {
        {id = 4583, name = "The Frozen Throne (10H)"},
        {id = 4601, name = "Been Waiting a Long Time (10H)"},
    },
    ICC10N = {
        {id = 4531, name = "Fall of the Lich King (10)"},
        {id = 4529, name = "The Frostwing Halls (10)"},
    },
    RS25H = {
        {id = 4817, name = "Heroic: Halion (25H)"},
    },
    RS25N = {
        {id = 4818, name = "The Twilight Destroyer (25)"},
    },
    RS10H = {
        {id = 4816, name = "Heroic: Halion (10H)"},
    },
    RS10N = {
        {id = 4815, name = "The Twilight Destroyer (10)"},
    },
    TOC25 = {
        {id = 3917, name = "Call of the Grand Crusade (25)"},
        {id = 3916, name = "Call of the Crusade (25)"},
    },
    TOC10 = {
        {id = 3918, name = "Call of the Grand Crusade (10)"},
        {id = 3808, name = "A Tribute to Skill (10)"},
    },
    ULDUAR25 = {
        {id = 2958, name = "Glory of the Ulduar Raider (25)"},
        {id = 2895, name = "The Secrets of Ulduar (25)"},
    },
    ULDUAR10 = {
        {id = 2957, name = "Glory of the Ulduar Raider (10)"},
        {id = 2894, name = "The Secrets of Ulduar (10)"},
    },
    NAXX25 = {
        {id = 2137, name = "Glory of the Raider (25)"},
        {id = 1658, name = "The Fall of Naxxramas (25)"},
    },
    NAXX10 = {
        {id = 2136, name = "Glory of the Raider (10)"},
        {id = 1657, name = "The Fall of Naxxramas (10)"},
    },
    VOA25 = {
        {id = 4017, name = "Earth, Wind & Fire (25)"},
    },
    VOA10 = {
        {id = 4016, name = "Earth, Wind & Fire (10)"},
    },
}

-- Template defaults for raids (used by Add Group popup)
-- mdps = melee DPS, rdps = ranged DPS
GUI.RaidTemplateDefaults = {
    -- ICC (Icecrown Citadel)
    ICC25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5800, ilvl = 264},
    ICC25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5400, ilvl = 251},
    ICC10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5600, ilvl = 251},
    ICC10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5000, ilvl = 232},
    -- RS (Ruby Sanctum)
    RS25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5900, ilvl = 264},
    RS25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5600, ilvl = 258},
    RS10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5700, ilvl = 258},
    RS10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5300, ilvl = 245},
    -- TOC/TOGC (Trial of the Crusader)
    TOC25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5000, ilvl = 232},
    TOC10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4600, ilvl = 219},
    TOGC25 = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5400, ilvl = 245},
    TOGC10 = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5000, ilvl = 232},
    -- VOA (Vault of Archavon)
    VOA25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5500, ilvl = 251},
    VOA25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4800, ilvl = 226},
    VOA10H = {tanks = 2, healers = 2, mdps = 3, rdps = 3, gs = 5200, ilvl = 245},
    VOA10N = {tanks = 2, healers = 2, mdps = 3, rdps = 3, gs = 4400, ilvl = 213},
    -- Ulduar
    ULDUAR25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4800, ilvl = 232},
    ULDUAR25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4400, ilvl = 219},
    ULDUAR10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4400, ilvl = 219},
    ULDUAR10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4000, ilvl = 200},
    -- Naxx
    NAXX25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4000, ilvl = 213},
    NAXX25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 3600, ilvl = 200},
    NAXX10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 3600, ilvl = 200},
    NAXX10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 3200, ilvl = 187},
    -- EoE (Eye of Eternity)
    EoE25H = {tanks = 1, healers = 6, mdps = 9, rdps = 9, gs = 4600, ilvl = 226},
    EoE25N = {tanks = 1, healers = 6, mdps = 9, rdps = 9, gs = 4200, ilvl = 213},
    EoE10H = {tanks = 1, healers = 3, mdps = 3, rdps = 3, gs = 4200, ilvl = 213},
    EoE10N = {tanks = 1, healers = 3, mdps = 3, rdps = 3, gs = 3800, ilvl = 200},
    -- OS (Obsidian Sanctum)
    OS25H = {tanks = 3, healers = 6, mdps = 8, rdps = 8, gs = 4600, ilvl = 226},
    OS25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4000, ilvl = 200},
    OS10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4200, ilvl = 213},
    OS10N = {tanks = 2, healers = 2, mdps = 3, rdps = 3, gs = 3600, ilvl = 187},
    -- Onyxia
    Ony25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5000, ilvl = 232},
    Ony25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4600, ilvl = 219},
    Ony10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4600, ilvl = 219},
    Ony10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4200, ilvl = 200},
    -- WotLK Heroic Dungeons
    HEROIC5 = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 3200, ilvl = 180},
    -- ICC 5-man Heroics
    FoS5H = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 4200, ilvl = 200},
    PoS5H = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 4600, ilvl = 213},
    HoR5H = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 5000, ilvl = 219},
    ToC5H = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 4200, ilvl = 200},
    -- Custom (no requirements)
    CUSTOM = {tanks = 0, healers = 0, mdps = 0, rdps = 0, gs = 0, ilvl = 0},
}

-- Valid sizes for each raid/dungeon type
-- Format: {sizes = {list}, defaultSize = "X", hasHeroic = bool}
GUI.RaidSizeInfo = {
    -- WotLK Raids (10/25)
    ICC = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    RS = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    TOC = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    VOA = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = false},
    ULDUAR = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    NAXX = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = false},
    EoE = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = false},
    OS = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    Ony = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = false},
    -- WotLK Dungeons (5-man only)
    FoS = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    PoS = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    HoR = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    ToC5 = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    HEROIC = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    -- TBC Raids
    SWP = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    BT = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    HYJAL = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    TK = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    SSC = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    GRUUL = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    MAG = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    KARA = {sizes = {"10"}, defaultSize = "10", hasHeroic = false},
    ZA = {sizes = {"10"}, defaultSize = "10", hasHeroic = false},
    -- TBC Dungeons (5-man)
    MGT = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    SH = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    SLABS = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    ARCA = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    MECH = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    BOT = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    -- Classic Raids
    MC = {sizes = {"40"}, defaultSize = "40", hasHeroic = false},
    BWL = {sizes = {"40"}, defaultSize = "40", hasHeroic = false},
    AQ40 = {sizes = {"40"}, defaultSize = "40", hasHeroic = false},
    AQ20 = {sizes = {"20"}, defaultSize = "20", hasHeroic = false},
    ZG = {sizes = {"20"}, defaultSize = "20", hasHeroic = false},
    -- Classic Dungeons
    UBRS = {sizes = {"10"}, defaultSize = "10", hasHeroic = false},
    LBRS = {sizes = {"5"}, defaultSize = "5", hasHeroic = false},
    STRAT = {sizes = {"5"}, defaultSize = "5", hasHeroic = false},
    SCHOLO = {sizes = {"5"}, defaultSize = "5", hasHeroic = false},
    BRD = {sizes = {"5"}, defaultSize = "5", hasHeroic = false},
    -- Custom
    CUSTOM = {sizes = {"5", "10", "20", "25", "40"}, defaultSize = "25", hasHeroic = false},
}

-- Raid categories for dropdown organization (with submenu support)
GUI.RaidCategories = {
    {id = "WOTLK_RAID", header = "WotLK Raids", items = {"ICC", "RS", "TOC", "VOA", "ULDUAR", "NAXX", "EoE", "OS", "Ony"}},
    {id = "WOTLK_DUNG", header = "WotLK Dungeons", items = {"FoS", "PoS", "HoR", "ToC5", "HEROIC"}},
    {id = "TBC_RAID", header = "TBC Raids", items = {"SWP", "BT", "HYJAL", "TK", "SSC", "GRUUL", "MAG", "KARA", "ZA"}},
    {id = "TBC_DUNG", header = "TBC Dungeons", items = {"MGT", "SH", "SLABS", "ARCA", "MECH", "BOT"}},
    {id = "CLASSIC_RAID", header = "Classic Raids", items = {"MC", "BWL", "AQ40", "AQ20", "ZG"}},
    {id = "CLASSIC_DUNG", header = "Classic Dungeons", items = {"UBRS", "LBRS", "STRAT", "SCHOLO", "BRD"}},
    {id = "OTHER", header = "Other", items = {"CUSTOM"}},
}

-- Class/spec options for recruitment
-- melee = true for melee DPS specs, false/nil for ranged
GUI.ClassSpecs = {
    TANK = {
        {class = "WARRIOR", spec = "Protection", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance"},
        {class = "PALADIN", spec = "Protection", icon = "Interface\\Icons\\Spell_Holy_DevotionAura"},
        {class = "DEATHKNIGHT", spec = "Blood", icon = "Interface\\Icons\\Spell_Deathknight_BloodPresence"},
        {class = "DRUID", spec = "Feral (Bear)", icon = "Interface\\Icons\\Ability_Racial_BearForm"},
    },
    HEALER = {
        {class = "PRIEST", spec = "Holy", icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit"},
        {class = "PRIEST", spec = "Discipline", icon = "Interface\\Icons\\Spell_Holy_PowerWordShield"},
        {class = "PALADIN", spec = "Holy", icon = "Interface\\Icons\\Spell_Holy_HolyBolt"},
        {class = "DRUID", spec = "Restoration", icon = "Interface\\Icons\\Spell_Nature_HealingTouch"},
        {class = "SHAMAN", spec = "Restoration", icon = "Interface\\Icons\\Spell_Nature_MagicImmunity"},
    },
    DPS = {
        -- Melee DPS
        {class = "WARRIOR", spec = "Arms/Fury", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", melee = true},
        {class = "PALADIN", spec = "Retribution", icon = "Interface\\Icons\\Spell_Holy_AuraOfLight", melee = true},
        {class = "DEATHKNIGHT", spec = "Frost", icon = "Interface\\Icons\\Spell_Deathknight_FrostPresence", melee = true},
        {class = "DEATHKNIGHT", spec = "Unholy", icon = "Interface\\Icons\\Spell_Deathknight_UnholyPresence", melee = true},
        {class = "ROGUE", spec = "All", icon = "Interface\\Icons\\Ability_BackStab", melee = true},
        {class = "DRUID", spec = "Feral (Cat)", icon = "Interface\\Icons\\Ability_Druid_CatForm", melee = true},
        {class = "SHAMAN", spec = "Enhancement", icon = "Interface\\Icons\\Spell_Nature_LightningShield", melee = true},
        -- Ranged DPS
        {class = "MAGE", spec = "All", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", melee = false},
        {class = "WARLOCK", spec = "All", icon = "Interface\\Icons\\Spell_Shadow_DeathCoil", melee = false},
        {class = "HUNTER", spec = "All", icon = "Interface\\Icons\\Ability_Hunter_SteadyShot", melee = false},
        {class = "DRUID", spec = "Balance", icon = "Interface\\Icons\\Spell_Nature_Starfall", melee = false},
        {class = "SHAMAN", spec = "Elemental", icon = "Interface\\Icons\\Spell_Nature_Lightning", melee = false},
        {class = "PRIEST", spec = "Shadow", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", melee = false},
    },
}

function GUI.CreateAddGroupPopup()
    local popup = CreateFrame("Frame", "AIPAddGroupPopup", UIParent)
    popup:SetSize(500, 340)  -- collapsed height; SetExpanded() grows it (500 wide: per-spec count boxes)
    popup:SetPoint("CENTER", -255, 0)  -- offset left clears the Enroll popup at the new 500 width
    popup:SetFrameStrata("DIALOG")
    AIP.UI.MakeDraggable(popup)
    popup:SetClampedToScreen(true)
    GUI.StylePopup(popup)

    local COLLAPSED_HEIGHT = 340  -- 320 + 20px so the needs hint clears the Customize button
    local EXPANDED_HEIGHT = 688  -- 668 + 20px for the composition "Need:" line

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Create Group Listing")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- ========================================================================
    -- RAID ROW (always visible)
    -- ========================================================================
    local raidLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", 20, -42)
    raidLabel:SetText("Raid:")

    local raidTypeDropdown = CreateFrame("Frame", "AIPAddGroupRaidType", popup, "UIDropDownMenuTemplate")
    raidTypeDropdown:SetPoint("LEFT", raidLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(raidTypeDropdown, 100)
    UIDropDownMenu_SetText(raidTypeDropdown, "ICC")
    popup.raidType = "ICC"
    popup.weeklyToken = nil   -- set when a Weekly quest activity is selected

    local sizeDropdown = CreateFrame("Frame", "AIPAddGroupSize", popup, "UIDropDownMenuTemplate")
    sizeDropdown:SetPoint("LEFT", raidTypeDropdown, "RIGHT", -15, 0)
    UIDropDownMenu_SetWidth(sizeDropdown, 50)
    UIDropDownMenu_SetText(sizeDropdown, "25")
    popup.raidSize = "25"

    local heroicCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    heroicCheck:SetSize(22, 22)
    heroicCheck:SetPoint("LEFT", sizeDropdown, "RIGHT", 5, 2)
    heroicCheck:SetChecked(true)
    popup.heroicCheck = heroicCheck
    local heroicLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heroicLabel:SetPoint("LEFT", heroicCheck, "RIGHT", 0, 0)
    heroicLabel:SetText("Heroic")

    -- Lockout warning indicator (red dot)
    local lockoutWarning = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockoutWarning:SetPoint("LEFT", heroicLabel, "RIGHT", 10, 0)
    lockoutWarning:SetText("|cFFFF4444\226\151\143|r")
    lockoutWarning:Hide()
    popup.lockoutWarning = lockoutWarning

    -- === Custom name / weekly status row (shared line under the raid row) ===
    local customLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOPLEFT", 20, -74)
    customLabel:SetText("Custom Name:")
    customLabel:Hide()
    popup.customLabel = customLabel

    local customInput, customContainer = GUI.CreateStyledEditBox(popup, 180, 16, false)
    customContainer:SetPoint("LEFT", customLabel, "RIGHT", 5, 0)
    customContainer:Hide()
    popup.customInput = customInput
    popup.customContainer = customContainer

    -- Weekly quest status strip ("You don't have this quest - ...")
    local weeklyStrip = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    weeklyStrip:SetPoint("TOPLEFT", 20, -76)
    weeklyStrip:SetPoint("RIGHT", popup, "RIGHT", -20, 0)
    weeklyStrip:SetJustifyH("LEFT")
    weeklyStrip:Hide()
    popup.weeklyStrip = weeklyStrip

    -- ========================================================================
    -- QUICK POST preset tiles (collapsed mode) / DETAIL frame (expanded mode)
    -- ========================================================================
    local quickLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    quickLabel:SetPoint("TOPLEFT", 20, -96)
    quickLabel:SetText("QUICK POST")
    quickLabel:SetTextColor(1, 0.82, 0)
    popup.quickLabel = quickLabel

    popup.presetTiles = {}
    local function makeTile(index)
        local tile = CreateFrame("Button", nil, popup)
        tile:SetSize(150, 52)
        tile:SetPoint("TOPLEFT", 20 + (index - 1) * 155, -112)
        GUI.ApplyBackdrop(tile, "Inset", 0.9)
        tile.titleText = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tile.titleText:SetPoint("TOP", 0, -8)
        tile.subText = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tile.subText:SetPoint("TOP", 0, -26)
        tile.subText:SetTextColor(0.7, 0.7, 0.7)
        tile:SetScript("OnEnter", function(self)
            if self.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return tile
    end
    popup.presetTiles.last = makeTile(1)
    popup.presetTiles.weekly = makeTile(2)
    popup.presetTiles.fresh = makeTile(3)

    -- One-line class-needs hint under the quick-post tiles, so the tandem
    -- suggestions are visible without expanding the full form. Clipped to a
    -- single line - it must never bleed into the PREVIEW section below.
    local collapsedNeedsText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    collapsedNeedsText:SetPoint("TOPLEFT", 20, -168)
    collapsedNeedsText:SetPoint("RIGHT", popup, "RIGHT", -20, 0)
    collapsedNeedsText:SetHeight(13)
    collapsedNeedsText:SetJustifyH("LEFT")
    if collapsedNeedsText.SetWordWrap then collapsedNeedsText:SetWordWrap(false) end
    collapsedNeedsText:SetText("")
    popup.collapsedNeedsText = collapsedNeedsText

    -- Detail frame: the full customization form, hidden while collapsed
    local detail = CreateFrame("Frame", nil, popup)
    detail:SetPoint("TOPLEFT", 0, -96)
    detail:SetSize(500, 435)
    detail:Hide()
    popup.detail = detail

    -- ========================================================================
    -- HELPERS (raid key, defaults, dropdown wiring)
    -- ========================================================================
    local function GetRaidKey()
        local raidType = popup.raidType or "ICC"
        if raidType == "CUSTOM" then
            local customText = popup.customInput and popup.customInput:GetText() or ""
            if customText ~= "" then
                return customText
            end
            return "Custom"
        end
        local size = popup.raidSize or "25"
        local heroic = popup.heroicCheck:GetChecked() and "H" or "N"
        if raidType == "TOC" and heroic == "H" then
            return "TOGC" .. size
        end
        return raidType .. size .. heroic
    end
    popup.GetRaidKey = GetRaidKey

    local function UpdateWeeklyStrip()
        if popup.weeklyToken and AIP.Weekly then
            local q = AIP.Weekly.ForToken(popup.weeklyToken)
            local status = AIP.Weekly.StatusText(popup.weeklyToken)
            weeklyStrip:SetText("|cFF33CCFF[W]|r " .. (q and q.boss or popup.weeklyToken) .. ": " .. status)
            weeklyStrip:Show()
        else
            weeklyStrip:Hide()
        end
    end
    popup.UpdateWeeklyStrip = UpdateWeeklyStrip

    local function UpdateCustomFieldVisibility()
        if popup.raidType == "CUSTOM" then
            popup.customLabel:Show()
            if popup.customContainer then popup.customContainer:Show() end
            popup.heroicCheck:Hide()
            heroicLabel:Hide()
            weeklyStrip:Hide()
        else
            popup.customLabel:Hide()
            if popup.customContainer then popup.customContainer:Hide() end
            popup.heroicCheck:Show()
            heroicLabel:Show()
            UpdateWeeklyStrip()
        end
    end
    popup.UpdateCustomFieldVisibility = UpdateCustomFieldVisibility

    local function UpdateLockoutWarning()
        local raidKey = GetRaidKey()
        if AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance then
            AIP.TreeBrowser.UpdateSavedInstances()
            if AIP.TreeBrowser.IsLockedToInstance(raidKey) then
                lockoutWarning:Show()
            else
                lockoutWarning:Hide()
            end
        else
            lockoutWarning:Hide()
        end
    end
    popup.UpdateLockoutWarning = UpdateLockoutWarning

    local function UpdateSizeDropdown()
        local raidInfo = GUI.RaidSizeInfo[popup.raidType]
        if raidInfo then
            local currentSizeValid = false
            for _, validSize in ipairs(raidInfo.sizes) do
                if validSize == popup.raidSize then
                    currentSizeValid = true
                    break
                end
            end
            if not currentSizeValid then
                popup.raidSize = raidInfo.defaultSize
                UIDropDownMenu_SetText(sizeDropdown, raidInfo.defaultSize)
            end
            if raidInfo.hasHeroic then
                heroicCheck:Show()
                heroicLabel:Show()
            else
                heroicCheck:Hide()
                heroicLabel:Hide()
                heroicCheck:SetChecked(false)
            end
            if #raidInfo.sizes == 1 then
                UIDropDownMenu_DisableDropDown(sizeDropdown)
            else
                UIDropDownMenu_EnableDropDown(sizeDropdown)
            end
        end
    end
    popup.UpdateSizeDropdown = UpdateSizeDropdown

    local function UpdateRaidDropdownText()
        local raidType = popup.raidType or "ICC"
        local prefix = popup.weeklyToken and "|cFF33CCFF[W]|r " or ""
        local isLocked = AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and AIP.TreeBrowser.IsLockedToInstance(raidType)
        if isLocked then
            UIDropDownMenu_SetText(raidTypeDropdown, prefix .. "|cFFFF6666" .. raidType .. "|r")
        else
            UIDropDownMenu_SetText(raidTypeDropdown, prefix .. raidType)
        end
    end
    popup.UpdateRaidDropdownText = UpdateRaidDropdownText

    -- Forward declarations (defined after the detail widgets exist)
    local ApplyTemplateDefaults
    local RefreshPreview

    -- Raid type dropdown: Weekly category pinned first, then the standard set
    UIDropDownMenu_Initialize(raidTypeDropdown, function(self, level, menuList)
        level = level or 1

        if level == 1 then
            if AIP.Weekly then
                local info = UIDropDownMenu_CreateInfo()
                info.text = "|cFF33CCFFWeekly Raid Quest|r"
                info.hasArrow = true
                info.menuList = "AIP_WEEKLY"
                info.notCheckable = true
                info.keepShownOnClick = true
                UIDropDownMenu_AddButton(info, level)
            end
            for _, cat in ipairs(GUI.RaidCategories) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = cat.header
                info.hasArrow = true
                info.menuList = cat.id
                info.notCheckable = true
                info.keepShownOnClick = true
                UIDropDownMenu_AddButton(info, level)
            end
        elseif level == 2 then
            if menuList == "AIP_WEEKLY" and AIP.Weekly then
                -- This week's detected quest first, then the full rotation
                local held = AIP.Weekly.Current()
                local ordered = {}
                if held then ordered[#ordered + 1] = held.quest end
                for _, q in ipairs(AIP.Weekly.Quests) do
                    if not held or q.token ~= held.quest.token then
                        ordered[#ordered + 1] = q
                    end
                end
                for idx, q in ipairs(ordered) do
                    local info = UIDropDownMenu_CreateInfo()
                    local tag = (held and q.token == held.quest.token) and " |cFF00FF00(this week)|r" or ""
                    info.text = q.boss .. " (" .. q.raid .. ")" .. tag
                    info.value = q.token
                    info.func = function()
                        popup.weeklyToken = q.token
                        popup.raidType = q.raid
                        popup.raidSize = "10"          -- weekly kill is any size; 10N is the common carry
                        popup.heroicCheck:SetChecked(false)
                        UpdateRaidDropdownText()
                        UpdateSizeDropdown()
                        -- SetText explicitly: UpdateSizeDropdown only rewrites
                        -- the label when the size is INVALID for the raid
                        UIDropDownMenu_SetText(sizeDropdown, "10")
                        ApplyTemplateDefaults()
                        CloseDropDownMenus()
                    end
                    info.checked = (popup.weeklyToken == q.token)
                    UIDropDownMenu_AddButton(info, level)
                end
                return
            end
            for _, cat in ipairs(GUI.RaidCategories) do
                if cat.id == menuList then
                    for _, rt in ipairs(cat.items) do
                        local info = UIDropDownMenu_CreateInfo()
                        local isLocked = AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and AIP.TreeBrowser.IsLockedToInstance(rt)
                        if isLocked then
                            info.text = "|cFFFF6666" .. rt .. "|r"
                        else
                            info.text = rt
                        end
                        info.value = rt
                        info.func = function()
                            popup.raidType = rt
                            popup.weeklyToken = nil    -- picking a plain raid clears the weekly tag
                            UpdateRaidDropdownText()
                            UpdateSizeDropdown()
                            ApplyTemplateDefaults()
                            CloseDropDownMenus()
                        end
                        info.checked = (popup.raidType == rt)
                        UIDropDownMenu_AddButton(info, level)
                    end
                    break
                end
            end
        end
    end)

    UIDropDownMenu_Initialize(sizeDropdown, function()
        local raidInfo = GUI.RaidSizeInfo[popup.raidType] or {sizes = {"5", "10", "25"}}
        for _, size in ipairs(raidInfo.sizes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = size .. " players"
            info.value = size
            info.func = function()
                popup.raidSize = size
                UIDropDownMenu_SetText(sizeDropdown, size)
                ApplyTemplateDefaults()
            end
            info.checked = (popup.raidSize == size)
            UIDropDownMenu_AddButton(info)
        end
    end)
    GUI.FixDropdownStrata(raidTypeDropdown)
    GUI.FixDropdownStrata(sizeDropdown)

    -- ========================================================================
    -- DETAIL FRAME CONTENT (composition, requirements, classes, note, keyword)
    -- ========================================================================

    -- === Detail Level selector (mode-level control - always visible, always
    -- the first row) ===
    -- This is a page-level control (it governs whether the Composition row
    -- OR the Class grid below is shown), not something scoped to "Looking
    -- For Classes" specifically, so it gets its own top-of-form row rather
    -- than being squeezed next to one section's label.
    local modeRowLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeRowLabel:SetPoint("TOPLEFT", 20, 0)
    modeRowLabel:SetText("Detail Level:")
    local classHint = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classHint:SetPoint("LEFT", modeRowLabel, "RIGHT", 8, 0)
    classHint:SetText("|cFF888888(box = count)|r")
    classHint:SetWidth(150)
    classHint:SetWordWrap(false)

    -- === Composition Row (Compact mode only - fixed position, this mode
    -- never shows anything above it) ===
    local compLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    compLabel:SetPoint("TOPLEFT", 20, -26)
    compLabel:SetText("Composition:")
    popup.compositionRowWidgets = { compLabel }

    local tankLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tankLabel:SetPoint("TOPLEFT", 30, -46)
    tankLabel:SetText("Tanks:")
    tankLabel:SetTextColor(0.5, 0.5, 1)
    local tankInput, tankContainer = GUI.CreateStyledEditBox(detail, 30, 14, true)
    tankContainer:SetPoint("LEFT", tankLabel, "RIGHT", 5, 0)
    tankInput:SetText("2")
    popup.tankInput = tankInput
    table.insert(popup.compositionRowWidgets, tankLabel)
    table.insert(popup.compositionRowWidgets, tankContainer)

    local healLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    healLabel:SetPoint("LEFT", tankContainer, "RIGHT", 10, 0)
    healLabel:SetText("Healers:")
    healLabel:SetTextColor(0.5, 1, 0.5)
    local healInput, healContainer = GUI.CreateStyledEditBox(detail, 30, 14, true)
    healContainer:SetPoint("LEFT", healLabel, "RIGHT", 5, 0)
    healInput:SetText("6")
    popup.healInput = healInput
    table.insert(popup.compositionRowWidgets, healLabel)
    table.insert(popup.compositionRowWidgets, healContainer)

    local mdpsLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mdpsLabel:SetPoint("LEFT", healContainer, "RIGHT", 10, 0)
    mdpsLabel:SetText("MDPS:")
    mdpsLabel:SetTextColor(1, 0.5, 0)
    local mdpsInput, mdpsContainer = GUI.CreateStyledEditBox(detail, 25, 14, true)
    mdpsContainer:SetPoint("LEFT", mdpsLabel, "RIGHT", 3, 0)
    mdpsInput:SetText("8")
    popup.mdpsInput = mdpsInput
    table.insert(popup.compositionRowWidgets, mdpsLabel)
    table.insert(popup.compositionRowWidgets, mdpsContainer)

    local rdpsLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rdpsLabel:SetPoint("LEFT", mdpsContainer, "RIGHT", 8, 0)
    rdpsLabel:SetText("RDPS:")
    rdpsLabel:SetTextColor(1, 0.8, 0)
    local rdpsInput, rdpsContainer = GUI.CreateStyledEditBox(detail, 25, 14, true)
    rdpsContainer:SetPoint("LEFT", rdpsLabel, "RIGHT", 3, 0)
    rdpsInput:SetText("9")
    popup.rdpsInput = rdpsInput
    table.insert(popup.compositionRowWidgets, rdpsLabel)
    table.insert(popup.compositionRowWidgets, rdpsContainer)

    -- === Requirements Row === (dynamic Y - repositioned per mode by
    -- ReflowDetailRows below; initial SetPoint values are placeholders,
    -- overwritten before the popup is ever shown)
    local reqLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reqLabel:SetPoint("TOPLEFT", 20, -26)
    reqLabel:SetText("Requirements:")

    local gsLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gsLabel:SetPoint("TOPLEFT", 30, -46)
    gsLabel:SetText("Min GS:")
    local gsInput, gsContainer = GUI.CreateStyledEditBox(detail, 45, 14, true)
    gsContainer:SetPoint("LEFT", gsLabel, "RIGHT", 5, 0)
    gsInput:SetText("5800")
    popup.gsInput = gsInput

    local ilvlLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlLabel:SetPoint("LEFT", gsContainer, "RIGHT", 15, 0)
    ilvlLabel:SetText("Min iLvl:")
    local ilvlInput, ilvlContainer = GUI.CreateStyledEditBox(detail, 35, 14, true)
    ilvlContainer:SetPoint("LEFT", ilvlLabel, "RIGHT", 5, 0)
    ilvlInput:SetText("264")
    popup.ilvlInput = ilvlInput

    -- === Achievement Row === (dynamic Y)
    local achieveLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achieveLabel:SetPoint("TOPLEFT", 30, -72)
    achieveLabel:SetText("Require Achievement:")

    local achieveDropdown = CreateFrame("Frame", "AIPAddGroupAchieve", detail, "UIDropDownMenuTemplate")
    achieveDropdown:SetPoint("LEFT", achieveLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(achieveDropdown, 180)
    UIDropDownMenu_SetText(achieveDropdown, "None")
    popup.achieveDropdown = achieveDropdown
    popup.selectedAchievement = nil
    GUI.FixDropdownStrata(achieveDropdown)

    -- === Class/Spec Selection (Detailed mode only - fixed position, this
    -- mode always shows the same fixed set of rows above it) ===
    local classGridLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classGridLabel:SetPoint("TOPLEFT", 20, -106)
    classGridLabel:SetText("Looking For Classes:")

    -- Composition detail mode: MINIMAL shows only the Note (role counts still
    -- come from the template, just not shown/editable); COMPACT broadcasts
    -- role counts only ([T:x/y]); DETAILED broadcasts the class list + counts
    -- ([T:PP..] + [Need:..]). The choice persists (AIP.db.lfmDetailMode) and
    -- rides the listing so FitEngine/regen/DataBus all respect it too.
    local MODE_LABEL = { minimal = "Minimal", compact = "Compact", detailed = "Detailed" }
    local MODE_TOOLTIP = {
        minimal = "Only the note is customized here - role counts still come from the selected template, they're just not shown.",
        compact = "Broadcast role counts only ([T:x/y]) - any class may apply.",
        detailed = "Broadcast the class list and per-class counts ([Need:...]).",
    }
    popup.modeButtons = {}
    -- Two redundant selection cues (color AND brackets), not color alone -
    -- plain-text toggle buttons (matching this file's existing makeRoleToggle
    -- convention) have no button art to show a pressed/selected state, so the
    -- active mode must be unmistakable even to a colorblind reader at a glance.
    local function updateModeButtonHighlight()
        for mode, btn in pairs(popup.modeButtons) do
            if mode == popup.detailMode then
                btn.text:SetTextColor(0.4, 0.8, 1)
                btn.text:SetText("[" .. MODE_LABEL[mode] .. "]")
            else
                btn.text:SetTextColor(0.6, 0.6, 0.6)
                btn.text:SetText(MODE_LABEL[mode])
            end
        end
    end
    popup.UpdateModeButtonHighlight = updateModeButtonHighlight
    local function makeModeButton(mode, xOffset)
        local btn = CreateFrame("Button", nil, detail)
        btn:SetSize(58, 18)
        btn:SetPoint("TOPRIGHT", detail, "TOPRIGHT", xOffset, 0)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(MODE_LABEL[mode])
        btn.text = fs
        btn:SetScript("OnClick", function()
            popup.detailMode = mode
            if AIP.db then AIP.db.lfmDetailMode = mode end
            if popup.ApplyDetailMode then popup.ApplyDetailMode(mode) end
            updateModeButtonHighlight()
            if RefreshPreview then RefreshPreview() end
        end)
        btn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Composition detail: " .. MODE_LABEL[mode])
            GameTooltip:AddLine(MODE_TOOLTIP[mode], 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            updateModeButtonHighlight()
            GameTooltip:Hide()
        end)
        popup.modeButtons[mode] = btn
        return btn
    end
    makeModeButton("detailed", -20)
    makeModeButton("compact", -84)
    makeModeButton("minimal", -148)
    popup.detailMode = (AIP.db and AIP.db.lfmDetailMode) or "detailed"
    if popup.detailMode == "vague" then
        -- Legacy SavedVariables value from before the 3-way toggle existed -
        -- persist the normalized value back to AIP.db too, not just the
        -- popup's in-memory copy, so any other code that reads
        -- AIP.db.lfmDetailMode directly doesn't see the stale "vague" string.
        popup.detailMode = "compact"
        if AIP.db then AIP.db.lfmDetailMode = "compact" end
    end

    popup.classChecks = {}
    popup.classGridWidgets = { classGridLabel }   -- shown/hidden as a group per mode
    local specSpacing = 76  -- check(20) + icon(20) + count box(18) + gap

    -- Role label doubling as an all/none toggle for its group
    local function makeRoleToggle(text, r, g, b, yOff, roleKey)
        local btn = CreateFrame("Button", nil, detail)
        btn:SetSize(48, 16)
        btn:SetPoint("TOPLEFT", 25, yOff)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", 0, 0)
        fs:SetText(text)
        fs:SetTextColor(r, g, b)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Click to check/uncheck all " .. text:gsub(":", ""))
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(popup.classGridWidgets, btn)
        btn:SetScript("OnClick", function()
            local group = popup.classChecks[roleKey]
            if not group then return end
            -- If any are unchecked, check all; otherwise uncheck all
            local anyUnchecked = false
            for _, check in pairs(group) do
                if not check:GetChecked() then anyUnchecked = true break end
            end
            for _, check in pairs(group) do
                check:SetChecked(anyUnchecked)
                if check.countInput then
                    if anyUnchecked then
                        if (tonumber(check.countInput:GetText()) or 0) <= 0 then
                            check.countInput:SetText("1")
                        end
                    else
                        check.countInput:SetText("0")
                    end
                end
            end
            if popup.SyncCompositionFromClassGrid then popup.SyncCompositionFromClassGrid() end
            if RefreshPreview then RefreshPreview() end
        end)
        return btn
    end

    local function makeSpecCheck(spec, x, yOff, roleKey)
        local check = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("TOPLEFT", x, yOff)
        check:SetChecked(true)
        local icon = check:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", check, "RIGHT", -2, 0)
        icon:SetTexture(spec.icon)
        check.specData = spec

        -- Per-spec need-count box: how many players of this class/spec are
        -- wanted. Feeds the [Need:] block, MyGroup.classNeeds and the
        -- FitEngine verdicts. 0 = spec accepted but not counted.
        local countInput, countContainer = GUI.CreateStyledEditBox(detail, 16, 12, true)
        countContainer:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        countInput:SetText("0")
        countInput:SetMaxLetters(2)
        check.countInput = countInput
        countInput:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(spec.class .. " - " .. spec.spec)
            GameTooltip:AddLine("How many of this class/spec you still need.", 1, 1, 1)
            GameTooltip:AddLine("Shown as [Need: ...] in the broadcast; 0 = accepted, not advertised.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        countInput:SetScript("OnLeave", function() GameTooltip:Hide() end)
        countInput:HookScript("OnTextChanged", function(self, isUser)
            if isUser then
                local n = tonumber(self:GetText()) or 0
                if n > 0 and not check:GetChecked() then check:SetChecked(true) end
                if popup.SyncCompositionFromClassGrid then popup.SyncCompositionFromClassGrid() end
                if RefreshPreview then RefreshPreview() end
            end
        end)

        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(spec.class .. " - " .. spec.spec)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        check:SetScript("OnClick", function(self)
            if self.countInput then
                if self:GetChecked() then
                    if (tonumber(self.countInput:GetText()) or 0) <= 0 then
                        self.countInput:SetText("1")
                    end
                else
                    self.countInput:SetText("0")
                end
            end
            if popup.SyncCompositionFromClassGrid then popup.SyncCompositionFromClassGrid() end
            if RefreshPreview then RefreshPreview() end
        end)
        popup.classChecks[roleKey][spec.class .. spec.spec] = check
        table.insert(popup.classGridWidgets, check)
        table.insert(popup.classGridWidgets, countContainer)
        table.insert(popup.classGridWidgets, countInput)  -- EnableMouse(false) blocks typing
        return check
    end

    popup.classChecks.TANK = {}
    makeRoleToggle("Tanks:", 0.5, 0.5, 1, -124, "TANK")
    local tankX = 80
    for _, spec in ipairs(GUI.ClassSpecs.TANK) do
        makeSpecCheck(spec, tankX, -122, "TANK")
        tankX = tankX + specSpacing
    end

    popup.classChecks.HEALER = {}
    makeRoleToggle("Heals:", 0.5, 1, 0.5, -150, "HEALER")
    local healX = 80
    for _, spec in ipairs(GUI.ClassSpecs.HEALER) do
        makeSpecCheck(spec, healX, -148, "HEALER")
        healX = healX + specSpacing
    end

    popup.classChecks.DPS = {}
    makeRoleToggle("DPS:", 1, 0.5, 0.5, -176, "DPS")
    local dpsX, dpsY = 80, -174
    local dpsCount = 0
    for _, spec in ipairs(GUI.ClassSpecs.DPS) do
        if dpsCount > 0 and dpsCount % 5 == 0 then
            dpsY = dpsY - 26
            dpsX = 80
        end
        makeSpecCheck(spec, dpsX, dpsY, "DPS")
        dpsX = dpsX + specSpacing
        dpsCount = dpsCount + 1
    end

    -- === Need summary (from the per-spec count boxes) ===
    -- Single CLIPPED line - the count boxes above are the full picture and
    -- /aip needs prints the detailed list, so this can never wrap over the
    -- Note row again (the old 2-line version did).
    local needsText = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    needsText:SetPoint("TOPLEFT", 20, -276)
    needsText:SetPoint("RIGHT", detail, "RIGHT", -20, 0)
    needsText:SetHeight(13)
    needsText:SetJustifyH("LEFT")
    if needsText.SetWordWrap then needsText:SetWordWrap(false) end
    needsText:SetText("")
    popup.needsText = needsText

    -- === Note Row ===
    local noteLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLabel:SetPoint("TOPLEFT", 20, -302)
    noteLabel:SetText("Note:")
    local noteInput, noteContainer = GUI.CreateStyledEditBox(detail, 300, 18, false)
    noteContainer:SetPoint("LEFT", noteLabel, "RIGHT", 5, 0)
    popup.noteInput = noteInput

    -- === Auto-Invite Keyword Row ===
    local keywordLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keywordLabel:SetPoint("TOPLEFT", 20, -330)
    keywordLabel:SetText("Invite Keyword:")
    keywordLabel:SetTextColor(0.4, 0.8, 1)
    local keywordInput, keywordContainer = GUI.CreateStyledEditBox(detail, 110, 18, false)
    keywordContainer:SetPoint("LEFT", keywordLabel, "RIGHT", 5, 0)
    keywordInput:SetText(AIP.db and AIP.db.triggers or "invme-auto")
    popup.keywordInput = keywordInput

    local keywordHintText = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keywordHintText:SetPoint("LEFT", keywordContainer, "RIGHT", 5, 0)
    keywordHintText:SetText("(whisper to join)")
    keywordHintText:SetTextColor(0.5, 0.5, 0.5)

    -- === Broadcast checkbox ===
    local broadcastCheck = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
    broadcastCheck:SetSize(22, 22)
    broadcastCheck:SetPoint("TOPLEFT", 20, -356)
    broadcastCheck:SetChecked(true)
    popup.broadcastCheck = broadcastCheck
    local broadcastLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    broadcastLabel:SetPoint("LEFT", broadcastCheck, "RIGHT", 2, 0)
    broadcastLabel:SetText("Broadcast to chat channels")

    -- === Reserved Items (read-only display from DB) ===
    local reservedLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reservedLabel:SetPoint("TOPLEFT", 20, -382)
    reservedLabel:SetText("Reserved Items:")
    reservedLabel:SetTextColor(1, 0.5, 0)

    local reservedEditHint = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reservedEditHint:SetPoint("LEFT", reservedLabel, "RIGHT", 10, 0)
    reservedEditHint:SetText("|cFF888888(edit in Raid Mgmt tab)|r")

    local reservedFrame = CreateFrame("Frame", nil, detail)
    reservedFrame:SetSize(460, 34)
    reservedFrame:SetPoint("TOPLEFT", 20, -400)
    GUI.ApplyBackdrop(reservedFrame, "Inset", 0.9)

    local reservedDisplay = reservedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reservedDisplay:SetPoint("TOPLEFT", 8, -6)
    reservedDisplay:SetPoint("BOTTOMRIGHT", -8, 6)
    reservedDisplay:SetJustifyH("LEFT")
    reservedDisplay:SetJustifyV("TOP")
    reservedDisplay:SetText("|cFF666666(none)|r")
    popup.reservedDisplay = reservedDisplay

    -- ========================================================================
    -- DYNAMIC LAYOUT: reposition every row below the mode selector based on
    -- which optional block (Composition / Class grid) the active mode shows,
    -- and resize the popup to match - so switching modes reclaims the space
    -- a hidden block would otherwise leave as a dead gap, instead of just
    -- hiding widgets in place. Rows that live in the mode-independent tail
    -- (Requirements, Achievement, Note, Keyword, Broadcast, Reserved Items)
    -- get looked up per mode; Composition and the Class grid keep the single
    -- fixed position set at creation above (each is visible in only one mode).
    -- Every mode shares the same fixed cascade below `needs` (needs->note -26,
    -- note->keyword -28, keyword->broadcast -26, broadcast->reservedLabel -26,
    -- reservedLabel->reservedFrame -18) - only `req`, `achieve` (composition
    -- present or not) and `needs` (class grid present or not) actually vary
    -- per mode. CONTENT_BOTTOM[mode] = ROW_Y[mode].reservedFrame - 34 (the
    -- reserved-items frame's own height) in every case - keep that identity
    -- if you ever change reservedFrame's height.
    --
    -- detailed's `needs` (-254) assumes the class grid is exactly 3 DPS rows
    -- (GUI.ClassSpecs.DPS currently has 13 entries, wrapped 5/5/3 -> Tanks
    -- -124, Heals -150, DPS rows -176/-202/-228, grid bottom ~-248). If
    -- GUI.ClassSpecs.DPS ever grows past 15 entries (a 4th wrapped row),
    -- lower detailed.needs (and everything below it, and CONTENT_BOTTOM.detailed)
    -- by 26 per extra row, or the grid will overlap the Need summary line.
    local ROW_Y = {
        minimal  = { req = -26, achieve = -72,  needs = -106, note = -132, keyword = -160, broadcast = -186, reservedLabel = -212, reservedFrame = -230 },
        compact  = { req = -74, achieve = -120, needs = -154, note = -180, keyword = -208, broadcast = -234, reservedLabel = -260, reservedFrame = -278 },
        detailed = { req = -26, achieve = -72,  needs = -254, note = -280, keyword = -308, broadcast = -334, reservedLabel = -360, reservedFrame = -378 },
    }
    local CONTENT_BOTTOM = { minimal = -264, compact = -312, detailed = -412 }
    local HEADER_HEIGHT = 96   -- detail frame's fixed TOPLEFT offset from the popup
    -- Vertical room the footer (customizeBtn @134, previewLabel @116,
    -- previewFrame @68, scheduleText @50, createBtn/cancelBtn @16 - all
    -- BOTTOMLEFT-anchored offsets from the popup's own bottom edge, set
    -- where the footer widgets are created below) needs below detail's
    -- content in every mode - a single reserve because those offsets never
    -- change per mode, only how much content sits above them does.
    local FOOTER_RESERVE = 158

    local function ReflowDetailRows(mode)
        local y = ROW_Y[mode] or ROW_Y.detailed
        reqLabel:ClearAllPoints()
        reqLabel:SetPoint("TOPLEFT", 20, y.req)
        gsLabel:ClearAllPoints()
        gsLabel:SetPoint("TOPLEFT", 30, y.req - 20)
        achieveLabel:ClearAllPoints()
        achieveLabel:SetPoint("TOPLEFT", 30, y.achieve)
        needsText:ClearAllPoints()
        needsText:SetPoint("TOPLEFT", 20, y.needs)
        needsText:SetPoint("RIGHT", detail, "RIGHT", -20, 0)
        noteLabel:ClearAllPoints()
        noteLabel:SetPoint("TOPLEFT", 20, y.note)
        keywordLabel:ClearAllPoints()
        keywordLabel:SetPoint("TOPLEFT", 20, y.keyword)
        broadcastCheck:ClearAllPoints()
        broadcastCheck:SetPoint("TOPLEFT", 20, y.broadcast)
        reservedLabel:ClearAllPoints()
        reservedLabel:SetPoint("TOPLEFT", 20, y.reservedLabel)
        reservedFrame:ClearAllPoints()
        reservedFrame:SetPoint("TOPLEFT", 20, y.reservedFrame)

        local contentBottom = CONTENT_BOTTOM[mode] or CONTENT_BOTTOM.detailed
        popup.expandedHeightForMode = HEADER_HEIGHT + math.abs(contentBottom) + FOOTER_RESERVE
        if popup.expanded then
            popup:SetHeight(popup.expandedHeightForMode)
        end
    end
    popup.ReflowDetailRows = ReflowDetailRows

    -- Fully show/hide (not just dim) the Composition row and Class grid per
    -- mode - Minimal hides both, Compact shows only Composition, Detailed
    -- shows only the Class grid (its counts drive the composition totals,
    -- see SyncCompositionFromClassGrid in the next task) - then reflow
    -- everything below to reclaim whichever block is now hidden.
    local function ApplyDetailMode(mode)
        local showComposition = (mode == "compact")
        local showClassGrid = (mode == "detailed")
        for _, w in ipairs(popup.compositionRowWidgets) do
            if showComposition then w:Show() else w:Hide() end
        end
        for _, w in ipairs(popup.classGridWidgets) do
            if showClassGrid then w:Show() else w:Hide() end
            w:SetAlpha(1)
            if w.Disable and w.Enable then w:Enable() end
            if w.EnableMouse then w:EnableMouse(true) end
        end
        if mode == "minimal" then
            classHint:SetText("|cFFFF8800(note only)|r")
        elseif mode == "compact" then
            classHint:SetText("|cFFFF8800(role counts only)|r")
        else
            classHint:SetText("|cFF888888(box = count)|r")
        end
        -- Switching into Detailed must re-derive the composition totals from
        -- the class grid immediately - otherwise the broadcast preview shows
        -- whatever totals were last typed/synced in another mode until the
        -- user happens to touch a checkbox or count field.
        if showClassGrid and popup.SyncCompositionFromClassGrid then
            popup.SyncCompositionFromClassGrid()
        end
        ReflowDetailRows(mode)
    end
    popup.ApplyDetailMode = ApplyDetailMode

    -- ========================================================================
    -- FOOTER: customize toggle, live preview, schedule line, buttons
    -- ========================================================================
    local customizeBtn = CreateFrame("Button", nil, popup)
    customizeBtn:SetSize(140, 18)
    customizeBtn:SetPoint("BOTTOMLEFT", 20, 134)
    local customizeText = customizeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customizeText:SetPoint("LEFT", 0, 0)
    customizeText:SetText("|cFF66AAFF[+] Customize...|r")
    customizeBtn.text = customizeText
    popup.customizeBtn = customizeBtn

    local previewLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLabel:SetPoint("BOTTOMLEFT", 20, 116)
    previewLabel:SetText("PREVIEW")
    previewLabel:SetTextColor(1, 0.82, 0)
    local previewHint = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewHint:SetPoint("LEFT", previewLabel, "RIGHT", 8, 0)
    previewHint:SetText("|cFF888888(exactly what gets broadcast)|r")

    local previewFrame = CreateFrame("Frame", nil, popup)
    previewFrame:SetSize(460, 46)
    previewFrame:SetPoint("BOTTOMLEFT", 20, 68)
    GUI.ApplyBackdrop(previewFrame, "Inset", 0.9)

    local previewText = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", 8, -6)
    previewText:SetPoint("BOTTOMRIGHT", -8, 6)
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")
    popup.previewText = previewText

    local scheduleText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scheduleText:SetPoint("BOTTOMLEFT", 20, 50)
    scheduleText:SetPoint("RIGHT", popup, "RIGHT", -20, 0)
    scheduleText:SetJustifyH("LEFT")
    scheduleText:SetTextColor(0.6, 0.6, 0.6)
    popup.scheduleText = scheduleText

    -- ========================================================================
    -- LOGIC: role spec collection, preview, presets, defaults, expansion
    -- ========================================================================

    -- Collect checked specs -> roleSpecs (codes), lookingForSpecs,
    -- selectedClasses (now incl. per-spec count), and classNeeds (the
    -- per-class need counts aggregated from the count boxes; role folded to
    -- TANK/HEALER/DPS to match Comp/FitEngine vocabulary)
    local function CollectRoleSpecs()
        local LF = AIP.LFMFormat
        local roleSpecs = {TANK = {}, HEALER = {}, MDPS = {}, RDPS = {}}
        local lookingForSpecs = {}
        local selectedClasses = {TANK = {}, HEALER = {}, MDPS = {}, RDPS = {}}
        local needByKey, classNeeds = {}, {}

        for role, roleChecks in pairs(popup.classChecks) do
            for _, check in pairs(roleChecks) do
                if check:GetChecked() and check.specData then
                    local targetRole = role
                    if role == "DPS" then
                        targetRole = check.specData.melee and "MDPS" or "RDPS"
                    end

                    local code = LF and LF.SpecCode(check.specData)
                        or (check.specData.class:sub(1, 1) .. check.specData.spec:sub(1, 1))
                    local found = false
                    for _, existing in ipairs(roleSpecs[targetRole]) do
                        if existing == code then found = true break end
                    end
                    if not found then
                        table.insert(roleSpecs[targetRole], code)
                        table.insert(lookingForSpecs, code)
                    end

                    local count = check.countInput and (tonumber(check.countInput:GetText()) or 0) or 0
                    table.insert(selectedClasses[targetRole], {
                        class = check.specData.class,
                        spec = check.specData.spec,
                        count = count,
                    })

                    if count > 0 then
                        local needRole = (targetRole == "MDPS" or targetRole == "RDPS") and "DPS" or targetRole
                        local key = check.specData.class .. ":" .. needRole
                        local row = needByKey[key]
                        if not row then
                            row = {class = check.specData.class, role = needRole, count = 0}
                            needByKey[key] = row
                            table.insert(classNeeds, row)
                        end
                        row.count = row.count + count
                    end
                end
            end
        end

        local ROLE_ORDER = {TANK = 1, HEALER = 2, DPS = 3}
        table.sort(classNeeds, function(a, b)
            local ra, rb = ROLE_ORDER[a.role] or 9, ROLE_ORDER[b.role] or 9
            if ra ~= rb then return ra < rb end
            return a.class < b.class
        end)

        return roleSpecs, lookingForSpecs, selectedClasses, classNeeds
    end

    -- While Detailed mode is active, the class grid's checked per-spec counts
    -- are authoritative: mirror their sums into the (hidden) composition-row
    -- inputs so BuildConfig's [x/y] segment can never disagree with the
    -- [Need:] block, and so switching back to Compact shows correct numbers.
    -- No-ops outside Detailed mode - Compact-mode manual edits are untouched.
    local function SyncCompositionFromClassGrid()
        if popup.detailMode ~= "detailed" then return end
        local tankSum, healSum, mdpsSum, rdpsSum = 0, 0, 0, 0
        for _, check in pairs(popup.classChecks.TANK or {}) do
            if check:GetChecked() and check.countInput then
                tankSum = tankSum + (tonumber(check.countInput:GetText()) or 0)
            end
        end
        for _, check in pairs(popup.classChecks.HEALER or {}) do
            if check:GetChecked() and check.countInput then
                healSum = healSum + (tonumber(check.countInput:GetText()) or 0)
            end
        end
        for _, check in pairs(popup.classChecks.DPS or {}) do
            if check:GetChecked() and check.countInput and check.specData then
                local n = tonumber(check.countInput:GetText()) or 0
                if check.specData.melee then mdpsSum = mdpsSum + n else rdpsSum = rdpsSum + n end
            end
        end
        popup.tankInput:SetText(tostring(tankSum))
        popup.healInput:SetText(tostring(healSum))
        popup.mdpsInput:SetText(tostring(mdpsSum))
        popup.rdpsInput:SetText(tostring(rdpsSum))
    end
    popup.SyncCompositionFromClassGrid = SyncCompositionFromClassGrid

    -- Build the LFM config table off the current popup state. Minimal and
    -- Compact strip every class-level detail: the message and the listing
    -- carry only the [x/y] + [T:x/y ...] role counts (FitEngine then skips
    -- spec/class scoring - all its class checks are nil-guarded).
    local function BuildConfig()
        local roleSpecs, lookingForSpecs, selectedClasses, classNeeds = CollectRoleSpecs()
        if popup.detailMode ~= "detailed" then
            -- Minimal and Compact both broadcast role counts only - neither
            -- shows the class grid, so neither should carry stale class
            -- detail from whatever was last checked while Detailed was active.
            roleSpecs, lookingForSpecs, selectedClasses, classNeeds = nil, {}, nil, nil
        end
        local achieveLink = ""
        if popup.selectedAchievement then
            achieveLink = GetAchievementLink(popup.selectedAchievement) or ""
        end
        local inviteKeyword = popup.keywordInput:GetText()
        if not inviteKeyword or inviteKeyword == "" then
            inviteKeyword = AIP.db and AIP.db.triggers or "invme-auto"
        end
        return {
            raidKey = GetRaidKey(),
            weekly = popup.weeklyToken,
            tanks = {current = 0, needed = tonumber(popup.tankInput:GetText()) or 2},
            healers = {current = 0, needed = tonumber(popup.healInput:GetText()) or 6},
            mdps = {current = 0, needed = tonumber(popup.mdpsInput:GetText()) or 8},
            rdps = {current = 0, needed = tonumber(popup.rdpsInput:GetText()) or 9},
            gsMin = tonumber(popup.gsInput:GetText()) or 0,
            ilvlMin = tonumber(popup.ilvlInput:GetText()) or 0,
            roleSpecs = roleSpecs,
            classNeeds = classNeeds,  -- straight from the per-spec count boxes
            keyword = inviteKeyword,
            achievementLink = achieveLink,
            note = popup.noteInput:GetText() or "",
            reservedItems = AIP.db and AIP.db.reservedItems or "",
        }, roleSpecs, lookingForSpecs, selectedClasses
    end

    -- One-line "Need (x/y): 2xMag 1xPP +3" summary rendered from the ACTUAL
    -- count boxes (cfg.classNeeds); mirrored into the collapsed hint. Driven
    -- from RefreshPreview so every count/checkbox edit refreshes it.
    local function RenderNeedsSummary(classNeeds)
        if popup.detailMode == "minimal" then
            local minimalTxt = "|cFF888888Minimal listing: only the note is broadcast.|r"
            needsText:SetText(minimalTxt)
            if popup.collapsedNeedsText then popup.collapsedNeedsText:SetText(minimalTxt) end
            return
        end
        if popup.detailMode == "compact" then
            local compactTxt = "|cFF888888Compact listing: role counts only - any class can apply.|r"
            needsText:SetText(compactTxt)
            if popup.collapsedNeedsText then popup.collapsedNeedsText:SetText(compactTxt) end
            return
        end
        local meta = popup.classNeedsMeta
        local head = "|cFFFFCC00Need|r"
        if meta and meta.total then
            head = head .. " |cFF888888(" .. (meta.occupied or 0) .. "/" .. (meta.total or 0) .. ")|r"
        end
        local LFm = AIP.LFMFormat
        -- UI-only compactness cap for this one-line summary; unrelated to the
        -- broadcast text, which is uncapped (see LF.ClassNeedString).
        local maxParts = 5
        local parts, extra = {}, 0
        for _, row in ipairs(classNeeds or {}) do
            if (row.count or 0) > 0 then
                if #parts < maxParts then
                    parts[#parts + 1] = row.count .. "x" .. (LFm and LFm.NeedCode(row.class, row.role) or row.class)
                else
                    extra = extra + row.count
                end
            end
        end
        local txt
        if #parts == 0 then
            txt = head .. ": |cFF888888no counts set - use the boxes above (0 = any)|r"
        else
            txt = head .. ": " .. table.concat(parts, " ")
            if extra > 0 then txt = txt .. " |cFF888888+" .. extra .. "|r" end
        end
        needsText:SetText(txt)
        if popup.collapsedNeedsText then popup.collapsedNeedsText:SetText(txt) end
    end

    RefreshPreview = function()
        if not AIP.LFMFormat then return end
        local cfg = BuildConfig()
        local msg, trimmed = AIP.LFMFormat.BuildLFM(cfg)
        previewText:SetText(msg)
        RenderNeedsSummary(cfg.classNeeds)

        -- Schedule line: the real rotor math, so the pacing is visible
        local targets = GUI.BuildBroadcastTargets and GUI.BuildBroadcastTargets("lfm") or {}
        local names = {}
        for _, t in ipairs(targets) do
            names[#names + 1] = t.kind == "CHANNEL" and t.name or t.kind
        end
        local interval = (AIP.db and AIP.db.autoSpamInterval) or 90
        local spacing = math.max(15, math.floor(interval / math.max(1, #targets)))
        local line = "Sends to: " .. (#names > 0 and table.concat(names, ", ") or "-")
            .. "  -  one channel every " .. spacing .. "s, each ~" .. math.max(interval, spacing * math.max(1, #targets)) .. "s"
        if trimmed and #trimmed > 0 then
            line = line .. "  |cFFFF6666(trimmed: " .. table.concat(trimmed, ", ") .. ")|r"
        end
        scheduleText:SetText(line)
    end
    popup.RefreshPreview = RefreshPreview

    -- Auto-select the Looking-For checkboxes AND prefill the count boxes from
    -- the template recommendations (the tandem "autoselect"). The class's
    -- recommended count goes on its FIRST spec box in the role; other specs of
    -- the same class stay checked with 0 (spec-flexible, counted once).
    local function ApplyRecommendedSpecs(needs)
        if not (needs and needs.ok and needs.list and #needs.list > 0) then return end
        local wanted = {}   -- wanted[role][class] = count left to assign
        for _, row in ipairs(needs.list) do
            wanted[row.role] = wanted[row.role] or {}
            wanted[row.role][row.class] = (wanted[row.role][row.class] or 0) + (row.count or 0)
        end
        for roleKey, group in pairs(popup.classChecks) do
            local roleWanted = wanted[roleKey]
            for _, check in pairs(group) do
                local cls = check.specData and check.specData.class
                local n = roleWanted and cls and roleWanted[cls] or nil
                check:SetChecked(n and true or false)  -- n == 0 still checked (spec-flexible)
                if check.countInput then
                    if n and n > 0 then
                        check.countInput:SetText(tostring(n))
                        roleWanted[cls] = 0
                    else
                        check.countInput:SetText("0")
                    end
                end
            end
        end
    end

    -- Recompute the recommendation rows vs the LIVE group for the currently
    -- selected raid (prefill source + occupied/total meta). Auto-selection
    -- only fires the first time a given template is picked (lastAutoSelectKey)
    -- - a heroic or size toggle back must not wipe manual counts.
    local function UpdateClassNeeds(autoSelect)
        local Comp = AIP.Composition
        popup.classNeeds = nil
        popup.classNeedsMeta = nil
        local templateKey = Comp and Comp.TemplateKeyForRaid
            and Comp.TemplateKeyForRaid(GetRaidKey()) or nil
        if templateKey and Comp.GetClassNeeds then
            -- BINDING: the popup's raid selection IS the Composition tab's
            -- active template (and vice versa via GUI.SyncPopupToTemplate).
            -- Only while the popup is actually SHOWN - merely creating or
            -- re-opening it must not hijack the tab (GetClassNeeds computes
            -- non-destructively via save/restore in that case).
            if Comp.SetTemplate and Comp.CurrentRaid
                and Comp.CurrentRaid.template ~= templateKey
                and popup:IsShown() then
                Comp.SetTemplate(templateKey, true)
                if GUI.UpdateCompositionTab then GUI.UpdateCompositionTab() end
            end
            local needs = Comp.GetClassNeeds(templateKey)
            if needs.ok then
                popup.classNeeds = needs.list
                popup.classNeedsMeta = {occupied = needs.occupied, total = needs.total,
                    templateKey = needs.templateKey}
                if autoSelect and popup.lastAutoSelectKey ~= needs.templateKey then
                    popup.lastAutoSelectKey = needs.templateKey
                    ApplyRecommendedSpecs(needs)
                end
            end
        end
    end
    popup.UpdateClassNeeds = UpdateClassNeeds

    ApplyTemplateDefaults = function()
        local raidKey = GetRaidKey()
        -- GetRaidKey() returns the free-typed custom name (or literal "Custom")
        -- for raidType == "CUSTOM" - never the canonical "CUSTOM" key
        -- GUI.RaidTemplateDefaults.CUSTOM actually uses, so look that up
        -- explicitly or switching to Custom would silently keep whatever
        -- numeric fields the previously-selected raid template left behind.
        local defaultsKey = (popup.raidType == "CUSTOM") and "CUSTOM" or raidKey
        local defaults = GUI.RaidTemplateDefaults[defaultsKey]
        if defaults then
            popup.tankInput:SetText(tostring(defaults.tanks))
            popup.healInput:SetText(tostring(defaults.healers))
            local mdps = defaults.mdps or math.floor((defaults.dps or 0) / 2)
            local rdps = defaults.rdps or math.ceil((defaults.dps or 0) / 2)
            popup.mdpsInput:SetText(tostring(mdps))
            popup.rdpsInput:SetText(tostring(rdps))
            popup.gsInput:SetText(tostring(defaults.gs))
            popup.ilvlInput:SetText(tostring(defaults.ilvl))
        end
        GUI.UpdateAchievementDropdown(popup, raidKey)
        popup.selectedRaid = raidKey
        UpdateCustomFieldVisibility()
        UpdateLockoutWarning()
        UpdateWeeklyStrip()
        UpdateClassNeeds(true)
        -- UpdateClassNeeds(true) just ran ApplyRecommendedSpecs, which set the
        -- per-spec count boxes from the template's recommendation - sync the
        -- (hidden while Detailed is active) composition-row mirror to match
        -- immediately, not just after the next manual class-grid edit.
        if popup.detailMode == "detailed" and popup.SyncCompositionFromClassGrid then
            popup.SyncCompositionFromClassGrid()
        end
        RefreshPreview()
    end
    popup.ApplyTemplateDefaults = ApplyTemplateDefaults

    -- Expansion toggle: collapsed = preset tiles, expanded = the full form
    local function SetExpanded(expanded)
        popup.expanded = expanded
        if expanded then
            quickLabel:Hide()
            for _, tile in pairs(popup.presetTiles) do tile:Hide() end
            if popup.collapsedNeedsText then popup.collapsedNeedsText:Hide() end
            detail:Show()
            -- expandedHeightForMode is always set by the ApplyDetailMode()
            -- call in the construction sequence before this can ever run
            -- (the popup starts collapsed, so this is the earliest SetExpanded(true)
            -- can fire) - the static EXPANDED_HEIGHT fallback is an unreachable
            -- safety net, kept only in case that construction order ever changes.
            popup:SetHeight(popup.expandedHeightForMode or EXPANDED_HEIGHT)
            customizeText:SetText("|cFF66AAFF[-] Hide details|r")
        else
            quickLabel:Show()
            popup.RefreshTiles()
            if popup.collapsedNeedsText then popup.collapsedNeedsText:Show() end
            detail:Hide()
            popup:SetHeight(COLLAPSED_HEIGHT)
            customizeText:SetText("|cFF66AAFF[+] Customize...|r")
        end
    end
    popup.SetExpanded = SetExpanded
    customizeBtn:SetScript("OnClick", function() SetExpanded(not popup.expanded) end)

    -- Apply a preset config to all fields
    local function ApplyPreset(cfg)
        if not cfg then return end
        popup.raidType = cfg.raidType or "ICC"
        popup.raidSize = cfg.raidSize or "25"
        popup.heroicCheck:SetChecked(cfg.heroic and true or false)
        popup.weeklyToken = cfg.weekly
        UpdateSizeDropdown()
        UIDropDownMenu_SetText(sizeDropdown, popup.raidSize)
        UpdateRaidDropdownText()
        ApplyTemplateDefaults()
        -- Preset-specific overrides on top of the template defaults
        if cfg.tanks then popup.tankInput:SetText(tostring(cfg.tanks)) end
        if cfg.healers then popup.healInput:SetText(tostring(cfg.healers)) end
        if cfg.mdps then popup.mdpsInput:SetText(tostring(cfg.mdps)) end
        if cfg.rdps then popup.rdpsInput:SetText(tostring(cfg.rdps)) end
        if cfg.gs then popup.gsInput:SetText(tostring(cfg.gs)) end
        if cfg.ilvl then popup.ilvlInput:SetText(tostring(cfg.ilvl)) end
        if cfg.keyword then popup.keywordInput:SetText(cfg.keyword) end
        if cfg.note then popup.noteInput:SetText(cfg.note) end
        -- The composition overrides above are stale/wrong in Detailed mode -
        -- BuildConfig takes [x/y] from these inputs but classNeeds from the
        -- class grid, so without this resync a "Last"/preset tile applied
        -- while Detailed is active could post totals that disagree with the
        -- grid's own [Need:] breakdown. No-ops outside Detailed.
        if popup.detailMode == "detailed" and popup.SyncCompositionFromClassGrid then
            popup.SyncCompositionFromClassGrid()
        end
        RefreshPreview()
    end
    popup.ApplyPreset = ApplyPreset

    -- Refresh the three preset tiles' labels/actions
    function popup.RefreshTiles()
        local tiles = popup.presetTiles

        -- Tile 1: last used
        local last = AIP.db and AIP.db.lastListingConfig
        if last and last.raidType then
            local key = (last.raidType or "?") .. (last.raidSize or "") .. (last.heroic and "H" or "N")
            tiles.last.titleText:SetText("|cFFFFD100* Last|r")
            tiles.last.subText:SetText(key .. (last.gs and ("  " .. last.gs .. "+") or ""))
            tiles.last.tooltip = "Repeat your last listing"
            tiles.last:SetScript("OnClick", function() ApplyPreset(last) end)
            tiles.last:Show()
        else
            tiles.last.titleText:SetText("|cFF888888* Last|r")
            tiles.last.subText:SetText("|cFF666666(none yet)|r")
            tiles.last.tooltip = "Post a listing once and it appears here"
            tiles.last:SetScript("OnClick", nil)
            tiles.last:Show()
        end

        -- Tile 2: this week's raid quest
        local held = AIP.Weekly and AIP.Weekly.Current()
        if held then
            tiles.weekly.titleText:SetText("|cFF33CCFF[W] Weekly|r")
            tiles.weekly.subText:SetText(held.quest.boss:sub(1, 18))
            tiles.weekly.tooltip = held.quest.title .. " (" .. held.quest.raid .. ")"
            tiles.weekly:SetScript("OnClick", function()
                ApplyPreset({ raidType = held.quest.raid, raidSize = "10", heroic = false, weekly = held.quest.token })
            end)
        else
            tiles.weekly.titleText:SetText("|cFF888888[W] Weekly|r")
            tiles.weekly.subText:SetText("|cFF666666not in log|r")
            tiles.weekly.tooltip = "Pick up the weekly raid quest from Archmage Lan'dalock in Dalaran"
            tiles.weekly:SetScript("OnClick", nil)
        end
        tiles.weekly:Show()

        -- Tile 3: fresh default
        tiles.fresh.titleText:SetText("ICC25H")
        tiles.fresh.subText:SetText("Fresh  5800+")
        tiles.fresh.tooltip = "Standard ICC25 Heroic listing"
        tiles.fresh:SetScript("OnClick", function()
            ApplyPreset({ raidType = "ICC", raidSize = "25", heroic = true })
        end)
        tiles.fresh:Show()
    end

    -- Live preview refresh on any text change
    for _, input in ipairs({tankInput, healInput, mdpsInput, rdpsInput, gsInput, ilvlInput, noteInput, keywordInput, customInput}) do
        input:HookScript("OnTextChanged", function() RefreshPreview() end)
    end
    heroicCheck:SetScript("OnClick", function() ApplyTemplateDefaults() end)

    -- ========================================================================
    -- BUTTONS
    -- ========================================================================
    local createBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    createBtn:SetSize(100, 24)
    createBtn:SetPoint("BOTTOM", popup, "BOTTOM", -60, 16)  -- pair centered in the 500-wide popup
    createBtn:SetText("Post Group")
    createBtn:SetScript("OnClick", function()
        local raidKey = GetRaidKey()
        if not raidKey then
            AIP.Print("Please configure raid settings")
            return
        end
        if not AIP.LFMFormat then
            AIP.Print("LFMFormat module missing - cannot build the listing message")
            return
        end

        local cfg, roleSpecs, lookingForSpecs, selectedClasses = BuildConfig()
        local msg, trimmed = AIP.LFMFormat.BuildLFM(cfg)
        if trimmed and #trimmed > 0 then
            AIP.Print("|cFFFFFF00Listing trimmed to fit chat:|r dropped " .. table.concat(trimmed, ", "))
        end

        local gsValue = cfg.gsMin
        local ilvlValue = cfg.ilvlMin
        local inviteKeyword = cfg.keyword
        local noteText = cfg.note
        local reservedItems = cfg.reservedItems
        local lootBans = AIP.db and AIP.db.lootBans or {}

        if AIP.GroupTracker and AIP.GroupTracker.AddGroup then
            AIP.GroupTracker.AddGroup({
                leader = UnitName("player"),
                raid = raidKey,
                weekly = popup.weeklyToken,
                message = msg,
                gsMin = gsValue,
                ilvlMin = ilvlValue,
                tanks = {current = 0, needed = cfg.tanks.needed},
                healers = {current = 0, needed = cfg.healers.needed},
                mdps = {current = 0, needed = cfg.mdps.needed},
                rdps = {current = 0, needed = cfg.rdps.needed},
                achievementId = popup.selectedAchievement,
                inviteKeyword = inviteKeyword,
                selectedClasses = selectedClasses,
                lookingForSpecs = lookingForSpecs,
                roleSpecs = roleSpecs,
                classNeeds = cfg.classNeeds,
                detailMode = popup.detailMode,
                templateKey = popup.classNeedsMeta and popup.classNeedsMeta.templateKey,
                note = noteText,
                reservedItems = reservedItems,
                lootBans = lootBans,
                isOwn = true,
                time = time(),
            })
        end

        -- Store our active LFM data for matching incoming LFG players
        GUI.MyGroup = {
            raid = raidKey,
            weekly = popup.weeklyToken,
            gsMin = gsValue,
            ilvlMin = ilvlValue,
            tanks = {current = 0, needed = cfg.tanks.needed},
            healers = {current = 0, needed = cfg.healers.needed},
            mdps = {current = 0, needed = cfg.mdps.needed},
            rdps = {current = 0, needed = cfg.rdps.needed},
            inviteKeyword = inviteKeyword,
            selectedClasses = selectedClasses,
            roleSpecs = roleSpecs,
            classNeeds = cfg.classNeeds,
            detailMode = popup.detailMode,
            templateKey = popup.classNeedsMeta and popup.classNeedsMeta.templateKey,
            note = noteText,
            time = time(),
        }

        -- Ensure the tandem binding at Post time: normally the live binding in
        -- UpdateClassNeeds already did this while the popup was shown; this
        -- covers the quick-post path where no selection was touched.
        if AIP.Composition and AIP.Composition.SetTemplate
            and popup.classNeedsMeta and popup.classNeedsMeta.templateKey
            and AIP.Composition.CurrentRaid
            and AIP.Composition.CurrentRaid.template ~= popup.classNeedsMeta.templateKey then
            AIP.Composition.SetTemplate(popup.classNeedsMeta.templateKey, true)
        end

        -- Baseline for live [Need:] decrementing: the posted counts plus a
        -- snapshot of the group's class counts at post time. Broadcast
        -- regeneration subtracts newly-joined classes from these counts, so
        -- the leader's manual numbers are honored (not recomputed away).
        GUI.MyGroup.classNeedsBase = cfg.classNeeds
        if AIP.Composition and AIP.Composition.ScanRaid then
            local raid = AIP.Composition.ScanRaid()
            local snap = {}
            for class, n in pairs((raid and raid.classCounts) or {}) do snap[class] = n end
            GUI.MyGroup.classCountsAtPost = snap
        end
        -- Stable ratio for splitting the live DPS remainder back across
        -- mdps/rdps (RegenerateBroadcastMessage) - captured once here and
        -- never mutated, so repeated regenerations don't read back their
        -- own previous output as the split source.
        GUI.MyGroup.dpsSplitBase = {mdps = cfg.mdps.needed, rdps = cfg.rdps.needed}

        -- Remember this config for the Quick Post "Last" tile
        if AIP.db then
            AIP.db.lastListingConfig = {
                raidType = popup.raidType,
                raidSize = popup.raidSize,
                heroic = popup.heroicCheck:GetChecked() and true or false,
                weekly = popup.weeklyToken,
                tanks = cfg.tanks.needed,
                healers = cfg.healers.needed,
                mdps = cfg.mdps.needed,
                rdps = cfg.rdps.needed,
                gs = gsValue,
                ilvl = ilvlValue,
                keyword = inviteKeyword,
                note = noteText,
            }
        end

        if AIP.SetPlayerMode then
            AIP.SetPlayerMode("lfm")
        end

        if popup.broadcastCheck:GetChecked() then
            AIP.db.spamMessage = msg
            GUI.StartBroadcast("lfm", msg, AIP.db.autoSpamInterval or 90)
        end

        popup:Hide()
        GUI.RefreshBrowserTab("lfm")
        AIP.Print("Group listing created for " .. raidKey ..
            (popup.weeklyToken and (" |cFF33CCFF[Weekly: " .. popup.weeklyToken .. "]|r") or "") ..
            "!" .. (popup.broadcastCheck:GetChecked() and " |cFF00FF00Auto-broadcasting started.|r" or ""))
    end)

    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("LEFT", createBtn, "RIGHT", 20, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Hide BEFORE the initial ApplyTemplateDefaults() call: CreateFrame frames
    -- default to shown, so UpdateClassNeeds' popup:IsShown() check (meant to
    -- gate the tab-sync to real user interaction) would otherwise see the
    -- brand-new popup as "shown" during construction and silently hijack the
    -- Composition tab to the popup's default raid on the very first open.
    popup:Hide()

    -- Apply initial defaults, start collapsed (preset-first)
    UpdateSizeDropdown()
    UpdateRaidDropdownText()
    ApplyTemplateDefaults()
    if popup.ApplyDetailMode then popup.ApplyDetailMode(popup.detailMode) end
    if popup.UpdateModeButtonHighlight then popup.UpdateModeButtonHighlight() end
    SetExpanded(false)
    tinsert(UISpecialFrames, "AIPAddGroupPopup")
    GUI.AddGroupPopup = popup
end

-- Update achievement dropdown based on selected raid
function GUI.UpdateAchievementDropdown(popup, raidKey)
    if not popup or not popup.achieveDropdown then return end

    local achievements = GUI.RaidAchievements[raidKey] or {}
    -- GetRaidKey() appends an H/N difficulty suffix (and uses TOGC for heroic
    -- ToC), but RaidAchievements keys most raids without it (only ICC/RS carry
    -- the suffix). Normalize so ULDUAR/NAXX/VOA/TOC resolve.
    if #achievements == 0 and raidKey then
        local altKey = raidKey:gsub("^TOGC", "TOC")
        altKey = altKey:gsub("([0-9]+)[HN]$", "%1")
        achievements = GUI.RaidAchievements[altKey] or {}
    end

    UIDropDownMenu_Initialize(popup.achieveDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "None"
        info.value = nil
        info.func = function()
            popup.selectedAchievement = nil
            UIDropDownMenu_SetText(popup.achieveDropdown, "None")
            if popup.RefreshPreview then popup.RefreshPreview() end
        end
        UIDropDownMenu_AddButton(info)

        for _, achieve in ipairs(achievements) do
            info = UIDropDownMenu_CreateInfo()
            info.text = achieve.name
            info.value = achieve.id
            info.func = function()
                popup.selectedAchievement = achieve.id
                UIDropDownMenu_SetText(popup.achieveDropdown, achieve.name)
                if popup.RefreshPreview then popup.RefreshPreview() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_SetText(popup.achieveDropdown, "None")
    popup.selectedAchievement = nil
end

-- Show Enroll popup
function GUI.ShowEnrollPopup()
    if not GUI.EnrollPopup then
        GUI.CreateEnrollPopup()
    end
    -- Restore the last enrollment config (raid/size/heroic/weekly)
    local last = AIP.db and AIP.db.lastEnrollConfig
    if last and last.raidType then
        GUI.EnrollPopup.raidType = last.raidType
        GUI.EnrollPopup.raidSize = last.raidSize or GUI.EnrollPopup.raidSize
        if GUI.EnrollPopup.heroicCheck then
            GUI.EnrollPopup.heroicCheck:SetChecked(last.heroic and true or false)
        end
        GUI.EnrollPopup.weeklyToken = last.weekly
    end
    -- Update size dropdown for current raid selection
    if GUI.EnrollPopup.UpdateSizeDropdown then
        GUI.EnrollPopup.UpdateSizeDropdown()
    end
    -- Update raid dropdown text with lockout color
    if GUI.EnrollPopup.UpdateRaidDropdownText then
        GUI.EnrollPopup.UpdateRaidDropdownText()
    end
    if GUI.EnrollPopup.UpdateWeeklyStrip then
        GUI.EnrollPopup.UpdateWeeklyStrip()
    end
    GUI.EnrollPopup:Show()
end

-- Spec names by class for WotLK 3.3.5a (fallback)
GUI.ClassSpecNames = {
    WARRIOR = {"Arms", "Fury", "Protection"},
    PALADIN = {"Holy", "Protection", "Retribution"},
    HUNTER = {"Beast Mastery", "Marksmanship", "Survival"},
    ROGUE = {"Assassination", "Combat", "Subtlety"},
    PRIEST = {"Discipline", "Holy", "Shadow"},
    DEATHKNIGHT = {"Blood", "Frost", "Unholy"},
    SHAMAN = {"Elemental", "Enhancement", "Restoration"},
    MAGE = {"Arcane", "Fire", "Frost"},
    WARLOCK = {"Affliction", "Demonology", "Destruction"},
    DRUID = {"Balance", "Feral Combat", "Restoration"},
}

-- Get player's spec name with improved WotLK 3.3.5a dual spec support
function GUI.GetPlayerSpecName()
    local _, playerClass = UnitClass("player")
    local specNames = GUI.ClassSpecNames[playerClass] or {"Unknown", "Unknown", "Unknown"}

    -- WotLK 3.3.5a dual spec: Get active talent group first (1 = Primary, 2 = Secondary)
    local activeTalentGroup = GetActiveTalentGroup and GetActiveTalentGroup() or 1

    -- Check which tree has most points in the ACTIVE talent group
    local maxPoints = 0
    local specIndex = 1
    local specName = nil

    local numTabs = GetNumTalentTabs() or 3
    if numTabs and numTabs > 0 then
        for i = 1, numTabs do
            -- GetTalentTabInfo(tabIndex, inspect, pet, talentGroup)
            -- In WotLK 3.3.5a, passing the talentGroup parameter gets the correct spec
            local name, iconTexture, pointsSpent
            if activeTalentGroup then
                name, iconTexture, pointsSpent = GetTalentTabInfo(i, false, false, activeTalentGroup)
            else
                name, iconTexture, pointsSpent = GetTalentTabInfo(i)
            end

            if pointsSpent and pointsSpent > maxPoints then
                maxPoints = pointsSpent
                specIndex = i
                -- Verify name is valid (not an icon path or empty)
                if name and name ~= "" and not name:find("Interface") and not name:find("\\") then
                    specName = name
                end
            end
        end
    end

    -- If we found a valid spec name from the API, return it
    if specName then
        return specName
    end

    -- Fallback: Use spec names lookup based on spec index
    if specIndex >= 1 and specIndex <= 3 then
        return specNames[specIndex]
    end

    -- Final fallback: Try GetPrimaryTalentTree (should return tree index for highest points)
    if GetPrimaryTalentTree then
        -- GetPrimaryTalentTree(isInspect, talentGroup) - get for active group
        local primaryTree = GetPrimaryTalentTree(false, activeTalentGroup)
        if primaryTree and primaryTree >= 1 and primaryTree <= 3 then
            return specNames[primaryTree]
        end
    end

    return specNames[1] or "Unknown"
end

-- Get player's spec index (1, 2, or 3 corresponding to talent tree)
function GUI.GetPlayerSpecIndex()
    local activeTalentGroup = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    local maxPoints = 0
    local specIndex = 1

    local numTabs = GetNumTalentTabs() or 3
    for i = 1, numTabs do
        local _, _, pointsSpent = GetTalentTabInfo(i, false, false, activeTalentGroup)
        if pointsSpent and pointsSpent > maxPoints then
            maxPoints = pointsSpent
            specIndex = i
        end
    end

    return specIndex
end

-- Auto-detect player's role based on class and talent spec
function GUI.DetectPlayerRole()
    local _, class = UnitClass("player")

    -- Get active talent spec (WotLK API)
    local specName = GUI.GetPlayerSpecName()

    -- Map class/spec to role
    local roleMap = {
        WARRIOR = {["Protection"] = "TANK", ["Arms"] = "DPS", ["Fury"] = "DPS"},
        PALADIN = {["Protection"] = "TANK", ["Holy"] = "HEALER", ["Retribution"] = "DPS"},
        DEATHKNIGHT = {["Blood"] = "TANK", ["Frost"] = "DPS", ["Unholy"] = "DPS"},
        DRUID = {["Feral Combat"] = "DPS", ["Restoration"] = "HEALER", ["Balance"] = "DPS"},  -- Feral tab is both cat (DPS) & bear; default to the common case (DPS)
        PRIEST = {["Holy"] = "HEALER", ["Discipline"] = "HEALER", ["Shadow"] = "DPS"},
        SHAMAN = {["Restoration"] = "HEALER", ["Elemental"] = "DPS", ["Enhancement"] = "DPS"},
        MAGE = "DPS",
        WARLOCK = "DPS",
        HUNTER = "DPS",
        ROGUE = "DPS",
    }

    local classRole = roleMap[class]
    if type(classRole) == "string" then
        return classRole
    elseif type(classRole) == "table" then
        return classRole[specName] or "DPS"
    end

    return "DPS"
end

-- Calculate player's GearScore (using GearScore addon if available)
function GUI.CalculatePlayerGS()
    local playerName = UnitName("player")

    -- Try GearScore addon first (same as GearScoreLite uses)
    if GearScore_GetScore then
        local gs, ilvl = GearScore_GetScore(playerName, "player")
        if gs and gs > 0 then
            return gs, ilvl
        end
    end

    -- Try PlayerScore addon
    if PlayerScore_GetScore then
        local ps = PlayerScore_GetScore(playerName)
        if ps and ps > 0 then
            return ps
        end
    end

    -- Fallback: Use Integrations module if available
    if AIP.Integrations and AIP.Integrations.GetGearScore then
        local gs, source, ilvl = AIP.Integrations.GetGearScore(playerName)
        if gs and gs > 0 then
            return gs, ilvl
        end
    end

    -- Final fallback: estimate from equipped item levels
    local totalIlvl = 0
    local slotCount = 0
    local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18}

    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local _, _, _, ilvl = GetItemInfo(link)
            if ilvl then
                totalIlvl = totalIlvl + ilvl
                slotCount = slotCount + 1
            end
        end
    end

    if slotCount > 0 then
        local avgIlvl = totalIlvl / slotCount
        -- Rough GS estimate: avgIlvl * 25 (approximate conversion)
        return math.floor(avgIlvl * 25), math.floor(avgIlvl)
    end

    return 4000, 200 -- Default fallback
end

-- Calculate player's average item level
function GUI.CalculatePlayerIlvl()
    local totalIlvl = 0
    local slotCount = 0
    local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}

    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local _, _, _, ilvl = GetItemInfo(link)
            if ilvl then
                totalIlvl = totalIlvl + ilvl
                slotCount = slotCount + 1
            end
        end
    end

    if slotCount > 0 then
        return math.floor(totalIlvl / slotCount)
    end

    return 200 -- Default fallback
end

-- Raid instance grouping - all variants of same instance
GUI.RaidInstanceVariants = {
    ICC = {"ICC25H", "ICC25N", "ICC10H", "ICC10N"},
    RS = {"RS25H", "RS25N", "RS10H", "RS10N"},
    TOC = {"TOGC25", "TOGC10", "TOC25", "TOC10"},
    VOA = {"VOA25", "VOA10"},
    ULDUAR = {"ULDUAR25", "ULDUAR10"},
    NAXX = {"NAXX25", "NAXX10"},
    EoE = {"EoE25", "EoE10"},
    OS = {"OS25", "OS10"},
    ONY = {"ONY25", "ONY10"},
}

-- Map specific raid keys to their instance group
GUI.RaidToInstance = {
    ICC25H = "ICC", ICC25N = "ICC", ICC10H = "ICC", ICC10N = "ICC", ICC25 = "ICC", ICC10 = "ICC", ICC = "ICC",
    RS25H = "RS", RS25N = "RS", RS10H = "RS", RS10N = "RS", RS25 = "RS", RS10 = "RS", RS = "RS",
    TOGC25 = "TOC", TOGC10 = "TOC", TOC25 = "TOC", TOC10 = "TOC", TOC25N = "TOC", TOC10N = "TOC", TOC = "TOC", TOGC = "TOC",
    VOA25 = "VOA", VOA10 = "VOA", VOA25N = "VOA", VOA25H = "VOA", VOA10N = "VOA", VOA10H = "VOA", VOA = "VOA",
    ULDUAR25 = "ULDUAR", ULDUAR10 = "ULDUAR", ULDUAR25N = "ULDUAR", ULDUAR25H = "ULDUAR", ULDUAR10N = "ULDUAR", ULDUAR10H = "ULDUAR", ULDUAR = "ULDUAR",
    NAXX25 = "NAXX", NAXX10 = "NAXX", NAXX25N = "NAXX", NAXX25H = "NAXX", NAXX10N = "NAXX", NAXX10H = "NAXX", NAXX = "NAXX",
    EoE25 = "EoE", EoE10 = "EoE", EoE = "EoE",
    OS25 = "OS", OS10 = "OS", OS = "OS",
    ONY25 = "ONY", ONY10 = "ONY", ONY = "ONY",
}

-- Get player's best achievement for a raid instance (checks all variants, returns best)
function GUI.GetPlayerAchievementsForRaid(raidKey)
    if not raidKey then return {} end

    -- Find the instance group for this raid key
    local instanceGroup = GUI.RaidToInstance[raidKey]

    -- Get all variant keys to check (ordered by prestige: 25H > 25N > 10H > 10N)
    local keysToCheck
    if instanceGroup and GUI.RaidInstanceVariants[instanceGroup] then
        keysToCheck = GUI.RaidInstanceVariants[instanceGroup]
    else
        -- Fallback: just check the exact key
        keysToCheck = {raidKey}
    end

    -- Collect ALL completed achievements across all variants
    local playerHas = {}

    for _, key in ipairs(keysToCheck) do
        local achievements = GUI.RaidAchievements[key] or {}
        for _, achieve in ipairs(achievements) do
            local _, name, _, completed = GetAchievementInfo(achieve.id)
            if completed then
                table.insert(playerHas, {id = achieve.id, name = name or achieve.name, raidKey = key})
                -- Only take first (best) achievement per variant
                break
            end
        end
    end

    -- Already sorted by prestige due to keysToCheck order (25H first, etc.)
    return playerHas
end

function GUI.CreateEnrollPopup()
    local popup = CreateFrame("Frame", "AIPEnrollPopup", UIParent)
    popup:SetSize(400, 480)  -- Optimized size for content
    popup:SetPoint("CENTER", 220, 0)  -- Offset right so it doesn't overlap with Add Group popup
    popup:SetFrameStrata("DIALOG")
    AIP.UI.MakeDraggable(popup)
    popup:SetClampedToScreen(true)
    GUI.StylePopup(popup)

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Enroll as Looking for Group")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local y = -45

    -- === Player Info Section ===
    local playerLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerLabel:SetPoint("TOPLEFT", 20, y)
    playerLabel:SetText("Your Character:")

    local _, class = UnitClass("player")
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local playerName = UnitName("player")

    local playerInfo = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    playerInfo:SetPoint("LEFT", playerLabel, "RIGHT", 10, 0)
    if classColor then
        playerInfo:SetTextColor(classColor.r, classColor.g, classColor.b)
    end
    playerInfo:SetText(playerName .. " (" .. (class or "Unknown") .. ")")
    y = y - 25

    -- Auto-detected stats display
    local statsFrame = CreateFrame("Frame", nil, popup)
    statsFrame:SetSize(360, 40)
    statsFrame:SetPoint("TOPLEFT", 20, y)
    GUI.ApplyBackdrop(statsFrame, "Inset", 0.8)

    local gsDisplayLabel = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gsDisplayLabel:SetPoint("TOPLEFT", 10, -8)
    gsDisplayLabel:SetText("GearScore:")
    gsDisplayLabel:SetTextColor(0.7, 0.7, 0.7)

    local gsDisplayValue = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    gsDisplayValue:SetPoint("LEFT", gsDisplayLabel, "RIGHT", 5, 0)
    popup.gsDisplayValue = gsDisplayValue

    local ilvlDisplayLabel = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlDisplayLabel:SetPoint("LEFT", gsDisplayValue, "RIGHT", 20, 0)
    ilvlDisplayLabel:SetText("Avg iLvl:")
    ilvlDisplayLabel:SetTextColor(0.7, 0.7, 0.7)

    local ilvlDisplayValue = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ilvlDisplayValue:SetPoint("LEFT", ilvlDisplayLabel, "RIGHT", 5, 0)
    popup.ilvlDisplayValue = ilvlDisplayValue

    local roleDisplayLabel = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleDisplayLabel:SetPoint("TOPLEFT", 10, -24)
    roleDisplayLabel:SetText("Detected Role:")
    roleDisplayLabel:SetTextColor(0.7, 0.7, 0.7)

    local roleDisplayValue = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    roleDisplayValue:SetPoint("LEFT", roleDisplayLabel, "RIGHT", 5, 0)
    popup.roleDisplayValue = roleDisplayValue
    y = y - 48  -- Account for stats frame

    -- === Raid Selection Section ===
    local raidSelectLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidSelectLabel:SetPoint("TOPLEFT", 20, y)
    raidSelectLabel:SetText("Looking for Raid:")
    y = y - 22

    -- Raid type dropdown
    local raidTypeLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidTypeLabel:SetPoint("TOPLEFT", 30, y)
    raidTypeLabel:SetText("Raid:")

    local raidTypeDropdown = CreateFrame("Frame", "AIPEnrollRaidType", popup, "UIDropDownMenuTemplate")
    raidTypeDropdown:SetPoint("LEFT", raidTypeLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(raidTypeDropdown, 100)
    popup.raidType = "ICC"

    -- Size dropdown
    local sizeLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("LEFT", raidTypeDropdown, "RIGHT", 0, 2)
    sizeLabel:SetText("Size:")

    local sizeDropdown = CreateFrame("Frame", "AIPEnrollSize", popup, "UIDropDownMenuTemplate")
    sizeDropdown:SetPoint("LEFT", sizeLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(sizeDropdown, 45)
    popup.raidSize = "25"

    -- Heroic checkbox
    local heroicCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    heroicCheck:SetSize(22, 22)
    heroicCheck:SetPoint("LEFT", sizeDropdown, "RIGHT", 10, 2)
    heroicCheck:SetChecked(false)
    popup.heroicCheck = heroicCheck
    local heroicLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heroicLabel:SetPoint("LEFT", heroicCheck, "RIGHT", 0, 0)
    heroicLabel:SetText("Heroic")

    -- Lockout warning indicator (red dot instead of text label)
    local lockoutWarning = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockoutWarning:SetPoint("LEFT", heroicLabel, "RIGHT", 8, 0)
    lockoutWarning:SetText("|cFFFF4444\226\151\143|r")  -- Red circle indicator
    lockoutWarning:Hide()
    popup.lockoutWarning = lockoutWarning

    -- Custom text input (shown when CUSTOM is selected) - on separate line
    y = y - 28
    local customLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOPLEFT", 30, y)
    customLabel:SetText("Custom Name:")
    customLabel:Hide()
    popup.customLabel = customLabel

    local customInput, customContainer = GUI.CreateStyledEditBox(popup, 280, 16, false)
    customContainer:SetPoint("LEFT", customLabel, "RIGHT", 5, 0)
    customContainer:Hide()
    popup.customInput = customInput
    popup.customContainer = customContainer
    popup.customY = y  -- Store for layout adjustment

    -- Weekly quest status strip (shares the custom-name row; a weekly
    -- selection and CUSTOM are mutually exclusive)
    popup.weeklyToken = nil
    local weeklyStrip = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    weeklyStrip:SetPoint("TOPLEFT", 30, y)
    weeklyStrip:SetPoint("RIGHT", popup, "RIGHT", -20, 0)
    weeklyStrip:SetJustifyH("LEFT")
    weeklyStrip:Hide()
    popup.weeklyStrip = weeklyStrip

    local function UpdateWeeklyStrip()
        if popup.weeklyToken and AIP.Weekly then
            local q = AIP.Weekly.ForToken(popup.weeklyToken)
            weeklyStrip:SetText("|cFF33CCFF[W]|r " .. (q and q.boss or popup.weeklyToken) .. ": " .. AIP.Weekly.StatusText(popup.weeklyToken))
            weeklyStrip:Show()
        else
            weeklyStrip:Hide()
        end
    end
    popup.UpdateWeeklyStrip = UpdateWeeklyStrip

    -- Helper to build raid key
    local function GetRaidKey()
        local raidType = popup.raidType or "ICC"
        -- Handle custom text
        if raidType == "CUSTOM" then
            local customText = popup.customInput and popup.customInput:GetText() or ""
            if customText ~= "" then
                return customText
            end
            return "Custom"
        end
        local size = popup.raidSize or "25"
        local heroic = popup.heroicCheck:GetChecked() and "H" or "N"
        if raidType == "TOC" and heroic == "H" then
            return "TOGC" .. size
        end
        return raidType .. size .. heroic
    end

    -- Update custom field visibility
    local function UpdateCustomFieldVisibility()
        local isCustom = popup.raidType == "CUSTOM"
        if isCustom then
            popup.customLabel:Show()
            if popup.customContainer then popup.customContainer:Show() end
        else
            popup.customLabel:Hide()
            if popup.customContainer then popup.customContainer:Hide() end
        end
    end

    -- Update achievements when raid changes
    -- Update lockout warning based on selected raid
    local function UpdateLockoutWarning()
        local raidKey = GetRaidKey()
        if AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance then
            AIP.TreeBrowser.UpdateSavedInstances()
            local isLocked = AIP.TreeBrowser.IsLockedToInstance(raidKey)
            if isLocked then
                lockoutWarning:Show()
            else
                lockoutWarning:Hide()
            end
        else
            lockoutWarning:Hide()
        end
    end
    popup.UpdateLockoutWarning = UpdateLockoutWarning

    local function UpdateAchievementsList()
        local raidKey = GetRaidKey()
        local achievements = GUI.GetPlayerAchievementsForRaid(raidKey)

        -- Clear previous messages (ScrollingMessageFrame)
        popup.achieveList:Clear()

        if #achievements > 0 then
            for _, a in ipairs(achievements) do
                -- Get actual achievement link for display
                local link = GetAchievementLink(a.id)
                if link then
                    popup.achieveList:AddMessage("|cFF00FF00+|r " .. link)
                else
                    popup.achieveList:AddMessage("|cFF00FF00+|r " .. a.name)
                end
            end
        else
            popup.achieveList:AddMessage("|cFFFF6666No achievements for this raid|r")
        end

        popup.playerAchievements = achievements
        UpdateLockoutWarning()
    end

    -- Function to update size dropdown based on selected raid
    local function UpdateSizeDropdown()
        local raidInfo = GUI.RaidSizeInfo[popup.raidType]
        if raidInfo then
            -- Set default size for this raid if current size is not valid
            local currentSizeValid = false
            for _, validSize in ipairs(raidInfo.sizes) do
                if validSize == popup.raidSize then
                    currentSizeValid = true
                    break
                end
            end
            if not currentSizeValid then
                popup.raidSize = raidInfo.defaultSize
                UIDropDownMenu_SetText(sizeDropdown, raidInfo.defaultSize)
            end
            -- Update heroic checkbox visibility
            if raidInfo.hasHeroic then
                heroicCheck:Show()
                heroicLabel:Show()
            else
                heroicCheck:Hide()
                heroicLabel:Hide()
                heroicCheck:SetChecked(false)
            end
            -- Enable/disable size dropdown based on available sizes
            if #raidInfo.sizes == 1 then
                UIDropDownMenu_DisableDropDown(sizeDropdown)
            else
                UIDropDownMenu_EnableDropDown(sizeDropdown)
            end
        end
        -- Refresh dropdown display
        UIDropDownMenu_Initialize(sizeDropdown, function()
            local info = GUI.RaidSizeInfo[popup.raidType] or {sizes = {"5", "10", "25"}}
            for _, size in ipairs(info.sizes) do
                local sizeInfo = UIDropDownMenu_CreateInfo()
                sizeInfo.text = size .. " players"
                sizeInfo.value = size
                sizeInfo.func = function()
                    popup.raidSize = size
                    UIDropDownMenu_SetText(sizeDropdown, size)
                    UpdateAchievementsList()
                end
                sizeInfo.checked = (popup.raidSize == size)
                UIDropDownMenu_AddButton(sizeInfo)
            end
        end)
    end
    popup.UpdateSizeDropdown = UpdateSizeDropdown

    -- Helper to update raid dropdown text with lockout color (+ weekly tag)
    local function UpdateRaidDropdownText()
        local raidType = popup.raidType or "ICC"
        local prefix = popup.weeklyToken and "|cFF33CCFF[W]|r " or ""
        local isLocked = AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and AIP.TreeBrowser.IsLockedToInstance(raidType)
        if isLocked then
            UIDropDownMenu_SetText(raidTypeDropdown, prefix .. "|cFFFF6666" .. raidType .. "|r")
        else
            UIDropDownMenu_SetText(raidTypeDropdown, prefix .. raidType)
        end
    end
    popup.UpdateRaidDropdownText = UpdateRaidDropdownText

    -- Initialize raid type dropdown with nested submenus
    UIDropDownMenu_Initialize(raidTypeDropdown, function(self, level, menuList)
        level = level or 1

        if level == 1 then
            -- Weekly raid quest category pinned first
            if AIP.Weekly then
                local info = UIDropDownMenu_CreateInfo()
                info.text = "|cFF33CCFFWeekly Raid Quest|r"
                info.hasArrow = true
                info.menuList = "AIP_WEEKLY"
                info.notCheckable = true
                info.keepShownOnClick = true
                UIDropDownMenu_AddButton(info, level)
            end
            -- Main level: show categories with arrows
            for _, cat in ipairs(GUI.RaidCategories) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = cat.header
                info.hasArrow = true
                info.menuList = cat.id
                info.notCheckable = true
                info.keepShownOnClick = true
                UIDropDownMenu_AddButton(info, level)
            end
        elseif level == 2 then
            if menuList == "AIP_WEEKLY" and AIP.Weekly then
                local held = AIP.Weekly.Current()
                local ordered = {}
                if held then ordered[#ordered + 1] = held.quest end
                for _, q in ipairs(AIP.Weekly.Quests) do
                    if not held or q.token ~= held.quest.token then
                        ordered[#ordered + 1] = q
                    end
                end
                for _, q in ipairs(ordered) do
                    local info = UIDropDownMenu_CreateInfo()
                    local tag = (held and q.token == held.quest.token) and " |cFF00FF00(this week)|r" or ""
                    info.text = q.boss .. " (" .. q.raid .. ")" .. tag
                    info.value = q.token
                    info.func = function()
                        popup.weeklyToken = q.token
                        popup.raidType = q.raid
                        popup.raidSize = "10"
                        popup.heroicCheck:SetChecked(false)
                        UpdateRaidDropdownText()
                        UpdateSizeDropdown()
                        UIDropDownMenu_SetText(sizeDropdown, "10")
                        UpdateCustomFieldVisibility()
                        UpdateWeeklyStrip()
                        UpdateAchievementsList()
                        CloseDropDownMenus()
                    end
                    info.checked = (popup.weeklyToken == q.token)
                    UIDropDownMenu_AddButton(info, level)
                end
                return
            end
            -- Submenu: show raids in category
            for _, cat in ipairs(GUI.RaidCategories) do
                if cat.id == menuList then
                    for _, rt in ipairs(cat.items) do
                        local info = UIDropDownMenu_CreateInfo()
                        -- Show lockout indicator (red text, no label)
                        local isLocked = AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and AIP.TreeBrowser.IsLockedToInstance(rt)
                        if isLocked then
                            info.text = "|cFFFF6666" .. rt .. "|r"
                        else
                            info.text = rt
                        end
                        info.value = rt
                        info.func = function()
                            popup.raidType = rt
                            popup.weeklyToken = nil  -- plain raid pick clears the weekly tag
                            UpdateRaidDropdownText()
                            UpdateSizeDropdown()
                            UpdateCustomFieldVisibility()
                            UpdateWeeklyStrip()
                            UpdateAchievementsList()
                            CloseDropDownMenus()
                        end
                        info.checked = (popup.raidType == rt)
                        UIDropDownMenu_AddButton(info, level)
                    end
                    break
                end
            end
        end
    end)

    -- Initialize size dropdown
    UIDropDownMenu_Initialize(sizeDropdown, function()
        local raidInfo = GUI.RaidSizeInfo[popup.raidType] or {sizes = {"5", "10", "25"}}
        for _, size in ipairs(raidInfo.sizes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = size .. " players"
            info.value = size
            info.func = function()
                popup.raidSize = size
                UIDropDownMenu_SetText(sizeDropdown, size)
                UpdateAchievementsList()
            end
            info.checked = (popup.raidSize == size)
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(sizeDropdown, "25")
    GUI.FixDropdownStrata(raidTypeDropdown)
    GUI.FixDropdownStrata(sizeDropdown)

    -- Apply initial size dropdown update
    UpdateSizeDropdown()
    UpdateRaidDropdownText()  -- Apply initial lockout color

    heroicCheck:SetScript("OnClick", UpdateAchievementsList)
    y = y - 32

    -- === Role Override ===
    local roleLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleLabel:SetPoint("TOPLEFT", 30, y)
    roleLabel:SetText("Role (override):")

    local roleDropdown = CreateFrame("Frame", "AIPEnrollRoleDrop", popup, "UIDropDownMenuTemplate")
    roleDropdown:SetPoint("LEFT", roleLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(roleDropdown, 80)
    popup.roleDropdown = roleDropdown
    popup.selectedRole = nil -- nil means auto-detect

    UIDropDownMenu_Initialize(roleDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Auto-detect"
        info.value = nil
        info.func = function()
            popup.selectedRole = nil
            UIDropDownMenu_SetText(roleDropdown, "Auto-detect")
        end
        UIDropDownMenu_AddButton(info)

        for _, role in ipairs({"TANK", "HEALER", "DPS"}) do
            info = UIDropDownMenu_CreateInfo()
            info.text = role
            info.value = role
            info.func = function()
                popup.selectedRole = role
                UIDropDownMenu_SetText(roleDropdown, role)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(roleDropdown, "Auto-detect")
    GUI.FixDropdownStrata(roleDropdown)
    y = y - 32

    -- === Your Achievements Section ===
    local achieveHeader = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    achieveHeader:SetPoint("TOPLEFT", 20, y)
    achieveHeader:SetText("Your Achievements for this Raid:")
    y = y - 20

    local achieveFrame = CreateFrame("Frame", nil, popup)
    achieveFrame:SetSize(360, 70)
    achieveFrame:SetPoint("TOPLEFT", 20, y)
    GUI.ApplyBackdrop(achieveFrame, "Inset", 0.9)

    -- Use ScrollingMessageFrame for achievement display with hyperlink support
    local achieveScroll = CreateFrame("ScrollingMessageFrame", nil, achieveFrame)
    achieveScroll:SetPoint("TOPLEFT", 8, -6)
    achieveScroll:SetPoint("BOTTOMRIGHT", -8, 6)
    achieveScroll:SetFontObject(GameFontNormalSmall)
    achieveScroll:SetJustifyH("LEFT")
    achieveScroll:SetInsertMode("TOP")  -- Messages appear from top-left
    achieveScroll:SetFading(false)
    achieveScroll:SetMaxLines(50)
    achieveScroll:EnableMouseWheel(true)
    achieveScroll:SetHyperlinksEnabled(true)
    achieveScroll:SetScript("OnHyperlinkEnter", function(self, link, text)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    achieveScroll:SetScript("OnHyperlinkLeave", function(self)
        GameTooltip:Hide()
    end)
    achieveScroll:SetScript("OnHyperlinkClick", function(self, link, text, button)
        SetItemRef(link, text, button)
    end)
    achieveScroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)
    popup.achieveList = achieveScroll
    popup.achieveListIsHTML = false  -- Using ScrollingMessageFrame now
    y = y - 78

    -- === Include Achievement checkbox ===
    local includeAchieveCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    includeAchieveCheck:SetSize(22, 22)
    includeAchieveCheck:SetPoint("TOPLEFT", 20, y)
    includeAchieveCheck:SetChecked(true)
    popup.includeAchieveCheck = includeAchieveCheck
    local includeAchieveLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    includeAchieveLabel:SetPoint("LEFT", includeAchieveCheck, "RIGHT", 2, 0)
    includeAchieveLabel:SetText("Link best achievement in message")
    y = y - 28

    -- === Custom note ===
    local noteLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLabel:SetPoint("TOPLEFT", 20, y)
    noteLabel:SetText("Note:")

    local noteInput, noteContainer = GUI.CreateStyledEditBox(popup, 280, 18, false)
    noteContainer:SetPoint("LEFT", noteLabel, "RIGHT", 5, 0)
    popup.noteInput = noteInput
    y = y - 28

    -- === Buttons ===
    local enrollBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    enrollBtn:SetSize(90, 24)
    enrollBtn:SetPoint("BOTTOMLEFT", 80, 15)
    enrollBtn:SetText("Enroll")
    enrollBtn:SetScript("OnClick", function()
        local raidKey = GetRaidKey()
        local role = popup.selectedRole or GUI.DetectPlayerRole()
        local gs = GUI.CalculatePlayerGS()
        local ilvl = GUI.CalculatePlayerIlvl()
        local _, class = UnitClass("player")

        -- Build achievement link
        local achieveLink = ""
        if popup.includeAchieveCheck:GetChecked() and popup.playerAchievements and #popup.playerAchievements > 0 then
            achieveLink = GetAchievementLink(popup.playerAchievements[1].id) or ""
        end

        local note = popup.noteInput:GetText() or ""

        -- Enhanced LFG message with all player stats
        -- Format: "LFG <RAID> - <Class> (<Spec>) <Role> | GS:<gs> iL:<ilvl> {AIP:5.2} [Achievement] note"
        local spec = GUI.GetPlayerSpecName()
        local classDisplay = class:sub(1,1) .. class:sub(2):lower()  -- Capitalize first letter only
        local level = UnitLevel("player")

        -- Short class codes for compact display
        local classShortCodes = {
            WARRIOR = "War", PALADIN = "Pal", DEATHKNIGHT = "DK", DRUID = "Dru",
            PRIEST = "Pri", SHAMAN = "Sha", MAGE = "Mag", WARLOCK = "Loc",
            HUNTER = "Hun", ROGUE = "Rog"
        }
        local classShort = classShortCodes[class] or classDisplay

        -- Single-source builder (same one the LFM side uses); weekly token is
        -- appended after the {AIP:x} tag, which all peer-parse regexes ignore.
        local msg
        if AIP.LFMFormat then
            msg = AIP.LFMFormat.BuildLFG({
                raidKey = raidKey,
                classShort = classShort,
                spec = spec,
                role = role,
                gs = gs,
                ilvl = ilvl,
                level = level,
                achievementLink = achieveLink,
                note = note,
                weekly = popup.weeklyToken,
            })
        else
            msg = string.format("LFG %s - %s (%s) %s - GS:%d iL:%d Lv:%d {AIP:5.2}",
                raidKey, classShort, spec, role, gs, ilvl, level)
        end

        -- Store enrollment data with all stats
        local playerName = UnitName("player")
        GUI.MyEnrollment = {
            name = playerName,
            raid = raidKey,
            class = class,
            classShort = classShort,
            spec = spec,
            role = role,
            gs = gs,
            ilvl = ilvl,
            level = level,
            weekly = popup.weeklyToken,
            message = msg,
            time = time(),
            isLfgEnrollment = true,
            isSelf = true,  -- Flag to indicate this is our own enrollment
        }

        -- Remember this config so the popup reopens on the same raid
        if AIP.db then
            AIP.db.lastEnrollConfig = {
                raidType = popup.raidType,
                raidSize = popup.raidSize,
                heroic = popup.heroicCheck:GetChecked() and true or false,
                weekly = popup.weeklyToken,
                role = popup.selectedRole,
            }
        end

        -- Also add to LfgEnrollments for display in LFG tab
        GUI.LfgEnrollments[playerName] = GUI.MyEnrollment

        -- Set player mode to LFG
        if AIP.SetPlayerMode then
            AIP.SetPlayerMode("lfg")
        end

        -- Start auto-broadcast for LFG (will auto-stop when joining group)
        GUI.StartBroadcast("lfg", msg, AIP.db and AIP.db.autoSpamInterval or 60)

        popup:Hide()

        -- Ensure main GUI exists before updating
        if not GUI.Frame then
            GUI.CreateFrame()
        end

        -- Update queue panel to show our enrollment and switch to LFG sub-tab
        local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
        if container then
            -- Switch to LFG sub-tab FIRST so content is visible
            if container.queueSubTab ~= "lfg" then
                container.queueSubTab = "lfg"
                -- Update tab visuals
                if container.queueTabBtn and container.queueTabBtn.bg then
                    container.queueTabBtn.bg:SetTexture(0.15, 0.15, 0.15, 1)
                    if container.queueTabBtn.text then container.queueTabBtn.text:SetTextColor(0.8, 0.8, 0.8) end
                end
                if container.lfgTabBtn and container.lfgTabBtn.bg then
                    container.lfgTabBtn.bg:SetTexture(0.3, 0.3, 0.4, 1)
                    if container.lfgTabBtn.text then container.lfgTabBtn.text:SetTextColor(1, 0.82, 0) end
                end
                if container.queueContent then container.queueContent:Hide() end
                if container.lfgContent then container.lfgContent:Show() end
            end
            -- Then update the panel data
            GUI.UpdateQueuePanel(container)
        end

        -- Show main window so user can see their enrollment
        GUI.Show("lfm")

        -- Update queue status to show enrollment
        GUI.UpdateEnrollmentStatus()

        AIP.Print("Enrolled as LFG for " .. raidKey .. " (" .. role .. ")! |cFF00FF00Auto-broadcasting until you join a group.|r")
    end)

    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("LEFT", enrollBtn, "RIGHT", 20, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Update stats when shown
    popup:SetScript("OnShow", function()
        local gs = GUI.CalculatePlayerGS()
        local ilvl = GUI.CalculatePlayerIlvl()
        local role = GUI.DetectPlayerRole()

        popup.gsDisplayValue:SetText(tostring(gs))
        popup.ilvlDisplayValue:SetText(tostring(ilvl))
        popup.roleDisplayValue:SetText(role)

        -- Update raid dropdown with lockout color
        UpdateRaidDropdownText()
        UpdateAchievementsList()
    end)

    popup:Hide()
    tinsert(UISpecialFrames, "AIPEnrollPopup")
    GUI.EnrollPopup = popup
end

-- Hook into tree selection to update details panel
local origSelectNode = AIP.TreeBrowser and AIP.TreeBrowser.SelectNode
if AIP.TreeBrowser then
    -- Extended SelectNode that accepts optional data parameter
    AIP.TreeBrowser.SelectNode = function(nodeId, playerName, nodeData)
        if origSelectNode then origSelectNode(nodeId, playerName) end

        -- Get data - prefer passed nodeData, then try lookups
        local data = nodeData
        if not data and playerName then
            -- Try GroupTracker (indexed by leader name)
            if AIP.GroupTracker and AIP.GroupTracker.Groups then
                data = AIP.GroupTracker.Groups[playerName]
            end
            -- Try LFMBrowser (indexed by player name)
            if not data and AIP.LFMBrowser and AIP.LFMBrowser.Players then
                data = AIP.LFMBrowser.Players[playerName]
            end
            -- Try ChatScanner directly
            if not data and AIP.ChatScanner then
                if AIP.ChatScanner.Groups then
                    data = AIP.ChatScanner.Groups[playerName]
                end
                if not data and AIP.ChatScanner.Players then
                    data = AIP.ChatScanner.Players[playerName]
                end
            end
        end

        -- Determine which tab container to update. LFM and LFG both render
        -- into the single "lfm" browser container (see GUI.RefreshBrowserTab) -
        -- there is no separate "lfg" tab, so an lfg_-prefixed node must route
        -- here too, not to the unrelated Favorites tab (which silently ate
        -- every LFG player-row click: the details panel never updated).
        local container = nil
        if GUI.Frame and GUI.Frame.tabContents then
            container = GUI.Frame.tabContents["lfm"]
        end

        if container then
            GUI.UpdateDetailsPanel(container, data)
        end
    end
end

-- Update composition tab (RaidComp-style)
-- Rebuild the numbered composition-variation buttons for the selected template.
-- The active variation is highlighted; the Recommend button is re-anchored after
-- the last visible variation button.
function GUI.RebuildVariationButtons(container)
    if not container or not container.variationButtons then return end
    if not AIP.Composition then return end

    local template = AIP.Composition.CurrentRaid.template
    local variations = template and AIP.Composition.GetTemplateVariations(template) or {}
    local activeIndex = AIP.Composition.CurrentRaid.variationIndex or 1
    local buttons = container.variationButtons
    local MAX_VAR_BTNS = 5

    local anchor = container.variationLabel
    for i = 1, MAX_VAR_BTNS do
        local v = variations[i]
        local btn = buttons[i]
        if v then
            if not btn then
                btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
                btn:SetSize(22, 22)
                buttons[i] = btn
            end
            btn:ClearAllPoints()
            if i == 1 then
                btn:SetPoint("LEFT", container.variationLabel, "RIGHT", 4, 0)
            else
                btn:SetPoint("LEFT", buttons[i-1], "RIGHT", 2, 0)
            end
            btn:SetText(tostring(i))
            btn.variationIndex = i
            btn.variationData = v
            btn:SetScript("OnClick", function(self)
                AIP.Composition.SetVariation(self.variationIndex)
                GUI.UpdateCompositionTab()
            end)
            btn:SetScript("OnEnter", function(self)
                local vv = self.variationData
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(vv.name, 1, 0.82, 0)
                GameTooltip:AddLine(string.format("%d Tank / %d Heal / %d DPS", vv.tanks, vv.healers, vv.dps), 1, 1, 1)
                if vv.gs and vv.ilvl then
                    GameTooltip:AddLine(string.format("GS %d-%d   (iLvl %d-%d)", vv.gs[1], vv.gs[2], vv.ilvl[1], vv.ilvl[2]), 0.5, 0.8, 1)
                end
                if vv.note then GameTooltip:AddLine(vv.note, 0.7, 0.7, 0.7, true) end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if i == activeIndex then btn:LockHighlight() else btn:UnlockHighlight() end
            btn:Show()
            anchor = btn
        elseif btn then
            btn:Hide()
        end
    end

    -- Dim the "Comp:" label when there is nothing to vary.
    if container.variationLabel then
        container.variationLabel:SetTextColor(#variations > 1 and 0.9 or 0.5,
            #variations > 1 and 0.9 or 0.5, #variations > 1 and 0.9 or 0.5)
    end

    if container.recommendBtn then
        container.recommendBtn:ClearAllPoints()
        container.recommendBtn:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
    end
end

-- Show the recruitment recommendations in a movable popup.
function GUI.ShowRecommendations()
    if not AIP.Composition or not AIP.Composition.BuildRecommendationLines then return end
    local lines = AIP.Composition.BuildRecommendationLines()
    local text = table.concat(lines, "\n")

    local popup = GUI.RecommendPopup
    if not popup then
        popup = CreateFrame("Frame", "AIPCompRecommendPopup", UIParent)
        popup:SetSize(430, 330)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("DIALOG")
        AIP.UI.MakeDraggable(popup)
        GUI.StylePopup(popup)

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Recruitment Recommendations")
        title:SetTextColor(1, 0.82, 0)

        local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)

        local scroll = CreateFrame("ScrollFrame", "AIPCompRecScroll", popup, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -40)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(370, 10)
        scroll:SetScrollChild(content)

        local body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", 0, 0)
        body:SetWidth(370)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        popup.body = body
        popup.content = content

        tinsert(UISpecialFrames, "AIPCompRecommendPopup")
        GUI.RecommendPopup = popup
    end

    popup.body:SetText(text)
    local h = (popup.body:GetStringHeight() or 100) + 10
    popup.content:SetHeight(math.max(h, 10))
    popup:Show()
end

function GUI.UpdateCompositionTab()
    local container = GUI.Frame.tabContents["composition"]
    if not container then return end

    if not AIP.Composition then
        if container.templateDisplay then
            container.templateDisplay:SetText("Composition module not available")
        end
        return
    end

    local status = AIP.Composition.GetCompositionStatus()
    local raid = AIP.Composition.CurrentRaid

    -- Update template display (name + active gear variation + GS range)
    if container.templateDisplay then
        if status then
            local text = status.template
            if status.variation then text = text .. " |cFF88CCFF[" .. status.variation .. "]|r" end
            if status.gs then
                text = text .. string.format(" |cFF888888GS %d-%d|r", status.gs[1], status.gs[2])
            end
            container.templateDisplay:SetText(text)
        else
            container.templateDisplay:SetText("No template selected (using current raid)")
        end
    end

    -- Update role bars
    local function UpdateRoleBar(bar, current, needed)
        if not bar then return end
        local ratio = needed > 0 and math.min(current / needed, 1) or 0
        local fillWidth = ratio * 150

        bar.fillBar:SetWidth(math.max(1, fillWidth))
        bar.countText:SetText(current .. "/" .. needed)

        -- Color based on status
        if current >= needed then
            bar.countText:SetTextColor(0, 1, 0)
        elseif current > 0 then
            bar.countText:SetTextColor(1, 1, 0)
        else
            bar.countText:SetTextColor(1, 0.3, 0.3)
        end
    end

    if status then
        UpdateRoleBar(container.roleBars.TANK, status.tanks.current, status.tanks.needed)
        UpdateRoleBar(container.roleBars.HEALER, status.healers.current, status.healers.needed)
        UpdateRoleBar(container.roleBars.DPS, status.dps.current, status.dps.needed)
        UpdateRoleBar(container.roleBars.TOTAL, status.size.current, status.size.needed)
    else
        UpdateRoleBar(container.roleBars.TANK, raid.roleCounts.TANK, 0)
        UpdateRoleBar(container.roleBars.HEALER, raid.roleCounts.HEALER, 0)
        UpdateRoleBar(container.roleBars.DPS, raid.roleCounts.DPS, 0)
        UpdateRoleBar(container.roleBars.TOTAL, #raid.members, 0)
    end

    -- Update buff/debuff display (new tabbed system)
    GUI.UpdateCompositionBuffDisplay(container)

    -- Update class counts
    if container.classDisplays then
        for class, display in pairs(container.classDisplays) do
            local count = raid.classCounts[class] or 0
            display.count:SetText(tostring(count))
            if count > 0 then
                display.count:SetAlpha(1)
                display.icon:SetAlpha(1)
                if display.frame then display.frame:SetAlpha(1) end
            else
                display.count:SetAlpha(0.4)
                display.icon:SetAlpha(0.4)
                if display.frame then display.frame:SetAlpha(0.5) end
            end
        end
    end

    -- Update raid member table (new scrollable table)
    GUI.UpdateCompositionMemberTable(container)

    -- Update raid benefits stats panel
    GUI.UpdateRaidBenefits(container)

    -- Keep the variation buttons in sync with the selected template
    GUI.RebuildVariationButtons(container)
end

-- Select a tab
function GUI.SelectTab(tabId)
    -- The LFM and LFG browsers share the single "lfm" container (LFG is a mode of
    -- the browser, not its own tab). Map it, and hard-guard against ANY tab id that
    -- has no container - otherwise the loop below hides every tab -> blank window.
    local containerId = (tabId == "lfg") and "lfm" or tabId
    if not (GUI.Frame.tabContents and GUI.Frame.tabContents[containerId]) then
        tabId, containerId = "lfm", "lfm"
    end
    GUI.CurrentTab = tabId

    for id, container in pairs(GUI.Frame.tabContents) do
        local tabBtn = GUI.Frame.tabButtons[id]
        if id == containerId then
            container:Show()
            -- Highlight selected tab with custom styling
            if tabBtn then
                if tabBtn.bg then
                    tabBtn.bg:SetTexture(0.30, 0.26, 0.12, 1)   -- selected: warm gold-tinted
                end
                if tabBtn.text then
                    tabBtn.text:SetTextColor(1, 0.82, 0)  -- Gold color for selected
                end
            end
        else
            container:Hide()
            -- Deselect tab with custom styling
            if tabBtn then
                if tabBtn.bg then
                    tabBtn.bg:SetTexture(0.11, 0.12, 0.17, 0.9)   -- unselected: dark navy
                end
                if tabBtn.text then
                    tabBtn.text:SetTextColor(0.8, 0.8, 0.8)  -- Gray for unselected
                end
            end
        end
    end

    -- Update the selected tab
    GUI.UpdateCurrentTab()
end

-- Update current tab content
function GUI.UpdateCurrentTab()
    local tabId = GUI.CurrentTab

    if tabId == "lfm" or tabId == "lfg" then
        GUI.RefreshBrowserTab(tabId)
    elseif tabId == "favorites" and AIP.Panels and AIP.Panels.Favorites then
        AIP.Panels.Favorites.Update()
    elseif tabId == "blacklist" and AIP.Panels and AIP.Panels.Blacklist then
        AIP.Panels.Blacklist.Update()
    elseif tabId == "composition" then
        GUI.UpdateCompositionTab()
    elseif tabId == "raidmgmt" and AIP.Panels and AIP.Panels.RaidMgmt then
        AIP.Panels.RaidMgmt.Update()
    elseif tabId == "loothistory" and AIP.Panels and AIP.Panels.LootHistory then
        AIP.Panels.LootHistory.Update()
    elseif tabId == "character" and AIP.Panels and AIP.Panels.Character then
        AIP.Panels.Character.Update()
    elseif tabId == "settings" and AIP.Panels and AIP.Panels.Settings then
        AIP.Panels.Settings.Update()
    end

    -- Update status bar
    GUI.UpdateStatus()
end

-- Get LFG enrollment count (same logic as LFG tab)
function GUI.GetLfgEnrollmentCount()
    local count = 0
    for _ in pairs(GUI.LfgEnrollments or {}) do
        count = count + 1
    end
    return count
end

-- Update status bar
function GUI.UpdateStatus()
    if not GUI.Frame then return end

    local status = ""
    if AIP.db and AIP.db.enabled then
        status = status .. "|cFF00FF00Auto-Invite: ON|r"
    else
        status = status .. "|cFFFF0000Auto-Invite: OFF|r"
    end

    local groupSize = AIP.GetGroupSize and AIP.GetGroupSize() or 1
    status = status .. "  |  Group: " .. groupSize

    local queueCount = AIP.GetQueueCount and AIP.GetQueueCount() or 0
    status = status .. "  |  Queue: " .. queueCount

    local lfmCount = AIP.GroupTracker and AIP.GroupTracker.GetGroupCount() or 0
    local lfgCount = GUI.GetLfgEnrollmentCount()
    status = status .. "  |  LFM: " .. lfmCount .. "  |  LFG: " .. lfgCount

    -- Add peer count to main status line
    local peerCount = AIP.DataBus and AIP.DataBus.GetPeerCount and AIP.DataBus.GetPeerCount() or 0
    local peerColor = peerCount > 0 and "|cFF00FF00" or "|cFF888888"
    status = status .. "  |  " .. peerColor .. "Peers: " .. peerCount .. "|r"

    -- Add mode to main status line (check broadcast state first, then db)
    local modeText, modeColor
    if GUI.Broadcast and GUI.Broadcast.active then
        -- Use active broadcast mode
        if GUI.Broadcast.mode == "lfm" then
            modeText = "LFM"
            modeColor = "|cFF00FFFF"
        elseif GUI.Broadcast.mode == "lfg" then
            modeText = "LFG"
            modeColor = "|cFFFFFF00"
        else
            modeText = "BC"
            modeColor = "|cFF00FF00"
        end
    else
        local mode = AIP.GetPlayerMode and AIP.GetPlayerMode() or "none"
        if mode == "lfm" then
            modeText = "LFM"
            modeColor = "|cFF00FFFF"
        elseif mode == "lfg" then
            modeText = "LFG"
            modeColor = "|cFFFFFF00"
        else
            modeText = "Off"
            modeColor = "|cFF888888"
        end
    end
    status = status .. "  |  " .. modeColor .. "Mode: " .. modeText .. "|r"

    GUI.Frame.statusText:SetText(status)

    -- Clear the separate displays (now consolidated)
    if GUI.Frame.statusBar.peerCountDisplay then
        GUI.Frame.statusBar.peerCountDisplay:SetText("")
    end
    if GUI.Frame.statusBar.modeIndicator then
        GUI.Frame.statusBar.modeIndicator:SetText("")
    end
end

-- Update peer count display in status bar (now handled by UpdateStatus)
function GUI.UpdatePeerCount()
    -- Consolidated into UpdateStatus for consistent formatting
end

-- Update mode indicator in status bar (now handled by UpdateStatus)
function GUI.UpdateModeIndicator()
    -- Consolidated into UpdateStatus for consistent formatting
end

-- Toggle the main window
function GUI.Toggle()
    if not GUI.Frame then
        GUI.CreateFrame()
    end

    if GUI.Frame:IsVisible() then
        GUI.Frame:Hide()
    else
        -- Restore position if saved (with nil checks and screen bounds clamping)
        if AIP.db and AIP.db.guiPosition then
            local pos = AIP.db.guiPosition
            if pos.point and pos.relPoint and pos.x and pos.y then
                -- Clamp position to screen bounds
                local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
                local frameW, frameH = GUI.Frame:GetWidth(), GUI.Frame:GetHeight()
                local x = math.max(-screenW + 100, math.min(pos.x, screenW - 100))
                local y = math.max(-screenH + 100, math.min(pos.y, screenH - 100))
                GUI.Frame:ClearAllPoints()
                GUI.Frame:SetPoint(pos.point, UIParent, pos.relPoint, x, y)
            end
        end

        -- Restore size if saved. A minimized window must come back at its
        -- minimized height with the content still collapsed - otherwise it
        -- reopens at full size with all panels hidden (a black empty window).
        if GUI.IsMinimized then
            GUI.Frame:SetHeight(GUI.Config.minimizedHeight)
        elseif AIP.db and AIP.db.guiWidth and AIP.db.guiHeight then
            -- Clamp a previously-saved size up to the current minimums, so an old
            -- short saved height gets the new, deeper minimum (fixes cramped panels).
            GUI.Frame:SetSize(math.max(AIP.db.guiWidth, GUI.Config.minWidth),
                math.max(AIP.db.guiHeight, GUI.Config.minHeight))
        end

        GUI.Frame:Show()
        -- Only (re)select a tab when expanded; the tab panels live inside the
        -- hidden content frame while minimized.
        if not GUI.IsMinimized then
            GUI.SelectTab(GUI.CurrentTab)
        end
    end
end

-- Show the main window (called by /lfm, /lfg)
function GUI.Show(tabId)
    if not GUI.Frame then
        GUI.CreateFrame()
    end

    GUI.Frame:Show()
    -- Opening to a specific tab implies the user wants to see content, so expand
    -- if the window was left minimized.
    if GUI.IsMinimized then
        GUI.ToggleMinimize()
    end
    if tabId then
        GUI.SelectTab(tabId)
    else
        GUI.SelectTab(GUI.CurrentTab)
    end

    -- Update GS display when showing
    GUI.UpdateGearScoreDisplay()
end

-- Update function called when data changes
-- Debounced "data changed -> refresh UI". Background triggers (group inspections
-- completing, peer addon data, chat scans) fire this constantly; refreshing the
-- current tab every time rebuilt the browser tree at random. Coalesce bursts into
-- a single deferred refresh so the tree doesn't flicker/reset.
function AIP.UpdateCentralGUI()
    if not (GUI.Frame and GUI.Frame:IsVisible()) then return end
    if GUI._updatePending then return end
    GUI._updatePending = true
    local function doUpdate()
        GUI._updatePending = false
        if GUI.Frame and GUI.Frame:IsVisible() then
            GUI.UpdateCurrentTab()
            GUI.UpdateGearScoreDisplay()
        end
    end
    if AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(0.4, doUpdate)
    else
        doUpdate()
    end
end

-- Update the GearScore/iLevel display in the footer
function GUI.UpdateGearScoreDisplay()
    if not GUI.Frame or not GUI.Frame.statusBar or not GUI.Frame.statusBar.gsDisplay then
        return
    end

    local gsDisplay = GUI.Frame.statusBar.gsDisplay
    local gs, ilvl

    -- Use the same function as Enroll popup for consistency
    gs, ilvl = GUI.CalculatePlayerGS()

    -- If no ilvl, calculate it separately
    if not ilvl then
        ilvl = GUI.CalculatePlayerIlvl()
    end

    -- Format the display with consistent separator style
    if gs and gs > 0 then
        local r, g, b = 1, 1, 1
        if AIP.Integrations and AIP.Integrations.GetGSColor then
            r, g, b = AIP.Integrations.GetGSColor(gs)
        end
        local gsStr = string.format("|cFF%02x%02x%02xGS: %d|r", r*255, g*255, b*255, gs)

        if ilvl and ilvl > 0 then
            gsDisplay:SetText(gsStr .. "  |  |cFFAAAAAAiLvl: " .. ilvl .. "|r")
        else
            gsDisplay:SetText(gsStr)
        end
    else
        -- No GS available, show just iLvl if we have it
        if ilvl and ilvl > 0 then
            gsDisplay:SetText("|cFFAAAAAAiLvl: " .. ilvl .. "|r")
        else
            gsDisplay:SetText("")
        end
    end
end

-- Hook equipment changes to update GS display
local gsUpdateFrame = CreateFrame("Frame")
gsUpdateFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
gsUpdateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
gsUpdateFrame:SetScript("OnEvent", function(self, event)
    -- Delay slightly to ensure item info is loaded (WotLK compatible)
    AIP.Utils.DelayedCall(0.5, function()
        if GUI.Frame and GUI.Frame:IsVisible() then
            GUI.UpdateGearScoreDisplay()
        end
    end)
end)

-- Tree selection changed handler
function AIP.OnTreeSelectionChanged(nodeId, playerName)
    if not GUI.Frame then return end

    local currentTab = GUI.CurrentTab
    if currentTab ~= "lfm" and currentTab ~= "lfg" then return end

    local container = GUI.Frame.tabContents[currentTab]
    if not container or not container.inspectPanel then return end

    local panel = container.inspectPanel

    if not playerName then
        -- No selection
        panel.playerName:SetText("Select a player")
        panel.classSpec:SetText("")
        panel.gsText:SetText("")
        panel.enchantText:SetText("")
        panel.enchantList:SetText("")
        panel.gemText:SetText("")
        panel.achieveText:SetText("")
        panel.perfText:SetText("")
        panel.msgText:SetText("")
        return
    end

    -- Get player data - try direct lookup and also check TreeBrowser's selected node
    local data
    if currentTab == "lfm" and AIP.GroupTracker then
        data = AIP.GroupTracker.Groups[playerName]
    elseif currentTab == "lfg" and AIP.LFMBrowser then
        data = AIP.LFMBrowser.Players[playerName]
    end

    -- Fallback: get data from TreeBrowser's selected node
    if not data and AIP.TreeBrowser then
        local selectedData = AIP.TreeBrowser.GetSelectedPlayerData()
        if selectedData then
            data = selectedData
        end
    end

    if not data then
        panel.playerName:SetText(playerName)
        panel.classSpec:SetText("No data available")
        panel.gsText:SetText("")
        panel.enchantText:SetText("")
        panel.enchantList:SetText("")
        panel.gemText:SetText("")
        panel.achieveText:SetText("")
        panel.perfText:SetText("")
        panel.msgText:SetText("")
        return
    end

    -- Update display
    panel.playerName:SetText(playerName)

    -- For LFM groups, show raid info instead of class
    local classText, roleText
    if currentTab == "lfm" and data.raid then
        classText = data.raid
        roleText = ""
        -- Show composition needs
        if data.composition then
            local needs = {}
            if data.composition.tanks and data.composition.tanks.needed > 0 then
                table.insert(needs, data.composition.tanks.needed .. " Tank(s)")
            end
            if data.composition.healers and data.composition.healers.needed > 0 then
                table.insert(needs, data.composition.healers.needed .. " Healer(s)")
            end
            if data.composition.mdps and data.composition.mdps.needed > 0 then
                table.insert(needs, data.composition.mdps.needed .. " Melee")
            end
            if data.composition.rdps and data.composition.rdps.needed > 0 then
                table.insert(needs, data.composition.rdps.needed .. " Ranged")
            end
            -- Backwards compatibility
            if not data.composition.mdps and not data.composition.rdps and data.composition.dps and data.composition.dps.needed > 0 then
                table.insert(needs, data.composition.dps.needed .. " DPS")
            end
            if #needs > 0 then
                roleText = "LF: " .. table.concat(needs, ", ")
            end
        end
    else
        classText = data.class and (data.class:sub(1, 1) .. data.class:sub(2):lower()) or "Unknown"
        roleText = data.role or ""
    end
    panel.classSpec:SetText(classText .. (roleText ~= "" and ("\n" .. roleText) or ""))

    -- GearScore display - show requirement for groups, actual GS for players
    local gs = data.gs or data.gearScore or data.gsRequirement
    if gs then
        local gsFormatted = AIP.InspectionEngine and AIP.InspectionEngine.FormatGS(gs) or tostring(gs)
        if currentTab == "lfm" and data.gsRequirement then
            panel.gsText:SetText("GS Requirement: " .. gsFormatted .. "+")
        else
            panel.gsText:SetText("GearScore: " .. gsFormatted)
        end
    else
        panel.gsText:SetText("")
    end

    -- Check for inspection data
    local inspectData = AIP.InspectionEngine and AIP.InspectionEngine.GetCachedData(playerName)
    if inspectData then
        panel.enchantText:SetText("Missing Enchants: " .. inspectData.analysis.missingEnchants)
        if #inspectData.analysis.enchantableSlots > 0 then
            panel.enchantList:SetText("- " .. table.concat(inspectData.analysis.enchantableSlots, ", "))
        else
            panel.enchantList:SetText("")
        end

        panel.gemText:SetText("Empty Gem Slots: " .. inspectData.analysis.emptyGemSlots .. " / " .. inspectData.analysis.totalGemSlots)

        if inspectData.performanceEstimate then
            local perf = inspectData.performanceEstimate
            local perfStr = "Role: " .. (perf.role or "Unknown")
            if perf.estimatedDPS then
                perfStr = perfStr .. "\nEst. DPS: " .. perf.estimatedDPS
            end
            if perf.estimatedEHP then
                perfStr = perfStr .. "\nEst. EHP: " .. perf.estimatedEHP
            end
            perfStr = perfStr .. "\nConfidence: " .. (perf.confidence or "Low")
            panel.perfText:SetText(perfStr)
        end

        container.sourceText:SetText("Data: " .. (inspectData.dataSource or "Cache"))
    else
        panel.enchantText:SetText("Missing Enchants: -")
        panel.enchantList:SetText("")
        panel.gemText:SetText("Empty Gem Slots: - / -")
        panel.perfText:SetText("No inspection data available")
        container.sourceText:SetText("Data: Chat")

        -- Queue for inspection if in range
        if AIP.InspectionEngine then
            AIP.InspectionEngine.QueueInspection(playerName, 2)
        end
    end

    -- Message
    panel.msgText:SetText(data.message or "")
end

-- Hook into AIP.UpdateQueueUI to also refresh GUI queue panel
local origUpdateQueueUI = AIP.UpdateQueueUI
AIP.UpdateQueueUI = function()
    if origUpdateQueueUI then origUpdateQueueUI() end

    -- Also update the CentralGUI queue panel
    if GUI.Frame and GUI.Frame:IsVisible() and GUI.Frame.tabContents then
        local container = GUI.Frame.tabContents["lfm"]
        if container then
            GUI.UpdateQueuePanel(container)
        end
    end
end

-- Initialize on addon load (delayed to ensure db is available)
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame.initialized = false
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "AutoInvitePlus" then
        -- Create minimap button after a short delay to ensure db is ready
        local delayFrame = CreateFrame("Frame")
        delayFrame.elapsed = 0
        delayFrame:SetScript("OnUpdate", function(df, elapsed)
            df.elapsed = df.elapsed + elapsed
            if df.elapsed >= 0.5 then
                if AIP.db and not initFrame.initialized then
                    GUI.CreateMinimapButton()
                    initFrame.initialized = true
                end
                df:SetScript("OnUpdate", nil)
                df:Hide()
            end
        end)
    elseif event == "PLAYER_LOGIN" then
        -- Fallback: create minimap button if not already done
        if AIP.db and not initFrame.initialized then
            GUI.CreateMinimapButton()
            initFrame.initialized = true
        end
    end
end)

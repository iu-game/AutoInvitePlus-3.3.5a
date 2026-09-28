-- AutoInvite Plus - Tank Cast window (presentation for AIP.TankCast)
-- A deliberately tiny floating window: a 16px title bar (right-click it for every
-- control - add off-tank, import, push, lock, clear all, close - as one menu, so
-- nothing but "TANKS" and a warning dot is ever drawn there) and one 22px row per
-- tank made of just
--   [selector + health bar][class-coloured badge][pick icons...][+]
-- (the window widens as picks are added, and flows into extra columns after 8 rows).
-- The selector strip targets the tank (secure `/target <Name>`); the badge's tooltip
-- carries everything else - name, class, spec, role, health/state, live debuffs with
-- icons and the tank's picks - for players AND pets. Each pick icon is a secure
-- button that casts that spell/item on that tank via `/cast [target=<Name>] <pick>`.
--
-- 3.3.5a secure-frame rules this file obeys:
--  * every row's pick buttons and selector are SecureActionButtonTemplate
--    (protected): attributes, Show/Hide and SetPoint are ONLY touched when not
--    InCombatLockdown() (see applyStructure). Rows are created ON DEMAND there too,
--    so adding a tank in combat simply waits for combat to end;
--  * their parents (the row containers) and the window are therefore
--    implicitly protected too (verified live: IsProtected() == 1): Show/Hide/
--    SetHeight/StartMoving on them are also blocked in combat, so they are
--    guarded/deferred the same way, and every frame is CREATED out of combat
--    (PLAYER_LOGIN / first ShowWindow);
--  * everything is rendered from the `applied` snapshot, so the window never
--    disagrees with what a click casts while an edit waits for combat to end -
--    and because the snapshot can lag the live list, index-based EDIT actions are
--    refused while a change is pending (TK.GuardEdit);
--  * all the visual polish (gradients, health glide, ready flash, cooldown text,
--    tints, the status dot) only touches textures / font strings, never protected.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.TankCast = AIP.TankCast or {}
local TK = AIP.TankCast
local UI = AIP.UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PAD, HDR_H = 3, 16
local ROW_H, ROW_GAP = 22, 1
local ROWS_PER_COL, COL_GAP = 8, 3                -- past 8 tanks the window flows into more columns
local SEL_X, SEL_W = 1, 9                         -- selector strip (holds the vertical health bar)
local HP_W = 5
local BADGE_X, BADGE_SZ = 12, 20
local PICK_X, PICK_SZ, PICK_GAP = 35, 20, 2
local MIN_SLOTS = 5                               -- never narrower than 5 icon slots (the title bar needs it)...
local function rowWidth(slots) return PICK_X + slots * (PICK_SZ + PICK_GAP) + 1 end
local ROW_W = rowWidth(MIN_SLOTS)                 -- ...and widens as picks are added (up to 8)
local WIN_W = ROW_W + PAD * 2
local HP_H = ROW_H - 4
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
TK.WHITE = WHITE

local STATE_TEXT = { away = "Not in your group", offline = "Offline", dead = "Dead" }

local win
local rows = {}
local menuFrame
-- Snapshot of what the secure buttons currently do:
-- applied.count = number of tanks; applied.tanks[i] = { name, picks = { {text, kind, icon, friendly} } }
local applied = { count = 0, tanks = {} }
local refresh, refreshValues                            -- forward declarations

-- ============================================================================
-- SKIN HELPERS (shared with TankCastConfig.lua)
-- ============================================================================

-- Locale-safe font: reuse the game's own font face at a custom size.
local function fontize(fs, size, flags)
    local font = GameFontHighlight and GameFontHighlight:GetFont()
    if font then fs:SetFont(font, size, flags or "") end
    return fs
end
TK.Fontize = fontize

-- Crisp 1px border + a subtle top-to-bottom body gradient.
function TK.SkinPanel(f, bgAlpha)
    f:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    f:SetBackdropColor(0.04, 0.045, 0.065, bgAlpha or 0.96)
    f:SetBackdropBorderColor(0.30, 0.33, 0.42, 1)
    local body = f:CreateTexture(nil, "BACKGROUND")
    body:SetPoint("TOPLEFT", 1, -1); body:SetPoint("BOTTOMRIGHT", -1, 1)
    body:SetTexture(1, 1, 1, 1)
    body:SetGradientAlpha("VERTICAL", 0.03, 0.035, 0.05, 1, 0.075, 0.08, 0.115, 1)
end

-- Gradient title strip with a gold hairline and a faint gold glow beneath it.
function TK.SkinHeader(f, h)
    local hdr = f:CreateTexture(nil, "BORDER")
    hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(h - 1)
    hdr:SetTexture(1, 1, 1, 1)
    hdr:SetGradientAlpha("VERTICAL", 0.09, 0.10, 0.15, 1, 0.17, 0.18, 0.26, 1)
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0); div:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    div:SetHeight(1); div:SetTexture(1, 0.82, 0, 0.55)
    local glow = f:CreateTexture(nil, "ARTWORK")
    glow:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, 0); glow:SetPoint("TOPRIGHT", div, "BOTTOMRIGHT", 0, 0)
    glow:SetHeight(4); glow:SetTexture(1, 1, 1, 1)
    glow:SetGradientAlpha("VERTICAL", 1, 0.82, 0, 0, 1, 0.82, 0, 0.12)
    return hdr
end

-- Flat button: dark fill, 1px border, gold on hover, dim when disabled
-- (Enable/Disable work as on any Button).
function TK.FlatButton(parent, text, w, h, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    b:SetBackdropColor(0.10, 0.11, 0.16, 0.95)
    b:SetBackdropBorderColor(0.24, 0.26, 0.34, 1)
    b:SetNormalFontObject(GameFontHighlightSmall)
    b:SetHighlightFontObject(GameFontNormalSmall)
    b:SetDisabledFontObject(GameFontDisableSmall)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.95, 0.76, 0.12, 1)
        self:SetBackdropColor(0.16, 0.15, 0.10, 0.98)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.24, 0.26, 0.34, 1)
        self:SetBackdropColor(0.10, 0.11, 0.16, 0.95)
        GameTooltip:Hide()
    end)
    return b
end

-- Small "x" close button (title bars).
function TK.CloseButton(parent, onClick, size)
    size = size or 14
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local fs = fontize(b:CreateFontString(nil, "OVERLAY"), size - 1, "OUTLINE")
    fs:SetPoint("CENTER", 0, 1); fs:SetText("x"); fs:SetTextColor(0.7, 0.72, 0.8)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        fs:SetTextColor(1, 0.35, 0.3)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Close"); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() fs:SetTextColor(0.7, 0.72, 0.8); GameTooltip:Hide() end)
    return b
end

local PET_R, PET_G, PET_B = 0.45, 0.75, 0.45

local function classColor(class)
    if class == "PET" then return PET_R, PET_G, PET_B end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.9
end

local function hex(r, g, b)
    return string.format("|cFF%02X%02X%02X",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function TK.EnsureMenuFrame()
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "AIPTankCastMenu", UIParent, "UIDropDownMenuTemplate")
    end
    return menuFrame
end

local function snapshotName(slot)
    local s = applied.tanks[slot]
    return s and s.name or ""
end

-- Structural edits are refused while a change waits for combat to end: the window
-- still shows the OLD list, so a slot/pick index taken from it could hit the wrong
-- entry of the live list.
function TK.GuardEdit()
    if TK.EditsAllowed() then return true end
    AIP.Print("Changes apply after combat - wait for the fight to end before editing again.")
    return false
end

-- Wrap a menu action so it re-checks the guard at click time.
local function act(fn)
    return function(...)
        if TK.GuardEdit() then fn(...) end
    end
end

-- ============================================================================
-- MENUS / DROP
-- ============================================================================

-- Tank menu (click a badge): use my target / clear / remove tank / assign.
local function openTankMenu(slot)
    if not TK.GuardEdit() then return end
    local current = TK.GetSlot(slot)
    local list = {}
    list[#list + 1] = {
        text = TK.SlotLabel(slot) .. ((current ~= "") and (" - " .. current) or ""),
        isTitle = true, notCheckable = true,
    }
    list[#list + 1] = {
        text = "Use my target", notCheckable = true,
        func = act(function()
            local n = TK.TargetName()
            if not n then AIP.Print("Target a player first.") return end
            local ok, err = TK.SetSlot(slot, n)
            if not ok then AIP.Print(err) end
        end),
    }
    if current ~= "" then
        list[#list + 1] = { text = "Clear player", notCheckable = true, func = act(function() TK.SetSlot(slot, "") end) }
    end
    if slot >= 2 then
        list[#list + 1] = {
            text = "Remove tank", notCheckable = true,
            func = act(function()
                local ok, err = TK.RemoveTank(slot)
                if not ok then AIP.Print(err) end
            end),
        }
    end

    local cands = TK.GetCandidates()
    if #cands > 0 then
        list[#list + 1] = { text = "Assign player", isTitle = true, notCheckable = true }
        local sawOthers, sawPets = false, false
        for k, cand in ipairs(cands) do
            if k > 60 then break end
            if cand.pet then
                if not sawPets then
                    sawPets = true
                    list[#list + 1] = { text = "Pets", isTitle = true, notCheckable = true }
                end
            elseif not cand.tank and not sawOthers then
                sawOthers = true
                list[#list + 1] = { text = "Other classes", isTitle = true, notCheckable = true }
            end
            local text = hex(classColor(cand.pet and "PET" or cand.class)) .. cand.name .. "|r"
            local at = TK.FindSlot(cand.name)
            if at then text = text .. " |cFF888888(" .. TK.SlotLabel(at) .. ")|r" end
            list[#list + 1] = {
                text = text, notCheckable = true,
                func = act(function()
                    local ok, err = TK.SetSlot(slot, cand.name)
                    if not ok then AIP.Print(err) end
                end),
            }
        end
    end
    list[#list + 1] = { text = "Cancel", notCheckable = true }
    EasyMenu(list, TK.EnsureMenuFrame(), "cursor", 0, 0, "MENU")
end

-- Pick menu (right-click an icon): change / remove.
local function openPickMenu(btn)
    if not TK.GuardEdit() then return end
    local slot, idx = btn.slot, btn.idx
    local pk = applied.tanks[slot] and applied.tanks[slot].picks[idx]
    local list = {
        { text = pk and pk.text or "Pick", isTitle = true, notCheckable = true },
        { text = "Change pick...", notCheckable = true,
          func = act(function() if TK.OpenPicker then TK.OpenPicker(slot, idx) end end) },
        { text = "Remove pick", notCheckable = true,
          func = act(function()
              local ok, err = TK.RemovePick(slot, idx)
              if not ok then AIP.Print(err) end
          end) },
        { text = "Cancel", notCheckable = true },
    }
    EasyMenu(list, TK.EnsureMenuFrame(), "cursor", 0, 0, "MENU")
end

-- A spell/item dragged from the spellbook/bags onto an icon (replace) or [+] (add).
-- Returns true if the cursor held one (even when the edit is refused).
local function dropOn(slot, idx)
    local name = TK.FromCursor()
    if not name then return false end
    if not TK.GuardEdit() then return true end
    ClearCursor()
    local ok, err
    if idx then ok, err = TK.SetPick(slot, idx, name) else ok, err = TK.AddPick(slot, name) end
    if not ok then AIP.Print(err) end
    return true
end

-- ============================================================================
-- ROWS
-- ============================================================================

local function createPick(row, i, j)
    local b = CreateFrame("Button", "AIPTankCastPick" .. i .. "_" .. j, row, "SecureActionButtonTemplate")
    b.slot, b.idx = i, j
    b:SetSize(PICK_SZ, PICK_SZ)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:Hide()

    -- Bezel (colour = state), icon inset by 1px, swipe, then a top frame for the
    -- cooldown number and the ready-flash so they draw above the swipe.
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints(); b.border:SetTexture(0.20, 0.22, 0.30, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints(); top:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.cdText = fontize(top:CreateFontString(nil, "OVERLAY"), 9, "OUTLINE")
    b.cdText:SetPoint("CENTER", 0, 0)
    b.flash = top:CreateTexture(nil, "OVERLAY")
    b.flash:SetAllPoints(b.icon); b.flash:SetTexture(1, 0.9, 0.5, 1)
    b.flash:SetBlendMode("ADD"); b.flash:SetAlpha(0)
    b.flashA = 0
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture(1, 0.82, 0, 0.28)
    b.dim = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.dim:SetAllPoints(b.icon); b.dim:SetTexture(0, 0, 0, 0.45); b.dim:Hide()

    -- Left-click is the secure macro; this non-secure hook handles right-click and
    -- the "why did nothing happen" hints.
    b:HookScript("OnClick", function(self, button)
        if button == "RightButton" then
            openPickMenu(self)
        elseif not self.macroSet then
            if snapshotName(self.slot) == "" then
                AIP.Print("Assign a player to this tank first (click the badge).")
            else
                AIP.Print("This pick can't be cast (check the spell or item name).")
            end
        end
    end)
    b:SetScript("OnReceiveDrag", function(self) dropOn(self.slot, self.idx) end)
    b:SetScript("OnEnter", function(self)
        local snap = applied.tanks[self.slot]
        local pk = snap and snap.picks[self.idx]
        if not pk then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(pk.text, 1, 0.82, 0)
        if snap.name ~= "" then
            GameTooltip:AddLine("Left-click: cast on " .. snap.name, 1, 1, 1)
        else
            GameTooltip:AddLine("Assign a player to this tank first.", 1, 0.5, 0.3)
        end
        if not pk.kind then
            GameTooltip:AddLine("Not in your spellbook or bags.", 0.95, 0.3, 0.3)
        elseif pk.friendly == false then
            GameTooltip:AddLine("Can't target a friendly player.", 1, 0.6, 0.2)
        end
        GameTooltip:AddLine("Right-click: change / remove", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- The row that the mouse is over (its tooltip is rebuilt twice a second so debuff
-- timers and new debuffs update live).
local hoverRow

-- Everything the row does not print is here: name, class, spec, role, health/state,
-- live debuffs (with icons), the tank's picks. Works for players and pets.
local function showTankTip(row)
    local i = row.slot
    local snap = applied.tanks[i]
    if not snap then return end
    local role = (i == 1) and "Main tank" or ("Off-tank " .. (i - 1))
    GameTooltip:SetOwner(row.badge, "ANCHOR_RIGHT")
    if snap.name == "" then
        GameTooltip:AddLine("Set " .. role, 1, 0.82, 0)
        GameTooltip:AddLine("Click to pick a player or pet.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local unit = TK.UnitFor(snap.name)
    local pet = unit and TK.IsPetUnit(unit)
    local r, g, b = classColor(pet and "PET" or row.class)
    GameTooltip:AddLine(snap.name .. (pet and " (Pet)" or ""), r, g, b)
    if unit then
        if pet then
            local fam = UnitCreatureFamily and UnitCreatureFamily(unit)
            GameTooltip:AddLine("Pet" .. (fam and (" - " .. fam) or ""), 0.8, 0.82, 0.9)
        else
            local line = UnitClass(unit) or "Unknown class"
            local spec, state = TK.TankSpec(unit)
            if spec then line = line .. " - " .. spec
            elseif state == "inspecting" then line = line .. " - inspecting spec..."
            elseif state == "range" then line = line .. " - spec unknown (too far to inspect)" end
            GameTooltip:AddLine(line, 0.8, 0.82, 0.9)
        end
    end
    if row.status == "ok" then
        local pct = row.pct or 0
        GameTooltip:AddLine(role .. "  -  " .. string.format("%d%% health", math.floor(pct * 100 + 0.5)), TK.HealthColor(pct))
    else
        GameTooltip:AddLine(role .. "  -  " .. (STATE_TEXT[row.status] or "Unavailable"), 1, 0.5, 0.3)
    end
    if TK.IsAmbiguousName(snap.name) then
        GameTooltip:AddLine("Another unit shares this name - name-based casts may hit it.", 1, 0.6, 0.2, true)
    end

    if unit then
        local list, total = TK.ListDebuffs(unit, 12)
        GameTooltip:AddLine(" ")
        if total > 0 then
            GameTooltip:AddLine("Debuffs (" .. total .. ")", 1, 0.82, 0)
            for _, d in ipairs(list) do
                local c = (DebuffTypeColor and (DebuffTypeColor[d.dtype or "none"] or DebuffTypeColor["none"])) or { r = 0.8, g = 0, b = 0 }
                local icon = d.icon and ("|T" .. d.icon .. ":14|t ") or ""
                GameTooltip:AddLine(icon .. TK.FormatDebuff(d), c.r, c.g, c.b)
            end
            if total > #list then GameTooltip:AddLine("+" .. (total - #list) .. " more", 0.6, 0.62, 0.7) end
        else
            GameTooltip:AddLine("No debuffs", 0.55, 0.58, 0.68)
        end
    end

    GameTooltip:AddLine(" ")
    if #snap.picks == 0 then
        GameTooltip:AddLine("No picks yet - click + to add one", 0.6, 0.62, 0.7)
    else
        for _, pk in ipairs(snap.picks) do GameTooltip:AddLine("  " .. pk.text, 0.85, 0.87, 0.95) end
    end
    GameTooltip:AddLine("Click the badge: change / clear / remove tank", 0.6, 0.62, 0.7)
    GameTooltip:Show()
end

local function createRow(i)
    local row = CreateFrame("Frame", "AIPTankCastRow" .. i, win)
    row.slot = i
    row.tank = ""
    row.hpShown = false
    row:SetSize(ROW_W, ROW_H)
    row:Hide()

    -- Surface: the MT row carries a faint gold tint, off-tanks stay neutral.
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    if i == 1 then row.bg:SetTexture(0.16, 0.135, 0.07, 0.95) else row.bg:SetTexture(0.10, 0.11, 0.16, 0.94) end

    -- Selector strip: a secure button that targets the tank. It also carries the
    -- vertical health bar (dark trough + colour-ramped fill that glides).
    row.sel = CreateFrame("Button", "AIPTankCastSel" .. i, row, "SecureActionButtonTemplate")
    row.sel.slot = i
    row.sel:SetSize(SEL_W, ROW_H - 2)
    row.sel:SetPoint("TOPLEFT", SEL_X, -1)
    row.sel:RegisterForClicks("LeftButtonUp")
    row.hpTrough = row.sel:CreateTexture(nil, "ARTWORK")
    row.hpTrough:SetPoint("TOPLEFT", 2, -1); row.hpTrough:SetSize(HP_W, HP_H)
    row.hpTrough:SetTexture(0, 0, 0, 0.7)
    row.hpFill = row.sel:CreateTexture(nil, "OVERLAY")
    row.hpFill:SetPoint("BOTTOMLEFT", row.hpTrough, "BOTTOMLEFT", 0, 0)
    row.hpFill:SetSize(HP_W, 1); row.hpFill:SetTexture(0.2, 0.85, 0.3, 1)
    local shl = row.sel:CreateTexture(nil, "HIGHLIGHT")
    shl:SetAllPoints(); shl:SetTexture(1, 0.82, 0, 0.25)
    row.sel:HookScript("OnClick", function(self)
        if not self.macroSet then AIP.Print("Assign a player or pet to this tank first (click the badge).") end
    end)
    row.sel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local nm = snapshotName(i)
        if nm == "" then
            GameTooltip:AddLine("No one assigned", 0.7, 0.72, 0.8)
        else
            GameTooltip:AddLine("Target " .. nm, 1, 0.82, 0)
            GameTooltip:AddLine("Click to select this tank.", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row.sel:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Badge: class-coloured tile with the role label. Click = tank menu; hover = details.
    row.badge = CreateFrame("Button", nil, row)
    row.badge:SetPoint("TOPLEFT", BADGE_X, -1); row.badge:SetSize(BADGE_SZ, BADGE_SZ)
    row.badge:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    row.badge.text = fontize(row.badge:CreateFontString(nil, "OVERLAY"), 9, "OUTLINE")
    row.badge.text:SetPoint("CENTER", 0, 0)
    row.badge.text:SetText(TK.SlotBadge(i))
    local bhl = row.badge:CreateTexture(nil, "HIGHLIGHT")
    bhl:SetAllPoints(); bhl:SetTexture(1, 0.82, 0, 0.25)
    row.badge:SetScript("OnClick", function() openTankMenu(i) end)
    row.badge:SetScript("OnEnter", function() hoverRow = row; showTankTip(row) end)
    row.badge:SetScript("OnLeave", function() hoverRow = nil; GameTooltip:Hide() end)

    row.picks = {}
    for j = 1, TK.MAX_PICKS do row.picks[j] = createPick(row, i, j) end

    -- Ghost [+] slot: add a pick.
    row.plus = CreateFrame("Button", nil, row)
    row.plus:SetSize(PICK_SZ, PICK_SZ); row.plus:Hide()
    row.plus:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    row.plus:SetBackdropColor(0.08, 0.09, 0.13, 0.6)
    row.plus:SetBackdropBorderColor(0.22, 0.24, 0.32, 0.8)
    local pfs = fontize(row.plus:CreateFontString(nil, "OVERLAY"), 14, "OUTLINE")
    pfs:SetPoint("CENTER", 0, 1); pfs:SetText("+"); pfs:SetTextColor(0.42, 0.45, 0.55)
    row.plus:SetScript("OnClick", function()
        if not TK.GuardEdit() then return end
        if not dropOn(i, nil) and TK.OpenPicker then TK.OpenPicker(i, nil) end
    end)
    row.plus:SetScript("OnReceiveDrag", function() dropOn(i, nil) end)
    row.plus:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.95, 0.76, 0.12, 1); pfs:SetTextColor(1, 0.82, 0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Add a pick", 1, 0.82, 0)
        GameTooltip:AddLine("Click to choose a spell or item, or drag one here.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.plus:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.22, 0.24, 0.32, 0.8); pfs:SetTextColor(0.42, 0.45, 0.55)
        GameTooltip:Hide()
    end)
    return row
end

local function paintHp(row)
    row.hpFill:SetHeight(math.max(1, (row.hpH or HP_H) * row.hpCur))
    row.hpFill:SetTexture(TK.HealthColor(row.hpCur))
end

-- Position of the k-th slot (the picks, then the [+]) inside a row: one line, left to right.
local function slotPos(k)
    return PICK_X + (k - 1) * (PICK_SZ + PICK_GAP), -1
end

-- ============================================================================
-- LAYOUT / STRUCTURE
-- ============================================================================

-- Window size. The window is implicitly protected (parent of protected rows),
-- so resizing in combat is blocked: defer to the post-combat flush (refresh
-- re-runs this).
function TK.LayoutWindow()
    if not win then return end
    if InCombatLockdown() then TK.dirty = true; return end
    win:SetSize(win.contentW or WIN_W, win.contentH or (HDR_H + PAD + ROW_H + PAD))
end

local function ensureRow(i)
    if not rows[i] then rows[i] = createRow(i) end   -- out of combat only (called from applyStructure)
    return rows[i]
end

-- Take a row (and all its secure buttons) out of service.
local function retireRow(row)
    row.tank = ""
    row.hpShown = false
    row.sel:SetAttribute("type1", nil)
    row.sel:SetAttribute("macrotext1", nil)
    row.sel.macroSet = false
    for j = 1, TK.MAX_PICKS do
        local btn = row.picks[j]
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("macrotext1", nil)
        btn.macroSet = false
        btn:Hide()
    end
    row.plus:Hide()
    row:Hide()
end

-- Out-of-combat only: snapshot the list, create any missing rows, (re)write every
-- secure attribute, lay out rows / pick icons / [+] in columns, refresh the
-- title-bar buttons' enabled state.
local function applyStructure()
    local n = TK.NumTanks()
    applied.count = n
    -- One line per tank; every row is as wide as the widest needs (picks + the [+]).
    local maxSlots = MIN_SLOTS
    for i = 1, n do
        local c = #TK.GetPicks(i)
        local sl = c + ((c < TK.MAX_PICKS) and 1 or 0)
        if sl > maxSlots then maxSlots = sl end
    end
    local rowW = rowWidth(maxSlots)
    for i = 1, n do
        local row = ensureRow(i)
        row.cacheKey = nil                                   -- force a repaint of badge/class
        local name = TK.GetSlot(i)
        local picks = TK.GetPicks(i)
        local snap = { name = name, picks = {} }
        applied.tanks[i] = snap
        row.tank = name
        local tmacro = TK.BuildTargetMacro(name)
        row.sel:SetAttribute("type1", tmacro and "macro" or nil)
        row.sel:SetAttribute("macrotext1", tmacro)
        row.sel.macroSet = tmacro ~= nil
        for j = 1, TK.MAX_PICKS do
            local btn, text = row.picks[j], picks[j]
            btn.cdStart, btn.cdDur = nil, nil
            btn.onCd, btn.flashA = false, 0
            btn.flash:SetAlpha(0)
            if text then
                local kind, icon = TK.ResolveSpell(text)
                snap.picks[j] = { text = text, kind = kind, icon = icon, friendly = TK.IsFriendlyCastable(text) }
                local macro = TK.BuildMacro(name, text)
                btn:SetAttribute("type1", macro and "macro" or nil)
                btn:SetAttribute("macrotext1", macro)
                btn.macroSet = macro ~= nil
                local px, py = slotPos(j)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", row, "TOPLEFT", px, py)
                btn:Show()
            else
                btn:SetAttribute("type1", nil)
                btn:SetAttribute("macrotext1", nil)
                btn.macroSet = false
                btn:Hide()
            end
        end
        if #picks < TK.MAX_PICKS then
            local px, py = slotPos(#picks + 1)
            row.plus:ClearAllPoints()
            row.plus:SetPoint("TOPLEFT", row, "TOPLEFT", px, py)
            row.plus:Show()
        else
            row.plus:Hide()
        end
        local col, r = math.floor((i - 1) / ROWS_PER_COL), (i - 1) % ROWS_PER_COL
        row:SetWidth(rowW)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + col * (rowW + COL_GAP), -(HDR_H + PAD + r * (ROW_H + ROW_GAP)))
        row:Show()
    end
    for i = n + 1, #rows do
        applied.tanks[i] = nil
        retireRow(rows[i])
    end
    local cols = math.max(1, math.ceil(n / ROWS_PER_COL))
    local tall = math.max(1, math.min(n, ROWS_PER_COL))
    win.contentW = PAD * 2 + cols * rowW + (cols - 1) * COL_GAP
    win.contentH = HDR_H + PAD + tall * (ROW_H + ROW_GAP) - ROW_GAP + PAD
    TK.LayoutWindow()
end

-- ============================================================================
-- LIVE VALUES (health, range, usability, cooldowns, status dot)
-- ============================================================================

-- Colour the badge for a class (nil class + filled = out of group: neutral;
-- unfilled = empty slot: near-black).
local function paintBadge(row, filled, class)
    local b = row.badge
    if not filled then
        b:SetBackdropColor(0.09, 0.10, 0.14, 0.9); b:SetBackdropBorderColor(0.25, 0.27, 0.35, 1)
        b.text:SetTextColor(0.5, 0.53, 0.62)
    else
        local r, g, bl = 0.45, 0.47, 0.55
        if class then r, g, bl = classColor(class) end
        b:SetBackdropColor(r * 0.42, g * 0.42, bl * 0.42, 0.95); b:SetBackdropBorderColor(r, g, bl, 1)
        if row.slot == 1 then b.text:SetTextColor(1, 0.86, 0.3) else b.text:SetTextColor(1, 1, 1) end
    end
end

local function cooldownFor(pk, cache)
    local c = cache[pk.text]
    if not c then
        local s, d, e = TK.GetCooldown(pk.text, pk.kind)
        if d and d <= 1.5 then s, d = 0, 0 end            -- ignore the global cooldown
        c = { s or 0, d or 0, e or 0 }
        cache[pk.text] = c
    end
    return c
end

local function updateRow(i, cache, now)
    local row, snap = rows[i], applied.tanks[i]
    if not snap then return end
    local name = snap.name
    local unit, status
    if name == "" then
        if row.cacheKey ~= "" then
            row.cacheKey = ""
            row.class = nil
            paintBadge(row, false, nil)
        end
        row.hpFill:Hide(); row.hpShown = false
        row.badge:SetAlpha(1)
        status = "away"
    else
        unit = TK.UnitFor(name)
        local class
        if unit then
            if TK.IsPetUnit(unit) then class = "PET" else local _, cl = UnitClass(unit); class = cl end
        end
        local key = name .. "|" .. (class or "")
        if row.cacheKey ~= key then                          -- name/class changed: repaint once
            row.cacheKey = key
            row.class = class
            paintBadge(row, true, class)
            row.hpCur = nil                                  -- snap (don't glide) on a new tank
        end
        local pct = 0
        if unit and UnitExists(unit) then
            local m = UnitHealthMax(unit)
            if m and m > 0 then pct = UnitHealth(unit) / m end
        end
        row.pct = pct
        row.hpTarget = pct
        if not row.hpCur then row.hpCur = pct; paintHp(row) end
        row.hpShown = true
        row.hpFill:Show()
        status = TK.Status(name)
        row.badge:SetAlpha(status == "ok" and 1 or 0.5)
    end
    row.status = status

    for j = 1, TK.MAX_PICKS do
        local btn, pk = row.picks[j], snap.picks[j]
        if pk then
            if not pk.kind then     -- an item may not have been cached when applied; retry
                pk.kind, pk.icon = TK.ResolveSpell(pk.text)
                if pk.kind then pk.friendly = TK.IsFriendlyCastable(pk.text) end
            end
            btn.icon:SetTexture(pk.icon or QUESTION)
            if not pk.kind then btn.border:SetTexture(0.9, 0.2, 0.2, 1)
            elseif pk.friendly == false then btn.border:SetTexture(0.95, 0.6, 0.2, 1)
            else btn.border:SetTexture(0.20, 0.22, 0.30, 1) end

            -- Out of reach (or tank away/dead/offline): grey it out. Otherwise tint
            -- like an action bar: blue = no mana, grey = not usable right now.
            local out = (status ~= "ok") or not TK.InRange(name, unit, pk.text, pk.kind)
            local usable, noMana = true, false
            if pk.kind then usable, noMana = TK.Usability(pk.text, pk.kind) end
            if out then
                btn.icon:SetDesaturated(1); btn.icon:SetVertexColor(1, 1, 1); btn.dim:Show()
            else
                btn.icon:SetDesaturated(nil); btn.dim:Hide()
                if noMana then btn.icon:SetVertexColor(0.45, 0.45, 1)
                elseif not usable then btn.icon:SetVertexColor(0.6, 0.6, 0.6)
                else btn.icon:SetVertexColor(1, 1, 1) end
            end

            -- Cooldown: swipe (only re-armed on change), readable number, ready flash.
            local cdv = cooldownFor(pk, cache)
            if btn.cdStart ~= cdv[1] or btn.cdDur ~= cdv[2] then
                CooldownFrame_SetTimer(btn.cd, cdv[1], cdv[2], cdv[3])
                btn.cdStart, btn.cdDur = cdv[1], cdv[2]
            end
            local remain = (cdv[2] > 0 and cdv[1] > 0) and (cdv[1] + cdv[2] - now) or 0
            if remain > 0 then
                btn.cdText:SetText(TK.FormatCooldown(remain))
                if remain <= 3 then btn.cdText:SetTextColor(1, 0.5, 0.2) else btn.cdText:SetTextColor(1, 1, 1) end
                btn.onCd = true
            else
                if btn.onCd then btn.flashA = 1 end          -- just came off cooldown: flash
                btn.onCd = false
                btn.cdText:SetText("")
            end
        end
    end
end

-- What needs the user's attention. Shown as a dot in the title bar (hover the
-- title for the list) - no footer, and no height change (the window can't be
-- resized in combat).
local function collectIssues()
    local out = {}
    if TK.dirty then out[#out + 1] = { "Changes apply after combat", 1, 0.6, 0.2 } end
    local anyPick, unknown, notFriendly = false, false, false
    for i = 1, applied.count do
        for _, pk in ipairs(applied.tanks[i].picks) do
            anyPick = true
            if not pk.kind then unknown = true elseif pk.friendly == false then notFriendly = true end
        end
    end
    if not anyPick then out[#out + 1] = { "No picks yet - click + on a row", 1, 0.5, 0.3 } end
    if unknown then out[#out + 1] = { "A pick isn't in your spellbook or bags", 0.95, 0.3, 0.3 } end
    if notFriendly then out[#out + 1] = { "A pick can't target a friendly player", 1, 0.6, 0.2 } end
    return out
end

local function updateStatus()
    win.issues = collectIssues()
    local first = win.issues[1]
    if first then
        win.dot:SetTexture(first[2], first[3], first[4], 1); win.dot:Show()
    else
        win.dot:Hide()
    end
end

refreshValues = function()
    if not win or not win:IsShown() then return end
    local cache, now = {}, GetTime()
    for i = 1, applied.count do updateRow(i, cache, now) end
    updateStatus()
end

-- Structural refresh: everything protected is deferred while in combat.
refresh = function()
    if not win then return end
    if InCombatLockdown() then
        TK.dirty = true
        refreshValues()
        return
    end
    TK.dirty = false
    applyStructure()
    refreshValues()
end

-- Per-frame polish (cheap: only textures): health bars glide to their target,
-- the "ready" flash fades out.
local function animate(elapsed)
    local k = math.min(1, elapsed * 10)
    for i = 1, applied.count do
        local row = rows[i]
        if row.hpShown and row.hpCur then
            local d = row.hpTarget - row.hpCur
            if d > 0.002 or d < -0.002 then
                row.hpCur = row.hpCur + d * k
                paintHp(row)
            elseif row.hpCur ~= row.hpTarget then
                row.hpCur = row.hpTarget
                paintHp(row)
            end
        end
        for j = 1, TK.MAX_PICKS do
            local b = row.picks[j]
            if b.flashA > 0 then
                b.flashA = b.flashA - elapsed * 2.2
                b.flash:SetAlpha(math.max(0, b.flashA) * 0.7)
            end
        end
    end
end

-- ============================================================================
-- WINDOW
-- ============================================================================

-- Anchor by the top-left corner so the window grows right/down as picks and tanks
-- are added (a centre anchor would make it drift sideways).
local function anchorTopLeft()
    local l, t = win:GetLeft(), win:GetTop()
    if l and t then
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end
end

local function restorePosition()
    local c = TK.Cfg()
    local pos = c and c.pos
    win:ClearAllPoints()
    if pos then
        win:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", -320, 0)
    end
    anchorTopLeft()                                  -- also converts a saved centre-anchored position
end

local function ensureWindow()
    if win then return win end
    win = CreateFrame("Frame", "AIPTankCastWindow", UIParent)
    win:SetSize(WIN_W, HDR_H + PAD + ROW_H + PAD)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    TK.SkinPanel(win)
    TK.SkinHeader(win, HDR_H)

    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self)
        if InCombatLockdown() or TK.IsLocked() then return end   -- implicitly protected in combat; or locked by the user
        self.moving = true
        self:StartMoving()
    end)
    win:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = false
        self:StopMovingOrSizing()
        anchorTopLeft()
        local point, _, relPoint, x, y = self:GetPoint()
        local c = TK.Cfg()
        if c then c.pos = {point = point, relPoint = relPoint, x = x, y = y} end
    end)
    restorePosition()

    -- Title: shield, TANKS, status dot. The help overlay shows usage + any issues
    -- and forwards drags so the title still moves the window.
    local shield = win:CreateTexture(nil, "OVERLAY")
    shield:SetSize(11, 11); shield:SetPoint("TOPLEFT", 5, -3)
    shield:SetTexture("Interface\\Icons\\Ability_Warrior_ShieldWall"); shield:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local title = fontize(win:CreateFontString(nil, "OVERLAY"), 9, "OUTLINE")
    title:SetPoint("LEFT", shield, "RIGHT", 3, 0); title:SetText("TANKS"); title:SetTextColor(1, 0.82, 0)
    win.dot = win:CreateTexture(nil, "OVERLAY")
    win.dot:SetSize(5, 5); win.dot:SetPoint("LEFT", title, "RIGHT", 4, 0); win.dot:Hide()

    -- The whole title bar is one hit region: left-drag moves the window (forwarded
    -- to the window's own drag scripts), right-click opens every control as a menu
    -- (TK.TitleMenu -> id -> action), hover shows the usage hints + any issues.
    local help = CreateFrame("Button", nil, win)
    help:SetPoint("TOPLEFT", 2, -1); help:SetPoint("TOPRIGHT", -2, -1); help:SetHeight(HDR_H - 2)
    help:RegisterForDrag("LeftButton")
    help:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    help:SetScript("OnDragStart", function() local f = win:GetScript("OnDragStart"); if f then f(win) end end)
    help:SetScript("OnDragStop", function() local f = win:GetScript("OnDragStop"); if f then f(win) end end)
    local TITLE_ACTIONS = {
        add = function()
            if not TK.GuardEdit() then return end
            local idx, err = TK.AddTank()
            if not idx then AIP.Print(err) end
        end,
        import = function()
            if not TK.GuardEdit() then return end
            local _, msg = TK.ImportFromBlizzard()
            AIP.Print(msg)
        end,
        push = function() StaticPopup_Show("AIP_TANKCAST_PUSH") end,
        lock = function() TK.ToggleLocked() end,
        clear = function()
            if not TK.GuardEdit() then return end
            if TK.IsEmpty() then AIP.Print("Nothing to clear.") return end
            StaticPopup_Show("AIP_TANKCAST_RESET")
        end,
        close = function() TK.HideWindow() end,
    }
    help:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        local list = { { text = "Tank Cast", isTitle = true, notCheckable = true } }
        for _, item in ipairs(TK.TitleMenu()) do
            list[#list + 1] = {
                text = item.text, notCheckable = true, disabled = not item.enabled,
                func = TITLE_ACTIONS[item.id],
            }
        end
        list[#list + 1] = { text = "Cancel", notCheckable = true }
        EasyMenu(list, TK.EnsureMenuFrame(), self, 0, 0, "MENU")
    end)
    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Tank Cast", 1, 0.82, 0)
        GameTooltip:AddLine("Click a pick: cast it on that tank", 1, 1, 1)
        GameTooltip:AddLine("Right-click a pick: change / remove", 0.75, 0.78, 0.88)
        GameTooltip:AddLine("Click the left strip: target that tank", 0.75, 0.78, 0.88)
        GameTooltip:AddLine("Click a badge: assign / clear / remove tank", 0.75, 0.78, 0.88)
        GameTooltip:AddLine("Drag a spell or item onto a pick or +", 0.75, 0.78, 0.88)
        for _, iss in ipairs(win.issues or {}) do
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(iss[1], iss[2], iss[3], iss[4], true)
        end
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)

    win:SetScript("OnUpdate", function(self, elapsed)
        animate(elapsed)
        -- Keep an open tank tooltip live (debuff timers, new debuffs, spec arriving).
        self.tipAcc = (self.tipAcc or 0) + elapsed
        if self.tipAcc >= 0.5 then
            self.tipAcc = 0
            if hoverRow and GameTooltip:IsOwned(hoverRow.badge) then showTankTip(hoverRow) end
        end
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.25 then return end
        self.acc = 0
        refreshValues()
    end)

    TK.OnChanged(refresh)
    TK.OnRoster(function()
        refreshValues()
        -- Auto-open the moment a solo player forms/joins a group. combat
        -- lockdown is checked FIRST and before JustFormedGroup() - the latch
        -- is one-shot, so consuming it while ShowWindow can't run (mid-fight)
        -- would silently lose the auto-show for that group forever. Left
        -- ungated, the group forming during combat never gets another roster
        -- event to retry on - see the PLAYER_REGEN_ENABLED handler below,
        -- which re-runs this check once combat ends. "already shown" is
        -- checked last so it never blocks the latch from updating.
        if not InCombatLockdown() and TK.JustFormedGroup() and AIP.db and AIP.db.autoShowOnGroup and not TK.IsWindowShown() then
            TK.ShowWindow()
        end
    end)
    TK.RebuildUnits()
    win:Hide()
    refresh()
    return win
end

function TK.ShowWindow()
    if InCombatLockdown() then
        AIP.Print("The tank window can't be opened during combat - open it before the pull.")
        return
    end
    ensureWindow()
    local c = TK.Cfg()
    if c then c.shown = true end
    if UI and UI.FadeIn then UI.FadeIn(win, 0.15, 1) else win:Show() end
    refresh()
end

function TK.HideWindow()
    if InCombatLockdown() then
        AIP.Print("The tank window can't be closed during combat.")
        return
    end
    if win then win:Hide() end
    local c = TK.Cfg()
    if c then c.shown = false end
end

function TK.ToggleWindow()
    if win and win:IsShown() then TK.HideWindow() else TK.ShowWindow() end
end

function TK.IsWindowShown()
    return win ~= nil and win:IsShown()
end

-- Create the (protected) frames out of combat at login, restore visibility. If
-- the UI was reloaded mid-combat, creation waits for PLAYER_REGEN_ENABLED
-- because calls on freshly created secure frames are blocked during lockdown.
local pendingInit = false
local function initWindow()
    if InCombatLockdown() then pendingInit = true; return end
    pendingInit = false
    ensureWindow()
    local c = TK.Cfg()
    if c and c.shown then win:Show(); refresh() end
end

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    AIP.Utils.Events.Register("PLAYER_LOGIN", initWindow, "TankCastUI")
    AIP.Utils.Events.Register("PLAYER_REGEN_ENABLED", function()
        if pendingInit then initWindow() end
    end, "TankCastUI")
end

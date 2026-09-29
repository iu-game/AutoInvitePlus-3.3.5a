-- AutoInvite Plus - Tank Cast window: pick chooser popup
-- The picker fills ONE pick of ONE tank (target context set by TK.OpenPicker):
--   * Spells tab: YOUR spellbook spells that can target a friendly player
--   * Items tab : bag items detected as castable on a friendly player
--   * type a name (or shift-click a spellbook link) into the box and press Enter
-- Dragging a spell/item onto a pick icon or [+] in the window also works (see
-- TankCastWindow.lua). This file also owns the Push confirmation popup (the
-- Import / Push buttons themselves live in the window title bar, along with
-- lock-position and clear-all, whose confirmation popup is also here).
-- Skinned with the shared helpers exported by TankCastWindow.lua (loaded first).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.TankCast = AIP.TankCast or {}
local TK = AIP.TankCast
local UI = AIP.UI

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Potions/flasks/elixirs/food are self-only: clicking the pick uses it on
-- whoever clicks, not on the row's tank (the [target=] macro condition is
-- irrelevant to a self-only consumable's actual effect - see
-- modules/TankCast.lua's FRIENDLY_KINDS comment). The picker tooltip must
-- say this plainly rather than the misleading "Cast on friendly" wording
-- used for genuinely friendly-targetable items (Bandage/Soulstone/Scroll).
local SELF_ONLY_KINDS = { Potion = true, ["Elixir/Flask"] = true, Food = true }

StaticPopupDialogs["AIP_TANKCAST_PUSH"] = {
    text = "Add Main Tank / Main Assist flags for the players in your Tanks list?\n\nThis is visible to the whole raid. Flags already on other players are not removed.",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnAccept = function()
        local _, msg = TK.PushToBlizzard()
        AIP.Print(msg)
    end,
}

-- Title-bar "clear all" asks first: it wipes every tank slot and every pick.
StaticPopupDialogs["AIP_TANKCAST_RESET"] = {
    text = "Clear ALL tanks and picks?\n\nThis removes every tank slot and every pick and can't be undone.",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnAccept = function()
        if not TK.GuardEdit() then return end
        TK.Reset()
        AIP.Print("Tank list cleared.")
    end,
}

-- ============================================================================
-- PICKER POPUP
-- ============================================================================

local COLS, MAXROWS, CELL = 8, 8, 28
local PICK_W = COLS * CELL + 16
local HDR, TAB_H, NOTE_H, EDIT_H = 26, 28, 34, 26
local picker
local pickerTab = "spells"
local target = { slot = nil, idx = nil }       -- which tank / pick the picker is filling
local DEFAULT_BEZEL = { 0.22, 0.24, 0.32 }

local function pickerTitle()
    local slot = target.slot
    if not slot then return "CHOOSE A PICK" end
    local nm = TK.GetSlot(slot)
    local who = TK.SlotLabel(slot) .. ((nm ~= "") and (" " .. nm) or "")
    return (target.idx and "CHANGE PICK" or "ADD PICK") .. "  |cFFAAB0C4" .. who .. "|r"
end

local function acceptChoice(name)
    if not name or name == "" or not target.slot then return end
    if not TK.GuardEdit() then return end
    local ok, err
    if target.idx then ok, err = TK.SetPick(target.slot, target.idx, name) else ok, err = TK.AddPick(target.slot, name) end
    if not ok then AIP.Print(err) return end
    picker:Hide()
end

local function makeCell(i)
    local cell = CreateFrame("Button", nil, picker)
    cell:SetSize(CELL - 3, CELL - 3)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    cell:SetPoint("TOPLEFT", picker, "TOPLEFT", 8 + col * CELL, -(HDR + TAB_H + row * CELL))
    cell.border = cell:CreateTexture(nil, "BACKGROUND")
    cell.border:SetAllPoints(); cell.border:SetTexture(DEFAULT_BEZEL[1], DEFAULT_BEZEL[2], DEFAULT_BEZEL[3], 1)
    cell.tex = cell:CreateTexture(nil, "ARTWORK")
    cell.tex:SetPoint("TOPLEFT", 1, -1); cell.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    cell.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local hl = cell:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture(1, 0.82, 0, 0.30)
    cell:SetScript("OnClick", function(self) acceptChoice(self.entry and self.entry.name) end)
    cell:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e.link then
            GameTooltip:SetHyperlink(e.link)
            GameTooltip:AddLine(" ")
            if SELF_ONLY_KINDS[e.kind] or e.why == "consumable" then
                GameTooltip:AddLine("Self-use " .. (e.kind or "consumable") .. ": uses on whoever clicks this pick, not the row's tank",
                    0.4, 1, 0.4, true)
            else
                -- What we identified: kind + how we knew it can target a friendly.
                local how = ({ api = "flagged helpful with a range", text = "its Use text names a friendly target",
                               kind = "this kind of item targets friendlies" })[e.why]
                GameTooltip:AddLine("Cast on friendly: " .. (e.kind or "Item") .. (how and (" (" .. how .. ")") or ""), 0.4, 1, 0.4, true)
            end
        elseif e.index then
            GameTooltip:SetSpell(e.index, e.book)
        else
            GameTooltip:AddLine(e.name)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    picker.cells[i] = cell
    return cell
end

local function paintTabs()
    for _, t in ipairs({ picker.tabSpells, picker.tabItems }) do
        if t.key == pickerTab then
            t:SetBackdropBorderColor(0.95, 0.76, 0.12, 1); t:SetBackdropColor(0.16, 0.15, 0.10, 0.98)
            t:GetFontString():SetTextColor(1, 0.82, 0)
        else
            t:SetBackdropBorderColor(0.24, 0.26, 0.34, 1); t:SetBackdropColor(0.10, 0.11, 0.16, 0.95)
            t:GetFontString():SetTextColor(0.75, 0.78, 0.88)
        end
    end
end

-- Repaints from the lists captured when the picker was opened (one bag scan per
-- open; switching tabs just re-reads them).
local function populatePicker()
    if not picker then return end
    picker.title:SetText(pickerTitle())
    local spells, items = picker.spells or {}, picker.items or {}
    picker.tabSpells:SetText("Spells (" .. #spells .. ")")
    picker.tabItems:SetText("Items (" .. #items .. ")")
    paintTabs()

    local list, filtered = spells, picker.sFiltered
    if pickerTab == "items" then list, filtered = items, picker.iFiltered end
    local n = math.min(#list, COLS * MAXROWS)
    for i = 1, n do
        local cell = picker.cells[i] or makeCell(i)
        local e = list[i]
        cell.entry = e
        cell.tex:SetTexture(e.icon or QUESTION)
        -- Items get a quality-coloured bezel (green/blue/purple...); spells stay neutral.
        local r, g, b = DEFAULT_BEZEL[1], DEFAULT_BEZEL[2], DEFAULT_BEZEL[3]
        if e.quality and e.quality >= 2 and GetItemQualityColor then
            r, g, b = GetItemQualityColor(e.quality)
        end
        cell.border:SetTexture(r, g, b, 1)
        cell:Show()
    end
    for i = n + 1, #picker.cells do picker.cells[i].entry = nil; picker.cells[i]:Hide() end

    local rows = math.max(1, math.ceil(n / COLS))
    picker:SetHeight(HDR + TAB_H + rows * CELL + NOTE_H + EDIT_H + 8)
    local what = (pickerTab == "spells") and "spells" or "items"
    local note
    if #list == 0 then
        note = "No " .. what .. " found. Type a name below, or drag one onto a pick."
    elseif not filtered then
        note = "Detection API missing on this client - showing " .. what .. " that might qualify."
    elseif #list > n then
        note = "Showing the first " .. n .. ". Type a name below for the rest."
    elseif pickerTab == "items" then
        note = "Bag items detected as castable on a friendly player (grouped by kind). Hover for details."
    else
        note = "Your whole spellbook (not every spell can target a player). Not listed? Type it below."
    end
    picker.note:SetText(note)
end

local function ensurePicker()
    if picker then return picker end
    picker = CreateFrame("Frame", "AIPTankCastPicker", UIParent)
    picker:SetSize(PICK_W, 120)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    TK.SkinPanel(picker, 0.97)
    TK.SkinHeader(picker, HDR)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    picker:SetMovable(true); picker:EnableMouse(true); picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    picker.cells = {}

    picker.title = TK.Fontize(picker:CreateFontString(nil, "OVERLAY"), 11, "OUTLINE")
    picker.title:SetPoint("LEFT", picker, "TOPLEFT", 10, -HDR / 2 - 1)
    picker.title:SetTextColor(1, 0.82, 0)
    local close = TK.CloseButton(picker, function() picker:Hide() end, 18)
    close:SetPoint("TOPRIGHT", -5, -4)

    local function tab(text, key, x)
        local b = TK.FlatButton(picker, text, 104, 20, function()
            pickerTab = key
            populatePicker()
        end)
        b.key = key
        b:SetPoint("TOPLEFT", picker, "TOPLEFT", x, -(HDR + 5))
        b:SetScript("OnLeave", function() paintTabs(); GameTooltip:Hide() end)   -- keep the active look
        return b
    end
    picker.tabSpells = tab("Spells", "spells", 8)
    picker.tabItems = tab("Items", "items", 116)

    -- Type a spell/item name (or shift-click a spellbook link) and press Enter.
    picker.edit = UI.CreateEditBox(picker, PICK_W - 16, 22, false, 120)
    picker.edit:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 8, 6)
    picker.edit:SetScript("OnEnterPressed", function(self)
        local clean = TK.ParseSpellInput(self:GetText())
        self:ClearFocus()
        if clean ~= "" then self:SetText(""); acceptChoice(clean) end
    end)
    picker.edit:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    picker.edit:SetScript("OnReceiveDrag", function()
        local name = TK.FromCursor()
        if name then ClearCursor(); acceptChoice(name) end
    end)
    picker.edit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Type a spell or item name, then Enter", 1, 0.82, 0)
        GameTooltip:AddLine("You can also shift-click a spellbook spell here, or drag a spell/item onto it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    picker.edit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    picker.note = TK.Fontize(picker:CreateFontString(nil, "OVERLAY"), 10, "")
    picker.note:SetPoint("BOTTOMLEFT", picker.edit, "TOPLEFT", 0, 4)
    picker.note:SetWidth(PICK_W - 16); picker.note:SetHeight(NOTE_H - 4)
    picker.note:SetJustifyH("LEFT"); picker.note:SetJustifyV("TOP")
    picker.note:SetTextColor(0.6, 0.62, 0.7)

    picker:Hide()
    tinsert(UISpecialFrames, "AIPTankCastPicker")       -- Esc closes it
    return picker
end

-- Open the picker to fill one pick: pickIndex = the pick to replace, nil = add a new one.
function TK.OpenPicker(slot, pickIndex)
    if not TK.GuardEdit() then return end
    ensurePicker()
    target.slot, target.idx = slot, pickIndex
    picker.spells, picker.sFiltered = TK.ListSpells()
    picker.items, picker.iFiltered = TK.ListItems()  -- the only bag scan for this open
    picker:Show()
    populatePicker()
end

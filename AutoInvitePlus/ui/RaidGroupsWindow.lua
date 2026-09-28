-- AutoInvite Plus - Raid Groups window (presentation for AIP.RaidGroups)
-- A compact "who's in what group" window: class-coloured name cells packed into
-- their raid subgroups. Click a cell to target that player (secure /target macro);
-- right-click for the per-rank menu (RG.MemberMenu). Managers (raid leader or
-- assistant) see every one of the 8 groups, including empty ones, and can drag a
-- cell to another group to move/swap. Everyone else sees only non-empty groups.
--
-- Styling is borrowed from Tank Cast (AIP.TankCast.SkinPanel/SkinHeader/
-- CloseButton/Fontize/EnsureMenuFrame - guarded, since RaidGroups does not
-- otherwise depend on the TankCast module).
--
-- 3.3.5a secure-frame rules (same as Tank Cast):
--  * member cells are SecureActionButtonTemplate (protected): attributes,
--    Show/Hide and SetPoint are ONLY touched when not InCombatLockdown()
--    (see applyStructure); cells are created ON DEMAND there too;
--  * their parents (group frames) and the window are therefore implicitly
--    protected too: Show/Hide/SetSize/StartMoving on them are guarded/deferred
--    the same way, and every frame is created out of combat
--    (PLAYER_LOGIN / first ShowWindow, deferred to PLAYER_REGEN_ENABLED if the
--    UI loaded mid-combat);
--  * everything renders from a snapshot, so the window never disagrees with what
--    a click targets while a roster change waits for combat to end; moves
--    (structural) are refused outright while RG.dirty (see TK.GuardEdit's
--    Tank Cast precedent - RG.GuardEdit mirrors it).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.RaidGroups = AIP.RaidGroups or {}
local RG = AIP.RaidGroups
local TC = AIP.TankCast   -- optional: only used for shared skin helpers + Tank Cast menu rows

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PAD, HDR_H = 4, 16
-- Two rows per cell: row 1 = raid-icon + rank + name + quick-cast icons; row 2 = up
-- to 4 small debuff icons. This is a first-pass layout (see the plan's Global
-- Constraints note) - expect a live-feedback round after this ships.
-- 92px was the original first-pass width; live testing showed a full-length
-- (12-char, WoW's own name cap) name still ellipsised even with the quick-cast
-- reservation reclaimed (see nameFS below) - there simply wasn't enough room
-- left over after the raid-icon/rank tag. Widened so a full name fits.
local CELL_W = 130
local ROW1_H, ROW2_H, ROW_GAP = 11, 10, 1
local CELL_H, CELL_GAP = ROW1_H + ROW_GAP + ROW2_H, 2
local GROUP_GAP = 4
-- Distinct from GROUP_GAP (spacing between group COLUMNS in the same grid-row):
-- with only GROUP_GAP governing row-to-row spacing too, the manager view's two
-- rows (groups 1-4, then 5-8 - GridSize(8) = 4x2) read as one undifferentiated
-- block of cells, not "two rows" - confirmed live (2026-09-27). Big enough to
-- be unmistakable at a glance without eating much vertical budget.
local ROW_BAND_GAP = 14
local DIMS = { cellW = CELL_W, cellH = CELL_H, gap = CELL_GAP, groupGap = GROUP_GAP, rowGap = ROW_BAND_GAP, pad = PAD }
local MAX_DEBUFF_ICONS = 4
local DEBUFF_ICON_SZ = ROW2_H

local function fontize(fs, size, flags)
    if TC and TC.Fontize then return TC.Fontize(fs, size, flags) end
    local font = GameFontHighlight and GameFontHighlight:GetFont()
    if font then fs:SetFont(font, size, flags or "") end
    return fs
end

local function skinPanel(f, alpha)
    if TC and TC.SkinPanel then TC.SkinPanel(f, alpha); return end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1} })
    f:SetBackdropColor(0.04, 0.045, 0.065, alpha or 0.96)
    f:SetBackdropBorderColor(0.30, 0.33, 0.42, 1)
end

local function skinHeader(f, h)
    if TC and TC.SkinHeader then TC.SkinHeader(f, h); return end
    local hdr = f:CreateTexture(nil, "BORDER")
    hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(h - 1)
    hdr:SetTexture(0.12, 0.13, 0.19, 1)
end

local function menuFrame()
    if TC and TC.EnsureMenuFrame then return TC.EnsureMenuFrame() end
    RG.menuFrame = RG.menuFrame or CreateFrame("Frame", "AIPRaidGroupsMenu", UIParent, "UIDropDownMenuTemplate")
    return RG.menuFrame
end

local win
local cellPool = {}             -- flat pool of member-cell buttons, reused across groups
local rowDividerPool = {}       -- thin horizontal lines between grid-rows of GROUPS (e.g. 1-4 / 5-8)
local applied = { snap = nil, visible = {}, layout = nil, hasTankCast = false }
local refresh, refreshValues

-- Structural edits are refused while a change waits for combat to end (mirrors
-- Tank Cast's TK.GuardEdit): the window still shows the OLD roster, so an index
-- taken from it could hit the wrong live member.
function RG.GuardEdit()
    if not RG.dirty then return true end
    AIP.Print("Changes apply after combat - wait for the fight to end before editing again.")
    return false
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.65
end

-- ============================================================================
-- MEMBER / WINDOW ACTIONS (menu id -> effect)
-- ============================================================================

local function act(fn)
    return function() if RG.GuardEdit() then fn() end end
end

local function doMemberAction(id, member)
    local unit = member.unit
    if id == "whisper" then if ChatFrame_SendTell then ChatFrame_SendTell(member.name) end
    elseif id == "inspect" then if InspectUnit and unit then InspectUnit(unit) end
    elseif id == "achievements" then if InspectAchievements and unit then InspectAchievements(unit) end
    elseif id == "trade" then if InitiateTrade and unit then InitiateTrade(unit) end
    elseif id == "follow" then if FollowUnit and unit then FollowUnit(unit) end
    elseif id == "tank_mt" then
        if AIP.TankCast and AIP.TankCast.SetSlot then
            local ok, err = AIP.TankCast.SetSlot(1, member.name); if not ok then AIP.Print(err) end
        end
    elseif id == "tank_ot" then
        if AIP.TankCast and AIP.TankCast.SetFirstOT then
            local ok, err = AIP.TankCast.SetFirstOT(member.name); if not ok then AIP.Print(err) end
        end
    -- set_mt/clear_mt/set_ma/clear_ma are gone: SetPartyAssignment/
    -- ClearPartyAssignment are unconditionally protected and this menu
    -- handler is not a secure context - see the comment in RG.MemberMenu.
    -- Replaced by a secure modifier-click on the cell itself (applyStructure,
    -- below).
    elseif id == "promote_leader" then if PromoteToLeader and unit then PromoteToLeader(unit) end
    elseif id == "promote_assist" then if PromoteToAssistant and unit then PromoteToAssistant(unit) end
    elseif id == "demote_assist" then if DemoteAssistant and unit then DemoteAssistant(unit) end
    elseif id == "master_looter" then if SetLootMethod then SetLootMethod("master", member.name) end
    elseif id == "uninvite" then
        StaticPopup_Show("AIP_RAIDGROUPS_UNINVITE", member.name, nil, member.name)
    elseif id == "add_friend" then if AddFriend then AddFriend(member.name) end
    elseif id == "note_private" then
        StaticPopup_Show("AIP_RAIDGROUPS_NOTE", member.name, nil, member.name)
    elseif id == "note_assignment" then
        StaticPopup_Show("AIP_RAIDGROUPS_ASSIGNMENT", member.name, nil, member.name)
    elseif id == "raid_icon_clear" then
        if applied.snap then
            local ok, err = RG.SetRaidIcon(applied.snap, member.name, 0)
            if not ok then AIP.Print(err) end
        end
    else
        local iconIdx = id:match("^raid_icon_(%d+)$")
        if iconIdx and applied.snap then
            local ok, err = RG.SetRaidIcon(applied.snap, member.name, tonumber(iconIdx))
            if not ok then AIP.Print(err) end
            return
        end
        local g = id:match("^move_(%d+)$")
        if g and applied.snap then
            local plan, err = RG.PlanMove(applied.snap, member.name, { group = tonumber(g) })
            if plan then RG.ExecMove(plan) else AIP.Print(err) end
        end
    end
end

-- Long same-kind runs (8 raid icons, 8 move-to-group, 4 MT/MA) would otherwise
-- make this a 20+ row flat menu; RG.MemberMenu tags each with a `group`, and
-- here they fold into one submenu row per group (hasArrow + menuList is
-- EasyMenu's own nested-submenu mechanism), leaving only the single-purpose
-- actions as top-level rows.
local GROUP_LABEL = { icons = "Set Raid Icon", move = "Move to Group", assign = "Main Tank / Assist" }
local GROUP_ORDER = { "assign", "icons", "move" }

local function openMemberMenu(member)
    if not applied.snap then return end
    local list = { { text = member.name, isTitle = true, notCheckable = true } }
    local groups = {}
    for _, item in ipairs(RG.MemberMenu(applied.snap, member, applied.hasTankCast)) do
        local entry = {
            text = item.text, notCheckable = true, disabled = not item.enabled,
            func = act(function() doMemberAction(item.id, member) end),
        }
        if item.group then
            groups[item.group] = groups[item.group] or {}
            local sub = groups[item.group]
            sub[#sub + 1] = entry
        else
            list[#list + 1] = entry
        end
    end
    for _, g in ipairs(GROUP_ORDER) do
        if groups[g] then
            list[#list + 1] = { text = GROUP_LABEL[g] or g, notCheckable = true, hasArrow = true, menuList = groups[g] }
        end
    end
    list[#list + 1] = { text = "Cancel", notCheckable = true }
    EasyMenu(list, menuFrame(), "cursor", 0, 0, "MENU")
end

local function doWindowAction(id)
    if id == "lock" then RG.ToggleLocked()
    elseif id == "group_lock" then
        if applied.snap then
            local ok, err = RG.ToggleGroupLocked(applied.snap)
            if not ok then AIP.Print(err) end
        end
    elseif id == "ready_check" then if DoReadyCheck then DoReadyCheck() end
    elseif id == "announce_all" then
        local isRaid = applied.snap and applied.snap.mode == "raid"
        StaticPopup_Show("AIP_RAIDGROUPS_ANNOUNCE_ALL", isRaid and "raid" or "party", isRaid and "Raid Warning" or "party message")
    elseif id == "convert" then
        if not applied.snap then return end
        if applied.snap.mode == "raid" and ConvertToParty then ConvertToParty()
        elseif applied.snap.mode == "party" and ConvertToRaid then ConvertToRaid() end
    elseif id == "convert_rebuild" then
        if not applied.snap then return end
        local plan, err = RG.PlanRebuildAsParty(applied.snap)
        if not plan then AIP.Print(err); return end
        table.sort(plan)
        StaticPopup_Show("AIP_RAIDGROUPS_REBUILD_PARTY", table.concat(plan, ", "), tostring(#plan), plan)
    elseif id == "close" then RG.HideWindow() end
end

local function openWindowMenu(anchor)
    if not applied.snap then return end
    local list = { { text = "Raid Groups", isTitle = true, notCheckable = true } }
    for _, item in ipairs(RG.WindowMenu(applied.snap, RG.IsLocked())) do
        list[#list + 1] = {
            text = item.text, notCheckable = true, disabled = not item.enabled,
            func = function() doWindowAction(item.id) end,
        }
    end
    list[#list + 1] = { text = "Cancel", notCheckable = true }
    EasyMenu(list, menuFrame(), anchor, 0, 0, "MENU")
end

-- text_arg1/data are both the player's name so the "Remove %s" formatting and the
-- OnAccept handler agree even if only one of them is populated on this client.
StaticPopupDialogs["AIP_RAIDGROUPS_UNINVITE"] = {
    text = "Remove %s from the raid?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self, data)
        local name = data or (self and self.data)
        if name and UninviteUnit then UninviteUnit(name) end
    end,
}

-- Fallback for a server where native ConvertToParty() is unavailable (RG.
-- PlanRebuildAsParty/ExecRebuildAsParty) - genuinely disruptive (everyone
-- else gets removed and re-invited), so unlike the "convert" id this always
-- confirms first and names exactly who it's about to touch. %s/%s are the
-- comma-joined name list and the count, filled at StaticPopup_Show time.
StaticPopupDialogs["AIP_RAIDGROUPS_REBUILD_PARTY"] = {
    text = "This server doesn't support converting a raid directly to a party. Remove and re-invite %s (%s player(s)) to rebuild it as a party instead?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self, data)
        local plan = data or (self and self.data)
        if plan then RG.ExecRebuildAsParty(plan) end
    end,
}

-- Both popups below replace the default `hasEditBox = true` single-line box
-- (a fixed ~2-inch EditBox, no word-wrap, Blizzard's own stock chrome) with a
-- custom auto-wrapping, hard-capped, non-scrollable field - see
-- ensureCappedEditBox below for the current design and its revision history.
-- Because the built-in editbox is gone, there's no `self.editBox` and no
-- EditBoxOnEnterPressed/EditBoxOnEscapePressed to wire on the
-- StaticPopupDialogs entries themselves (those fields only ever apply to the
-- auto-created box) - the custom box wires its own OnEnterPressed/
-- OnEscapePressed instead, and Escape still also closes the whole dialog via
-- `hideOnEscape`.
--
-- StaticPopup1-4 are a small POOL of frames Blizzard reuses across every
-- addon's dialogs, not one frame per dialog TYPE - so the custom child we
-- cache on `self.aipEB` must be explicitly hidden in OnHide, or it would
-- keep showing (empty, but visible) if that pooled frame is later reused for
-- a completely unrelated dialog.
-- REVISED 2026-09-27, twice: (1) notes/assignments must be hard-capped at
-- RG.MAX_NOTE_LEN and never scrollable (the user reversed the earlier
-- "multi-line" ask once they saw it live); (2) "hold, keep the design of the
-- input as is, remove the scroll bar, and the text should be wrapped to fit
-- ... automatic, not with new lines" - i.e. keep the taller box's visual
-- size, drop the scrollbar entirely, and let long text WRAP across visual
-- lines within the fixed box (word-wrap is a display concern - WoW never
-- writes an actual "\n" into the string for a wrapped line, only for a real
-- Enter keypress) while still never allowing a genuine newline into the
-- stored value.
-- EB_H is a MINIMUM only (two lines' worth) - the box now grows elastically
-- with real measured content instead of a fixed guess, because
-- RG.MAX_NOTE_LEN went 60->240 (to fit a full RAID_WARNING) and a fixed
-- 90px box sized for 60 chars would overflow behind the buttons for a
-- long one with no scrollbar to fall back on (see
-- elastic-container-sizing-principle memory).
local EB_W, EB_MIN_H = 280, 40
local TITLE_GAP, BTN_GAP, BOTTOM_MARGIN = 14, 30, 12
local function ensureCappedEditBox(self)
    if not self.aipEB then
        -- Re-skin the whole popup to match this addon's dark navy/gold theme
        -- instead of default Blizzard stone chrome (reported live with
        -- screenshots, 2026-09-27). StaticPopupTemplate draws its ornate
        -- border art as separate Texture regions on top of the backdrop, so
        -- hiding them (BEFORE re-skinning, not after - this client's own
        -- SetBackdrop fill is ALSO implemented as regular Texture children,
        -- confirmed live; hiding "every texture" after skinPanel() wiped out
        -- the freshly-set backdrop right along with Blizzard's chrome) is
        -- required, not optional. Skip FontStrings so self.text survives.
        for i = 1, select("#", self:GetRegions()) do
            local region = select(i, self:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:Hide()
            end
        end
        skinPanel(self, 0.97)
        self.text:SetTextColor(1, 0.82, 0)

        -- Plain multi-line EditBox, no ScrollFrame wrapper at all (that's
        -- what made it scrollable before) - SetMultiLine(true) is what
        -- enables automatic word-wrap onto multiple visual lines; it does
        -- NOT by itself insert a real newline character anywhere - that only
        -- happens on an actual Enter keypress, which is intercepted below.
        local box = CreateFrame("Frame", nil, self)
        box:SetSize(EB_W, EB_MIN_H)
        box:SetPoint("TOP", self.text, "BOTTOM", 0, -TITLE_GAP)
        skinPanel(box, 0.97)
        local eb = CreateFrame("EditBox", nil, box)
        eb:SetPoint("TOPLEFT", 5, -3); eb:SetPoint("BOTTOMRIGHT", -5, 3)
        eb:SetAutoFocus(false)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetMultiLine(true)
        -- Hard-caps input at the exact same limit sanitizeNote enforces
        -- (RG.MAX_NOTE_LEN, single source of truth) - the box can never hold
        -- more than fits, so there is nothing left to scroll to; the box
        -- itself grows to fit whatever wrapped height that produces (see
        -- the OnUpdate below) instead of guessing a fixed size for it.
        eb:SetMaxLetters(RG.MAX_NOTE_LEN)
        -- Hidden same-font/same-width measuring FontString: the only
        -- reliable way to learn a wrapped multi-line EditBox's real content
        -- height in this client (EditBox:GetHeight() just reports whatever
        -- SetHeight gave it, not the wrapped text extent).
        local measure = box:CreateFontString(nil, "ARTWORK")
        measure:SetFontObject(GameFontHighlightSmall)
        measure:SetWidth(EB_W - 10)
        measure:SetWordWrap(true)
        measure:Hide()
        box.measure = measure
        -- Setting OnEnterPressed on a multi-line EditBox REPLACES its default
        -- behaviour (insert a newline) with this handler instead - Enter
        -- submits the dialog, exactly like a single-line box would, and a
        -- real newline can never be typed. (A stray one from e.g. a paste is
        -- still stripped server-side by sanitizeNote's %c match - defence in
        -- depth, not the only guard.)
        eb:SetScript("OnEnterPressed", function() StaticPopup_OnClick(self, 1) end)
        eb:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
        box.editBox = eb
        self.aipEB = box
    end
    self.aipEB:Show()
    self:SetWidth(math.max(EB_W + 60, 340))
    self.button1:ClearAllPoints()
    self.button1:SetPoint("BOTTOMLEFT", self.aipEB, "BOTTOMLEFT", 0, -BTN_GAP)
    self.button2:ClearAllPoints()
    self.button2:SetPoint("BOTTOMRIGHT", self.aipEB, "BOTTOMRIGHT", 0, -BTN_GAP)
    -- Measure-and-enforce every frame, box AND popup: a one-shot SetHeight
    -- lost a race against Blizzard's own internal StaticPopup layout
    -- re-asserting ITS OWN, unaware-of-this-box height sometime after
    -- OnShow (confirmed live by reading GetHeight() back wrong - 73px
    -- instead of ~162px - after a single SetHeight call). This has the
    -- last word every frame instead, for both the box's elastic content
    -- height and the popup's own outer height that must enclose it.
    self:SetScript("OnUpdate", function(popup)
        local box = popup.aipEB
        if box and box.measure and box.editBox then
            box.measure:SetText(box.editBox:GetText())
            local wantBoxH = math.max(EB_MIN_H, (box.measure:GetStringHeight() or 0) + 12)
            if math.abs((box:GetHeight() or 0) - wantBoxH) > 0.5 then
                box:SetHeight(wantBoxH)
            end
        end
        local top, btnBottom = popup:GetTop(), popup.button1:GetBottom()
        local wantH = top and btnBottom and ((top - btnBottom) + BOTTOM_MARGIN)
        if wantH and math.abs((popup:GetHeight() or 0) - wantH) > 0.5 then
            popup:SetHeight(wantH)
        end
    end)
    return self.aipEB.editBox
end

StaticPopupDialogs["AIP_RAIDGROUPS_NOTE"] = {
    text = "Note for %s:",
    button1 = OKAY, button2 = CANCEL, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self, data)
        local name = data or self.data
        local eb = ensureCappedEditBox(self)
        eb:SetText(name and RG.GetNote(name) or "")
        eb:SetFocus(); eb:HighlightText()
    end,
    OnHide = function(self) if self.aipEB then self.aipEB:Hide() end end,
    OnAccept = function(self, data)
        local name = data or self.data
        if not (name and self.aipEB) then return end
        local ok, err = RG.SetNote(name, self.aipEB.editBox:GetText())
        if not ok then AIP.Print(err) end
    end,
}

StaticPopupDialogs["AIP_RAIDGROUPS_ASSIGNMENT"] = {
    text = "Assignment for %s (shared with the group):",
    button1 = OKAY, button2 = CANCEL, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self, data)
        local name = data or self.data
        local eb = ensureCappedEditBox(self)
        eb:SetText(name and (RG.GetAssignment(name)) or "")
        eb:SetFocus(); eb:HighlightText()
    end,
    OnHide = function(self) if self.aipEB then self.aipEB:Hide() end end,
    OnAccept = function(self, data)
        local name = data or self.data
        if not (name and applied.snap and self.aipEB) then return end
        local ok, err = RG.SetAssignment(applied.snap, name, self.aipEB.editBox:GetText())
        if not ok then AIP.Print(err) end
    end,
}

StaticPopupDialogs["AIP_RAIDGROUPS_ANNOUNCE_ALL"] = {
    -- %s/%s filled at StaticPopup_Show time (see its call site) with the
    -- actual group word and push channel, so this reads correctly whether
    -- it was opened in a raid or a party.
    text = "Announce to the whole %s (shown as ALL: and pushed as a %s):",
    button1 = OKAY, button2 = CANCEL, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self)
        local eb = ensureCappedEditBox(self)
        local current = (RG.GetAllAnnouncementIfFresh and RG.GetAllAnnouncementIfFresh()) or ""
        eb:SetText(current)
        eb:SetFocus(); eb:HighlightText()
    end,
    OnHide = function(self) if self.aipEB then self.aipEB:Hide() end end,
    OnAccept = function(self)
        if not (applied.snap and self.aipEB) then return end
        local ok, err = RG.SetAllAnnouncement(applied.snap, self.aipEB.editBox:GetText())
        if not ok then AIP.Print(err) end
    end,
}

-- ============================================================================
-- DRAG (managers only)
-- ============================================================================

local dragTag       -- the small name tag that follows the cursor
local dragFrom       -- member name being dragged

local function ensureDragTag()
    if dragTag then return dragTag end
    dragTag = CreateFrame("Frame", "AIPRaidGroupsDragTag", UIParent)
    dragTag:SetSize(CELL_W, CELL_H)
    dragTag:SetFrameStrata("TOOLTIP")
    local bg = dragTag:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(1, 1, 1, 1)
    dragTag.bg = bg
    dragTag.fs = fontize(dragTag:CreateFontString(nil, "OVERLAY"), 10, "OUTLINE")
    dragTag.fs:SetAllPoints(); dragTag.fs:SetJustifyH("CENTER")
    dragTag:Hide()
    return dragTag
end

local function findCellUnder()
    for _, cell in ipairs(cellPool) do
        if cell:IsShown() and cell.member and cell:IsMouseOver() then return cell end
    end
    for _, frame in pairs(cellPool) do
        if type(frame) == "table" and frame.emptyGroup and frame:IsShown() and frame:IsMouseOver() then return frame end
    end
    return nil
end

local DRAG_FADE_IN = 0.12
local DRAG_FADE_OUT = 0.15

local function beginDrag(cell)
    if not (applied.snap and applied.snap.mode == "raid" and applied.snap.canManage) then return end
    dragFrom = cell.member.name
    local tag = ensureDragTag()
    local r, g, b = classColor(cell.member.class)
    tag.bg:SetTexture(r, g, b, 0.9)
    tag.fs:SetText(cell.member.name)
    -- Position at the actual cursor location before the first Show() -
    -- previously this anchored to UIParent's BOTTOMLEFT corner (0,0) for one
    -- frame before the OnUpdate below caught up, which read as a visible
    -- jump-from-the-corner glitch on every drag pickup.
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    tag:ClearAllPoints()
    tag:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    tag:SetAlpha(0)
    tag:Show()
    local fadeElapsed = 0
    tag:SetScript("OnUpdate", function(self, elapsed)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
        if fadeElapsed < DRAG_FADE_IN then
            fadeElapsed = fadeElapsed + elapsed
            self:SetAlpha(math.min(fadeElapsed / DRAG_FADE_IN, 1))
        end
    end)
end

local function endDrag()
    if not dragFrom then return end
    local target = findCellUnder()
    local plan, err
    if target and target.member then
        if not RG.GuardEdit() then dragFrom = nil; if dragTag then dragTag:Hide() end; return end
        plan, err = RG.PlanMove(applied.snap, dragFrom, { name = target.member.name })
    elseif target and target.emptyGroup then
        if not RG.GuardEdit() then dragFrom = nil; if dragTag then dragTag:Hide() end; return end
        plan, err = RG.PlanMove(applied.snap, dragFrom, { group = target.emptyGroup })
    end
    if plan then RG.ExecMove(plan) elseif err then AIP.Print(err) end
    dragFrom = nil
    -- Fade out instead of an instant Hide() so the drop reads as a release,
    -- not a hard cut.
    if dragTag then
        local tag = dragTag
        local startAlpha = tag:GetAlpha()
        local fadeElapsed = 0
        tag:SetScript("OnUpdate", function(self, elapsed)
            fadeElapsed = fadeElapsed + elapsed
            local t = math.min(fadeElapsed / DRAG_FADE_OUT, 1)
            self:SetAlpha(startAlpha * (1 - t))
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end)
    end
end

-- ============================================================================
-- CELLS
-- ============================================================================

-- Extensive tooltip: identity, live buffs/debuffs, notes/assignment, hints.
local function showCellTooltip(cell)
    local m = cell.member
    if not m then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    local r, g, b = classColor(m.class)
    GameTooltip:AddLine(m.name, r, g, b)
    GameTooltip:AddLine((m.level and (m.level .. " ") or "") .. (m.class or ""), 0.8, 0.82, 0.9)
    GameTooltip:AddLine("Group " .. m.group, 0.8, 0.82, 0.9)
    if m.rank and m.rank > 0 then GameTooltip:AddLine(RG.RankLabel(m.rank), 1, 0.82, 0) end
    if m.role == "MAINTANK" then GameTooltip:AddLine("Main Tank", 0.6, 0.8, 1) end
    if m.role == "MAINASSIST" then GameTooltip:AddLine("Main Assist", 0.6, 0.8, 1) end
    -- Live-polled, not the snapshot m.dead/m.online - see the note in
    -- refreshValues (same stale-status bug applied here too: the tooltip
    -- must never show a different status than the cell's own dot).
    local ttDead, ttOnline = m.dead, m.online
    if m.unit then
        if UnitIsDeadOrGhost then ttDead = UnitIsDeadOrGhost(m.unit) and true or false end
        if UnitIsConnected then ttOnline = UnitIsConnected(m.unit) and true or false end
    end
    if not ttOnline then GameTooltip:AddLine("Offline", 0.6, 0.6, 0.6) end
    if ttDead then GameTooltip:AddLine("Dead", 0.9, 0.3, 0.3) end
    if m.unit and UnitIsDND and UnitIsDND(m.unit) then GameTooltip:AddLine("Do Not Disturb", 1, 0.3, 0.1)
    elseif m.unit and UnitIsAFK and UnitIsAFK(m.unit) then GameTooltip:AddLine("AFK", 1, 0.82, 0) end
    -- Text backstop for the whole-cell dim in refreshValues (same
    -- accessibility reasoning as the ring+label states above it) - explains
    -- WHY a cell looks faded instead of leaving it a silent visual-only cue.
    if not m.isSelf and m.unit and UnitInRange and (UnitInRange(m.unit) == false) then
        GameTooltip:AddLine("Not nearby - may need a summon", 0.6, 0.6, 1)
    end
    local ready = RG.GetReadyStatus(m.name)
    if ready == "ready" then GameTooltip:AddLine("Ready Check: Ready", 0.4, 1, 0.4)
    elseif ready == "notready" then GameTooltip:AddLine("Ready Check: Not Ready", 1, 0.3, 0.3)
    elseif ready == "waiting" then GameTooltip:AddLine("Ready Check: No response yet", 0.8, 0.8, 0.4) end

    if m.unit then
        local buffs, btotal = RG.ListBuffs(m.unit, 20)
        local debuffs, dtotal = RG.ListDebuffs(m.unit, 20)
        if btotal > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Buffs (" .. btotal .. ")", 0.6, 1, 0.6)
            for _, a in ipairs(buffs) do
                local icon = a.icon and ("|T" .. a.icon .. ":12|t ") or ""
                local stacks = (a.count and a.count > 1) and (" x" .. a.count) or ""
                GameTooltip:AddLine(icon .. a.name .. stacks, 0.85, 0.95, 0.85)
            end
        end
        if dtotal > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Debuffs (" .. dtotal .. ")", 1, 0.6, 0.6)
            for _, a in ipairs(debuffs) do
                local c = (DebuffTypeColor and (DebuffTypeColor[a.dtype or "none"] or DebuffTypeColor["none"])) or { r = 0.8, g = 0, b = 0 }
                local icon = a.icon and ("|T" .. a.icon .. ":12|t ") or ""
                local stacks = (a.count and a.count > 1) and (" x" .. a.count) or ""
                GameTooltip:AddLine(icon .. a.name .. stacks, c.r, c.g, c.b)
            end
        end
    end

    local note = RG.GetNote(m.name)
    if note ~= "" then GameTooltip:AddLine(" "); GameTooltip:AddLine("Note: " .. note, 0.9, 0.9, 0.6, true) end
    -- *IfFresh, not the unconditional accessor: a player-directed
    -- announcement auto-clears from display RG.ANNOUNCEMENT_LINGER (40s)
    -- after being set, independent of the raid-wide one below.
    -- NOTE: an `and/or` ternary here would silently truncate the call's
    -- second return value (Lua only keeps a function call's full multi-
    -- return when it's the last/only expression on the right-hand side of
    -- the assignment, not when it's wrapped in `and`/`or`) - confirmed live,
    -- aauthor came back nil and the tooltip showed "- ?" instead of the
    -- real name. A plain if/else keeps both values intact.
    local atext, aauthor
    if RG.GetAssignmentIfFresh then
        atext, aauthor = RG.GetAssignmentIfFresh(m.name)
    else
        atext, aauthor = RG.GetAssignment(m.name)
    end
    if atext ~= "" then GameTooltip:AddLine("Assignment: " .. atext .. " - " .. (aauthor or "?"), 1, 0.82, 0, true) end
    -- Raid-wide announcement, always shown BELOW the private/player-directed
    -- one (matches "display in the tooltip under a private/player directed
    -- announcement"), independently timed from it.
    if RG.GetAllAnnouncementIfFresh then
        local alltext, allauthor = RG.GetAllAnnouncementIfFresh()
        if alltext ~= "" then GameTooltip:AddLine("All: " .. alltext .. " - " .. (allauthor or "?"), 1, 0.5, 0.2, true) end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: target  |  Right-click: options", 0.7, 0.72, 0.8)
    if applied.snap and applied.snap.mode == "raid" and applied.snap.canManage then
        GameTooltip:AddLine("Drag: move to another group", 0.7, 0.72, 0.8)
        GameTooltip:AddLine("Shift-click: Set Main Tank  |  Ctrl-click: Set Main Assist  |  Ctrl+Shift-click: Clear", 0.7, 0.72, 0.8)
    end
    GameTooltip:Show()
end

local function acquireCell(index)
    local cell = cellPool[index]
    if cell then return cell end
    cell = CreateFrame("Button", "AIPRaidGroupsCell" .. index, win, "SecureActionButtonTemplate")
    cell:SetSize(CELL_W, CELL_H)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:RegisterForDrag("LeftButton")
    cell:Hide()

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints(); cell.bg:SetTexture(0.5, 0.5, 0.5, 0.85)
    -- RG-020 design pass finding: this "wash" was at OVERLAY, which sits
    -- ABOVE the raid icon/debuff/quick-cast icons (all ARTWORK) - every time
    -- it showed, it re-tinted those icons too, making them murky. Moved to
    -- BORDER (below ARTWORK, above BACKGROUND) so it only ever tints the
    -- class-colour background, leaving icons crisp regardless of state.
    cell.overlay = cell:CreateTexture(nil, "BORDER")
    cell.overlay:SetAllPoints(); cell.overlay:SetTexture(0, 0, 0, 0.55); cell.overlay:Hide()
    -- Presence-state ring (RG-020): a second, colour-coded signal alongside
    -- the wash and text label, inset 1px so it never collides with the gold
    -- target ring below (which is drawn at the cell's outer edge, one frame
    -- level higher, so a targeted+dead player shows both at once).
    cell.stateBorder = CreateFrame("Frame", nil, cell)
    cell.stateBorder:SetPoint("TOPLEFT", 1, -1); cell.stateBorder:SetPoint("BOTTOMRIGHT", -1, 1)
    cell.stateBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    cell.stateBorder:SetFrameLevel(cell:GetFrameLevel() + 1)
    cell.stateBorder:Hide()
    cell.targetBorder = CreateFrame("Frame", nil, cell)
    cell.targetBorder:SetAllPoints()
    cell.targetBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    cell.targetBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
    cell.targetBorder:SetFrameLevel(cell:GetFrameLevel() + 2)   -- always above stateBorder
    cell.targetBorder:Hide()

    -- Row 1: raid icon (left) + rank tag + name (flex).
    cell.raidIcon = cell:CreateTexture(nil, "ARTWORK")
    cell.raidIcon:SetSize(ROW1_H, ROW1_H); cell.raidIcon:SetPoint("TOPLEFT", 1, -1)
    cell.raidIcon:Hide()
    cell.rankFS = fontize(cell:CreateFontString(nil, "OVERLAY"), 8, "OUTLINE")
    cell.rankFS:SetPoint("TOPLEFT", cell.raidIcon, "TOPRIGHT", 1, 0)

    cell.nameFS = fontize(cell:CreateFontString(nil, "OVERLAY"), 10, "OUTLINE")
    cell.nameFS:SetPoint("LEFT", cell.rankFS, "RIGHT", 2, 0)
    cell.nameFS:SetPoint("TOP", cell, "TOP", 0, -1)
    cell.nameFS:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
    cell.nameFS:SetJustifyH("LEFT")
    -- SetWordWrap(false): without it, the default word-wraps onto a 2nd line
    -- that this 1-row-tall cell has no room for, which reads as the name
    -- being cut off.
    cell.nameFS:SetWordWrap(false)
    -- Captured so the "Offline" state (RG-020, the only state that also dims
    -- the name text) can be reverted back to whatever the font object's own
    -- default colour actually is, instead of hardcoding a guess at it.
    cell.nameFS._defR, cell.nameFS._defG, cell.nameFS._defB = cell.nameFS:GetTextColor()

    -- Row 2: a reserved STATE_DOT_COL-wide column for the ready-check icon
    -- (below), then up to MAX_DEBUFF_ICONS small debuff icons starting after
    -- it. BUG FIX (found on audit, pre-RG-020): the old presence dot and
    -- debuffIcons[1] were BOTH anchored to the cell's bottom-left corner (dot
    -- at x1-5,y1-5 from-bottom; debuffIcons[1] at x1-11,y-1-9 from-bottom -
    -- fully overlapping ranges), so a dead/offline/AFK/DND member with any
    -- debuff would render the dot directly on top of their first debuff icon.
    -- Fixed by giving that corner its own column and starting the debuff row
    -- after it - widened from 6 to 11 for RG-020's ready-check icon, which is
    -- a real 9x9 icon (shape-coded, for colourblind legibility) rather than a
    -- 4x4 colour dot.
    local STATE_DOT_COL = 11
    cell.debuffIcons = {}
    for d = 1, MAX_DEBUFF_ICONS do
        local t = cell:CreateTexture(nil, "ARTWORK")
        t:SetSize(DEBUFF_ICON_SZ, DEBUFF_ICON_SZ)
        t:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        t:SetPoint("TOPLEFT", 1 + STATE_DOT_COL + (d - 1) * (DEBUFF_ICON_SZ + 1), -(ROW1_H + ROW_GAP + 1))
        t:Hide()
        cell.debuffIcons[d] = t
    end

    -- Missing-buff indicator: a small dot, bottom-right.
    cell.missingDot = cell:CreateTexture(nil, "OVERLAY")
    cell.missingDot:SetSize(4, 4); cell.missingDot:SetPoint("BOTTOMRIGHT", -1, 1)
    cell.missingDot:SetTexture(1, 0.3, 0.3, 1); cell.missingDot:Hide()

    -- Presence-state text label (RG-020's 3rd channel, the accessibility
    -- backstop alongside the wash and ring - readable even colourblind, or
    -- when the ring/wash alone would be ambiguous at a glance). Sits in the
    -- ~60px of row-2 width left over after the debuff icons and before the
    -- missing-buff dot.
    cell.stateFS = fontize(cell:CreateFontString(nil, "OVERLAY"), 8, "OUTLINE")
    cell.stateFS:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -6, -(ROW1_H + ROW_GAP + 1))
    cell.stateFS:SetJustifyH("RIGHT")
    cell.stateFS:Hide()

    -- Ready-check icon (RG-020's 4th, fully independent channel - shown or
    -- hidden purely on whether a check is currently active/lingering for
    -- this unit, layered on top of whatever persistent-state treatment is
    -- showing underneath). Repurposes the reserved bottom-left column
    -- (STATE_DOT_COL, above) that used to hold a small 4x4 presence dot;
    -- grown to a real 9x9 icon since this now shows Blizzard's own
    -- ready/not-ready/waiting textures (shape-coded, not just colour - a
    -- deliberate colourblind-accessibility choice from the design pass).
    cell.readyIcon = cell:CreateTexture(nil, "ARTWORK")
    cell.readyIcon:SetSize(9, 9); cell.readyIcon:SetPoint("BOTTOMLEFT", 1, 1)
    cell.readyIcon:Hide()

    cell:HookScript("OnClick", function(self, button)
        if button == "RightButton" then openMemberMenu(self.member) end
    end)
    cell:SetScript("OnDragStart", function(self) if self.member then beginDrag(self) end end)
    cell:SetScript("OnDragStop", function() endDrag() end)
    cell:SetScript("OnEnter", function(self) showCellTooltip(self) end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cellPool[index] = cell
    return cell
end

-- An empty manager slot: same size, no secure attributes, a drop target only.
local function acquireEmptySlot(group, slotNum)
    local key = "empty_" .. group .. "_" .. slotNum
    local cell = cellPool[key]
    if cell then return cell end
    cell = CreateFrame("Frame", nil, win)
    cell:SetSize(CELL_W, CELL_H)
    cell.emptyGroup = group
    local bg = cell:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(0.12, 0.13, 0.18, 0.5)
    cell:Hide()
    cellPool[key] = cell
    return cell
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

function RG.LayoutWindow()
    if not win then return end
    if InCombatLockdown() then RG.dirty = true; return end
    win:SetSize(applied.layout and (applied.layout.w + PAD * 2) or (CELL_W + PAD * 2),
                HDR_H + (applied.layout and applied.layout.h or CELL_H) + PAD)
end

local function applyStructure()
    local snap = RG.Snapshot()
    applied.snap = snap
    applied.hasTankCast = (AIP.TankCast and AIP.TankCast.SetSlot) and true or false
    local visible = RG.VisibleGroups(snap)
    applied.visible = visible
    local layout = RG.ComputeLayout(visible, snap, DIMS)
    applied.layout = layout

    -- A bigger gap alone (ROW_BAND_GAP) wasn't unambiguous enough live
    -- (2026-09-27) - an explicit divider line removes any doubt that groups
    -- 1-4 and 5-8 are two separate rows. Drawn once per grid-row boundary
    -- (in practice at most 1, since RG.GridSize never produces more than 2
    -- grid-rows), reusing a small pool of plain (non-secure) textures - safe
    -- to Show/Hide/SetPoint any time, unlike the secure member cells.
    local dividerCount = math.max(0, (layout.rows or 1) - 1)
    for r = 1, dividerCount do
        local d = rowDividerPool[r]
        if not d then
            d = win:CreateTexture(nil, "ARTWORK")
            d:SetTexture(0.30, 0.33, 0.42, 0.9)
            rowDividerPool[r] = d
        end
        d:SetHeight(1)
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(HDR_H + PAD + layout.rowBottom[r] + DIMS.rowGap / 2))
        d:SetPoint("RIGHT", win, "TOPLEFT", PAD + layout.w - PAD * 2, 0)
        d:Show()
    end
    for r = dividerCount + 1, #rowDividerPool do rowDividerPool[r]:Hide() end

    local idx = 0
    for _, g in ipairs(visible) do
        local gl = layout.groups[g]
        local members = snap.groups[g]
        local shown = gl.rows
        for slot = 1, shown do
            local m = members[slot]
            if m then
                idx = idx + 1
                local cell = acquireCell(idx)
                cell.member = m
                local macro = "/target " .. (m.name:gsub("[/;%[%]|]", ""))
                cell:SetAttribute("type1", "macro")
                cell:SetAttribute("macrotext1", macro)
                -- RG-023: Set/Clear Main Tank/Assist via secure modifier-click
                -- attributes - SetPartyAssignment/ClearPartyAssignment are
                -- unconditionally protected (confirmed against Wowpedia/
                -- Warcraft Wiki, not guessed) and cannot be called from a
                -- menu handler (an EasyMenu row is not a SecureActionButton).
                -- Attribute name order is modifier-attribute-button, modifiers
                -- in "ctrl-shift-" order (confirmed against
                -- warcraft.wiki.gg/wiki/SecureActionButtonTemplate):
                --   shift-click       -> Set Main Tank
                --   ctrl-click        -> Set Main Assist
                --   ctrl-shift-click  -> Clear whichever of MT/MA this member
                --                        currently holds (a harmless no-op if
                --                        neither)
                -- Manager-only, raid-only, matching the menu's own old gating.
                local canAssign = snap.mode == "raid" and snap.canManage
                cell:SetAttribute("shift-type1", canAssign and "maintank" or nil)
                cell:SetAttribute("shift-unit1", canAssign and m.name or nil)
                cell:SetAttribute("shift-action1", canAssign and "set" or nil)
                cell:SetAttribute("ctrl-type1", canAssign and "mainassist" or nil)
                cell:SetAttribute("ctrl-unit1", canAssign and m.name or nil)
                cell:SetAttribute("ctrl-action1", canAssign and "set" or nil)
                cell:SetAttribute("ctrl-shift-type1", canAssign and (m.role == "MAINASSIST" and "mainassist" or "maintank") or nil)
                cell:SetAttribute("ctrl-shift-unit1", canAssign and m.name or nil)
                cell:SetAttribute("ctrl-shift-action1", canAssign and "clear" or nil)
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", win, "TOPLEFT", gl.x + PAD, -(HDR_H + gl.y + (slot - 1) * (CELL_H + CELL_GAP)))
                cell:Show()
            else
                local slotFrame = acquireEmptySlot(g, slot)
                slotFrame:ClearAllPoints()
                slotFrame:SetPoint("TOPLEFT", win, "TOPLEFT", gl.x + PAD, -(HDR_H + gl.y + (slot - 1) * (CELL_H + CELL_GAP)))
                slotFrame:Show()
            end
        end
    end
    for i = idx + 1, #cellPool do
        local cell = cellPool[i]
        if cell and cell.SetAttribute then
            cell.member = nil
            cell:SetAttribute("type1", nil)
            cell:SetAttribute("macrotext1", nil)
            cell:SetAttribute("shift-type1", nil); cell:SetAttribute("shift-unit1", nil); cell:SetAttribute("shift-action1", nil)
            cell:SetAttribute("ctrl-type1", nil); cell:SetAttribute("ctrl-unit1", nil); cell:SetAttribute("ctrl-action1", nil)
            cell:SetAttribute("ctrl-shift-type1", nil); cell:SetAttribute("ctrl-shift-unit1", nil); cell:SetAttribute("ctrl-shift-action1", nil)
            cell:Hide()
        end
    end
    for key, frame in pairs(cellPool) do
        if type(key) == "string" then frame:Hide() end
    end
    -- Re-show the empty slots this pass actually used (the blanket hide above
    -- clears every string-keyed slot frame first so stale ones from a shrunk
    -- raid don't linger).
    for _, g in ipairs(visible) do
        local gl = layout.groups[g]
        local members = snap.groups[g]
        for slot = 1, gl.rows do
            if not members[slot] then
                local slotFrame = cellPool["empty_" .. g .. "_" .. slot]
                if slotFrame then slotFrame:Show() end
            end
        end
    end

    win.memberCount:SetText(#snap.members .. (snap.mode == "raid" and ("/" .. (RG.MAX_GROUPS * RG.GROUP_SIZE)) or ""))
    RG.LayoutWindow()
end

refreshValues = function()
    if not win or not win:IsShown() or not applied.snap then return end
    local targetName = UnitName and UnitExists and UnitExists("target") and UnitName("target")
    for _, cell in ipairs(cellPool) do
        if cell.member then
            local m = cell.member
            cell.bg:SetTexture(classColor(m.class))
            cell.nameFS:SetText(m.name)
            -- BUG FOUND LIVE (2026-09-27): m.dead/m.online come from
            -- RG.Snapshot(), which only re-runs on structural roster events
            -- (RAID_ROSTER_UPDATE etc, see applyStructure) - not every 0.25s
            -- tick like AFK/DND already are (below). A player who died then
            -- revived with no roster event in between kept showing "dead"
            -- indefinitely - reported live as "warrior shows as dead... but
            -- alive". Per this addon's own governing principle (prefer a
            -- live interface query over cached/broadcast data - see RG-013 in
            -- the requirements doc), poll live every tick instead, same as
            -- AFK/DND; only fall back to the snapshot value if there's no
            -- resolvable unit token.
            local isDead, isOnline = m.dead, m.online
            if m.unit then
                if UnitIsDeadOrGhost then isDead = UnitIsDeadOrGhost(m.unit) and true or false end
                if UnitIsConnected then isOnline = UnitIsConnected(m.unit) and true or false end
            end
            if targetName == m.name then cell.targetBorder:Show() else cell.targetBorder:Hide() end
            local tag = (m.role == "MAINTANK" and "MT") or (m.role == "MAINASSIST" and "MA") or ""
            if applied.snap.canManage and m.rank and m.rank > 0 then
                tag = (tag ~= "" and (tag .. " ") or "") .. (m.rank == 2 and "L" or "A")
            end
            cell.rankFS:SetText(tag)

            local iconIdx = RG.GetRaidIcon(applied.snap, m.name)
            if iconIdx and iconIdx > 0 then
                cell.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                local col, row = (iconIdx - 1) % 4, math.floor((iconIdx - 1) / 4)
                cell.raidIcon:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
                cell.raidIcon:Show()
            else
                cell.raidIcon:Hide()
            end

            if m.unit then
                local debuffs = RG.ListDebuffs(m.unit, MAX_DEBUFF_ICONS)
                for d = 1, MAX_DEBUFF_ICONS do
                    local a, t = debuffs[d], cell.debuffIcons[d]
                    if a then t:SetTexture(a.icon); t:Show() else t:Hide() end
                end
                local missing = RG.MissingBuffsForViewer(m.unit)
                if #missing > 0 then cell.missingDot:Show() else cell.missingDot:Hide() end
            else
                for d = 1, MAX_DEBUFF_ICONS do cell.debuffIcons[d]:Hide() end
                cell.missingDot:Hide()
            end

            -- RG-020: persistent player state as three redundant channels -
            -- wash (whole-cell darken, brightness-only, never relies on hue
            -- so it doesn't fight the class-colour background), ring (a
            -- colour-coded border, the secondary signal) and a text label
            -- (the colourblind-accessibility backstop). Exactly one state
            -- wins, worst-first: Offline > Dead > DND > AFK > Normal.
            -- Offline is ranked worst on purpose (design-pass call, not an
            -- oversight - see RG-020 in the requirements doc): it's total
            -- information loss (no health, no buffs, nothing else about that
            -- player), matching Grid/Blizzard convention - this FLIPS the
            -- earlier dead > offline > dnd > afk order this addon shipped
            -- with initially. isDead/isOnline are the same live-polled
            -- values as above (not the stale snapshot m.dead/m.online).
            local afk = m.unit and UnitIsAFK and UnitIsAFK(m.unit)
            local dnd = m.unit and UnitIsDND and UnitIsDND(m.unit)
            local wR, wG, wB, wA, rR, rG, rB, label, lR, lG, lB
            if not isOnline then
                wR, wG, wB, wA = 0.4, 0.4, 0.43, 0.75
                rR, rG, rB = 0.45, 0.48, 0.55
                label, lR, lG, lB = "OFFLINE", 0.72, 0.74, 0.79
            elseif isDead then
                wR, wG, wB, wA = 0.05, 0.05, 0.05, 0.6
                rR, rG, rB = 0.75, 0.08, 0.08
                label, lR, lG, lB = "DEAD", 1, 0.48, 0.48
            elseif dnd then
                wR, wG, wB, wA = 0.05, 0.05, 0.05, 0.35
                rR, rG, rB = 0.6, 0.2, 0.75
                label, lR, lG, lB = "DND", 0.84, 0.55, 0.95
            elseif afk then
                wR, wG, wB, wA = 0.05, 0.05, 0.05, 0.2
                rR, rG, rB = 0.2, 0.65, 0.65
                label, lR, lG, lB = "AFK", 0.44, 0.84, 0.84
            end

            if label then
                cell.overlay:SetTexture(wR, wG, wB, wA); cell.overlay:Show()
                cell.stateBorder:SetBackdropBorderColor(rR, rG, rB, 0.85); cell.stateBorder:Show()
                cell.stateFS:SetText(label); cell.stateFS:SetTextColor(lR, lG, lB); cell.stateFS:Show()
            else
                cell.overlay:Hide(); cell.stateBorder:Hide(); cell.stateFS:Hide()
            end
            -- Offline is the only state that also dims the name text itself
            -- (per the design spec) - reverts to the font object's own
            -- captured default otherwise (cells are pooled/reused, so this
            -- MUST be reset every refresh, not just set once).
            if not isOnline then
                cell.nameFS:SetTextColor(0.72, 0.74, 0.79)
            else
                cell.nameFS:SetTextColor(cell.nameFS._defR, cell.nameFS._defG, cell.nameFS._defB)
            end

            -- Proximity dimming: a whole-cell alpha reduction for a member
            -- who isn't near the raid (may need a summon, or the raid may
            -- need to wait for them before pulling) - fully independent of
            -- the wash/ring/label priority chain above, same as ready-check
            -- below, so it can coexist with any persistent state (e.g. an
            -- AFK member who is ALSO far away shows both at once). Uses
            -- UnitInRange, the same ~40yd/helpful-spell-range check Blizzard's
            -- own raid frames use to desaturate an out-of-range portrait
            -- (verified via web search 2026-09-28, not guessed; in 3.3.5a it
            -- returns a single boolean, not the inRange+checkedRange pair
            -- added much later in Cata/MoP). Meaningless for yourself (you
            -- are never "out of range" of yourself) and for a member with no
            -- resolvable unit token, so both are skipped rather than dimmed.
            -- Realtime: refreshValues already runs on the same fast tick as
            -- AFK/DND above, so this updates at the same cadence.
            local outOfRange = (not m.isSelf) and m.unit and UnitInRange and (UnitInRange(m.unit) == false)
            cell:SetAlpha(outOfRange and 0.45 or 1)

            -- RG-020's 4th channel: ready-check status, fully independent of
            -- the persistent-state treatment above - shown on top of
            -- whatever wash/ring/label is active whenever a check is
            -- currently active/lingering for this unit (a Dead+NotReady
            -- member shows both at once, deliberately - see the design doc).
            -- Real Blizzard textures (shape-coded, not just colour) rather
            -- than a plain dot - the same colourblind-accessibility reasoning
            -- as the ring+label above.
            local ready = RG.GetReadyStatus(m.name)
            if ready == "ready" then
                cell.readyIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready"); cell.readyIcon:Show()
            elseif ready == "notready" then
                cell.readyIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady"); cell.readyIcon:Show()
            elseif ready == "waiting" then
                -- Static, no pulse animation: refreshValues only runs every
                -- 0.25s, so a sine-wave alpha pulse would look choppy, not
                -- smooth - deliberately skipped (design-pass call).
                cell.readyIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting"); cell.readyIcon:Show()
            else
                cell.readyIcon:Hide()
            end
        end
    end
end

refresh = function()
    if not win then return end
    if InCombatLockdown() then RG.dirty = true; refreshValues(); return end
    RG.dirty = false
    applyStructure()
    refreshValues()
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local function restorePosition()
    local c = RG.Cfg()
    local pos = c and c.pos
    win:ClearAllPoints()
    if pos then
        win:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end
end

local function anchorTopLeft()
    local l, t = win:GetLeft(), win:GetTop()
    if l and t then win:ClearAllPoints(); win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t) end
end

local function ensureWindow()
    if win then return win end
    win = CreateFrame("Frame", "AIPRaidGroupsWindow", UIParent)
    win:SetSize(CELL_W + PAD * 2, HDR_H + CELL_H + PAD)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    skinPanel(win)
    skinHeader(win, HDR_H)
    restorePosition()

    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self)
        if InCombatLockdown() or RG.IsLocked() then return end
        self.moving = true; self:StartMoving()
    end)
    win:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = false; self:StopMovingOrSizing(); anchorTopLeft()
        local point, _, relPoint, x, y = self:GetPoint()
        local c = RG.Cfg(); if c then c.pos = {point = point, relPoint = relPoint, x = x, y = y} end
    end)

    local title = fontize(win:CreateFontString(nil, "OVERLAY"), 9, "OUTLINE")
    title:SetPoint("TOPLEFT", 5, -3); title:SetText("GROUPS"); title:SetTextColor(1, 0.82, 0)
    win.memberCount = fontize(win:CreateFontString(nil, "OVERLAY"), 9, "")
    win.memberCount:SetPoint("TOPRIGHT", -5, -3); win.memberCount:SetTextColor(0.7, 0.72, 0.8)

    local hit = CreateFrame("Button", nil, win)
    hit:SetPoint("TOPLEFT", 1, -1); hit:SetPoint("TOPRIGHT", -1, -1); hit:SetHeight(HDR_H - 2)
    hit:RegisterForDrag("LeftButton")
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnDragStart", function() local f = win:GetScript("OnDragStart"); if f then f(win) end end)
    hit:SetScript("OnDragStop", function() local f = win:GetScript("OnDragStop"); if f then f(win) end end)
    hit:SetScript("OnClick", function(self, button) if button == "RightButton" then openWindowMenu(self) end end)
    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Raid Groups", 1, 0.82, 0)
        GameTooltip:AddLine("Click a name: target", 1, 1, 1)
        GameTooltip:AddLine("Right-click a name: options", 0.75, 0.78, 0.88)
        GameTooltip:AddLine("Right-click here: window options", 0.75, 0.78, 0.88)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    win:SetScript("OnUpdate", function(self, elapsed)
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.25 then return end
        self.acc = 0
        refreshValues()
    end)

    RG.OnChanged(function()
        refresh()
        -- Auto-open the moment a solo player forms/joins a group. combat
        -- lockdown is checked FIRST and before JustFormedGroup() - the latch
        -- is one-shot, so consuming it while ShowWindow can't run (mid-fight)
        -- would silently lose the auto-show for that group forever. If dirty
        -- (deferred by lockdown), refresh() above already re-fires this same
        -- callback once combat ends (RG.Changed() on PLAYER_REGEN_ENABLED), so
        -- the check gets a real retry. "already shown" is checked last so it
        -- never blocks the latch from updating.
        if not InCombatLockdown() and RG.JustFormedGroup() and AIP.db and AIP.db.autoShowOnGroup and not RG.IsWindowShown() then
            RG.ShowWindow()
        end
    end)
    win:Hide()
    refresh()
    return win
end

function RG.ShowWindow()
    if InCombatLockdown() then AIP.Print("The Raid Groups window can't be opened during combat.") return end
    ensureWindow()
    local c = RG.Cfg(); if c then c.shown = true end
    if AIP.UI and AIP.UI.FadeIn then AIP.UI.FadeIn(win, 0.15, 1) else win:Show() end
    refresh()
end

function RG.HideWindow()
    if InCombatLockdown() then AIP.Print("The Raid Groups window can't be closed during combat.") return end
    if win then win:Hide() end
    local c = RG.Cfg(); if c then c.shown = false end
end

function RG.ToggleWindow()
    if win and win:IsShown() then RG.HideWindow() else RG.ShowWindow() end
end

function RG.IsWindowShown() return win ~= nil and win:IsShown() end

local pendingInit = false
local function initWindow()
    if InCombatLockdown() then pendingInit = true; return end
    pendingInit = false
    ensureWindow()
    local c = RG.Cfg()
    if c and c.shown then win:Show(); refresh() end
end

-- ============================================================================
-- TOAST BUBBLE (assignments) - a standalone, non-secure frame. Never parented to
-- the protected window, so it is safe to create/show/hide even in combat.
-- ============================================================================

local bubble
local BUBBLE_W = 260
local function ensureBubble()
    if bubble then return bubble end
    bubble = CreateFrame("Frame", "AIPRaidGroupsBubble", UIParent)
    bubble:SetSize(BUBBLE_W, 30)
    skinPanel(bubble, 0.97)
    -- Brighter gold border (matches the target-highlight accent used elsewhere
    -- in this UI) so the toast reads as an alert, not just another dark panel -
    -- "more visible" was an explicit ask, not just repositioning.
    bubble:SetBackdropBorderColor(1, 0.82, 0, 1)
    bubble.fs = fontize(bubble:CreateFontString(nil, "OVERLAY"), 12, "OUTLINE")
    bubble.fs:SetPoint("TOPLEFT", 10, -7); bubble.fs:SetPoint("TOPRIGHT", -10, -7)
    -- Two-point anchoring alone does NOT reliably constrain a FontString's
    -- wrap width on this client - confirmed live: GetWidth() reported the
    -- string's natural unwrapped width (~500px for a long message) instead
    -- of the anchor-implied 240px, and the text rendered as a single
    -- ellipsis-truncated line instead of wrapping. An explicit SetWidth is
    -- the only reliable fix (same reason the popup's measuring FontString
    -- uses one too).
    bubble.fs:SetWidth(BUBBLE_W - 20)
    bubble.fs:SetJustifyH("CENTER")
    bubble.fs:SetWordWrap(true)
    bubble:Hide()
    return bubble
end

function RG.ShowBubble(text)
    ensureBubble()
    bubble.fs:SetText(text)
    if win and win:IsShown() then
        -- Corner to corner: the bubble's TOPLEFT sits at the window's own
        -- TOPRIGHT (a small 4px gap, not flush-touching), so the bubble
        -- reads as attached to the window's right edge and grows downward
        -- as wrapped content adds lines - matching normal reading direction
        -- and how the window itself grows. Anchoring relative to `win`
        -- (not a hardcoded offset) keeps this correct regardless of the
        -- window's own current height/width (manager vs member view).
        bubble:ClearAllPoints(); bubble:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0)
    else
        bubble:ClearAllPoints(); bubble:SetPoint("TOP", UIParent, "TOP", 0, -80)
    end
    if AIP.UI and AIP.UI.FadeIn then AIP.UI.FadeIn(bubble, 0.15, 1) else bubble:Show() end
    bubble.hideAt = ((GetTime and GetTime()) or 0) + 3
    -- Measure-and-enforce every frame, same pattern (and same reason) as the
    -- Note/Assignment popup box: GetStringHeight() right after SetText can
    -- race a layout pass that hasn't happened yet, so a one-shot SetHeight
    -- can undershoot for a long wrapped message. This already runs every
    -- frame for the auto-hide timer, so the elastic-height check rides
    -- along for free instead of needing a second OnUpdate.
    bubble:SetScript("OnUpdate", function(self)
        local wantH = math.max(30, (self.fs:GetStringHeight() or 0) + 14)
        if math.abs((self:GetHeight() or 0) - wantH) > 0.5 then
            self:SetHeight(wantH)
        end
        if ((GetTime and GetTime()) or 0) >= self.hideAt then
            self:SetScript("OnUpdate", nil)
            if AIP.UI and AIP.UI.FadeOut then AIP.UI.FadeOut(self, 0.4, true) else self:Hide() end
        end
    end)
end

RG.OnAssignment(function(name, text, author)
    if text == "" then return end   -- a clear is silent; only a new assignment toasts
    RG.ShowBubble(author .. ": " .. text)
end)

if RG.OnAllAnnouncementChanged then
    RG.OnAllAnnouncementChanged(function(text, author)
        if text == "" then return end   -- a clear is silent; only a new announcement toasts
        RG.ShowBubble("ALL: " .. text)
    end)
end

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    AIP.Utils.Events.Register("PLAYER_LOGIN", initWindow, "RaidGroupsUI")
    AIP.Utils.Events.Register("PLAYER_REGEN_ENABLED", function() if pendingInit then initWindow() end end, "RaidGroupsUI")
    AIP.Utils.Events.Register("PLAYER_TARGET_CHANGED", function() refreshValues() end, "RaidGroupsUI")
end

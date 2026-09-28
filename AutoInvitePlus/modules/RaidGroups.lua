-- AutoInvite Plus - Raid Groups (logic layer)
-- A compact "who's in what group" window: a roster snapshot, the grid-layout math,
-- the move planner (SetRaidSubgroup vs SwapRaidSubgroup), and the per-rank menu
-- models. Kept headless (tools/tests/raidgroups_spec.lua) so ui/RaidGroupsWindow.lua
-- is pure presentation. "Manager" = raid leader OR assistant, matching what the
-- game itself lets rearrange groups and set Main Tank/Main Assist; promote/demote/
-- master-looter/uninvite/convert stay leader-only (see RG.MemberMenu/WindowMenu).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.RaidGroups = AIP.RaidGroups or {}
local RG = AIP.RaidGroups

RG.MAX_GROUPS = 8
RG.GROUP_SIZE = 5
RG.dirty = false

-- Shared gate for assignments/announcements: manager-in-raid (leader or
-- assistant, matching who can already rearrange groups/set MT-MA) OR
-- leader-in-party (a party has no assistant rank - "manage" there just
-- means the party leader). Used by both the menu builders (RG.MemberMenu/
-- RG.WindowMenu, so the option only appears when it would work) and the Set*
-- functions themselves (the real enforcement - never trust a menu built from
-- a stale snapshot). Originally raid-only; the user asked these to keep
-- working in a normal party too, 2026-09-27.
function RG.CanAnnounce(snap)
    return (snap.mode == "raid" and snap.canManage) or (snap.mode == "party" and snap.isLeader) or false
end

local changedListeners = {}
local function fire(list) for _, fn in ipairs(list) do pcall(fn) end end
function RG.OnChanged(fn) changedListeners[#changedListeners + 1] = fn end
function RG.Changed() fire(changedListeners) end

RG.wasGrouped = nil    -- nil = "never evaluated yet this session", distinct from false
-- True exactly once: the instant the player's group goes from empty to
-- non-empty (solo -> party/raid). Used to auto-open the window on
-- joining/forming a group without re-opening it on every later roster tick.
function RG.JustFormedGroup()
    local grouped = ((GetNumRaidMembers and GetNumRaidMembers() or 0) > 0)
        or ((GetNumPartyMembers and GetNumPartyMembers() or 0) > 0)
    if RG.wasGrouped == nil then
        -- First-ever check (fresh login/reload) only seeds the latch - it must
        -- never fire just because the player happens to already be grouped at
        -- that point, or every /reload during an ongoing raid would re-open a
        -- window the player had deliberately closed.
        RG.wasGrouped = grouped
        return false
    end
    local justFormed = grouped and not RG.wasGrouped
    RG.wasGrouped = grouped
    return justFormed
end

local function say(msg) if AIP.Print then AIP.Print(msg) end end

-- ============================================================================
-- SAVED STATE (position/lock only - the roster itself is never persisted)
-- ============================================================================

local function cfg()
    local db = AIP.db
    if not db then return nil end
    local c = db.raidGroups
    if type(c) ~= "table" then c = {}; db.raidGroups = c end
    return c
end
RG.Cfg = cfg

local function charKey() return (AIP.Utils and AIP.Utils.CharKey and AIP.Utils.CharKey()) or "?" end

-- Per-character data (private notes, quick-cast spells): AutoInvitePlusDB is
-- account-wide, and a note you jotted down or the heal/buff spell you configured
-- on one character makes no sense following you to a different-class alt - see
-- AIP.Utils.CharKey. Window position/lock stay in the account-wide `cfg()` table
-- above (harmless, arguably nice, to share). One-time migration: whichever
-- character loads first after this split inherits the old account-wide
-- notes/quickCast; every other character then starts clean.
local function charCfg()
    local db = AIP.db
    if not db then return nil end
    if type(db.raidGroupsByChar) ~= "table" then db.raidGroupsByChar = {} end
    local key = charKey()
    local c = db.raidGroupsByChar[key]
    if type(c) ~= "table" then
        c = { notes = {}, quickCast = {} }
        local acct = cfg()
        if acct then
            if type(acct.notes) == "table" then c.notes = acct.notes; acct.notes = nil end
            if type(acct.quickCast) == "table" then c.quickCast = acct.quickCast; acct.quickCast = nil end
        end
        db.raidGroupsByChar[key] = c
    end
    return c
end

function RG.IsLocked()
    local c = cfg()
    return (c and c.locked) and true or false
end

function RG.SetLocked(on)
    local c = cfg()
    if not c then return false end
    c.locked = on and true or false
    return true
end

function RG.ToggleLocked()
    RG.SetLocked(not RG.IsLocked())
    return RG.IsLocked()
end

function RG.IsGroupLocked()
    local c = cfg()
    return (c and c.groupLocked) and true or false
end

function RG.SetGroupLocked(on)
    local c = cfg()
    if not c then return false end
    c.groupLocked = on and true or false
    return true
end

-- Manager-only: this protects a manager from their OWN mis-drags, so only a
-- manager may turn it on or off.
function RG.ToggleGroupLocked(snap)
    if not (snap and snap.canManage) then
        return false, "You must be raid leader or assistant to lock group positions."
    end
    RG.SetGroupLocked(not RG.IsGroupLocked())
    return true, RG.IsGroupLocked()
end

-- ============================================================================
-- SNAPSHOT
-- ============================================================================

-- Everyone in the player's group right now. mode = "raid" | "party" | "solo".
function RG.Snapshot()
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    local members, groups, counts = {}, {}, {}
    for g = 1, RG.MAX_GROUPS do groups[g] = {} end

    if n > 0 then
        local myRank = 0
        for i = 1, n do
            local name, rank, subgroup, level, _, fileName, _, online, isDead, role, isML = GetRaidRosterInfo(i)
            if name then
                subgroup = subgroup or 1
                local m = {
                    name = name, unit = "raid" .. i, class = fileName, level = level, group = subgroup,
                    index = i, rank = rank or 0, role = role, isML = isML and true or false,
                    online = online ~= false, dead = isDead and true or false,
                    isSelf = (UnitName and UnitName("player") == name),
                }
                members[#members + 1] = m
                groups[subgroup][#groups[subgroup] + 1] = m
                counts[subgroup] = (counts[subgroup] or 0) + 1
                if m.isSelf then myRank = m.rank end
            end
        end
        local isLeader = (IsRaidLeader and IsRaidLeader()) and true or false
        local isOfficer = (IsRaidOfficer and IsRaidOfficer()) and true or false
        return {
            mode = "raid", members = members, groups = groups, counts = counts,
            myRank = myRank, isLeader = isLeader, canManage = isLeader or isOfficer,
        }
    end

    local nParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    local mode = (nParty > 0) and "party" or "solo"
    local meName = (UnitName and UnitName("player")) or "You"
    -- `and`/`or` always collapse a multi-return call to ONE value (Lua 5.1, even
    -- as the last expression), so `UnitClass and UnitClass(unit)` silently drops
    -- the class token no matter how it's assigned - this bit both the self entry
    -- and, identically, every party member below. Guard with a plain `if` instead.
    local meClass
    if UnitClass then local _, c = UnitClass("player"); meClass = c end
    -- Party "leadership" never grants raid MANAGE powers (no raid to manage), but
    -- it does make WindowMenu's "Convert to Raid" reachable - see isLeader below.
    local isPartyLeader = (UnitIsPartyLeader and UnitIsPartyLeader("player")) and true or false
    local meRank = isPartyLeader and 2 or 0
    local me = {
        name = meName, unit = "player", class = meClass, level = UnitLevel and UnitLevel("player"),
        group = 1, index = 0, rank = meRank, role = nil, isML = false, online = true, dead = false, isSelf = true,
    }
    members[1] = me
    groups[1][1] = me
    counts[1] = 1
    for i = 1, nParty do
        local unit = "party" .. i
        local name = UnitName and UnitName(unit)
        if name then
            local class
            if UnitClass then local _, c = UnitClass(unit); class = c end
            local m = {
                name = name, unit = unit, class = class, level = UnitLevel and UnitLevel(unit),
                group = 1, index = i, rank = (UnitIsPartyLeader and UnitIsPartyLeader(unit)) and 2 or 0,
                role = nil, isML = false, online = true, dead = false, isSelf = false,
            }
            members[#members + 1] = m
            groups[1][#groups[1] + 1] = m
            counts[1] = counts[1] + 1
        end
    end
    -- isLeader (party leader) makes "Convert to Raid" reachable in WindowMenu;
    -- canManage stays false - there is no raid to manage yet.
    return { mode = mode, members = members, groups = groups, counts = counts, myRank = meRank, isLeader = isPartyLeader, canManage = false }
end

-- Which groups a viewer gets to see: managers get all 8 (so they can drag into an
-- empty one); everyone else only sees groups that actually have someone in them.
function RG.VisibleGroups(snap)
    if snap.mode == "raid" and snap.canManage then
        local all = {}
        for g = 1, RG.MAX_GROUPS do all[g] = g end
        return all
    end
    local out = {}
    for g = 1, RG.MAX_GROUPS do
        if (snap.counts[g] or 0) > 0 then out[#out + 1] = g end
    end
    return out
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

-- Columns/rows for n groups: up to 4 groups -> one row; more -> ceil(n/2), capped
-- at 4 columns (so 5-8 groups always draw as a 2-row grid, never a single wide row).
function RG.GridSize(n)
    if n <= 0 then return 1, 1 end
    if n <= 4 then return n, 1 end
    local cols = math.min(4, math.ceil(n / 2))
    return cols, math.ceil(n / cols)
end

-- Pixel layout for the visible groups, in reading order (row-major) into the grid
-- GridSize gives. dims = {cellW, cellH, gap, groupGap, pad}. A manager's groups are
-- always GROUP_SIZE cells tall (room to drop into); a non-manager's are only as
-- tall as the group's real member count (never 0 - VisibleGroups already excludes
-- empty groups for them).
function RG.ComputeLayout(visible, snap, dims)
    local cols, rows = RG.GridSize(#visible)
    local cellH, gap, groupGap, pad = dims.cellH, dims.gap, dims.groupGap, dims.pad
    local groupW = dims.cellW
    -- Distinct from groupGap (which spaces columns within one grid-row): with
    -- only groupGap governing the row-to-row gap too, groups 1-4 and 5-8 (the
    -- manager view's GridSize(8) = 4x2) rendered as one undifferentiated
    -- block - confirmed live (2026-09-27). Falls back to groupGap so callers
    -- that don't care about the distinction (existing tests, any other user
    -- of this function) keep working unchanged.
    local rowGap = dims.rowGap or groupGap

    local function shownFor(g)
        if snap.canManage and snap.mode == "raid" then return RG.GROUP_SIZE end
        return math.max(1, snap.counts[g] or 0)
    end

    -- Row heights: each grid row is as tall as its tallest group that row.
    local rowH = {}
    for k, g in ipairs(visible) do
        local r = math.floor((k - 1) / cols) + 1
        local h = shownFor(g) * (cellH + gap) - gap
        if not rowH[r] or h > rowH[r] then rowH[r] = h end
    end

    local out = { groups = {}, cols = cols, rows = rows }
    for k, g in ipairs(visible) do
        local col = (k - 1) % cols
        local row = math.floor((k - 1) / cols) + 1
        local x = pad + col * (groupW + groupGap)
        local y = pad
        for r = 1, row - 1 do y = y + rowH[r] + rowGap end
        local shown = shownFor(g)
        out.groups[g] = { x = x, y = y, w = groupW, h = shown * (cellH + gap) - gap, rows = shown }
    end

    -- Per-grid-row bottom edge (relative to the group grid's own top, i.e.
    -- excluding `pad`), so the UI can draw an explicit divider between row
    -- bands - a bigger gap alone wasn't unambiguous enough live (2026-09-27).
    local rowBottom, acc = {}, 0
    for r = 1, rows do
        acc = acc + (rowH[r] or 0)
        rowBottom[r] = acc
        if r < rows then acc = acc + rowGap end
    end
    out.rowBottom = rowBottom

    local totalRowH = 0
    for r = 1, rows do totalRowH = totalRowH + (rowH[r] or 0) end
    out.w = pad * 2 + cols * groupW + (cols - 1) * groupGap
    out.h = pad * 2 + totalRowH + (rows - 1) * rowGap
    return out
end

-- ============================================================================
-- MOVE PLANNING
-- ============================================================================

local function findByName(snap, name)
    if not name then return nil end
    local l = name:lower()
    for _, m in ipairs(snap.members) do if m.name:lower() == l then return m end end
    return nil
end

-- Decide what a drop should do. target = {group = n} (dropped on empty space / the
-- group itself) or {name = "X"} (dropped on member X's cell). Returns a plan or
-- nil, reason. Rule: if the destination group has room, it is always a plain move
-- (even when dropped on a specific member - there is no need to swap when a slot
-- is free); only a FULL destination group turns a member-drop into a swap, and a
-- background-drop on a full group is refused outright (nothing to swap with).
function RG.PlanMove(snap, fromName, target)
    if not (snap.mode == "raid" and snap.canManage) then
        return nil, "You must be raid leader or assistant to move players."
    end
    if RG.IsGroupLocked() then
        return nil, "Group positions are locked."
    end
    local mover = findByName(snap, fromName)
    if not mover then return nil, "Unknown player." end

    local targetMember, tg
    if target and target.name then
        targetMember = findByName(snap, target.name)
        if not targetMember then return nil, "Unknown player." end
        tg = targetMember.group
    elseif target and target.group then
        tg = target.group
    else
        return nil, "No destination given."
    end

    if tg == mover.group then return nil, mover.name .. " is already in that group." end

    local count = snap.counts[tg] or 0
    if count < RG.GROUP_SIZE then
        return { op = "set", index = mover.index, group = tg }
    end
    if targetMember then
        return { op = "swap", index1 = mover.index, index2 = targetMember.index }
    end
    return nil, "Group " .. tg .. " is full - drop on a member to swap."
end

function RG.ExecMove(plan)
    if not plan then return end
    if plan.op == "set" and SetRaidSubgroup then
        SetRaidSubgroup(plan.index, plan.group)
    elseif plan.op == "swap" and SwapRaidSubgroup then
        SwapRaidSubgroup(plan.index1, plan.index2)
    end
end

-- ============================================================================
-- RAID TARGET ICONS (interface-only: the server already syncs these to everyone;
-- no DataBus involved - see the spec's governing rule. Reading is unrestricted;
-- setting requires a manager.)
-- ============================================================================

RG.RAID_ICONS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

function RG.GetRaidIcon(snap, name)
    local m = findByName(snap, name)
    if not m or not m.unit then return nil end
    if not GetRaidTargetIndex then return 0 end
    return GetRaidTargetIndex(m.unit) or 0
end

-- index 0 clears the icon; 1-8 selects one of RG.RAID_ICONS.
function RG.SetRaidIcon(snap, name, index)
    if not (snap.mode == "raid" and snap.canManage) then
        return false, "You must be raid leader or assistant to set raid icons."
    end
    local m = findByName(snap, name)
    if not m then return false, "Unknown player." end
    if type(index) ~= "number" or index < 0 or index > 8 then return false, "Bad icon." end
    if SetRaidTarget then SetRaidTarget(m.unit, index) end
    return true
end

-- ============================================================================
-- NOTES (private, local only) AND ASSIGNMENTS (shared, manager-set, broadcast over
-- DataBus - the ONE piece of information here with no native interface equivalent;
-- see the spec's governing rule). Assignments are never persisted: they live only
-- as long as this session's DataBus event cache would, exactly like a PING/LFM.
-- ============================================================================

-- Exposed (not local) so the UI's input box can SetMaxLetters() to the exact
-- same cap instead of duplicating the number - a single source of truth, per
-- the user's ask that notes/assignments be single-line and hard-capped: the
-- INPUT itself should refuse to exceed this, not silently get truncated
-- after the fact by sanitizeNote below (which remains as defence in depth
-- for any other caller, e.g. a future slash-command path).
-- Sized to fit a real chat message: SendChatMessage is capped at 255
-- characters on every channel type, RAID_WARNING included (verified via web
-- search 2026-09-27, consistent across Classic/WotLK/Retail - not guessed),
-- since this module now pushes assignments/announcements as real chat too
-- (see pushAnnouncement below). 240 leaves headroom for the worst-case
-- "PlayerName: " prefix a
-- player-directed assignment gets when pushed (WoW's own 12-char name cap +
-- ": " = 14 chars; 255-14=241, rounded down to 240 for 1 char of margin).
RG.MAX_NOTE_LEN = 240

local function sanitizeNote(text)
    if type(text) ~= "string" then return "" end
    -- Strip control chars (this already removes newlines/tabs - %c matches
    -- them - so a pasted multi-line string collapses to one line even before
    -- the UI-level fix below existed), and backslash/pipe: backslash because
    -- DataBus's own wire encoding treats it as an escape character (a stray
    -- one could corrupt the OTHER fields of this event on decode), pipe
    -- because it's WoW's markup escape (|c/|H/|T) - without this a manager's
    -- assignment text could inject colour codes or hyperlinks into every
    -- recipient's tooltip/toast.
    text = text:gsub("%c", " "):gsub("[\\|]", ""):gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text > RG.MAX_NOTE_LEN then text = text:sub(1, RG.MAX_NOTE_LEN) end
    return text
end

function RG.GetNote(name)
    local c = charCfg()
    if not c or type(name) ~= "string" or name == "" then return "" end
    if type(c.notes) ~= "table" then c.notes = {} end
    return c.notes[name:lower()] or ""
end

function RG.SetNote(name, text)
    local c = charCfg()
    if not c then return false, "Settings are not loaded yet." end
    if type(name) ~= "string" or name == "" then return false, "Unknown player." end
    if type(c.notes) ~= "table" then c.notes = {} end
    local clean = sanitizeNote(text)
    c.notes[name:lower()] = (clean ~= "") and clean or nil
    RG.Changed()
    return true
end

-- How long an assignment/announcement stays visible in the TOOLTIP after being
-- set/received, before GetAssignmentIfFresh/GetAllAnnouncementIfFresh start
-- reporting it as cleared again - independently per announcement TYPE (a
-- fresh player-directed assignment does not reset, or get reset by, the
-- all-raid announcement's own timer, and vice versa - each is its own stored
-- {text,author,time} and only a fresh SET of THAT type refreshes ITS OWN
-- time). Does NOT touch the underlying stored data or RG.GetAssignment
-- (unconditional - used e.g. to pre-fill the "Set Assignment..." popup with
-- whatever is currently set, regardless of tooltip staleness).
RG.ANNOUNCEMENT_LINGER = 40

-- Pushes an assignment/announcement as REAL chat so non-addon users see it
-- too: RAID_WARNING in a raid (verified via web search 2026-09-27, not
-- guessed: RAID_WARNING has required raid leader or assistant status since
-- it was added in patch 1.11 - unchanged through WotLK), plain PARTY chat in
-- a party (no special permission needed for /p - any member can send one,
-- but this is only ever reached after RG.CanAnnounce's own leader-only gate,
-- so it's already restricted in practice). Silently does nothing outside
-- those gates rather than erroring - callers already check RG.CanAnnounce
-- themselves before reaching this, so this is a second, defence-in-depth
-- check against calling it from somewhere that didn't. Not raid-exclusive
-- any more (was pushRaidWarning) - the user asked 2026-09-27 to keep
-- announcements working in a normal party too, just on the right channel.
local function pushAnnouncement(snap, text)
    if text == "" or not SendChatMessage then return end
    if snap.mode == "raid" then
        if (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer()) then
            SendChatMessage(text, "RAID_WARNING")
        end
    elseif snap.mode == "party" then
        SendChatMessage(text, "PARTY")
    end
end

RG.assignments = RG.assignments or {}   -- [lowerName] = {text, author, time}
local assignmentListeners = {}
function RG.OnAssignment(fn) assignmentListeners[#assignmentListeners + 1] = fn end
local function fireAssignment(name, text, author)
    for _, fn in ipairs(assignmentListeners) do pcall(fn, name, text, author) end
end

-- Unconditional (see RG.ANNOUNCEMENT_LINGER's comment above for why).
function RG.GetAssignment(name)
    if type(name) ~= "string" then return "", nil end
    local a = RG.assignments[name:lower()]
    if not a then return "", nil end
    return a.text, a.author
end

-- For tooltip display: same as RG.GetAssignment, but reports "" once more
-- than RG.ANNOUNCEMENT_LINGER seconds have passed since it was last set.
function RG.GetAssignmentIfFresh(name)
    if type(name) ~= "string" then return "", nil end
    local a = RG.assignments[name:lower()]
    if not a then return "", nil end
    if GetTime and (GetTime() - (a.time or 0)) > RG.ANNOUNCEMENT_LINGER then return "", nil end
    return a.text, a.author
end

-- Manager-set only (RG.CanAnnounce: raid manager, or party leader); broadcasts
-- to the group's other AIP users AND pushes a real chat message (RAID_WARNING
-- in a raid, /p in a party - see pushAnnouncement) so non-addon members see it
-- too, prefixed with the target's name since a bare message wouldn't otherwise
-- say who it's for. Updates the LOCAL cache immediately - DataBus never echoes
-- a broadcast back to its own sender, so without this the setter would never
-- see their own assignment appear.
function RG.SetAssignment(snap, name, text)
    if not RG.CanAnnounce(snap) then
        return false, "You must be raid leader/assistant, or party leader, to set an assignment."
    end
    local m = findByName(snap, name)
    if not m then return false, "Unknown player." end
    local clean = sanitizeNote(text)
    local author = (UnitName and UnitName("player")) or "?"
    RG.assignments[m.name:lower()] = (clean ~= "")
        and { text = clean, author = author, time = (GetTime and GetTime()) or 0 } or nil
    fireAssignment(m.name, clean, author)
    if AIP.DataBus and AIP.DataBus.CreateEvent and AIP.DataBus.Broadcast then
        local event = AIP.DataBus.CreateEvent("RGNOTE", { player = m.name, note = clean, author = author })
        -- DataBus rate-limits broadcasts of the same event type to one per ~2s;
        -- a second assignment set within that window would otherwise be silently
        -- dropped (the setter's own cache is already updated above, but no one
        -- else would ever receive it) - retry once after the window closes.
        local sent = AIP.DataBus.Broadcast(event)
        if not sent and AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(2.1, function() AIP.DataBus.Broadcast(event) end)
        end
    end
    if clean ~= "" then pushAnnouncement(snap, m.name .. ": " .. clean) end
    return true
end

-- The DataBus subscriber: someone else's assignment arrived. Only accepted for a
-- player who is actually in MY current group, raid or party (an assignment fans
-- out over guild/cross-guild channels too, so this keeps someone else's group's
-- business off my screen when I'm not in it); the author is always the real
-- sender, never the payload's own (spoofable) author field.
function RG.OnAssignmentEvent(event)
    local data = event and event.data
    if not data or not data.player then return end
    local snap = RG.Snapshot()
    if not findByName(snap, data.player) then return end
    local text = sanitizeNote(data.note)
    local author = (event and event.sender) or data.author or "?"
    RG.assignments[data.player:lower()] = (text ~= "")
        and { text = text, author = author, time = (GetTime and GetTime()) or 0 } or nil
    fireAssignment(data.player, text, author)
end

-- ============================================================================
-- ALL-GROUP ANNOUNCEMENT (RG-020's title-bar broadcast: same idea as an
-- assignment, but for the whole raid/party, not one player - a single shared
-- slot, not a per-player table. Mirrors RG.assignments'/RG.SetAssignment's
-- shape and pushAnnouncement behaviour closely on purpose, minus the
-- per-player name-prefix on the pushed text, since a group-wide message is
-- already inherently seen by everyone - no "who is this for" ambiguity to
-- resolve. Works in a party too, not just a raid - see RG.CanAnnounce.)
-- ============================================================================

RG.allAnnouncement = nil   -- {text, author, time} or nil
local allAnnouncementListeners = {}
function RG.OnAllAnnouncementChanged(fn) allAnnouncementListeners[#allAnnouncementListeners + 1] = fn end
local function fireAllAnnouncement(text, author)
    for _, fn in ipairs(allAnnouncementListeners) do pcall(fn, text, author) end
end

function RG.GetAllAnnouncementIfFresh()
    local a = RG.allAnnouncement
    if not a then return "", nil end
    if GetTime and (GetTime() - (a.time or 0)) > RG.ANNOUNCEMENT_LINGER then return "", nil end
    return a.text, a.author
end

function RG.SetAllAnnouncement(snap, text)
    if not RG.CanAnnounce(snap) then
        return false, "You must be raid leader/assistant, or party leader, to announce to the group."
    end
    local clean = sanitizeNote(text)
    local author = (UnitName and UnitName("player")) or "?"
    RG.allAnnouncement = (clean ~= "") and { text = clean, author = author, time = (GetTime and GetTime()) or 0 } or nil
    fireAllAnnouncement(clean, author)
    if AIP.DataBus and AIP.DataBus.CreateEvent and AIP.DataBus.Broadcast then
        local event = AIP.DataBus.CreateEvent("RGALL", { note = clean, author = author })
        local sent = AIP.DataBus.Broadcast(event)
        if not sent and AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(2.1, function() AIP.DataBus.Broadcast(event) end)
        end
    end
    if clean ~= "" then pushAnnouncement(snap, clean) end
    return true
end

-- Same author-trust rule as RG.OnAssignmentEvent - event.sender, never the
-- payload's own (spoofable) author field. No per-player name to validate
-- against my own raid roster here (this is for everyone), so - unlike
-- OnAssignmentEvent - the only gate is being in a raid at all.
function RG.OnAllAnnouncementEvent(event)
    local data = event and event.data
    if not data then return end
    local snap = RG.Snapshot()
    -- Accept in a raid OR a party now (RG.CanAnnounce) - only reject when
    -- truly ungrouped, where a group-wide announcement has no meaning.
    if snap.mode == "solo" then return end
    local text = sanitizeNote(data.note)
    local author = (event and event.sender) or data.author or "?"
    RG.allAnnouncement = (text ~= "") and { text = text, author = author, time = (GetTime and GetTime()) or 0 } or nil
    fireAllAnnouncement(text, author)
end

-- ============================================================================
-- BUFFS / DEBUFFS / MISSING-BUFF INDICATOR (interface-only: UnitBuff/UnitDebuff
-- plus the existing buff-coverage engine in the Raid Management panel; guarded,
-- independent scan - see the spec's reuse-boundary decision)
-- ============================================================================

local function scanAuras(unit, fn, limit)
    local out, total = {}, 0
    if not unit or not fn then return out, 0 end
    limit = limit or 12
    for i = 1, 40 do
        local name, _, icon, count, dtype, _, expires = fn(unit, i)
        if not name then break end
        total = total + 1
        if #out < limit then
            local left = (type(expires) == "number" and expires > 0) and (expires - ((GetTime and GetTime()) or 0)) or nil
            out[#out + 1] = { name = name, icon = icon, count = count, dtype = dtype, timeLeft = left }
        end
    end
    return out, total
end

function RG.ListDebuffs(unit, limit) return scanAuras(unit, UnitDebuff, limit) end
function RG.ListBuffs(unit, limit) return scanAuras(unit, UnitBuff, limit) end

-- Raid buffs missing from this unit that YOUR class can provide - not "someone is
-- missing something" in general, only what is personally actionable for you.
--
-- RM.CheckUnitBuffs only reports a buff as "missing" once RM.ScanBuffProviders has
-- run and found someone present who can cast it (RM.AvailableBuffs) - without ever
-- calling that scan ourselves, missingBuffs is always empty and this indicator can
-- never light up. Call it here, throttled (it walks the whole raid), rather than
-- on every 4Hz cell refresh.
local lastBuffScan = 0
function RG.MissingBuffsForViewer(unit)
    local Panel = AIP.Panels and AIP.Panels.RaidMgmt
    if not (Panel and Panel.CheckUnitBuffs and Panel.ClassBuffs and Panel.ScanBuffProviders) then return {} end
    local now = (GetTime and GetTime()) or 0
    if now - lastBuffScan > 5 then
        Panel.ScanBuffProviders()
        lastBuffScan = now
    end
    local myClass
    if UnitClass then local _, c = UnitClass("player"); myClass = c end
    local canProvide = myClass and Panel.ClassBuffs[myClass]
    if not canProvide then return {} end
    local mine = {}
    for _, b in ipairs(canProvide) do mine[b.buffName] = true end
    local result = Panel.CheckUnitBuffs(unit)
    local missing = (result and result.missingBuffs) or {}
    local out = {}
    for _, name in ipairs(missing) do
        if mine[name] then out[#out + 1] = name end
    end
    return out
end

-- ============================================================================
-- QUICK-CAST (click-to-cast buffs/heals on ANY cell; a thin wrapper around Tank
-- Cast's existing spell/item engine - see the spec's reuse-boundary decision.
-- Requires AIP.TankCast; degrades to a clear error message without it.)
-- ============================================================================

RG.MAX_QUICKCAST = 2

local function tcRequired()
    return AIP.TankCast and AIP.TankCast.ParseSpellInput and AIP.TankCast.BuildMacro
end

function RG.GetQuickCast()
    local c = charCfg()
    local list = (c and c.quickCast) or {}
    local out = {}
    -- Clamped even though AddQuickCast/SetQuickCast already enforce the cap -
    -- a hand-edited/corrupt save could still hold more, and the UI anchors a
    -- name field to cell.qc[#GetQuickCast()], which would be a nil relativeTo
    -- past RG.MAX_QUICKCAST.
    for i = 1, math.min(#list, RG.MAX_QUICKCAST) do out[i] = list[i] end
    return out
end

local function qcHas(list, clean, skip)
    local l = clean:lower()
    for k, v in ipairs(list) do if k ~= skip and v:lower() == l then return true end end
    return false
end

function RG.AddQuickCast(text)
    if not tcRequired() then return false, "Tank Cast module is required for quick-cast." end
    local c = charCfg()
    if not c then return false, "Settings are not loaded yet." end
    if type(c.quickCast) ~= "table" then c.quickCast = {} end
    local clean = AIP.TankCast.ParseSpellInput(text)
    if clean == "" then return false, "Enter a spell or item name." end
    if #c.quickCast >= RG.MAX_QUICKCAST then return false, "You already have " .. RG.MAX_QUICKCAST .. " quick-cast slots." end
    if qcHas(c.quickCast, clean) then return false, "Already a quick-cast slot." end
    c.quickCast[#c.quickCast + 1] = clean
    RG.Changed()
    return true
end

function RG.SetQuickCast(i, text)
    if not tcRequired() then return false, "Tank Cast module is required for quick-cast." end
    local c = charCfg()
    if not c or type(c.quickCast) ~= "table" or not c.quickCast[i] then return false, "Bad slot." end
    local clean = AIP.TankCast.ParseSpellInput(text)
    if clean == "" then return false, "Enter a spell or item name." end
    if qcHas(c.quickCast, clean, i) then return false, "Already a quick-cast slot." end
    c.quickCast[i] = clean
    RG.Changed()
    return true
end

function RG.RemoveQuickCast(i)
    local c = charCfg()
    if not c or type(c.quickCast) ~= "table" or not c.quickCast[i] then return false, "Bad slot." end
    table.remove(c.quickCast, i)
    RG.Changed()
    return true
end

function RG.BuildQuickCastMacro(name, spellText)
    if not tcRequired() then return nil end
    return AIP.TankCast.BuildMacro(name, spellText)
end

-- ============================================================================
-- MENUS
-- ============================================================================

function RG.RankLabel(rank)
    if rank == 2 then return "Raid leader" end
    if rank == 1 then return "Assistant" end
    return "Member"
end

-- Right-click a member cell. hasTankCast lets the caller fold in Tank Cast
-- shortcuts without RaidGroups depending on that module directly.
function RG.MemberMenu(snap, member, hasTankCast)
    local list = {}
    -- `group` tags a long same-kind run of entries (raid icons, move-to-group,
    -- MT/MA) so the UI can fold it into one submenu instead of a long flat
    -- list; nil (the default) means "render as an ordinary top-level row".
    local function add(id, text, enabled, group)
        list[#list + 1] = { id = id, text = text, enabled = enabled ~= false, group = group }
    end

    if not member.isSelf then add("whisper", "Whisper") end
    add("inspect", "Inspect")
    add("achievements", "Compare Achievements")
    if not member.isSelf then
        add("trade", "Trade")
        add("follow", "Follow")
        -- Set/Clear Focus are deliberately NOT offered here: FocusUnit/ClearFocus are
        -- protected on 3.3.5a and calling them from a plain (insecure) menu handler
        -- is always blocked (ADDON_ACTION_BLOCKED). There is no menu-based fix -
        -- only a secure modifier-click could do this, which is a different
        -- interaction than "more menu options" and out of scope here.
        add("add_friend", "Add Friend")
    end
    add("note_private", "Set Note...")
    if hasTankCast then
        add("tank_mt", "Set as Main Tank (Tank Cast)")
        add("tank_ot", "Add as Off-Tank (Tank Cast)")
    end

    -- Works in a party too now (RG.CanAnnounce), not just a raid - everything
    -- else in the raid-only block below it (raid icons, move-to-group,
    -- promote/demote/uninvite) genuinely has no party equivalent and stays
    -- gated as before.
    if RG.CanAnnounce(snap) then
        add("note_assignment", "Set Assignment...")
    end

    if snap.mode == "raid" and snap.canManage then
        for i = 1, #RG.RAID_ICONS do
            add("raid_icon_" .. i, "Set Raid Icon: " .. RG.RAID_ICONS[i], true, "icons")
        end
        add("raid_icon_clear", "Clear Raid Icon", true, "icons")
        -- Set/Clear Main Tank/Assist are deliberately NOT offered here:
        -- SetPartyAssignment/ClearPartyAssignment are unconditionally
        -- protected on 3.3.5a (confirmed against Wowpedia/Warcraft Wiki -
        -- verified, not guessed), and an EasyMenu row is not a
        -- SecureActionButtonTemplate and cannot carry secure attributes - the
        -- exact same class of bug, and the exact same non-fix, as Focus/Clear
        -- Focus above. The real fix is a secure modifier-click on the member
        -- cell itself (shift=set MT, ctrl=set MA, ctrl+shift=clear) - see
        -- ui/RaidGroupsWindow.lua's applyStructure.
        for g = 1, RG.MAX_GROUPS do
            add("move_" .. g, "Move to Group " .. g,
                g ~= member.group and (snap.counts[g] or 0) < RG.GROUP_SIZE and not RG.IsGroupLocked(), "move")
        end
        if snap.isLeader and not member.isSelf then
            add("promote_leader", "Promote to Leader")
            if member.rank == 1 then add("demote_assist", "Demote Assistant") else add("promote_assist", "Promote to Assistant") end
            add("master_looter", "Set as Master Looter")
            add("uninvite", "Remove from Raid")
        end
    end
    return list
end

-- ============================================================================
-- REBUILD-AS-PARTY FALLBACK (for when native ConvertToParty() is unavailable -
-- confirmed live 2026-09-27: it's `nil` as a global on at least one server
-- this addon runs on. Not a member-count restriction - the function itself is
-- simply not exposed there, so the "Convert to Party" menu item silently
-- no-ops (guarded with `and ConvertToParty` in ui/RaidGroupsWindow.lua).
-- The fix: capture the roster, remove everyone else, then re-invite them - a
-- fresh invite chain always starts as a party, never a raid, so no actual
-- "conversion" call is needed. Genuinely disruptive (every other member gets
-- booted, however briefly), so this is Plan/Exec split like RG.PlanMove/
-- ExecMove - the UI shows the plan in a confirmation popup before executing.
-- ============================================================================

function RG.PlanRebuildAsParty(snap)
    if not (snap.mode == "raid" and snap.isLeader) then
        return nil, "You must be the raid leader to rebuild this raid as a party."
    end
    if #snap.members > RG.GROUP_SIZE then
        return nil, "Too many members (" .. #snap.members .. ") to rebuild as a party - remove players down to "
            .. RG.GROUP_SIZE .. " or fewer first."
    end
    local others = {}
    for _, m in ipairs(snap.members) do
        if not m.isSelf then others[#others + 1] = m.name end
    end
    if #others == 0 then
        return nil, "Nobody else to rebuild with - just leave the raid instead."
    end
    return others
end

-- Uninvites everyone from the plan, THEN (after a short delay) re-invites them.
-- The delay matters: firing InviteUnit in the very same tick as the uninvites
-- can race a raid-membership state the server hasn't finished clearing yet -
-- staggering it gives the uninvites time to actually land first, the same
-- reasoning as RG.SetAssignment's DataBus retry delay elsewhere in this file.
function RG.ExecRebuildAsParty(others)
    for _, name in ipairs(others) do
        if UninviteUnit then UninviteUnit(name) end
    end
    local function doInvites()
        for _, name in ipairs(others) do
            if InviteUnit then InviteUnit(name) end
        end
    end
    if AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(1.5, doInvites)
    else
        doInvites()
    end
end

-- Right-click the window's title/background.
function RG.WindowMenu(snap, locked)
    local list = {}
    list[#list + 1] = { id = "lock", text = locked and "Unlock position" or "Lock position", enabled = true }
    if snap.canManage then
        list[#list + 1] = { id = "group_lock", text = RG.IsGroupLocked() and "Unlock Group Positions" or "Lock Group Positions", enabled = true }
        list[#list + 1] = { id = "ready_check", text = "Ready Check", enabled = true }
    end
    -- Works in a party too now (RG.CanAnnounce) - group_lock/ready_check
    -- above stay raid-only (no party equivalent), but a group-wide
    -- announcement is just as useful in a 2-4 person party. RG.SetAllAnnouncement
    -- itself re-checks RG.CanAnnounce (never trust a stale menu-open-time
    -- snapshot for the real gate) - this only controls whether the item shows.
    if RG.CanAnnounce(snap) then
        local label = (snap.mode == "raid") and "Announce to Raid..." or "Announce to Party..."
        list[#list + 1] = { id = "announce_all", text = label, enabled = true }
    end
    if snap.isLeader then
        local total = #snap.members
        if snap.mode == "raid" and total <= RG.GROUP_SIZE then
            -- Feature-detected, not hardcoded to "this server is broken":
            -- native ConvertToParty() is confirmed nil on at least one server
            -- this addon runs on (see RG.PlanRebuildAsParty above) - when
            -- it's genuinely absent, offer the disband+reinvite fallback
            -- instead of a menu item that would silently do nothing.
            if ConvertToParty then
                list[#list + 1] = { id = "convert", text = "Convert to Party", enabled = true }
            else
                list[#list + 1] = { id = "convert_rebuild", text = "Rebuild as Party...", enabled = true }
            end
        elseif snap.mode == "party" then
            list[#list + 1] = { id = "convert", text = "Convert to Raid", enabled = true }
        end
    end
    list[#list + 1] = { id = "close", text = "Close", enabled = true }
    return list
end

-- ============================================================================
-- SLASH: /aip groups [lock|unlock]
-- ============================================================================

function RG.SlashHandler(rest)
    local sub = (rest or ""):match("^%s*(%S*)"):lower()
    if sub == "" then
        if RG.ToggleWindow then RG.ToggleWindow() else say("The Raid Groups window is not loaded.") end
    elseif sub == "lock" then
        say(RG.ToggleLocked() and "Raid Groups window locked." or "Raid Groups window unlocked.")
    elseif sub == "unlock" then
        RG.SetLocked(false)
        say("Raid Groups window unlocked.")
    else
        say("/aip groups [lock|unlock]")
    end
end

-- ============================================================================
-- READY CHECK (RG-020: an independent per-member status channel from the
-- persistent dead/offline/AFK/DND state - see the requirements doc). Separate
-- tracker from Integrations.lua's own READY_CHECK handler, which drives a
-- different feature (a chat summary); both simply listen to the same native
-- events. Ground truth for the exact event signatures was verified against
-- Integrations.lua's own already-working handler, not guessed.
-- ============================================================================

-- status[lowerName] = "ready" | "notready" | "waiting"
RG.readyCheck = { active = false, status = {}, finishedAt = nil }
-- How long results stay visible after a check finishes (long enough to
-- glance at who didn't respond) before GetReadyStatus starts reporting nil
-- again. BUG FOUND LIVE (2026-09-27): with no expiry at all, a "Not Ready"
-- icon from one real ready check was still showing on a player's cell an
-- entire play session later, with no new check in sight to ever reset it -
-- reported directly by the user as a persistent, unwanted "X" mark. Fixed
-- with a polled expiry (checked in GetReadyStatus, so on every refreshValues
-- tick already) rather than a DelayedCall timer - this addon's own
-- DelayedCall test stub fires synchronously, so a timer-based clear would be
-- unverifiable here; GetTime() is stubbed as a plain mutable value instead,
-- so a polled check is fully testable.
RG.READY_CHECK_LINGER = 20

local readyCheckListeners = {}
function RG.OnReadyCheckChanged(fn) readyCheckListeners[#readyCheckListeners + 1] = fn end
local function fireReadyCheck() fire(readyCheckListeners) end

-- Returns "ready"/"notready"/"waiting" for this player, or nil if no ready
-- check has ever run, this session doesn't know that name, or the last
-- check finished more than RG.READY_CHECK_LINGER seconds ago.
function RG.GetReadyStatus(name)
    if not name then return nil end
    if not RG.readyCheck.active and RG.readyCheck.finishedAt
        and GetTime and (GetTime() - RG.readyCheck.finishedAt) > RG.READY_CHECK_LINGER then
        return nil
    end
    return RG.readyCheck.status[name:lower()]
end

-- The three functions below are what the real client's READY_CHECK /
-- READY_CHECK_CONFIRM / READY_CHECK_FINISHED events call (wired below) -
-- exposed directly (mirrors the established RG.OnAssignmentEvent pattern) so
-- they're independently testable without a fake WoW-event dispatcher.
function RG.OnReadyCheckStart()
    RG.readyCheck.active = true
    RG.readyCheck.finishedAt = nil
    for k in pairs(RG.readyCheck.status) do RG.readyCheck.status[k] = nil end
    local snap = RG.Snapshot()
    for _, m in ipairs(snap.members) do RG.readyCheck.status[m.name:lower()] = "waiting" end
    fireReadyCheck()
end

function RG.OnReadyCheckConfirm(unit, ready)
    local name = UnitName and unit and UnitName(unit)
    if not name then return end
    RG.readyCheck.status[name:lower()] = ready and "ready" or "notready"
    fireReadyCheck()
end

-- Anyone who never responded is demoted from "waiting" to "notready" (matches
-- Blizzard's own raid frames). Results then linger for RG.READY_CHECK_LINGER
-- seconds (GetReadyStatus enforces this, polled - see there for why not a
-- DelayedCall timer), not forever.
function RG.OnReadyCheckFinished()
    RG.readyCheck.active = false
    RG.readyCheck.finishedAt = GetTime and GetTime() or nil
    for k, v in pairs(RG.readyCheck.status) do
        if v == "waiting" then RG.readyCheck.status[k] = "notready" end
    end
    fireReadyCheck()
end

-- ============================================================================
-- EVENTS
-- ============================================================================

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    local E = AIP.Utils.Events
    local function onRoster() RG.Changed() end
    E.Register("RAID_ROSTER_UPDATE", onRoster, "RaidGroups")
    E.Register("PARTY_MEMBERS_CHANGED", onRoster, "RaidGroups")
    E.Register("PARTY_LEADER_CHANGED", onRoster, "RaidGroups")
    E.Register("PLAYER_ENTERING_WORLD", onRoster, "RaidGroups")
    E.Register("PLAYER_REGEN_ENABLED", function() if RG.dirty then RG.Changed() end end, "RaidGroups")
    -- Events.Dispatch calls handlers as (event, ...native args...) - see
    -- core/Utils.lua - so the event name itself is the first (ignored) arg.
    E.Register("READY_CHECK", function() RG.OnReadyCheckStart() end, "RaidGroups")
    E.Register("READY_CHECK_CONFIRM", function(_, unit, ready) RG.OnReadyCheckConfirm(unit, ready) end, "RaidGroups")
    E.Register("READY_CHECK_FINISHED", function() RG.OnReadyCheckFinished() end, "RaidGroups")
end

if AIP.DataBus and AIP.DataBus.Subscribe then
    AIP.DataBus.Subscribe("RGNOTE", RG.OnAssignmentEvent, "RaidGroups")
    AIP.DataBus.Subscribe("RGALL", RG.OnAllAnnouncementEvent, "RaidGroups")
end

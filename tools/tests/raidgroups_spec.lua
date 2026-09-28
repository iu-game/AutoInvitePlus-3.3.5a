-- Headless tests for AutoInvitePlus/modules/RaidGroups.lua (pure logic; no WoW client).
-- Run from the repo root:  luajit tools/tests/raidgroups_spec.lua

local printed = {}
local currentCharKey = "TestRealm-Me"
AutoInvitePlus = {
    db = { raidGroups = {} },
    Print = function(msg) printed[#printed + 1] = msg end,
    Utils = { CharKey = function() return currentCharKey end },
}
local AIP = AutoInvitePlus

-- ---- WoW API stubs ---------------------------------------------------------
local raid, party, isLeaderFlag, isOfficerFlag, partyLeaderUnit = {}, {}, false, false, nil
local assignCalls = {}

local function raidEntry(i) return raid[i] end
GetNumRaidMembers = function() return #raid end
GetNumPartyMembers = function() return #party end
GetRaidRosterInfo = function(i)
    local r = raidEntry(i); if not r then return nil end
    -- name, rank, subgroup, level, class(localized), fileName, zone, online, isDead, role, isML
    return r.name, r.rank or 0, r.group or 1, r.level or 80, r.class or "Warrior", r.class and r.class:upper() or "WARRIOR",
        "Zone", r.online ~= false, r.dead and true or false, r.role, r.isML and true or false
end
UnitName = function(unit)
    if unit == "player" then return "Me" end
    local n = unit:match("^party(%d)$")
    if n then local e = party[tonumber(n)]; return e and e.name end
    n = unit:match("^raid(%d+)$")
    if n then local e = raid[tonumber(n)]; return e and e.name end
end
UnitClass = function(unit)
    if unit == "player" then return "Warrior", "WARRIOR" end
    local n = unit:match("^party(%d)$")
    if n then local e = party[tonumber(n)]; if e then return e.class, e.class:upper() end end
end
UnitLevel = function() return 80 end
UnitIsDead = function() return false end
UnitIsConnected = function() return true end
IsRaidLeader = function() return isLeaderFlag and 1 or nil end
IsRaidOfficer = function() return isOfficerFlag and 1 or nil end
local chatSent = {}
SendChatMessage = function(msg, chatType) chatSent[#chatSent + 1] = { msg = msg, chatType = chatType } end
UnitIsPartyLeader = function(unit) return unit == partyLeaderUnit end
SetRaidSubgroup = function(index, group) assignCalls[#assignCalls + 1] = "set:" .. index .. "->" .. group end
SwapRaidSubgroup = function(i1, i2) assignCalls[#assignCalls + 1] = "swap:" .. i1 .. "/" .. i2 end

-- Raid target icons: a plain unit->index map, exactly like the real client state.
local raidIcons = {}
SetRaidTarget = function(unit, index) raidIcons[unit] = (index and index > 0) and index or nil end
GetRaidTargetIndex = function(unit) return raidIcons[unit] end

-- Rebuild-as-party fallback (RG.PlanRebuildAsParty/ExecRebuildAsParty): records
-- calls in order so a test can assert uninvite-then-invite sequencing.
local groupActionLog = {}
UninviteUnit = function(name) groupActionLog[#groupActionLog + 1] = "uninvite:" .. name end
InviteUnit = function(name) groupActionLog[#groupActionLog + 1] = "invite:" .. name end

-- Time + auras (same stub shape as tools/tests/tankcast_spec.lua's UnitDebuff stub).
local now = 100
GetTime = function() return now end
local buffsByUnit, debuffsByUnit = {}, {}
local function auraStub(byUnit)
    return function(unit, i)
        local d = byUnit[unit] and byUnit[unit][i]
        if d then return d[1], "", d[2], d[3], d[4], 0, d[5], "player" end
    end
end
UnitBuff = auraStub(buffsByUnit)
UnitDebuff = auraStub(debuffsByUnit)

-- DataBus: records outgoing broadcasts and captures the RGNOTE subscriber so tests
-- can simulate an incoming assignment from another player.
local dbBroadcasts, subscribedCb, subscribedAllCb = {}, nil, nil
AutoInvitePlus.DataBus = {
    CreateEvent = function(t, d) return { type = t, data = d } end,
    Broadcast = function(event) dbBroadcasts[#dbBroadcasts + 1] = event; return true end,
    Subscribe = function(eventType, cb, owner)
        if eventType == "RGNOTE" then subscribedCb = cb
        elseif eventType == "RGALL" then subscribedAllCb = cb end
    end,
}

-- AIP.Utils.DelayedCall: fires immediately (the retry path only needs to run
-- eventually, and tests don't have a real WoW frame OnUpdate clock to wait on).
-- Added to the existing AIP.Utils table (which already carries CharKey) - a
-- flat reassignment here would silently wipe that field out.
AutoInvitePlus.Utils.DelayedCall = function(delay, fn) fn() end

-- Raid Management panel's buff-coverage engine (real shape: RM.ClassBuffs[class] is an
-- array of {buffName=...}; RM.CheckUnitBuffs(unit).missingBuffs is an array of names).
local missingFor = {}
local scanCalls = 0
AutoInvitePlus.Panels = { RaidMgmt = {
    ClassBuffs = { WARRIOR = { { buffName = "Battle Shout" }, { buffName = "Commanding Shout" } } },
    CheckUnitBuffs = function(unit) return { missingBuffs = missingFor[unit] or {} } end,
    ScanBuffProviders = function() scanCalls = scanCalls + 1 end,
} }

-- Tank Cast's reused spell/item engine (only the two functions quick-cast needs).
AutoInvitePlus.TankCast = {
    ParseSpellInput = function(t)
        if type(t) ~= "string" then return "" end
        return (t:gsub("^%s+", ""):gsub("%s+$", ""))
    end,
    BuildMacro = function(name, spell)
        if name == "" or spell == "" then return nil end
        return "/cast [target=" .. name .. "] " .. spell
    end,
}

dofile("AutoInvitePlus/modules/RaidGroups.lua")
local RG = AIP.RaidGroups

-- ---- tiny test framework ---------------------------------------------------
local pass, fail = 0, 0
local function eq(actual, expected, label)
    if actual == expected then pass = pass + 1
    else fail = fail + 1; print("FAIL " .. label .. ": expected [" .. tostring(expected) .. "], got [" .. tostring(actual) .. "]") end
end
local function wipe(t) for k in pairs(t) do t[k] = nil end end

local function reset()
    raid, party, isLeaderFlag, isOfficerFlag, partyLeaderUnit = {}, {}, false, false, nil
    assignCalls, printed, chatSent = {}, {}, {}
    currentCharKey = "TestRealm-Me"
    AIP.db.raidGroups = {}
    AIP.db.raidGroupsByChar = nil
    raidIcons, dbBroadcasts, missingFor = {}, {}, {}
    scanCalls = 0
    wipe(groupActionLog)
    -- buffsByUnit/debuffsByUnit are captured by UnitBuff/UnitDebuff through a
    -- helper function call (auraStub(byUnit)), which binds to the table it was
    -- called with, not to this outer variable - reassigning it here would
    -- silently detach the stub from the new table. Clear in place instead.
    wipe(buffsByUnit); wipe(debuffsByUnit)
    now = 100
    RG.assignments = {}
    RG.allAnnouncement = nil
    RG.wasGrouped = nil
end

local function findId(list, id) for _, it in ipairs(list) do if it.id == id then return it end end end

-- ---- Snapshot: solo / party / raid -----------------------------------------
reset()
local snap = RG.Snapshot()
eq(snap.mode, "solo", "solo mode"); eq(#snap.members, 1, "solo: just me"); eq(snap.members[1].isSelf, true, "solo: self flagged")
eq(snap.canManage, false, "solo: cannot manage"); eq(snap.groups[1][1].name, "Me", "solo: in group 1")

reset(); party = { [1] = { name = "Ally", class = "Priest" } }
snap = RG.Snapshot()
eq(snap.mode, "party", "party mode"); eq(#snap.members, 2, "party: me + 1"); eq(snap.counts[1], 2, "party: both in group 1")
eq(snap.canManage, false, "party: cannot manage without real leadership")
partyLeaderUnit = "player"
snap = RG.Snapshot(); eq(snap.canManage, false, "party leader alone does not grant raid manage powers")

reset()
raid = {
    { name = "Boss", rank = 2, group = 1, class = "Paladin" },
    { name = "Ass", rank = 1, group = 1, class = "Priest" },
    { name = "Grunt", rank = 0, group = 2, class = "Warrior" },
    { name = "Offline", rank = 0, group = 2, class = "Mage", online = false },
    { name = "Dead", rank = 0, group = 3, class = "Rogue", dead = true },
}
snap = RG.Snapshot()
eq(snap.mode, "raid", "raid mode"); eq(#snap.members, 5, "raid: five members"); eq(snap.counts[1], 2, "raid: two in group 1")
eq(snap.counts[2], 2, "raid: two in group 2"); eq(snap.counts[3], 1, "raid: one in group 3"); eq(snap.counts[4] or 0, 0, "raid: group 4 empty")
eq(snap.groups[3][1].dead, true, "raid: dead flagged"); eq(snap.groups[2][2].online, false, "raid: offline flagged")
eq(snap.myRank, 0, "raid: my own rank when not listed defaults to 0"); eq(snap.canManage, false, "raid: not manager")
isOfficerFlag = true; snap = RG.Snapshot(); eq(snap.canManage, true, "raid: officer can manage")
isOfficerFlag, isLeaderFlag = false, true; snap = RG.Snapshot(); eq(snap.canManage, true, "raid: leader can manage"); eq(snap.isLeader, true, "raid: isLeader flag")

-- ---- VisibleGroups ----------------------------------------------------------
reset(); local vsolo = RG.VisibleGroups(RG.Snapshot()); eq(#vsolo, 1, "solo visible: 1 group"); eq(vsolo[1], 1, "solo visible: group 1")
reset()
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 3, class = "Mage" } }
local vmember = RG.VisibleGroups(RG.Snapshot())
eq(#vmember, 2, "member view: only non-empty groups"); eq(vmember[1], 1, "member view: group 1 first"); eq(vmember[2], 3, "member view: group 3 second, group 2 skipped")
isLeaderFlag = true
local vmgr = RG.VisibleGroups(RG.Snapshot())
eq(#vmgr, 8, "manager view: all 8 groups"); eq(vmgr[8], 8, "manager view: includes empty group 8")

-- ---- GridSize ----------------------------------------------------------------
local function grid(n) local c, r = RG.GridSize(n); return c .. "x" .. r end
eq(grid(1), "1x1", "grid 1"); eq(grid(3), "3x1", "grid 3"); eq(grid(4), "4x1", "grid 4")
eq(grid(5), "3x2", "grid 5"); eq(grid(6), "3x2", "grid 6"); eq(grid(7), "4x2", "grid 7"); eq(grid(8), "4x2", "grid 8")

-- ---- ComputeLayout ------------------------------------------------------------
reset()
raid = {
    { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" },
    { name = "C", group = 2, class = "Priest" },
}
local dims = { cellW = 10, cellH = 2, gap = 0, groupGap = 1, pad = 0 }
local s2 = RG.Snapshot()
local layout = RG.ComputeLayout({ 1, 2 }, s2, dims)
eq(layout.groups[1].x, 0, "layout: group 1 at x=0"); eq(layout.groups[1].rows, 2, "layout: group 1 shows its 2 members (non-manager)")
eq(layout.groups[1].h, 4, "layout: group 1 height = 2 rows * (cellH+gap) - gap = 4")
eq(layout.groups[2].x, 11, "layout: group 2 starts after group 1's width + groupGap"); eq(layout.groups[2].rows, 1, "layout: group 2 shows its 1 member")
eq(layout.w, 21, "layout: total width = 2 groups * 10 + 1 gap"); eq(layout.h, 4, "layout: total height = the taller row (group 1's 4px)")

isLeaderFlag = true
local smgr = RG.Snapshot()
local layoutMgr = RG.ComputeLayout(RG.VisibleGroups(smgr), smgr, dims)
eq(layoutMgr.groups[1].rows, RG.GROUP_SIZE, "layout: manager view always reserves 5 rows per group")
eq(layoutMgr.groups[1].h, 10, "layout: manager group height = 5*(2)-0 = 10 with these dims")

-- Groups 1-4 land in grid-row 1 and 5-8 in grid-row 2 (GridSize(8) = 4x2), but
-- without a gap distinct from the horizontal one, the two rows read as one
-- undifferentiated block - confirmed live (2026-09-27) before this fix.
eq(layoutMgr.groups[4].y, layoutMgr.groups[1].y, "layout: group 4 (last of row 1) shares row 1's y with group 1")
eq(layoutMgr.groups[5].y > layoutMgr.groups[1].y, true, "layout: group 5 (first of row 2) starts below row 1")
local dimsRowGap = { cellW = 10, cellH = 2, gap = 0, groupGap = 1, rowGap = 5, pad = 0 }
local layoutRowGap = RG.ComputeLayout(RG.VisibleGroups(smgr), smgr, dimsRowGap)
eq(layoutRowGap.groups[5].y, 15, "layout: a distinct (bigger) rowGap widens the gap between row 1 and row 2 (10 + 5), independent of the horizontal groupGap")
eq(layoutRowGap.h, 25, "layout: total height uses rowGap between grid-rows, not groupGap (10+10+5)")
-- Omitting rowGap falls back to groupGap (old dims tables, e.g. `dims` above,
-- keep working unchanged).
eq(layoutMgr.groups[5].y, 11, "layout: rowGap defaults to groupGap when not given (10 + 1)")

-- Grid dimensions and per-row bottom edges are exposed so the UI can draw an
-- explicit divider between row bands (a gap alone, even a bigger one, wasn't
-- unambiguous enough live - confirmed 2026-09-27).
eq(layoutMgr.rows, 2, "layout: exposes the grid row count"); eq(layoutMgr.cols, 4, "layout: exposes the grid column count")
eq(layoutMgr.rowBottom[1], 10, "layout: row 1's bottom edge = its height (10)")
eq(layoutMgr.groups[5].y, layoutMgr.rowBottom[1] + dims.groupGap, "layout: row 2 starts exactly rowGap below row 1's bottom edge (dims has no explicit rowGap, so it fell back to groupGap)")

-- ---- PlanMove / ExecMove ------------------------------------------------------
reset()
raid = {
    { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" },
    { name = "C", group = 2, class = "Priest" },
}
local snapNoMgr = RG.Snapshot()
eq((RG.PlanMove(snapNoMgr, "A", { group = 2 })), nil, "PlanMove: refused without manage permission")
isOfficerFlag = true
local snapMgr = RG.Snapshot()
local plan = RG.PlanMove(snapMgr, "A", { group = 2 })
eq(plan.op, "set", "PlanMove: room available -> set"); eq(plan.group, 2, "PlanMove: target group"); eq(plan.index, 1, "PlanMove: source raid index")
eq((RG.PlanMove(snapMgr, "A", { group = 1 })), nil, "PlanMove: refused, already in that group")
eq((RG.PlanMove(snapMgr, "Nobody", { group = 2 })), nil, "PlanMove: refused, unknown player")
plan = RG.PlanMove(snapMgr, "A", { name = "C" })
eq(plan.op, "set", "PlanMove: dropped on a member of a non-full group is still a plain move")

reset(); isOfficerFlag = true
local full = {}
for i = 1, RG.GROUP_SIZE do full[i] = { name = "M" .. i, group = 1, class = "Warrior" } end
full[#full + 1] = { name = "X", group = 2, class = "Mage" }
raid = full
local snapFull = RG.Snapshot()
eq((RG.PlanMove(snapFull, "X", { group = 1 })), nil, "PlanMove: full group + no target member -> refused")
local swapPlan = RG.PlanMove(snapFull, "X", { name = "M3" })
eq(swapPlan.op, "swap", "PlanMove: full group + dropped on a member -> swap")
eq(swapPlan.index1, RG.GROUP_SIZE + 1, "PlanMove: swap index1 = mover"); eq(swapPlan.index2, 3, "PlanMove: swap index2 = the member dropped on")

RG.ExecMove({ op = "set", index = 5, group = 3 }); eq(assignCalls[#assignCalls], "set:5->3", "ExecMove: set calls SetRaidSubgroup")
RG.ExecMove({ op = "swap", index1 = 1, index2 = 2 }); eq(assignCalls[#assignCalls], "swap:1/2", "ExecMove: swap calls SwapRaidSubgroup")

-- ---- Menus --------------------------------------------------------------------
eq(RG.RankLabel(2), "Raid leader", "RankLabel 2"); eq(RG.RankLabel(1), "Assistant", "RankLabel 1"); eq(RG.RankLabel(0), "Member", "RankLabel 0")

reset()
-- "Me" is the row that matches the UnitName("player") stub, i.e. the viewer's own
-- row (rank 2, so later it also stands in for "the raid leader querying their own
-- row"); "Grunt" is the other member every officer/leader assertion acts on.
raid = { { name = "Me", rank = 2, group = 1, class = "Paladin" }, { name = "Grunt", rank = 0, group = 2, class = "Warrior" } }
local snapMember = RG.Snapshot()
local grunt = snapMember.members[2]
local mm = RG.MemberMenu(snapMember, grunt, true)
eq(findId(mm, "whisper") ~= nil, true, "member menu: whisper present for others")
eq(findId(mm, "tank_mt") ~= nil, true, "member menu: Tank Cast entries present when hasTankCast")
eq(findId(mm, "move_1"), nil, "member menu: no move entries without manage permission")
eq(findId(mm, "promote_leader"), nil, "member menu: no leader-only entries for a plain member")

local me = snapMember.members[1]
eq(me.isSelf, true, "fixture sanity: 'Me' resolves as the viewer's own row")
local selfMenu = RG.MemberMenu(snapMember, me, true)
eq(findId(selfMenu, "whisper"), nil, "member menu: no whisper on yourself")
eq(findId(selfMenu, "inspect") ~= nil, true, "member menu: inspect still offered on yourself")

isOfficerFlag = true
local snapOfficer = RG.Snapshot()
local mmOfficer = RG.MemberMenu(snapOfficer, snapOfficer.members[2], false)
-- Set/Clear Main Tank/Assist are NOT offered from the menu at all (same class
-- of protected-function bug as Focus/Clear Focus - SetPartyAssignment cannot
-- be called from an insecure EasyMenu handler); the real fix is a secure
-- modifier-click on the member cell, in ui/RaidGroupsWindow.lua, untestable
-- headlessly.
eq(findId(mmOfficer, "set_mt"), nil, "officer menu: no Set Main Tank (moved to a secure modifier-click - see ui/RaidGroupsWindow.lua)")
eq(findId(mmOfficer, "set_ma"), nil, "officer menu: no Set Main Assist either")
local move2 = findId(mmOfficer, "move_2")
eq(move2.enabled, false, "officer menu: move to the member's own group is disabled")
eq(findId(mmOfficer, "move_3").enabled, true, "officer menu: move to a different, non-full group is enabled")
eq(findId(mmOfficer, "promote_leader"), nil, "officer (non-leader) menu: no leader-only entries")

-- compact/organised menus: long same-kind runs (raid icons, move-to-group,
-- MT/MA) carry a `group` tag so the UI can fold them into a submenu instead
-- of a 20+ row flat list; ordinary single-purpose entries stay ungrouped
-- (nil) so they render as normal top-level rows.
eq(findId(mmOfficer, "raid_icon_1").group, "icons", "member menu: raid icon entries are grouped for a submenu")
eq(findId(mmOfficer, "raid_icon_clear").group, "icons", "...including 'clear'")
eq(findId(mmOfficer, "move_2").group, "move", "member menu: move-to-group entries are grouped for a submenu")
eq(findId(mm, "whisper").group, nil, "member menu: ordinary entries stay top-level (ungrouped)")
eq(findId(mm, "tank_mt").group, nil, "member menu: Tank Cast entries stay top-level (ungrouped)")

isLeaderFlag, isOfficerFlag = true, false
local snapLeader = RG.Snapshot()
local mmLeader = RG.MemberMenu(snapLeader, snapLeader.members[2], false)
eq(findId(mmLeader, "promote_leader") ~= nil, true, "leader menu: promote_leader present")
eq(findId(mmLeader, "uninvite") ~= nil, true, "leader menu: uninvite present")
eq(findId(mmLeader, "promote_assist") ~= nil, true, "leader menu: rank-0 member offered promote_assist, not demote")
eq(findId(mmLeader, "demote_assist"), nil, "leader menu: rank-0 member is not offered demote")
local mmLeaderOnBoss = RG.MemberMenu(snapLeader, snapLeader.members[1], false)
eq(findId(mmLeaderOnBoss, "demote_assist"), nil, "leader menu: the raid leader row has no demote entry")
eq(findId(mmLeaderOnBoss, "promote_leader"), nil, "leader menu: no 'promote to leader' on yourself")

local wmMember = RG.WindowMenu(snapMember, false)
eq(findId(wmMember, "ready_check"), nil, "window menu: no ready check for a plain member")
eq(findId(wmMember, "lock").text, "Lock position", "window menu: lock label unlocked")
local wmLeader = RG.WindowMenu(snapLeader, true)
eq(findId(wmLeader, "ready_check") ~= nil, true, "window menu: ready check for a manager")
eq(findId(wmLeader, "lock").text, "Unlock position", "window menu: lock label locked")
eq(findId(wmLeader, "close") ~= nil, true, "window menu: close always present")
eq(findId(wmMember, "announce_all"), nil, "window menu: no announce-to-raid for a plain member")
eq(findId(wmLeader, "announce_all").text, "Announce to Raid...", "window menu: manager in raid sees announce-to-raid")

-- ---- lock / slash -------------------------------------------------------------
reset()
eq(RG.IsLocked(), false, "starts unlocked"); eq(RG.ToggleLocked(), true, "toggle locks"); eq(RG.IsLocked(), true, "locked")
eq(AIP.db.raidGroups.locked, true, "lock persisted in db.raidGroups.locked")
RG.SetLocked(false); eq(RG.IsLocked(), false, "SetLocked(false)")
RG.SlashHandler("lock"); eq(RG.IsLocked(), true, "slash lock toggles"); RG.SlashHandler("unlock"); eq(RG.IsLocked(), false, "slash unlock")

-- ---- party/solo class + convert-to-raid (fixed after a live SetShown crash and
-- an -truncation bug review) ------------------------------------------
reset()
snap = RG.Snapshot()
eq(snap.members[1].class, "WARRIOR", "solo: self class populated (UnitClass and-truncation bug)")

reset(); party = { [1] = { name = "Ally", class = "Priest" } }
snap = RG.Snapshot()
eq(snap.members[1].class, "WARRIOR", "party: self class still populated")
eq(snap.members[2].class, "PRIEST", "party: OTHER member's class populated too (and-truncation hit this line as well)")

reset(); party = { [1] = { name = "Ally", class = "Priest" } }; partyLeaderUnit = "player"
snap = RG.Snapshot()
eq(snap.mode, "party", "party mode"); eq(snap.canManage, false, "party leader still cannot manage (no raid to manage)")
eq(snap.isLeader, true, "party leader IS isLeader (so window-menu convert is reachable)")
local wm = RG.WindowMenu(snap, false)
eq(findId(wm, "convert").text, "Convert to Raid", "window menu: party leader can convert to raid")
eq(findId(wm, "announce_all").text, "Announce to Party...", "window menu: party leader CAN announce to the party now (RG.CanAnnounce, not canManage)")
reset(); party = { [1] = { name = "Ally", class = "Priest" } }
snap = RG.Snapshot()
eq(findId(RG.WindowMenu(snap, false), "convert"), nil, "window menu: a non-leader party member has no convert option")

-- Feature-detected raid->party path: ConvertToParty is nil in this test env
-- by default (matches the real server this was found broken on, 2026-09-27) -
-- the menu should offer the fallback id, not a dead "convert" that would
-- silently no-op.
reset()
raid = { { name = "Me", rank = 2, group = 1, class = "Warrior" }, { name = "A", group = 1, class = "Mage" } }
isLeaderFlag = true
local snapConvertFallback = RG.Snapshot()
local wmFallback = RG.WindowMenu(snapConvertFallback, false)
eq(findId(wmFallback, "convert"), nil, "window menu: no dead 'convert' entry when ConvertToParty is nil")
eq(findId(wmFallback, "convert_rebuild").text, "Rebuild as Party...", "window menu: offers the fallback instead")
_G.ConvertToParty = function() end   -- simulate a server where the native function DOES exist
local wmNative = RG.WindowMenu(snapConvertFallback, false)
eq(findId(wmNative, "convert").text, "Convert to Party", "window menu: uses the native path when ConvertToParty is actually defined")
eq(findId(wmNative, "convert_rebuild"), nil, "...and does not also offer the fallback")
_G.ConvertToParty = nil   -- restore for every test below this one

-- ---- group-position lock ----------------------------------------------------
reset()
eq(RG.IsGroupLocked(), false, "starts unlocked")
local gok, gerr = RG.ToggleGroupLocked({ canManage = false })
eq(gok, false, "toggle refused without manage permission"); eq(RG.IsGroupLocked(), false, "...and stays unlocked")
gok, gerr = RG.ToggleGroupLocked({ canManage = true })
eq(gok, true, "manager can toggle"); eq(gerr, true, "returns the new state"); eq(RG.IsGroupLocked(), true, "now locked")
RG.SetGroupLocked(false); eq(RG.IsGroupLocked(), false, "SetGroupLocked(false)")

reset(); isOfficerFlag = true
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" }, { name = "C", group = 2, class = "Priest" } }
local snapGL = RG.Snapshot()
RG.SetGroupLocked(true)
local _, glReason = RG.PlanMove(snapGL, "A", { group = 2 })
eq(glReason, "Group positions are locked.", "PlanMove refuses while group-locked")
RG.SetGroupLocked(false)
eq((RG.PlanMove(snapGL, "A", { group = 2 })).op, "set", "PlanMove works again once unlocked")

-- ---- raid target icons -------------------------------------------------------
reset()
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" } }
local snapIcon = RG.Snapshot()
eq(RG.GetRaidIcon(snapIcon, "A"), 0, "no icon by default")
eq((RG.SetRaidIcon(snapIcon, "A", 8)), false, "no permission without manage")
isOfficerFlag = true
snapIcon = RG.Snapshot()
eq((RG.SetRaidIcon(snapIcon, "A", 8)), true, "manager can set")
eq(RG.GetRaidIcon(snapIcon, "A"), 8, "reads back the icon just set")
eq((RG.SetRaidIcon(snapIcon, "A", 9)), false, "bad index rejected")
eq((RG.SetRaidIcon(snapIcon, "Nobody", 1)), false, "unknown player")
eq(RG.RAID_ICONS[8], "Skull", "canonical icon order")

-- ---- private notes ------------------------------------------------------------
reset()
eq(RG.GetNote("Bob"), "", "no note by default")
eq((RG.SetNote("Bob", "  hello world  ")), true, "set ok")
eq(RG.GetNote("bob"), "hello world", "note lookup is case-insensitive and trimmed")
RG.SetNote("Bob", string.rep("x", RG.MAX_NOTE_LEN + 40))
eq(#RG.GetNote("Bob"), RG.MAX_NOTE_LEN, "note capped at RG.MAX_NOTE_LEN chars (asserted against the constant, not a hardcoded number, so this can't go stale again)")
RG.SetNote("Bob", "")
eq(RG.GetNote("Bob"), "", "empty text clears the note")
eq((RG.SetNote("", "x")), false, "rejects an empty name")

-- ---- assignments (shared, manager-set, broadcast) ------------------------------
reset()
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" } }
local snapAsg = RG.Snapshot()
eq((RG.SetAssignment(snapAsg, "A", "Interrupt")), false, "no permission without manage")
isOfficerFlag = true
snapAsg = RG.Snapshot()
eq((RG.SetAssignment(snapAsg, "A", "Interrupt")), true, "manager can set")
local atext, aauthor = RG.GetAssignment("A")
eq(atext, "Interrupt", "local cache updated immediately (no DataBus echo to wait for)")
eq(aauthor, "Me", "author is the setter")
eq(#dbBroadcasts, 1, "exactly one broadcast sent"); eq(dbBroadcasts[1].type, "RGNOTE", "broadcast event type")
eq(dbBroadcasts[1].data.player, "A", "broadcast player field"); eq(dbBroadcasts[1].data.note, "Interrupt", "broadcast note field")
RG.SetAssignment(snapAsg, "A", "")
eq(RG.GetAssignment("A"), "", "clearing removes it")
eq(type(subscribedCb), "function", "the module subscribed to RGNOTE at load")
subscribedCb({ type = "RGNOTE", sender = "Zed", data = { player = "B", note = "Kite", author = "Zed" } })
local btext, bauthor = RG.GetAssignment("B")
eq(btext, "Kite", "an assignment received from another player updates the cache"); eq(bauthor, "Zed", "...with its real author")
local seen = {}
RG.OnAssignment(function(name, text, author) seen[#seen + 1] = name .. ":" .. text .. ":" .. author end)
subscribedCb({ type = "RGNOTE", sender = "Zed", data = { player = "B", note = "Stack", author = "Zed" } })
eq(seen[#seen], "B:Stack:Zed", "OnAssignment listeners fire on a received event")

-- ---- MAX_NOTE_LEN: sized to fit a real Raid Warning message ---------------------
-- Verified (not guessed) via web search, 2026-09-27: SendChatMessage/
-- RAID_WARNING is capped at 255 characters, consistent across Classic/WotLK/
-- Retail. 240 leaves headroom for the worst-case "PlayerName: " prefix this
-- module itself adds when pushing a player-directed assignment as a real
-- raid warning (WoW's own 12-character name cap + ": " = 14 chars,
-- 255-14=241, rounded down to 240 for a clean number with 1 char to spare).
eq(RG.MAX_NOTE_LEN, 240, "MAX_NOTE_LEN fits a real Raid Warning message (255) minus worst-case 'Name: ' prefix")

-- ---- Raid Warning push: setting a player assignment also sends a real RW -------
reset()
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" } }
isOfficerFlag = true
local snapRW = RG.Snapshot()
RG.SetAssignment(snapRW, "A", "Interrupt casters")
eq(#chatSent, 1, "setting an assignment also pushes a real Raid Warning")
eq(chatSent[1].chatType, "RAID_WARNING", "...on the RAID_WARNING channel")
eq(chatSent[1].msg, "A: Interrupt casters", "...prefixed with the target's name so non-addon raiders know who it's for")
RG.SetAssignment(snapRW, "A", "")
eq(#chatSent, 1, "clearing an assignment does NOT push a spurious empty Raid Warning")

-- ---- All-raid announcement (RG-title-bar broadcast, new 2026-09-27 feature) -----
reset()
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" } }
local snapAll = RG.Snapshot()
eq((RG.SetAllAnnouncement(snapAll, "Wipe it, reset")), false, "no permission without manage")
isLeaderFlag = true
snapAll = RG.Snapshot()
eq((RG.SetAllAnnouncement(snapAll, "Wipe it, reset")), true, "manager can set")
local alltext, allauthor = RG.GetAllAnnouncementIfFresh()
eq(alltext, "Wipe it, reset", "local cache updated immediately"); eq(allauthor, "Me", "author is the setter")
eq(#dbBroadcasts, 1, "exactly one broadcast sent"); eq(dbBroadcasts[1].type, "RGALL", "broadcast event type (distinct from RGNOTE)")
eq(dbBroadcasts[1].data.note, "Wipe it, reset", "broadcast note field"); eq(dbBroadcasts[1].data.player, nil, "no player field - this is for everyone")
eq(#chatSent, 1, "also pushes a real Raid Warning"); eq(chatSent[1].chatType, "RAID_WARNING", "...RAID_WARNING channel")
eq(chatSent[1].msg, "Wipe it, reset", "...with NO name prefix (unlike a player-directed assignment) - it's already raid-wide via the RW channel itself")

local allSeen = {}
RG.OnAllAnnouncementChanged(function(text, author) allSeen[#allSeen + 1] = text .. ":" .. author end)
eq(type(subscribedAllCb), "function", "the module subscribed to RGALL at load")
subscribedAllCb({ type = "RGALL", sender = "Zed", data = { note = "Focus adds", author = "Zed" } })
local rtext, rauthor = RG.GetAllAnnouncementIfFresh()
eq(rtext, "Focus adds", "a received all-announcement updates the shared cache"); eq(rauthor, "Zed", "...with its real author")
eq(allSeen[#allSeen], "Focus adds:Zed", "OnAllAnnouncementChanged listeners fire on a received event")

-- ---- 40s tooltip linger, independent per announcement TYPE ---------------------
-- "autoclear after 40 sec if not overwritten by another of same type" - a
-- fresh player-directed assignment must not reset (or be reset by) the ALL
-- announcement's own independent timer, and vice versa.
reset()
raid = { { name = "A", group = 1, class = "Warrior" } }
isOfficerFlag, isLeaderFlag = true, true
local snapLinger = RG.Snapshot()
RG.SetAssignment(snapLinger, "A", "Tank swap now")
RG.SetAllAnnouncement(snapLinger, "Enrage in 10s")
eq(select(1, RG.GetAssignmentIfFresh("A")), "Tank swap now", "fresh player-directed assignment shows")
eq(select(1, RG.GetAllAnnouncementIfFresh()), "Enrage in 10s", "fresh all-announcement shows too, independently")
now = now + RG.ANNOUNCEMENT_LINGER + 1
eq(RG.GetAssignmentIfFresh("A"), "", "player-directed assignment expires after the linger window")
eq(RG.GetAllAnnouncementIfFresh(), "", "...and the all-announcement expires too")
eq(RG.GetAssignment("A"), "Tank swap now", "GetAssignment (unconditional, used e.g. to pre-fill the edit popup) is NOT affected by the tooltip linger")
-- A fresh SET of one type resets ONLY that type's own timer.
RG.SetAssignment(snapLinger, "A", "New call")
eq(select(1, RG.GetAssignmentIfFresh("A")), "New call", "re-setting the player-directed one refreshes ITS OWN timer")
eq(RG.GetAllAnnouncementIfFresh(), "", "...without reviving the already-expired all-announcement (independent timers)")

-- ---- RG.CanAnnounce / announcements work in a PARTY too, not just a raid -------
-- The user asked 2026-09-27 to keep assignments/announcements enabled in a
-- normal party, just gating which chat channel gets the real push (RW in a
-- raid, /p in a party) instead of raid-only.
reset()
eq(RG.CanAnnounce({ mode = "solo" }), false, "solo: never announceable")
eq(RG.CanAnnounce({ mode = "party", isLeader = false }), false, "party, not leader: no")
eq(RG.CanAnnounce({ mode = "party", isLeader = true }), true, "party leader: yes")
eq(RG.CanAnnounce({ mode = "raid", canManage = false }), false, "raid, not manager: no")
eq(RG.CanAnnounce({ mode = "raid", canManage = true }), true, "raid manager: yes")

reset(); party = { { name = "A", class = "Mage" } }; partyLeaderUnit = "player"
local snapPartyLeader = RG.Snapshot()
eq(snapPartyLeader.mode, "party", "party mode"); eq(snapPartyLeader.isLeader, true, "self is party leader")
eq((RG.SetAssignment(snapPartyLeader, "A", "Sheep the add")), true, "party leader can set an assignment")
eq(select(1, RG.GetAssignment("A")), "Sheep the add", "assignment cached")
eq(#chatSent, 1, "pushes a real chat message"); eq(chatSent[1].chatType, "PARTY", "...on PARTY, not RAID_WARNING")
eq(chatSent[1].msg, "A: Sheep the add", "...still prefixed with the target's name")

reset(); party = { { name = "A", class = "Mage" }, { name = "B", class = "Priest" } }; partyLeaderUnit = "party1"
local snapPartyMember = RG.Snapshot()
eq(snapPartyMember.isLeader, false, "self is not the party leader here")
local pOk, pErr = RG.SetAssignment(snapPartyMember, "B", "Heal me")
eq(pOk, false, "a non-leader party member cannot set an assignment"); eq(type(pErr), "string", "...with an explanatory error")
eq(#chatSent, 0, "...and nothing was pushed")

reset(); party = { { name = "A", class = "Mage" } }; partyLeaderUnit = "player"
local snapPartyAll = RG.Snapshot()
eq((RG.SetAllAnnouncement(snapPartyAll, "Regroup at the door")), true, "party leader can set an all-announcement")
eq(select(1, RG.GetAllAnnouncementIfFresh()), "Regroup at the door", "cached")
eq(chatSent[1].chatType, "PARTY", "all-announcement also pushes to PARTY in party mode")
eq(chatSent[1].msg, "Regroup at the door", "...with no name prefix, same as the raid case")

-- Menus: "Announce to Party..." (not "...to Raid...") and "Set Assignment..."
-- both appear for a party leader; neither for a non-manager/non-leader.
local wmParty = RG.WindowMenu(snapPartyAll, false)
eq(findId(wmParty, "announce_all").text, "Announce to Party...", "window menu: party-mode label")
local wmPartyMember = RG.WindowMenu(snapPartyMember, false)
eq(findId(wmPartyMember, "announce_all"), nil, "window menu: no announce entry for a non-leader party member")
local mmPartyLeaderOther = RG.MemberMenu(snapPartyAll, snapPartyAll.members[2], false)
eq(findId(mmPartyLeaderOther, "note_assignment") ~= nil, true, "member menu: party leader sees Set Assignment on another member")
local mmPartyMemberOther = RG.MemberMenu(snapPartyMember, snapPartyMember.members[2], false)
eq(findId(mmPartyMemberOther, "note_assignment"), nil, "member menu: non-leader party member does not see Set Assignment")

-- Remote-event acceptance now covers party too (previously raid-only).
reset(); party = { { name = "A", class = "Mage" } }; partyLeaderUnit = "player"
subscribedCb({ type = "RGNOTE", sender = "A", data = { player = "A", note = "Interrupt", author = "A" } })
eq(select(1, RG.GetAssignment("A")), "Interrupt", "a remote assignment event is accepted while in a party")
subscribedAllCb({ type = "RGALL", sender = "A", data = { note = "Regroup", author = "A" } })
eq(select(1, RG.GetAllAnnouncementIfFresh()), "Regroup", "a remote all-announcement event is accepted while in a party")

-- ---- Rebuild-as-party fallback (RG.PlanRebuildAsParty / ExecRebuildAsParty) -----
-- Confirmed live 2026-09-27: `ConvertToParty` is `nil` as a global on at least
-- one server this addon runs on - not a member-count restriction, the native
-- function itself is simply unavailable there. This is the fallback the user
-- asked for: capture the roster, remove everyone else, re-invite them - which
-- naturally reforms as a party (a fresh invite chain never starts as a raid).
reset()
raid = {
    { name = "Me", rank = 2, group = 1, class = "Warrior" },
    { name = "A", group = 1, class = "Mage" }, { name = "B", group = 1, class = "Priest" },
}
isLeaderFlag = true
local snapRebuild = RG.Snapshot()
local plan, perr = RG.PlanRebuildAsParty(snapRebuild)
eq(perr, nil, "no error for a valid raid leader with room to rebuild")
table.sort(plan)
eq(table.concat(plan, ","), "A,B", "plan captures every OTHER member (not self)")

isLeaderFlag = false
local snapNotLeader = RG.Snapshot()
local plan2, perr2 = RG.PlanRebuildAsParty(snapNotLeader)
eq(plan2, nil, "a non-leader cannot plan a rebuild"); eq(type(perr2), "string", "...with an explanatory error")

reset(); isLeaderFlag = true
local full = { { name = "Me", rank = 2, group = 1, class = "Warrior" } }
for i = 1, RG.GROUP_SIZE + 1 do full[#full + 1] = { name = "M" .. i, group = 1, class = "Warrior" } end
raid = full
local snapTooBig = RG.Snapshot()
local plan3, perr3 = RG.PlanRebuildAsParty(snapTooBig)
eq(plan3, nil, "too many members (raid > GROUP_SIZE) refuses to plan a rebuild"); eq(type(perr3), "string", "...with an explanatory error")

reset(); isLeaderFlag = true
raid = { { name = "Me", rank = 2, group = 1, class = "Warrior" } }
local snapAlone = RG.Snapshot()
local plan4, perr4 = RG.PlanRebuildAsParty(snapAlone)
eq(plan4, nil, "solo in a 1-person raid: nothing to rebuild with"); eq(type(perr4), "string", "...with an explanatory error")

reset()
RG.ExecRebuildAsParty({ "A", "B" })
eq(table.concat(groupActionLog, "|"), "uninvite:A|uninvite:B|invite:A|invite:B",
    "exec uninvites everyone first, THEN re-invites everyone (via DelayedCall, which the test stub fires immediately) - never interleaved, so a slow uninvite can't race an invite for the same name")

-- ---- debuffs / buffs -----------------------------------------------------------
reset()
debuffsByUnit.raid1 = { { "Sunder Armor", "iconSA", 5, nil, 112 }, { "Curse of Weakness", "iconCW", 1, "Curse", 220 } }
buffsByUnit.raid1 = { { "Battle Shout", "iconBS", 1, nil, 0 } }
local dl, dtotal = RG.ListDebuffs("raid1", 1)
eq(#dl, 1, "ListDebuffs honours the limit"); eq(dtotal, 2, "...but reports the real total")
eq(dl[1].name, "Sunder Armor", "debuff name"); eq(dl[1].timeLeft, 12, "time left = expiration - now")
local bl = RG.ListBuffs("raid1", 5)
eq(#bl, 1, "ListBuffs"); eq(bl[1].name, "Battle Shout", "buff name"); eq(bl[1].timeLeft, nil, "no expiration = no timer")
eq(#(RG.ListDebuffs(nil, 5)), 0, "ListDebuffs nil unit")

-- ---- missing-buff indicator (personal: only what the viewer can provide) ------
reset()
missingFor.raid1 = { "Battle Shout", "Arcane Intellect" }
eq(table.concat(RG.MissingBuffsForViewer("raid1"), ","), "Battle Shout", "only the buff the viewer's own class (WARRIOR) can provide")
missingFor.raid1 = { "Arcane Intellect" }
eq(#RG.MissingBuffsForViewer("raid1"), 0, "nothing the viewer can provide -> empty")
local savedPanels = AIP.Panels; AIP.Panels = nil
eq(#RG.MissingBuffsForViewer("raid1"), 0, "gracefully empty when the Raid Management panel is absent")
AIP.Panels = savedPanels

-- ---- quick-cast -----------------------------------------------------------------
reset()
eq((RG.AddQuickCast("Flash of Light")), true, "add ok"); eq(RG.GetQuickCast()[1], "Flash of Light", "stored")
eq((RG.AddQuickCast("flash of light")), false, "duplicate rejected (case-insensitive)")
eq((RG.AddQuickCast("Renew")), true, "second slot"); eq((RG.AddQuickCast("Regrowth")), false, "cap at MAX_QUICKCAST")
eq((RG.SetQuickCast(2, "Regrowth")), true, "replace slot 2"); eq(RG.GetQuickCast()[2], "Regrowth", "replaced")
eq((RG.SetQuickCast(2, "Flash of Light")), false, "SetQuickCast rejects a duplicate of another slot")
eq((RG.RemoveQuickCast(1)), true, "remove ok"); eq(RG.GetQuickCast()[1], "Regrowth", "later slots shift up"); eq(#RG.GetQuickCast(), 1, "one fewer")
local qcCopy = RG.GetQuickCast(); qcCopy[1] = "Hacked"
eq(RG.GetQuickCast()[1], "Regrowth", "GetQuickCast returns a copy")
eq(RG.BuildQuickCastMacro("Bob", "Flash of Light"), "/cast [target=Bob] Flash of Light", "macro built via Tank Cast")
local savedTC = AIP.TankCast; AIP.TankCast = nil
eq((RG.AddQuickCast("Renew")), false, "AddQuickCast requires Tank Cast")
eq(RG.BuildQuickCastMacro("Bob", "X"), nil, "BuildQuickCastMacro requires Tank Cast")
AIP.TankCast = savedTC

-- ---- extended menus -------------------------------------------------------------
reset()
raid = { { name = "Me", rank = 2, group = 1, class = "Paladin" }, { name = "Grunt", rank = 0, group = 2, class = "Warrior" } }
local snapMember = RG.Snapshot()
local mm = RG.MemberMenu(snapMember, snapMember.members[2], false)
eq(findId(mm, "add_friend") ~= nil, true, "menu: Add Friend present for others")
eq(findId(mm, "focus"), nil, "menu: no Set Focus (FocusUnit is protected, can't run from a menu)")
eq(findId(mm, "note_private") ~= nil, true, "menu: private note present")
eq(findId(mm, "note_assignment"), nil, "menu: assignment note requires manage")
eq(findId(mm, "raid_icon_1"), nil, "menu: raid icons require manage")
isOfficerFlag = true
local snapMgr = RG.Snapshot()
local mmMgr = RG.MemberMenu(snapMgr, snapMgr.members[2], false)
eq(findId(mmMgr, "note_assignment") ~= nil, true, "manager menu: assignment note present")
eq(findId(mmMgr, "raid_icon_8").text, "Set Raid Icon: Skull", "manager menu: raid icon rows are labelled")
eq(findId(mmMgr, "raid_icon_clear") ~= nil, true, "manager menu: clear raid icon present")
eq(findId(mmMgr, "move_2").enabled, false, "move to the member's own group is still disabled")
RG.SetGroupLocked(true)
local mmLocked = RG.MemberMenu(snapMgr, snapMgr.members[2], false)
eq(findId(mmLocked, "move_3").enabled, false, "move rows disabled while group positions are locked")
RG.SetGroupLocked(false)

local wm = RG.WindowMenu(snapMember, false)
eq(findId(wm, "group_lock"), nil, "window menu: group-lock control requires manage")
eq(findId(wm, "quickcast_config"), nil, "window menu: quick-cast config option removed")
local wmMgr = RG.WindowMenu(snapMgr, false)
eq(findId(wmMgr, "group_lock").text, "Lock Group Positions", "window menu: group-lock label")
RG.SetGroupLocked(true)
eq(findId(RG.WindowMenu(snapMgr, false), "group_lock").text, "Unlock Group Positions", "window menu: group-lock label flips")
RG.SetGroupLocked(false)

-- ---- fixes from the fresh review --------------------------------------------

-- note sanitising also strips backslash/pipe (wire safety + tooltip-markup injection)
reset()
RG.SetNote("Bob", "back\\slash |cffff0000red|r end")
local hardened = RG.GetNote("Bob")
eq(hardened:find("\\", 1, true), nil, "note strips backslash")
eq(hardened:find("|", 1, true), nil, "note strips pipe (blocks |c/|H/|T markup injection)")

-- a rate-limited broadcast (DataBus returns false) is retried, not silently dropped
reset(); isOfficerFlag = true
raid = { { name = "A", group = 1, class = "Warrior" } }
local snapRetry = RG.Snapshot()
local realBroadcast = AIP.DataBus.Broadcast
local failOnce = true
AIP.DataBus.Broadcast = function(event)
    if failOnce then failOnce = false; return false end
    return realBroadcast(event)
end
RG.SetAssignment(snapRetry, "A", "Retry me")
eq(#dbBroadcasts, 1, "a rate-limited broadcast is retried until it is actually recorded")
AIP.DataBus.Broadcast = realBroadcast

-- an incoming assignment is only accepted for someone in MY current raid, and its
-- author is the trusted event.sender, not the (spoofable) payload field
reset(); isOfficerFlag = true
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" } }
local snapIn = RG.Snapshot()
subscribedCb({ type = "RGNOTE", sender = "Zed", data = { player = "B", note = "Kite", author = "Zed" } })
local bt, ba = RG.GetAssignment("B")
eq(bt, "Kite", "accepted: B is in my raid"); eq(ba, "Zed", "author matches the real sender")
subscribedCb({ type = "RGNOTE", sender = "Zed", data = { player = "NotInMyRaid", note = "Ignored", author = "Zed" } })
eq(RG.GetAssignment("NotInMyRaid"), "", "rejected: the named player is not in my current raid")
subscribedCb({ type = "RGNOTE", sender = "RealSender", data = { player = "B", note = "Spoofed", author = "FakeAuthor" } })
local _, spoofCheck = RG.GetAssignment("B")
eq(spoofCheck, "RealSender", "author always comes from event.sender, never the untrusted payload field")

-- the missing-buff provider scan is throttled (was previously never invoked at
-- all, so the indicator could never light up - now it runs, but not every call)
reset()
missingFor.raid1 = { "Battle Shout" }
now = now + 1000   -- clear of any stale throttle state left by earlier test blocks
RG.MissingBuffsForViewer("raid1")
eq(scanCalls, 1, "first call (after a time jump) scans buff providers")
RG.MissingBuffsForViewer("raid1")
eq(scanCalls, 1, "a second call within the throttle window does not rescan")
now = now + 6
RG.MissingBuffsForViewer("raid1")
eq(scanCalls, 2, "rescans once the throttle window has passed")

-- ---- per-character notes/quick-cast (fixes cross-character bleed) -----------
reset()
RG.SetNote("Bob", "kite"); RG.AddQuickCast("Flash of Light")
currentCharKey = "TestRealm-Alt"
eq(RG.GetNote("Bob"), "", "a different character starts with no private notes")
eq(#RG.GetQuickCast(), 0, "...and no quick-cast slots carried over (this is the bug being fixed)")
RG.SetNote("Bob", "stack")
currentCharKey = "TestRealm-Me"
eq(RG.GetNote("Bob"), "kite", "switching back: the first character's own note is untouched")
eq(RG.GetQuickCast()[1], "Flash of Light", "...and its quick-cast slot")

-- one-time migration of the OLD account-wide notes/quickCast into whichever
-- character loads first; window position/lock (the account-wide half) untouched
reset()
AIP.db.raidGroups = { locked = true, notes = { bob = "old shared note" }, quickCast = { "Renew" } }
eq(RG.GetNote("Bob"), "old shared note", "migration: the old shared note is inherited once")
eq(RG.GetQuickCast()[1], "Renew", "migration: the old shared quick-cast slot too")
eq(AIP.db.raidGroups.notes, nil, "migration: claimed and cleared from the account-wide table")
eq(AIP.db.raidGroups.quickCast, nil, "migration: claimed and cleared from the account-wide table")
eq(AIP.db.raidGroups.locked, true, "migration: window-state keys are untouched (still account-wide)")

-- GetQuickCast() clamps to RG.MAX_QUICKCAST even if the saved list somehow
-- holds more (hand-edited/corrupt SavedVariables) - the UI anchors a name
-- field to cell.qc[#GetQuickCast()], and an out-of-range index there would be
-- a nil relativeTo.
reset()
AIP.db.raidGroupsByChar = { [currentCharKey] = { quickCast = { "A", "B", "C" } } }
eq(#RG.GetQuickCast(), RG.MAX_QUICKCAST, "GetQuickCast clamps to MAX_QUICKCAST even with a corrupt over-long saved list")

reset()
eq(RG.JustFormedGroup(), false, "solo: not just-formed")
raid = { { name = "Aa", class = "Warrior" } }
eq(RG.JustFormedGroup(), true, "solo -> raid: fires once")
eq(RG.JustFormedGroup(), false, "...but not again while still grouped")
raid = {}
eq(RG.JustFormedGroup(), false, "leaving the group is not a formation")
party = { [1] = { name = "Cc", class = "Priest" } }
eq(RG.JustFormedGroup(), true, "solo -> party: fires once too")

-- The very first evaluation this session (fresh /reload or login) must only
-- SEED the latch, never fire it, even if already grouped at that point -
-- otherwise every /reload mid-raid would re-open a window the player had
-- deliberately closed (RG.wasGrouped starts nil, not false, to distinguish
-- "never checked yet" from "checked and was solo").
reset()
raid = { { name = "Aa", class = "Warrior" } }
eq(RG.JustFormedGroup(), false, "first-ever check while ALREADY grouped (e.g. reload mid-raid) does not fire")
eq(RG.JustFormedGroup(), false, "...nor does the next check while nothing changed")
raid = {}
eq(RG.JustFormedGroup(), false, "leaving afterward is still not a formation")
party = { [1] = { name = "Cc", class = "Priest" } }
eq(RG.JustFormedGroup(), true, "a REAL solo -> party transition after that still fires")

-- ---- Ready check (RG-020: per-member ready-check status, an independent
-- channel from the persistent dead/offline/AFK/DND state) --------------------
-- RG.OnReadyCheckStart/Confirm/Finished are the directly-testable functions
-- the real client's READY_CHECK/READY_CHECK_CONFIRM/READY_CHECK_FINISHED
-- event handlers call (see the E.Register block below) - mirrors the
-- established RG.OnAssignmentEvent pattern, since this test harness has no
-- fake WoW-event dispatcher to fire through.
reset()
raid = {
    { name = "Aa", class = "Warrior" }, { name = "Bb", class = "Priest" }, { name = "Cc", class = "Mage" },
}
eq(RG.GetReadyStatus("Aa"), nil, "ready check: no status before any check has ever run")

RG.OnReadyCheckStart()
eq(RG.readyCheck.active, true, "ready check: active once started")
eq(RG.GetReadyStatus("Aa"), "waiting", "ready check: everyone starts 'waiting', case-insensitively looked up")
eq(RG.GetReadyStatus("aA"), "waiting", "ready check: name lookup is case-insensitive")

RG.OnReadyCheckConfirm("raid1", true)
eq(RG.GetReadyStatus("Aa"), "ready", "ready check: a true confirm marks that unit ready")
RG.OnReadyCheckConfirm("raid2", false)
eq(RG.GetReadyStatus("Bb"), "notready", "ready check: a false confirm marks that unit not ready")
eq(RG.GetReadyStatus("Cc"), "waiting", "ready check: a non-responder stays 'waiting' until finished")

RG.OnReadyCheckFinished()
eq(RG.readyCheck.active, false, "ready check: no longer active once finished")
eq(RG.GetReadyStatus("Aa"), "ready", "ready check: a real response survives finish")
eq(RG.GetReadyStatus("Cc"), "notready", "ready check: finish demotes any lingering 'waiting' to 'notready' (matches Blizzard's own frames)")

-- Results linger briefly after finish (matches Blizzard's own raid frames -
-- long enough to glance at who didn't respond), but NOT forever: reported
-- live (2026-09-27) as a real bug - a real ready check had finished, nothing
-- since then ever cleared it, and the "Not Ready" icon was still showing on
-- a player's cell an entire play session later, permanently, with no new
-- check in sight to reset it. Fixed with a polled time-based expiry (checked
-- on every GetReadyStatus call, i.e. every refreshValues tick already) -
-- deliberately NOT a DelayedCall timer (this addon's own DelayedCall test
-- stub fires synchronously, so a timer-based clear would be unverifiable
-- here; GetTime() is stubbed as a plain mutable value instead, so this is
-- fully testable without that problem).
eq(RG.GetReadyStatus("Aa"), "ready", "ready check: results linger right after finish, not cleared immediately")
now = now + RG.READY_CHECK_LINGER + 1
eq(RG.GetReadyStatus("Aa"), nil, "ready check: but NOT forever - expires READY_CHECK_LINGER seconds after finish")
eq(RG.readyCheck.status["aa"], "ready", "ready check: the underlying data is untouched by expiry (still queryable via readyCheck.status directly) - only GetReadyStatus's public read is gated")

RG.OnReadyCheckStart()
eq(RG.GetReadyStatus("Aa"), "waiting", "ready check: a fresh start wipes, re-seeds everyone, and resets the expiry")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)

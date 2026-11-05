-- Headless tests for AutoInvitePlus/data/ChatScanner.lua (listing store, prune, matching, DataBus intake).
-- Run from the repo root:  luajit tools/tests/chatscanner_spec.lua

local pass, fail = 0, 0
local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function eq(a, b, name)
    if a == b then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end
local function noerr(name, fn, ...)
    local good, err = pcall(fn, ...)
    ok(good, name .. " must not error: " .. tostring(not good and err or ""))
    return good
end

local function noop() end
CreateFrame = function() return setmetatable({}, { __index = function() return noop end }) end
local now = 1000000
time = function() return now end
UnitName = function() return "Me" end

local handlers = {}
local notifies = 0
AutoInvitePlus = {
    Print = noop, Debug = noop,
    UpdateCentralGUI = function() notifies = notifies + 1 end,
    db = { cacheDuration = 10 },
    Utils = { DelayedCall = noop },
    DataBus = { Config = { chatPrefix = "!A:" }, Subscribe = function(ev, cb) handlers[ev] = cb end },
    CentralGUI = {},
}
local AIP = AutoInvitePlus
assert(loadfile("AutoInvitePlus/core/Parsers.lua"))()
assert(loadfile("AutoInvitePlus/data/ChatScanner.lua"))()
local CS = AIP.ChatScanner
CS.InitDataBus()
ok(handlers.LFM ~= nil and handlers.LFG ~= nil, "DataBus handlers registered")

local function countKeys(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function reset() CS.Groups = {}; CS.Players = {}; CS.Excluded = {}; CS.Requested = {}; AIP.CentralGUI = {} end

-- ---- AddGroup / AddPlayer basics -------------------------------------------------
reset()
noerr("AddGroup nil", CS.AddGroup, nil)
noerr("AddGroup no author", CS.AddGroup, {})
noerr("AddPlayer nil", CS.AddPlayer, nil)
noerr("AddPlayer no author", CS.AddPlayer, {})
eq(countKeys(CS.Groups), 0, "no group created from invalid input")

noerr("AddGroup nil time (new)", CS.AddGroup, { author = "Lead", raid = "ICC25N", message = "lfm icc" })
ok(CS.Groups.Lead and type(CS.Groups.Lead.time) == "number", "new group gets numeric time")
eq(CS.Groups.Lead.time, now, "new group time defaults to now")
CS.Groups.Lead.time = nil   -- simulate a legacy/corrupt entry lacking a time
noerr("AddGroup nil time (existing, entry has no time)", CS.AddGroup, { author = "Lead", message = "lfm icc again" })
eq(CS.Groups.Lead.time, now, "existing group with nil time repaired")
noerr("Prune after repair", CS.Prune)

noerr("AddPlayer nil time (new)", CS.AddPlayer, { author = "Pla", isLFG = true, role = "TANK" })
eq(CS.Players.Pla.time, now, "new player time defaults to now")
CS.Players.Pla.time = nil
noerr("AddPlayer nil time (existing)", CS.AddPlayer, { author = "Pla", isLFG = true })
eq(CS.Players.Pla.time, now, "existing player nil time repaired")
noerr("PrunePlayers", CS.Prune)

-- self is skipped for players
noerr("AddPlayer self", CS.AddPlayer, { author = "Me" })
eq(CS.Players.Me, nil, "own player listing not stored")

-- raids merge without dupes
CS.AddPlayer({ author = "Pla", raids = { "ICC25N", "VOA10" }, time = now })
CS.AddPlayer({ author = "Pla", raids = { "ICC25N" }, time = now })
eq(#CS.Players.Pla.raids, 2, "raids merged without duplicates")

-- dps -> mdps/rdps conversion
reset()
CS.AddGroup({ author = "D", dps = { current = 3, needed = 7 }, time = now })
eq(CS.Groups.D.mdps.needed + CS.Groups.D.rdps.needed, 7, "dps split preserves needed total")

-- ---- prune ----------------------------------------------------------------------------
reset()
CS.AddGroup({ author = "Old", time = now - 10, raid = "ICC25N" })
CS.AddGroup({ author = "New", time = now - 10, raid = "ICC25N" })
CS.MarkExcluded("Old")
CS.Groups.Old.time = now - 700      -- > 10 min
CS.PruneGroups()
eq(CS.Groups.Old, nil, "expired group pruned")
ok(CS.Groups.New ~= nil, "fresh group kept")
ok(not CS.IsExcluded("Old"), "pruned listing clears excluded state")
AIP.db.cacheDuration = 1
CS.AddPlayer({ author = "P1", time = now - 90 })
CS.AddPlayer({ author = "P2", time = now - 10 })
CS.PrunePlayers()
eq(CS.Players.P1, nil, "player older than cacheDuration pruned")
ok(CS.Players.P2 ~= nil, "recent player kept")
AIP.db.cacheDuration = 10
eq(CS.GetExpiry(), 600, "expiry from cacheDuration minutes")
AIP.db.cacheDuration = nil
eq(CS.GetExpiry(), CS.Config.expiryTime, "expiry fallback")
AIP.db.cacheDuration = 10
-- cap
reset()
CS.Config.maxGroups = 5
for i = 1, 12 do CS.AddGroup({ author = "G" .. i, time = now - i }) end
ok(countKeys(CS.Groups) <= 5, "group cap enforced (" .. countKeys(CS.Groups) .. ")")
ok(CS.Groups.G1 ~= nil, "newest group survives cap")
CS.Config.maxGroups = 100

-- ---- MatchesMyLFM -------------------------------------------------------------------------
reset()
AIP.CentralGUI = {}
eq(CS.MatchesMyLFM({ raid = "ICC25N" }), false, "no own LFM -> false")
AIP.CentralGUI = { MyGroup = { raid = "ICC25N", tanks = { needed = 2, current = 0 }, healers = { needed = 0, current = 0 } } }
noerr("MatchesMyLFM nil raid", CS.MatchesMyLFM, { role = "TANK" })
noerr("MatchesMyLFM nil arg", CS.MatchesMyLFM, nil)
eq(CS.MatchesMyLFM(nil), false, "MatchesMyLFM nil -> false")
eq(CS.MatchesMyLFM({ role = "TANK" }), false, "nil raid -> false")
eq(CS.MatchesMyLFM({ raids = {}, role = "TANK" }), false, "empty raids + nil raid -> false")
noerr("MatchesMyLFM numeric raid", CS.MatchesMyLFM, { raid = 5 })
eq(CS.MatchesMyLFM({ raid = "ICC10N", role = "TANK" }), false, "different raid -> false")
eq(CS.MatchesMyLFM({ raid = "icc25n", role = "TANK" }), true, "same raid, case-insensitive, needed role")
eq(CS.MatchesMyLFM({ raids = { "ICC25N" }, role = "TANK" }), true, "raids[1] used")
eq(CS.MatchesMyLFM({ raid = "ICC25N", role = "HEALER" }), false, "role not needed")
AIP.CentralGUI.MyGroup.myLFMGs = nil
AIP.CentralGUI.MyGroup.gsMin = 5800
eq(CS.MatchesMyLFM({ raid = "ICC25N", role = "TANK", gs = 5000 }), false, "gs too low")
eq(CS.MatchesMyLFM({ raid = "ICC25N", role = "TANK", gs = 6000 }), true, "gs ok")
eq(CS.MatchesMyLFM({ raid = "ICC25N", role = "TANK" }), false, "gs required but unknown")

-- ---- OnDataBusLFM ---------------------------------------------------------------------------
reset()
local LFM = handlers.LFM
noerr("LFM nil event", LFM, nil)
noerr("LFM no sender", LFM, { data = {} })
noerr("LFM no data", LFM, { sender = "X" })
eq(countKeys(CS.Groups), 0, "invalid events create nothing")

LFM({ sender = "Peer", timestamp = now, version = "1.0", data = { raid = "ICC25H", gsMin = 5800, note = "hi", dm = "D" } })
eq(CS.Groups.Peer and CS.Groups.Peer.raid, "ICC25H", "valid raid accepted")
eq(CS.Groups.Peer.isDataBus, true, "marked isDataBus")
eq(CS.Groups.Peer.hasExplicitComposition, true, "explicit composition")

for i, bad in ipairs({ 5, true, {}, { "ICC25H" }, 1.5 }) do
    local name = "Hostile" .. i
    noerr("LFM non-string raid #" .. i, LFM, { sender = name, timestamp = now, data = { raid = bad, raidCategory = bad } })
    eq(CS.Groups[name] and CS.Groups[name].raid, nil, "non-string raid #" .. i .. " rejected (nil)")
    eq(CS.Groups[name] and CS.Groups[name].raidCategory, nil, "non-string raidCategory #" .. i .. " rejected (nil)")
end
-- A hostile listing must not match anything
AIP.CentralGUI = { MyGroup = { raid = "ICC25N", tanks = { needed = 1, current = 0 } } }
eq(CS.MatchesMyLFM(CS.Groups.Hostile1), false, "listing with rejected raid never matches")

CS.Config.useDataBus = false
LFM({ sender = "Off", timestamp = now, data = { raid = "ICC25N" } })
eq(CS.Groups.Off, nil, "useDataBus=false ignores events")
CS.Config.useDataBus = true

-- ---- OnChatMessage ------------------------------------------------------------------------------
reset()
CS.OnChatMessage("!A:1.0;LFM;1;d0~", "Spammer", "x")
eq(countKeys(CS.Groups) + countKeys(CS.Players), 0, "serialized DataBus payload never ingested from chat")
CS.OnChatMessage("LFM ICC25 HC need tank 5800 gs", "Lead2", "LookingForGroup")
eq(CS.Groups.Lead2 and CS.Groups.Lead2.raid, "ICC25H", "chat LFM -> group")
CS.OnChatMessage("LFG ICC25 prot warr 6k gs", "Tanky", "LookingForGroup")
eq(CS.Players.Tanky and CS.Players.Tanky.gs, 6000, "chat LFG -> player")
eq(CS.Groups.Tanky, nil, "LFG not leaked into group tree")
noerr("OnChatMessage nil msg", CS.OnChatMessage, nil, "x", "y")
noerr("OnChatMessage nil author", CS.OnChatMessage, "lfm icc", nil, "y")

-- ---- OnDataBusLFG hostility (pcall'd by DataBus.Dispatch, but should still not corrupt state) ---------
reset()
local LFG = handlers.LFG
LFG({ sender = "Pl", timestamp = now, version = "1.0", data = { raids = { "ICC25N" }, role = "TANK", gs = 5800 } })
eq(CS.Players.Pl and CS.Players.Pl.gs, 5800, "valid LFG stored")
local lfgBad = { "str", 5, true }
for i, bad in ipairs(lfgBad) do
    local nm = "BadLFG" .. i
    noerr("LFG non-table raids #" .. i, LFG, { sender = nm, timestamp = now, data = { raids = bad } })
    ok(CS.Players[nm] == nil or type(CS.Players[nm].raids) == "table", "LFG non-table raids #" .. i .. " leaves raids a table")
end
for _, nm in ipairs({ "BadLFG1", "BadLFG2", "BadLFG3" }) do
    local p = CS.Players[nm]
    ok(p == nil or type(p.raids) == "table", nm .. " raids table or entry absent")
end

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)

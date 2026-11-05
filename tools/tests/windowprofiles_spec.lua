-- Headless tests for AutoInvitePlus/modules/WindowProfiles.lua.
-- Run from the repo root:  luajit tools/tests/windowprofiles_spec.lua

local charKey = "R-Me"
local printed = {}
AutoInvitePlus = {
    Print = function(m) printed[#printed + 1] = m end,
    Utils = { CharKey = function() return charKey end },
    Defaults = {
        tankCastEnabled = true, raidGroupsEnabled = true, autoShowOnGroup = true,
        restoreWindowsOnLogin = true, floatingBarEnabled = false, timerBarsEnabled = true,
        minimapBubbles = true, assignmentToasts = true,
        rollDuration = 10, responseInvite = "hello", enabled = true,
        guiPosition = "x", dbVersion = 5, debugLog = "x", windowsTipShown = false,
        queue = {}, blacklist = {},
    },
}
local AIP = AutoInvitePlus
AIP.db = { rollDuration = 15, responseInvite = "hi; there=%", floatingBarEnabled = false, queue = { "a" } }
InCombatLockdown = function() return false end

local barUpdates = 0
AIP.RaidTools = { UpdateBar = function() barUpdates = barUpdates + 1 end }
local tkShown, rgShown = true, true
AIP.TankCast = { IsWindowShown = function() return tkShown end, HideWindow = function() tkShown = false end }
AIP.RaidGroups = { IsWindowShown = function() return rgShown end, HideWindow = function() rgShown = false end }

dofile("AutoInvitePlus/modules/WindowProfiles.lua")
local WP = AIP.WindowProfiles

local fails = 0
local function check(name, cond) if not cond then fails = fails + 1; print("FAIL: " .. name) end end

-- Get / Set precedence
check("keys", #WP.KEYS == 8)
check("default on", WP.Get("tankCastEnabled") == true)
check("default bar off", WP.Get("floatingBarEnabled") == false)
WP.Set("tankCastEnabled", false)
check("account off", WP.Get("tankCastEnabled") == false and not WP.HasOverride("tankCastEnabled"))
WP.Set("tankCastEnabled", true, true)
check("override wins", WP.Get("tankCastEnabled") == true and WP.HasOverride("tankCastEnabled"))
charKey = "R-Alt"
check("other char uses account", WP.Get("tankCastEnabled") == false)
charKey = "R-Me"
WP.Set("tankCastEnabled", nil, true)
check("override removed", WP.Get("tankCastEnabled") == false)
WP.Set("timerBarsEnabled", false, true)
WP.ClearOverrides()
check("clear overrides", WP.Get("timerBarsEnabled") == true)
check("bad key rejected", WP.Set("bogus", true) == false)

-- Profiles
tkShown, rgShown = true, true
check("apply Minimal", WP.ApplyProfile("minimal") == "Minimal")
check("minimal off", not WP.Get("tankCastEnabled") and not WP.Get("timerBarsEnabled"))
check("windows hidden", tkShown == false and rgShown == false and barUpdates > 0)
check("RaidLeader", WP.ApplyProfile("RaidLeader") and WP.Get("tankCastEnabled")
    and not WP.Get("floatingBarEnabled") and not WP.Get("minimapBubbles") and WP.Get("assignmentToasts"))
WP.ApplyProfile("Full"); check("Full", WP.Get("floatingBarEnabled") and WP.Get("minimapBubbles"))
WP.ApplyProfile("Multibox"); check("Multibox", not WP.Get("autoShowOnGroup"))
check("unknown profile", WP.ApplyProfile("nope") == nil)
WP.ApplyProfile("Full")
WP.ApplyProfile("Full", true)
WP.ApplyProfile("Minimal", true)
check("per-char profile", not WP.Get("tankCastEnabled") and AIP.db.tankCastEnabled == true)
charKey = "R-Alt"; check("per-char isolated", WP.Get("tankCastEnabled")); charKey = "R-Me"
WP.ApplyProfile("Full")
check("account profile clears overrides", WP.Get("tankCastEnabled"))

-- Export / Import
local s = WP.Export()
check("prefix", s:sub(1, 6) == "AIPS1:")
check("single line", not s:find("[\r\n]"))
check("no volatile", not s:find("guiPosition") and not s:find("dbVersion") and not s:find("queue")
    and not s:find("debugLog") and not s:find("windowsTipShown"))
check("has setting", s:find("rollDuration=n15", 1, true) ~= nil)
local savedDb = AIP.db
AIP.db = { rollDuration = 3, responseInvite = "zzz" }
local n, err = WP.Import(s)
check("import count", n and n >= 10)
check("roundtrip number", AIP.db.rollDuration == 15)
check("roundtrip string", AIP.db.responseInvite == "hi; there=%")
check("roundtrip bool", AIP.db.minimapBubbles == true)
check("no volatile imported", AIP.db.guiPosition == nil and AIP.db.queue == nil)

-- Hostile / malformed
local function rej(name, str)
    AIP.db = { rollDuration = 3 }
    local r = WP.Import(str)
    check("reject " .. name, r == nil and AIP.db.rollDuration == 3)
end
rej("nil", nil)
rej("number", 5)
rej("empty", "")
rej("no prefix", "rollDuration=n99")
rej("wrong prefix", "AIPS2:rollDuration=n99")
rej("too long", "AIPS1:" .. string.rep("a", 40000))
rej("lua code", "AIPS1:return os.execute('x')")
rej("only unknown", "AIPS1:evil=b1;queue=s1;other=n5")
rej("type mismatch", "AIPS1:rollDuration=sabc;enabled=n1")
rej("volatile key", "AIPS1:guiPosition=sx;dbVersion=n9;windowsTipShown=b1")
rej("nan", "AIPS1:rollDuration=nnan")
rej("inf", "AIPS1:rollDuration=ninf")
rej("bad bool", "AIPS1:enabled=b7")
AIP.db = { rollDuration = 3 }
local r = WP.Import("AIPS1:rollDuration=n42;evil=b1;__index=b1;enabled=nzzz")
check("partial accept", r == 1 and AIP.db.rollDuration == 42 and AIP.db.evil == nil and AIP.db.enabled == nil)
AIP.db = { rollDuration = 3 }
check("string encode safe", WP.Import("AIPS1:responseInvite=sa%3Bb%3Dc") == 1 and AIP.db.responseInvite == "a;b=c")

-- ResetPositions
AIP.db = { guiPosition = {1}, rotationPos = {1}, timerBarPos = {1}, lfgWatchPos = {1}, floatingBarPos = {1} }
local pts = {}
UIParent = {}
_G.AIPCentralGUI = { SetPoint = function(_, ...) pts.gui = { ... } end, ClearAllPoints = function() end }
local nn = WP.ResetPositions()
check("reset db keys", AIP.db.guiPosition == nil and AIP.db.rotationPos == nil and AIP.db.timerBarPos == nil)
check("reset live", nn == 1 and pts.gui[1] == "CENTER")

if fails == 0 then print("windowprofiles_spec: all passed") else print(fails .. " FAILED"); os.exit(1) end

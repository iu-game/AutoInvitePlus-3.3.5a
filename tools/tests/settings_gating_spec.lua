-- Headless tests for the "Windows & Bars" setting gates. The real WindowProfiles.lua is loaded;
-- the gated functions/conditions are extracted verbatim from their source files (so a regression
-- in the real code fails this spec) and run against stubs:
--   tankCastEnabled / raidGroupsEnabled / restoreWindowsOnLogin / autoShowOnGroup (TankCastWindow, RaidGroupsWindow)
--   minimapBubbles (CentralGUI GUI.ShowMinimapBubble), assignmentToasts (RG.ShowBubble),
--   timerBarsEnabled (RaidTools RT.StartTimer)
-- Run from the repo root:  luajit tools/tests/settings_gating_spec.lua

local pass, fail = 0, 0
local function eq(a, b, name)
    if a == b then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local function readFile(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a"); f:close()
    return (s:gsub("\r\n", "\n"))
end

-- Source of a top-level function: from the header line to the first line that is exactly "end".
-- A leading "local " is stripped so it becomes a global in the sandbox env (stands in for an upvalue).
local function extractFn(path, headerPattern)
    local src = readFile(path)
    local out, on = {}, false
    for line in (src .. "\n"):gmatch("(.-)\n") do
        if not on and line:find(headerPattern) then on = true end
        if on then
            out[#out + 1] = line
            if line == "end" then break end
        end
    end
    assert(#out > 0 and out[#out] == "end", "could not extract " .. headerPattern .. " from " .. path)
    return (table.concat(out, "\n"):gsub("^local function", "function"))
end

-- The `if <cond> then` condition on the line containing `marker` (a plain substring).
local function extractCond(path, marker)
    local src = readFile(path)
    for line in (src .. "\n"):gmatch("(.-)\n") do
        if line:find(marker, 1, true) then
            local cond = line:match("^%s*if (.-) then")
            if cond then return cond end
        end
    end
    error("no condition line containing " .. marker .. " in " .. path)
end

local function newEnv(db)
    local env = setmetatable({}, { __index = _G })
    env.AutoInvitePlus = { db = db, Utils = { CharKey = function() return "Realm-Me" end } }
    env.AIP = env.AutoInvitePlus
    env.printed = {}
    env.AIP.Print = function(m) env.printed[#env.printed + 1] = m end
    return env
end

local function load(env, chunkSrc, name)
    local fn = assert(loadstring(chunkSrc, name))
    setfenv(fn, env)
    return fn()
end

local function loadWP(env)
    local fn = assert(loadfile("AutoInvitePlus/modules/WindowProfiles.lua"))
    setfenv(fn, env)
    fn()
    return env.AIP.WindowProfiles
end

local KEYS = { "tankCastEnabled", "raidGroupsEnabled", "restoreWindowsOnLogin", "autoShowOnGroup",
               "minimapBubbles", "assignmentToasts", "timerBarsEnabled" }

-- ---- WindowProfiles.Get semantics ---------------------------------------------------------
do
    local env = newEnv({})
    local WP = loadWP(env)
    for _, k in ipairs(KEYS) do eq(WP.Get(k), true, "default ON: " .. k) end
    for _, k in ipairs(KEYS) do
        env.AIP.db[k] = false
        eq(WP.Get(k), false, "db false -> off: " .. k)
        env.AIP.db.windowsByChar = { ["Realm-Me"] = { [k] = true } }
        eq(WP.Get(k), true, "per-character override beats account-wide: " .. k)
        env.AIP.db.windowsByChar = nil
        env.AIP.db[k] = nil
    end
    eq(newEnv(nil) and true, true, "env builds with nil db")
    local e2 = newEnv(nil); local WP2 = loadWP(e2)
    eq(WP2.Get("tankCastEnabled"), true, "nil db -> default ON, no error")
end

-- ---- RT.StartTimer <- timerBarsEnabled ----------------------------------------------------------
local RT_PATH = "AutoInvitePlus/modules/RaidTools.lua"
local function timerHarness(db, withWP)
    local env = newEnv(db)
    if withWP then loadWP(env) end
    env.GetSpellInfo = function() return "n", "r", "icon" end
    env.GetTime = function() return 100 end
    env.RT = { timers = {}, CreateTimerAnchor = function() return { Show = function() env.anchorShown = true end } end }
    load(env, extractFn(RT_PATH, "^function RT%.StartTimer%("), "StartTimer")
    -- the extractor produced "function RT.StartTimer", which assigns into env.RT
    env.StartTimer = env.RT.StartTimer
    return env
end
for _, withWP in ipairs({ true, false }) do
    local tag = withWP and " (WindowProfiles)" or " (db fallback)"
    local e = timerHarness({ timerBarsEnabled = true }, withWP)
    e.StartTimer("k", "Pull", 10)
    eq(e.RT.timers.k and e.RT.timers.k.duration, 10, "timers ON starts bar" .. tag)
    eq(e.anchorShown, true, "timers ON shows anchor" .. tag)
    e = timerHarness({ timerBarsEnabled = false }, withWP)
    e.StartTimer("k", "Pull", 10)
    eq(e.RT.timers.k, nil, "timers OFF suppresses bar" .. tag)
    eq(e.anchorShown, nil, "timers OFF never creates/shows anchor" .. tag)
    e = timerHarness({}, withWP)
    e.StartTimer("k", "Pull", 10)
    ok = e.RT.timers.k ~= nil
    eq(ok, true, "timers unset defaults ON" .. tag)
    e.StartTimer("z", "Pull", 0); e.StartTimer("n", "Pull", nil); e.StartTimer("neg", "Pull", -5)
    eq(e.RT.timers.z or e.RT.timers.n or e.RT.timers.neg, nil, "bad durations ignored" .. tag)
end
do   -- per-character override wins over account-wide
    local e = timerHarness({ timerBarsEnabled = true, windowsByChar = { ["Realm-Me"] = { timerBarsEnabled = false } } }, true)
    e.StartTimer("k", "Pull", 10)
    eq(e.RT.timers.k, nil, "per-character timer OFF override honored")
end

-- ---- GUI.ShowMinimapBubble <- minimapBubbles ---------------------------------------------------------
local GUI_PATH = "AutoInvitePlus/ui/CentralGUI.lua"
local function bubbleHarness(db, withWP)
    local env = newEnv(db)
    if withWP then loadWP(env) end
    local made = 0
    local frameMT
    frameMT = { __index = function(t, k)
        return function() return setmetatable({}, frameMT) end
    end }
    env.CreateFrame = function() made = made + 1; return setmetatable({}, frameMT) end
    env.UIParent, env.Minimap = {}, {}
    env.GetTime = function() return 0 end
    env.GUI = {}
    -- stop at the first statement past the gate: we only need to know whether the gate returned early.
    -- Re-use the real gate lines and the first CreateFrame call by running the real function with generic stubs.
    local src = extractFn(GUI_PATH, "^function GUI%.ShowMinimapBubble%(")
    local good, err = pcall(load, env, src, "ShowMinimapBubble")
    assert(good, tostring(err))
    return env, function(text) return pcall(env.GUI.ShowMinimapBubble, text) end, function() return made end
end
for _, withWP in ipairs({ true, false }) do
    local tag = withWP and " (WindowProfiles)" or " (db fallback)"
    local env, call, made = bubbleHarness({ minimapBubbles = false }, withWP)
    local good, err = call("VOA Listed")
    eq(good, true, "bubble OFF no error" .. tag .. " " .. tostring(not good and err or ""))
    eq(made(), 0, "bubble OFF creates no frame" .. tag)
    eq(env.GUI.MinimapBubble, nil, "bubble OFF leaves no bubble" .. tag)
    env, call, made = bubbleHarness({ minimapBubbles = true }, withWP)
    call("VOA Listed")
    ok = made() >= 1 and env.GUI.MinimapBubble ~= nil
    eq(ok, true, "bubble ON creates the frame" .. tag)
    env, call, made = bubbleHarness({}, withWP)
    call("VOA Listed")
    eq(env.GUI.MinimapBubble ~= nil, true, "bubble unset defaults ON" .. tag)
end

-- ---- RG.ShowBubble <- assignmentToasts ---------------------------------------------------------------------
local RGW = "AutoInvitePlus/ui/RaidGroupsWindow.lua"
local function rgHarness(db)
    local env = newEnv(db)
    loadWP(env)
    env.RG = {}
    env.ensured = 0
    env.InCombatLockdown = function() return false end
    env.GetTime = function() return 0 end
    local frameMT
    frameMT = { __index = function() return function() return 0 end end }
    env.ensureBubble = function()
        env.ensured = env.ensured + 1
        env.bubble = setmetatable({ fs = setmetatable({}, frameMT) }, frameMT)
    end
    env.ensureWindow = function() env.ensuredWindow = (env.ensuredWindow or 0) + 1; env.win = setmetatable({ IsShown = function() return false end }, frameMT) end
    env.refresh = function() end
    env.RG.Cfg = function() return {} end
    load(env, extractFn(RGW, "^local function winOn%("), "winOn")
    load(env, extractFn(RGW, "^function RG%.ShowBubble%("), "ShowBubble")
    load(env, extractFn(RGW, "^function RG%.ShowWindow%("), "ShowWindow")
    return env
end
do
    local e = rgHarness({ assignmentToasts = false })
    e.RG.ShowBubble("hi")
    eq(e.ensured, 0, "toasts OFF: bubble never built")
    e = rgHarness({ assignmentToasts = true })
    e.RG.ShowBubble("hi")
    eq(e.ensured, 1, "toasts ON: bubble built")
    e = rgHarness({})
    e.RG.ShowBubble("hi")
    eq(e.ensured, 1, "toasts unset defaults ON")

    e = rgHarness({ raidGroupsEnabled = false })
    e.RG.ShowWindow()
    eq(e.ensuredWindow, nil, "raidGroupsEnabled OFF: ShowWindow does not build window")
    eq(#e.printed, 1, "raidGroupsEnabled OFF: user told why")
    e = rgHarness({ raidGroupsEnabled = true })
    e.RG.ShowWindow()
    eq(e.ensuredWindow, 1, "raidGroupsEnabled ON: ShowWindow builds window")
end

-- ---- Tank Cast ShowWindow <- tankCastEnabled ---------------------------------------------------------------------------
local TKW = "AutoInvitePlus/ui/TankCastWindow.lua"
do
    local function tkHarness(db)
        local env = rgHarness(db)
        env.TK = {}
        env.RG = nil
        env.ensureWindow = function() env.ensuredWindow = (env.ensuredWindow or 0) + 1; env.win = setmetatable({ IsShown = function() return false end }, { __index = function() return function() return 0 end end }) end
        env.TK.Cfg = function() return {} end
        load(env, extractFn(TKW, "^local function winOn%("), "winOn")
        load(env, extractFn(TKW, "^function TK%.ShowWindow%("), "TKShowWindow")
        return env
    end
    local e = tkHarness({ tankCastEnabled = false })
    e.TK.ShowWindow()
    eq(e.ensuredWindow, nil, "tankCastEnabled OFF: ShowWindow does not build window")
    eq(#e.printed, 1, "tankCastEnabled OFF: user told why")
    e = tkHarness({ tankCastEnabled = true })
    e.TK.ShowWindow()
    eq(e.ensuredWindow, 1, "tankCastEnabled ON: ShowWindow builds window")
end

-- ---- autoShowOnGroup / restoreWindowsOnLogin conditions (extracted verbatim, evaluated) ------------------------------
local function condEval(path, marker, db, ctx)
    local env = newEnv(db); loadWP(env)
    env.InCombatLockdown = function() return ctx.combat or false end
    env.RG = { JustFormedGroup = function() return ctx.formed end, IsWindowShown = function() return ctx.shown end }
    env.TK = { JustFormedGroup = function() return ctx.formed end, IsWindowShown = function() return ctx.shown end }
    env.c = ctx.cfg
    env.win = setmetatable({}, { __index = function() return function() end end })
    load(env, extractFn(path, "^local function winOn%("), "winOn")
    local fn = assert(loadstring("return (" .. extractCond(path, marker) .. ") and true or false", "cond"))
    setfenv(fn, env)
    return fn()
end
for _, spec in ipairs({
    { path = RGW, enabled = "raidGroupsEnabled", name = "RaidGroups" },
    { path = TKW, enabled = "tankCastEnabled", name = "TankCast" },
}) do
    local function auto(db, ctx) return condEval(spec.path, 'winOn("autoShowOnGroup")', db, ctx) end
    local function restore(db, ctx) return condEval(spec.path, 'winOn("restoreWindowsOnLogin")', db, ctx) end
    local on = { [spec.enabled] = true, autoShowOnGroup = true, restoreWindowsOnLogin = true }
    local function with(over) local t = {}; for k, v in pairs(on) do t[k] = v end; for k, v in pairs(over) do t[k] = v end; return t end

    eq(auto(with({}), { formed = true, shown = false }), true, spec.name .. " auto-show fires when formed + enabled")
    eq(auto(with({ autoShowOnGroup = false }), { formed = true, shown = false }), false, spec.name .. " autoShowOnGroup OFF blocks")
    eq(auto(with({ [spec.enabled] = false }), { formed = true, shown = false }), false, spec.name .. " window disabled blocks auto-show")
    eq(auto(with({}), { formed = true, shown = true }), false, spec.name .. " already shown blocks")
    eq(auto(with({}), { formed = false, shown = false }), false, spec.name .. " not just formed blocks")
    eq(auto(with({}), { formed = true, shown = false, combat = true }), false, spec.name .. " combat blocks")

    eq(restore(with({}), { cfg = { shown = true } }), true, spec.name .. " restore at login when was open")
    eq(restore(with({}), { cfg = { shown = false } }), false, spec.name .. " not restored when it was closed")
    eq(restore(with({ restoreWindowsOnLogin = false }), { cfg = { shown = true } }), false, spec.name .. " restoreWindowsOnLogin OFF blocks")
    eq(restore(with({ [spec.enabled] = false }), { cfg = { shown = true } }), false, spec.name .. " window disabled blocks restore")
    eq(restore(with({}), { cfg = nil }), false, spec.name .. " no cfg -> no restore, no error")
end

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)

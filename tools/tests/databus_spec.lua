-- Headless tests for AutoInvitePlus/core/DataBus.lua serialization (hostile-input safety).
-- Run from the repo root:  luajit tools/tests/databus_spec.lua

local pass, fail = 0, 0
local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function eq(a, b, name)
    if a == b then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

local function noop() end
local frameMT = { __index = function() return noop end }
CreateFrame = function() return setmetatable({}, frameMT) end
ChatFrame_AddMessageEventFilter = noop
time = os.time
GetTime = os.clock
UnitName = function() return "Me" end
string.trim = string.trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

AutoInvitePlus = {
    Print = noop, Debug = noop, Version = "6.9.0",
    Utils = { DelayedCall = noop, NormalizeName = function(n) return n end },
}
local chunk = assert(loadfile("AutoInvitePlus/core/DataBus.lua"))
chunk()
local DB = AutoInvitePlus.DataBus

local function try(name, fn, ...)
    local okc, res = pcall(fn, ...)
    ok(okc, name .. " must not error: " .. tostring(not okc and res or ""))
    return okc and res or nil
end

-- ---- round trip -------------------------------------------------------------
local ev = { type = "LFM", data = {
    raid = "ICC25", name = "Tank^Boy", note = "a|b~c\nd;e", n = 5800, f = 1.5,
    yes = true, no = false, list = { "a", "b", 3 }, nested = { x = { y = { 1, 2 } } },
} }
local s = DB.Serialize(ev)
ok(type(s) == "string", "serialize returns string")
ok(not s:find("|"), "serialized form has no pipe (chat safe)")
ok(not s:find("\n"), "serialized form has no newline")
local d = try("round trip", DB.Deserialize, s, "Bob")
ok(d ~= nil, "round trip decodes")
if d then
    eq(d.type, "LFM", "type")
    eq(d.sender, "Bob", "sender")
    eq(d.data.raid, "ICC25", "string field")
    eq(d.data.name, "Tank^Boy", "caret escaped")
    eq(d.data.note, "a|b~c\nd;e", "special chars survive (;|~ newline)")
    eq(d.data.n, 5800, "number")
    eq(d.data.f, 1.5, "float")
    eq(d.data.yes, true, "true")
    eq(d.data.no, false, "false")
    eq(#d.data.list, 3, "array len")
    eq(d.data.list[3], 3, "array number elt")
    eq(d.data.nested.x.y[2], 2, "nested")
    ok(math.abs(d.timestamp - os.time()) <= 2, "timestamp stamped locally")
end
eq(DB.Serialize(nil), nil, "serialize nil")
eq(DB.Serialize({}), nil, "serialize no type")
local e2 = try("empty data", DB.Deserialize, DB.Serialize({ type = "PING" }), "x")
ok(e2 and type(e2.data) == "table", "empty data -> table")

-- ---- version handling ---------------------------------------------------------
eq(DB.Deserialize("2.0;LFM;1;d0~", "x"), nil, "other major version rejected")
ok(DB.Deserialize("1.7;LFM;1;d0~", "x") ~= nil, "same major, other minor accepted")
eq(DB.Deserialize("abc;LFM;1;d0~", "x"), nil, "non-numeric version rejected")
eq(DB.Deserialize("123456789012345678901234567890;LFM;1;d0~", "x"), nil, "huge version rejected")
ok(DB.Deserialize("1.0|LFM|1|d0~", "x") ~= nil, "legacy pipe separator")

-- ---- malformed ------------------------------------------------------------------
local bad = {
    "", ";", ";;;", "garbage", "1.0;LFM", "1.0;LFM;1", "1.0;;1;d0~", "1.0;LFM;nan;N",
    "1.0;LFM;1;", "1.0;LFM;1;sfoo", "1.0;LFM;1;strunc^", "1.0;LFM;1;s^", "1.0;LFM;1;s\\",
    "1.0;LFM;1;n", "1.0;LFM;1;nabc", "1.0;LFM;1;T", "1.0;LFM;1;F", "1.0;LFM;1;N", "1.0;LFM;1;n42",
    "1.0;LFM;1;sscalar", "1.0;LFM;1;a", "1.0;LFM;1;d", "1.0;LFM;1;a~", "1.0;LFM;1;d~",
    "1.0;LFM;1;a-5~sx", "1.0;LFM;1;d-5~sx~sy", "1.0;LFM;1;aabc~", "1.0;LFM;1;dnan~", "1.0;LFM;1;ainf~",
    "1.0;LFM;1;a99999999999~", "1.0;LFM;1;d99999999999~", "1.0;LFM;1;a1e308~sx", "1.0;LFM;1;d1e999~",
    "1.0;LFM;1;a3~sx", "1.0;LFM;1;d2~sk~sv~sk2", "1.0;LFM;1;d1~N~sv", "1.0;LFM;1;d1~a1~sx~sv",
    "1.0;LFM;1;zzzz", "1.0;LFM;1;~~~~", "1.0;LFM;1;a2~a2~a2~",
}
for i, p in ipairs(bad) do
    local r = try("malformed #" .. i .. " [" .. p .. "]", DB.Deserialize, p, "evil")
    if r then ok(type(r.data) == "table", "malformed #" .. i .. " data is always a table") end
end
for _, v in ipairs({ 42, true, {}, 3.5 }) do
    local okc = pcall(DB.Deserialize, v, "x")
    ok(true, "non-string input " .. type(v) .. " handled (pcall ok=" .. tostring(okc) .. ")")
end
eq(DB.Deserialize(nil, "x"), nil, "nil input")
-- scalar payloads must come back as {} not scalars
for _, p in ipairs({ "sfoo", "n42", "T", "F", "N" }) do
    local r = DB.Deserialize("1.0;LFM;1;" .. p, "x")
    ok(r and type(r.data) == "table" and next(r.data) == nil, "scalar payload '" .. p .. "' -> empty table")
end
-- truncated string value in dict keeps going without error
local r = DB.Deserialize("1.0;LFM;1;d2~sk~sv~skey2~sval", "x")
ok(r and r.data.k == "v", "truncated dict keeps decoded prefix")
-- non-string 'raid' in payload survives decode as its real type (consumers must guard)
r = DB.Deserialize("1.0;LFM;1;d1~sraid~n5", "x")
eq(r and r.data.raid, 5, "numeric raid decodes as number (consumer must type-check)")

-- ---- hostile sizes / hang protection --------------------------------------------
local t0 = os.clock()
local huge = DB.Deserialize("1.0;LFM;1;a999999999~sx", "x")
ok(huge ~= nil, "huge claimed array count")
ok(os.clock() - t0 < 2, "huge array count returns quickly (" .. (os.clock() - t0) .. "s)")
t0 = os.clock()
local hd = DB.Deserialize("1.0;LFM;1;d999999999~sk~sv", "x")
ok(hd ~= nil, "huge claimed dict count")
ok(os.clock() - t0 < 2, "huge dict count returns quickly")
-- big legit payload (255-char limit is enforced by transport, but decoder must cope with large)
t0 = os.clock()
local big = {}
for i = 1, 2000 do big[i] = "item" .. i end
local rb = DB.Deserialize(DB.Serialize({ type = "X", data = { l = big } }), "x")
ok(rb and #rb.data.l == 2000, "2000-element array round trip")
ok(os.clock() - t0 < 3, "big payload fast")
-- long string
local ls = string.rep("a^b", 50000)
local rl = DB.Deserialize(DB.Serialize({ type = "X", data = { s = ls } }), "x")
ok(rl and rl.data.s == ls, "long string round trip")
-- count claims bigger than payload with many nested empties
t0 = os.clock()
try("nested claim blowup", DB.Deserialize, "1.0;LFM;1;" .. string.rep("a99999~", 3000), "x")
ok(os.clock() - t0 < 3, "nested huge claims fast (" .. (os.clock() - t0) .. "s)")

-- ---- nesting depth -------------------------------------------------------------------
for _, depth in ipairs({ 50, 150, 1000, 20000, 200000 }) do
    local payload = string.rep("a1~", depth) .. "N"
    t0 = os.clock()
    local okc, res = pcall(DB.Deserialize, "1.0;LFM;1;" .. payload, "x")
    ok(okc, "array nesting depth " .. depth .. " must not raise (" .. tostring(not okc and res or "") .. ")")
    ok(os.clock() - t0 < 3, "depth " .. depth .. " fast")
    payload = string.rep("d1~sk~", depth) .. "N"
    okc, res = pcall(DB.Deserialize, "1.0;LFM;1;" .. payload, "x")
    ok(okc, "dict nesting depth " .. depth .. " must not raise (" .. tostring(not okc and res or "") .. ")")
end

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)

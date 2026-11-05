-- Headless tests for AutoInvitePlus/modules/Blacklist.lua import parsing
-- (hostile-input safety). Loads the REAL module file with a stubbed WoW API.
-- Run from the repo root:  luajit tools/tests/blacklist_import_spec.lua

local pass, fail = 0, 0
local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function eq(a, b, name)
    if a == b then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

-- ---- WoW API stubs ---------------------------------------------------------
local function noop() end
local frameMT = { __index = function() return noop end }
CreateFrame = function() return setmetatable({}, frameMT) end
time = os.time
date = os.date
-- WoW string extensions
function string.trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(delim, str, pieces)
    local out, pos = {}, 1
    while true do
        if pieces and #out >= pieces - 1 then out[#out + 1] = str:sub(pos); break end
        local s, e = str:find(delim, pos, true)
        if not s then out[#out + 1] = str:sub(pos); break end
        out[#out + 1] = str:sub(pos, s - 1)
        pos = e + 1
    end
    return unpack(out)
end

local printed = {}
AutoInvitePlus = {
    db = { blacklist = {} },
    Print = function(m) printed[#printed + 1] = m end,
    Debug = noop,
}
local AIP = AutoInvitePlus
assert(loadfile("AutoInvitePlus/modules/Blacklist.lua"))()
local L = AIP.BLACKLIST_IMPORT_LIMITS

local function parse(data)
    local okc, e, errs, fmt = pcall(AIP.ParseImportData, data)
    if not okc then fail = fail + 1; print("FAIL: ParseImportData threw: " .. tostring(e)); return {}, {}, "error" end
    return e, errs, fmt
end

-- ---- non-string / empty input never errors ---------------------------------
for _, v in ipairs({ 42, true, {}, function() end }) do
    local e, errs = parse(v)
    eq(#e, 0, "non-string " .. type(v) .. " -> no entries")
end
local e = parse(nil); eq(#e, 0, "nil -> no entries")
e = parse(""); eq(#e, 0, "empty -> no entries")
e = parse("   \n\r\n\t "); eq(#e, 0, "whitespace-only -> no entries")
e = parse("# just a comment\n# another"); eq(#e, 0, "only comments -> no entries")

-- ---- simple format ---------------------------------------------------------
local e1, er1, f1 = parse("bob;ninja looter\nALICE\n  carl ; afk  ")
eq(f1, "simple", "simple format detected")
eq(#e1, 3, "simple: 3 entries")
eq(e1[1].name, "Bob", "name normalized (Bob)")
eq(e1[1].reason, "ninja looter", "reason kept")
eq(e1[2].name, "Alice", "uppercase name normalized")
eq(e1[2].reason, "Imported", "missing reason defaulted")
eq(e1[3].name, "Carl", "padded name trimmed")
eq(e1[3].reason, "afk", "padded reason trimmed")
eq(e1[1].source, "import", "simple source = import")

-- CRLF input
local ec = parse("bob;x\r\nalice;y\r\n")
eq(#ec, 2, "CRLF lines split cleanly")
eq(ec[1].name, "Bob", "no stray CR in name")

-- ---- full format -----------------------------------------------------------
local ef, _, ff = parse("Bob|reason one|queue|some notes|12345\nCarl|r2")
eq(ff, "full", "full format detected")
eq(#ef, 2, "full: 2 entries")
eq(ef[1].source, "queue", "full: source")
eq(ef[1].notes, "some notes", "full: notes")
eq(ef[2].source, "import", "full: missing source defaulted")

-- ---- CSV -------------------------------------------------------------------
local csv = 'Name,Reason,Source,Notes,Date Added\nBob,"ninja, big",manual,"said ""hi""",2020-01-01\nCarl,,queue,,'
local ecsv, _, fcsv = parse(csv)
eq(fcsv, "csv", "csv format detected")
eq(#ecsv, 2, "csv: 2 entries")
eq(ecsv[1].reason, "ninja, big", "csv: quoted comma")
eq(ecsv[1].notes, 'said "hi"', "csv: escaped quote")
eq(ecsv[2].reason, "Imported", "csv: empty reason defaulted")
-- BOM + leading blank/comment lines before CSV header
local ecb, _, fcb = parse("\239\187\191\n# comment\nName,Reason,Source,Notes,Date Added\nBob,r,manual,n,x")
eq(fcb, "csv", "csv detected past BOM/blank/comment")
eq(#ecb, 1, "csv past BOM: header dropped, row kept")
-- runaway comma line must not blow up
local wide = "Bob" .. string.rep(",x", 500)
local ew = parse("Name,Reason,Source,Notes,Date Added\n" .. wide)
eq(#ew, 1, "csv with 500 columns still parses one entry")

-- ---- name validation -------------------------------------------------------
local en, ern = parse("good;ok\nb4d;digits\nsp ace;space\na;x\n;noname\n  ;blank\nname-realm;ok\nje\195\168n;accent\n" .. string.rep("x", 40) .. ";toolong")
local names = {}
for _, x in ipairs(en) do names[x.name] = true end
ok(names["Good"], "valid name kept")
ok(not names["B4d"], "digits rejected")
ok(not names["Sp ace"], "space in name rejected")
ok(not names["A"], "single char rejected")
ok(names["Name"], "realm suffix stripped")
ok(names["Je\195\168n"] or names["je\195\168n"], "UTF-8 accented name allowed")
eq(#en, 3, "exactly good/name/accent entries")
ok(#ern >= 4, "errors reported for rejected lines")

-- ---- duplicates ------------------------------------------------------------
local ed, erd = parse("bob;first\nBOB;second\nbOb;third\nnameB")
eq(#ed, 2, "duplicates (case-insensitive) collapsed")
eq(ed[1].reason, "first", "first duplicate wins")
eq(#erd, 2, "one error per duplicate")

-- ---- control chars / escapes -----------------------------------------------
local ecc = parse("first;x\nbob;rea\0son\1 x\127y |cFFFF0000red|r |Hitem:1|h[x]|h")
eq(#ecc, 2, "control chars do not break parse")
ok(not ecc[2].reason:find("%c"), "control chars stripped from reason")
ok(not ecc[2].reason:find("|", 1, true), "pipe escapes neutralised in reason")
local enc = parse("bo\0b;x")
eq(enc[1] and enc[1].name, "Bob", "NUL inside name stripped")

-- ---- length caps -----------------------------------------------------------
local el = parse("bob;" .. string.rep("a", 900))
eq(#el[1].reason, L.MAX_REASON_CHARS, "reason capped")
local el2 = parse("bob;" .. string.rep("a", L.MAX_LINE_BYTES + 5))
eq(#el2, 0, "over-long line skipped")
local efs = parse("bob|r|" .. string.rep("z", 500) .. "|" .. string.rep("n", 500) .. "|1")
eq(#efs[1].source, L.MAX_SOURCE_CHARS, "source capped")
eq(#efs[1].notes, L.MAX_NOTES_CHARS, "notes capped")
local eso = parse("bob|r|we!ird so$urce|n|1")
eq(eso[1].source, "weirdsource", "source sanitised to [%w_]")

-- ---- UTF-8 truncation ------------------------------------------------------
local TU = AIP.TruncateUtf8
eq(TU("hello", 3), "hel", "TruncateUtf8 ascii")
eq(TU("hello", 10), "hello", "TruncateUtf8 short string unchanged")
eq(TU("\195\169\195\169\195\169", 2), "\195\169\195\169", "TruncateUtf8 cuts on char boundary (2-byte)")
eq(TU("a\226\130\172b", 2), "a\226\130\172", "TruncateUtf8 3-byte char kept whole")
eq(TU("a\226\130", 1), "a", "TruncateUtf8 drops dangling partial sequence")
eq(TU(nil, 5), "", "TruncateUtf8 nil safe")
local utf = parse("bob;" .. string.rep("\195\169", 150))
eq(#utf[1].reason, L.MAX_REASON_CHARS * 2, "reason of 2-byte chars capped by chars not bytes")
ok(utf[1].reason:match("^[\195][\169]") ~= nil and #utf[1].reason % 2 == 0, "no half multi-byte char left")

-- ---- volume caps -----------------------------------------------------------
local many = {}
for i = 1, 5000 do
    -- alphabetic-only unique names
    local a, b, c = math.floor(i / 676) % 26, math.floor(i / 26) % 26, i % 26
    many[#many + 1] = "zz" .. string.char(97 + a, 97 + b, 97 + c) .. ";r"
end
local t0 = os.clock()
local em, erm = parse(table.concat(many, "\n"))
ok(os.clock() - t0 < 5, "5000-line import is fast")
ok(#em <= L.MAX_ENTRIES, "entry count capped (" .. #em .. ")")
ok(#em > 0, "capped import still returns entries")
ok(#erm >= 1, "cap reported as an error")

-- huge single blob (no newlines) and huge multi-line blob
local blob = string.rep("a", 5 * 1024 * 1024)
t0 = os.clock()
local eb = parse(blob)
ok(os.clock() - t0 < 5, "5MB single-line blob handled quickly")
eq(#eb, 0, "5MB blob yields no entries")
local big = string.rep("bob;x\n", 100000)   -- 600KB
local eg, erg = parse(big)
ok(#eg <= 1, "huge repetitive paste collapses via dedupe")
ok(#erg <= L.MAX_ERRORS + 1, "error list bounded (" .. #erg .. ")")

-- truncation at the byte cap cuts on a line boundary (no half names)
local pad = string.rep("# pad\n", math.floor(L.MAX_BYTES / 6) - 2)   -- just under the cap
local tail = "alexander;x\nbarbaranna;y\n"
local ecut = parse(pad .. tail)
for _, x in ipairs(ecut) do
    ok(x.name == "Alexander" or x.name == "Barbaranna", "cap never yields a half-read name: " .. x.name)
end

-- pathological pattern inputs
t0 = os.clock()
parse(string.rep("|", 100000))
parse(string.rep(";", 100000))
parse(string.rep(",\"", 50000))
parse("Name,Reason,Source,Notes,Date Added\n" .. string.rep("\"", 900))
parse(string.rep("a|", 400))
ok(os.clock() - t0 < 5, "pathological delimiter floods stay fast")
parse("Name,Reason,Source,Notes,Date Added\n" .. string.rep("\"", 900)); pass = pass + 1

-- ---- ImportBlacklist end-to-end -------------------------------------------
AIP.db.blacklist = { bob = { name = "Bob", reason = "old" } }
local imported, skipped = AIP.ImportBlacklist("bob;new\ncarl;x\ndave;y", "merge")
eq(imported, 2, "merge imports 2 new")
eq(skipped, 1, "merge skips existing")
eq(AIP.db.blacklist.bob.reason, "old", "merge does not overwrite existing")
imported = AIP.ImportBlacklist("erin;z", "replace")
eq(imported, 1, "replace imports")
ok(AIP.db.blacklist.bob == nil and AIP.db.blacklist.erin ~= nil, "replace clears old entries")
local before = AIP.db.blacklist
imported = AIP.ImportBlacklist("b4d;x\n!!!;y", "replace")
eq(imported, 0, "all-invalid import returns 0")
ok(AIP.db.blacklist == before and AIP.db.blacklist.erin ~= nil, "all-invalid replace does NOT wipe existing list")
okc = pcall(AIP.ImportBlacklist, 12345, "merge")
ok(okc, "ImportBlacklist(non-string) does not throw")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)

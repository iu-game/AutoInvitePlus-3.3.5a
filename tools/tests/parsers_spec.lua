-- Headless tests for AutoInvitePlus/core/Parsers.lua (chat parsing).
-- Run from the repo root:  luajit tools/tests/parsers_spec.lua

local pass, fail = 0, 0
local function eq(a, b, name)
    if a == b then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end

time = os.time
AutoInvitePlus = {}
assert(loadfile("AutoInvitePlus/core/Parsers.lua"))()
local P = AutoInvitePlus.Parsers

-- ---- GearScore ---------------------------------------------------------------
local gs = {
    { "LFM ICC25 5800 gs", 5800 }, { "lfm icc 25 gs 5800+", 5800 }, { "5800+ gs", 5800 },
    { "lf2m 5.8k gs icc", 5800 }, { "need 5,8k gs", 5800 }, { "gs: 5800", 5800 },
    { "min gs 5.5k", 5500 }, { "5,800 gs", 5800 }, { "5800+ ilvl", 5800 }, { "gearscore 5800", 5800 },
    { "gs 5800 pst", 5800 }, { "GS 5800", 5800 }, { "LF tank gs5800", 5800 },
    { "6k gs", 6000 }, { "gs 6k", 6000 }, { "5.8k gs", 5800 }, { "gs 5.8k+", 5800 },
    { "hello world", nil }, { "GS 580", nil }, { "5.8k", nil }, { "", nil },
}
for _, c in ipairs(gs) do eq(P.ParseGearScore(c[1]), c[2], "GS '" .. c[1] .. "'") end
eq(P.ParseGearScore(nil), nil, "GS nil")

-- ---- raid detection ------------------------------------------------------------
local raids = {
    { "LFM ICC25 HC", "ICC25H", "ICC" }, { "LFM ICC 25 heroic", "ICC25H", "ICC" },
    { "icc10 normal", "ICC10N", "ICC" }, { "LF ICC 10 man", "ICC10N", "ICC" },
    { "lfm icc25n", "ICC25N", "ICC" }, { "LFM ICC", "ICC", "ICC" }, { "icc10 hc", "ICC10H", "ICC" },
    { "icc rep", "ICCREP", "ICC" }, { "ashen verdict rep run", "ICCREP", "ICC" },
    { "LFM Ulduar 25", "ULDUAR25", "ULDUAR" }, { "LFM TOC 10 hc", "TOGC10", "TOC" },
    { "lfm toc25 heroic", "TOGC25", "TOC" }, { "lfm toc 25", "TOC25", "TOC" }, { "LFM togc 25", "TOGC25", "TOC" },
    { "lfm toc", "TOC", "TOC" }, { "lfm voa 25", "VOA25", "VOA" }, { "lfm voa10", "VOA10", "VOA" },
    { "LFM RS 25 hc", "RS25H", "RS" }, { "lfm naxx 10", "NAXX10", "NAXX" }, { "lfm os10", "OS10", "OS" },
    { "lfm eoe", "EOE", "EOE" }, { "lfm lich king kill", "ICC", "ICC" },
    { "report me", nil, nil }, { "hello", nil, nil }, { "", nil, nil },
}
for _, c in ipairs(raids) do
    local r, cat = P.DetectRaid(c[1])
    eq(r, c[2], "raid '" .. c[1] .. "'")
    eq(cat, c[3], "category '" .. c[1] .. "'")
end
eq(P.DetectRaid(nil), nil, "DetectRaid nil")
eq(#P.DetectAllRaids(nil), 0, "DetectAllRaids nil")
do
    local all = P.DetectAllRaids("lfm icc25 hc and voa10")
    local set = {}
    for _, r in ipairs(all) do set[r] = true end
    eq(set.ICC25H, true, "DetectAllRaids finds ICC25H")
    eq(set.VOA10, true, "DetectAllRaids finds VOA10")
end

-- ---- role / class ---------------------------------------------------------------
local roles = {
    { "LF tank for ICC", "TANK" }, { "lf mt", "TANK" }, { "LF healer", "HEALER" }, { "LFM dps", "DPS" },
    { "Resto druid LFG", "HEALER" }, { "holy pala LF ICC", "HEALER" }, { "protection warrior LFG", "TANK" },
    { "not now", nil }, { "add me", nil }, { "hello", nil },   -- short codes must not match inside words
}
for _, c in ipairs(roles) do eq(P.DetectRole(c[1]), c[2], "role '" .. c[1] .. "'") end
eq(P.DetectRole(nil), nil, "role nil")

-- ---- previously-open gaps --------------------------------------------------------
for _, c in ipairs({
    { "LFM ICC 25 man hc", "ICC25H" }, { "icc 25 man heroic", "ICC25H" }, { "icc 10 men hc", "ICC10H" },
    { "icc 25 man", "ICC25N" }, { "lk25", "ICC25N" }, { "lfm lk 10", "ICC10N" }, { "lk25 hc", "ICC25H" },
    { "lk", nil }, { "my lk is low", nil }, { "talk 25 now", nil },
}) do eq((P.DetectRaid(c[1])), c[2], "gap raid '" .. c[1] .. "'") end
for _, c in ipairs({
    { "5.80k gs", 5800 }, { "gs 5.85k", 5850 }, { "icc gs 58000", nil }, { "58000 gs", nil },
    { "ToC5k gs", nil }, { "toc 5k gs", 5000 }, { "50k gs", nil }, { "gs 99999", nil },
}) do eq(P.ParseGearScore(c[1]), c[2], "gap GS '" .. c[1] .. "'") end
for _, c in ipairs({
    { "need tanks", "TANK" }, { "need 2 heals", "HEALER" }, { "LF healers", "HEALER" }, { "more dps pls", "DPS" },
    { "casters wanted", "DPS" }, { "trees", nil }, { "mts", nil }, { "tankard", nil }, { "healthy", nil },
}) do eq(P.DetectRole(c[1]), c[2], "gap role '" .. c[1] .. "'") end
eq(P.DetectClass("Resto druid LFG"), "DRUID", "class druid")
eq(P.DetectClass("holy pala LF ICC"), "PALADIN", "class pala")
eq(P.DetectClass("melee locate"), nil, "class: no false positive on melee/locate")
eq(P.DetectClass(nil), nil, "class nil")

-- ---- LFG/LFM -----------------------------------------------------------------------
eq(P.IsLFM("LFM icc"), true, "IsLFM")
eq(P.IsLFM("lf2m icc"), true, "IsLFM lf2m")
eq(P.IsLFG("LFG icc"), true, "IsLFG")
eq(P.IsLFM("lfg"), false, "lfg is not lfm")
eq(P.IsLFM(nil), false, "IsLFM nil")
eq(P.IsLFG(nil), false, "IsLFG nil")

-- ---- composition / counts / ilvl / weekly --------------------------------------------
local c = P.ParseAIPComposition("[T:0/2 H:1/6 M:0/8 R:3/9]")
eq(c and c.tanks.needed, 2, "AIP comp tanks needed")
eq(c and c.healers.current, 1, "AIP comp healers current")
eq(c and c.rdps.current, 3, "AIP comp rdps current")
eq(P.ParseAIPComposition("[T:0/2 H:1/6]"), nil, "partial comp rejected")
eq(P.ParseAIPComposition(nil), nil, "comp nil")
local cur, max = P.ParseFilledCount("LFM [12/25]")
eq(cur, 12, "filled cur"); eq(max, 25, "filled max")
cur, max = P.ParseFilledCount("[3/7]")
eq(cur, nil, "non raid size rejected")
eq(P.ParseNeedCount("lf3m need 2 tank", "tank"), 2, "need 2 tank")
eq(P.ParseNeedCount("lf2m heal", "healer"), 2, "lf2m heal")
eq(P.ParseNeedCount("hello", "tank"), 0, "need none")
eq(P.ParseNeedCount(nil, "tank"), 0, "need nil msg")
eq(P.ParseNeedCount("lf tank", "bogus"), 0, "need bogus role")
eq(P.ParseItemLevel("ilvl 264+"), 264, "ilvl")
eq(P.ParseItemLevel("iLvl:264"), 264, "iLvl:")
eq(P.ParseWeekly("WQ:Marrowgar x"), "Marrowgar", "weekly")
eq(P.ParseWeekly("nope"), nil, "weekly none")
eq(P.ParseWeekly(nil), nil, "weekly nil")

-- ---- spec codes / lookingfor ---------------------------------------------------------
local si = P.GetSpecInfo("BDK")
eq(si and si.class, "DEATHKNIGHT", "spec BDK class")
eq(si and si.spec, "Blood", "spec BDK spec")
eq(P.GetSpecInfo("PP").class, "PALADIN", "spec PP")
eq(P.GetSpecInfo("Zzz"), nil, "unknown spec code")
local rs = P.ParseLookingFor("LFM [T:BD,BDK H:HPal M:Ret R:Mag] ICC25")
eq(rs and rs.TANK and #rs.TANK, 2, "lookingfor tanks")
eq(rs and rs.HEALER and rs.HEALER[1], "HPal", "lookingfor healer")
eq(rs and rs.MDPS and rs.MDPS[1], "Ret", "lookingfor mdps")
eq(rs and rs.RDPS and rs.RDPS[1], "Mag", "lookingfor rdps")
eq(P.GetClassColor("NOPE").hex, "FFFFFF", "unknown class color fallback")

-- ---- ParseChatMessage ------------------------------------------------------------------
local m = P.ParseChatMessage("LFM ICC25 HC [T:0/2 H:0/6 M:0/8 R:0/9] [0/25] 5800 gs", "Bob", "LookingForGroup")
eq(m and m.raid, "ICC25H", "chat raid")
eq(m and m.isLFM, true, "chat isLFM")
eq(m and m.gs, 5800, "chat gs")
eq(m and m.filledMax, 25, "chat filledMax")
eq(m and m.tanks.needed, 2, "chat tanks needed")
eq(m and m.dps.needed, 17, "chat dps needed (8+9)")
eq(m and m.hasExplicitComposition, true, "chat explicit composition")
m = P.ParseChatMessage("LF2M ICC10 need tank and heal", "Bob", "x")
eq(m and m.raid, "ICC10N", "chat2 raid")
eq(m and m.hasExplicitComposition, false, "chat2 not explicit")
m = P.ParseChatMessage("WQ:Marrowgar LFM ICC10", "Bob", "x")
eq(m and m.weekly, "Marrowgar", "chat weekly")
eq(m and m.raid, "ICC10N", "chat weekly raid still found")
m = P.ParseChatMessage("LFG ICC25 prot warr 6k gs", "Bob", "x")
eq(m and m.isLFG, true, "chat LFG")
eq(m and m.role, "TANK", "chat LFG role")
eq(m and m.gs, 6000, "chat LFG 6k gs")
eq(P.ParseChatMessage("hello world", "Bob", "x"), nil, "irrelevant chat -> nil")
eq(P.ParseChatMessage(nil, "Bob", "x"), nil, "chat nil msg")
eq(P.ParseChatMessage("lfm icc", nil, "x"), nil, "chat nil author")

-- ---- raid metadata ------------------------------------------------------------------------
eq(P.GetRaidName("ICC25H"), "ICC 25 Heroic", "raid name")
eq(P.GetRaidCategory("ICC25H"), "ICC", "raid category")
eq(P.IsHeroicRaidId("ICC25H"), true, "heroic id")
eq(P.IsHeroicRaidId("ICC25N"), false, "normal id")

-- ---- hostile / garbage input never errors ---------------------------------------------------
local junk = { string.rep("a", 100000), string.rep("%", 500), "[[[[", "lf" .. string.rep("9", 5000) .. "m",
    "|cffff0000|Hitem:1|h[x]|h|r", string.rep("5800 gs ", 2000), "\0\1\2", "(((" }
for i, j in ipairs(junk) do
    local ok, err = pcall(P.ParseChatMessage, j, "Bob", "x")
    eq(ok, true, "junk #" .. i .. " no error " .. tostring(not ok and err or ""))
end

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)

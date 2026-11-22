-- SPDX-License-Identifier: MIT
local _, ns = ...
ns.version = "1.0.0"
-- Rank order is explicit. Spell IDs are facts checked against WoWSims Forever
-- 00fecd9c spell_data_auto_gen.go; never sort by ID or localized rank text.
ns.spells = {
    auto = {75}, mark = {1130,14323,14324,14325},
    sting = {1978,13549,13550,13551,13552,13553,13554,13555,25295},
    arcane = {3044,14281,14282,14283,14284,14285,14286,14287},
    aimed = {19434,20900,20901,20902,20903,20904},
    sniper = {1310687,1310785,1310786}, multi = {2643}, volley = {1510,14294,14295},
    hawk = {1293241,1293525,1293526,1293527}, wrath = {19574}, rapid = {3045},
    raptor = {2973,14260,14261,14262,14263,14264,14265,14266},
    mongoose = {1495,14269,14270,14271}, strider = {1317257},
    immolation = {13795,14302,14303,14304,14305}, explosive = {13813,14316,14317},
}
ns.byID = {}
for key, ranks in pairs(ns.spells) do for _, id in ipairs(ranks) do ns.byID[id] = key end end
ns.castTime = {aimed=true, sniper=true, multi=true, volley=true}
ns.selfSpell = {rapid=true, wrath=true, immolation=true, explosive=true}
ns.meleeSpell = {raptor=true, mongoose=true, strider=true, immolation=true, explosive=true}
ns.family = {hawk={"hawk","arcane"}, arcane={"hawk","arcane"},
    aimed={"aimed","multi"}, multi={"aimed","multi"},
    immolation={"immolation","explosive"}, explosive={"immolation","explosive"}}
ns.defaults = {spec="auto", mode="balanced", targets=1, cooldowns=true,
    traps=false, weave="normal", enabled=true, locked=false, x=180, y=-130, scale=1}
ns.specNames = {auto="自动", bm="兽王", mm="射击", sv="生存"}
ns.modeNames = {balanced="均衡", conserve="省蓝", burst="全力"}
function ns.Settings(raw)
    local out = {}
    if type(raw) ~= "table" then raw = {} end
    for k,v in pairs(ns.defaults) do
        if type(raw[k])==type(v) then out[k]=raw[k] else out[k]=v end
    end
    if not ns.specNames[out.spec] then out.spec="auto" end
    if not ns.modeNames[out.mode] then out.mode="balanced" end
    if out.targets~=1 and out.targets~=3 and out.targets~=6 then out.targets=1 end
    if out.weave~="normal" and out.weave~="aggressive" then out.weave="normal" end
    for _,k in ipairs({"x","y","scale"}) do
        if out[k]~=out[k] or math.abs(out[k])>4000 then out[k]=ns.defaults[k] end
    end
    out.scale=math.max(0.6,math.min(2,out.scale))
    return out
end
function ns.SelectRank(ranks, learned)
    for i=#ranks,1,-1 do if learned[ranks[i]] then return ranks[i] end end
end

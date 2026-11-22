-- SPDX-License-Identifier: MIT
local _, ns = ...
ns.version = "1.1.0"
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
    traps=false, weave="normal", enabled=true, locked=false, x=180, y=-130, scale=1,
    fontScale=1, opacity=0.92, visibility="always", layoutVersion=2}
ns.optionBounds={scale={0.6,2},fontScale={0.9,1.25},opacity={0.2,1},x={-4000,4000},y={-4000,4000}}
ns.layoutKeys={"x","y","scale","fontScale","opacity"}
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
    for k,bounds in pairs(ns.optionBounds) do
        if out[k]~=out[k] or math.abs(out[k])>4000 then out[k]=ns.defaults[k] end
        out[k]=math.max(bounds[1],math.min(bounds[2],out[k]))
    end
    if raw.layoutVersion~=2 then
        out.x=math.max(-4000,math.min(4000,out.x*out.scale))
        out.y=math.max(-4000,math.min(4000,out.y*out.scale))
    end
    out.layoutVersion=2
    if out.visibility~="always" and out.visibility~="target" and out.visibility~="combat" then out.visibility="always" end
    return out
end
-- Coordinates are in UIParent units; root's anchor offset uses root units.
function ns.LayoutGeometry(db,width,height)
    local scale=math.min(db.scale,math.max(0.1,(width-24)/400),math.max(0.1,(height-24)/270))
    local mx=math.max(0,(width-400*scale)/2-12)
    local my=math.max(0,(height-270*scale)/2-12)
    local x=math.max(-mx,math.min(mx,db.x));local y=math.max(-my,math.min(my,db.y))
    return x,y,scale,x/scale,y/scale
end
function ns.CenterToParent(x,y,effectiveScale,parentScale,px,py)
    return x*effectiveScale/parentScale-px,y*effectiveScale/parentScale-py
end
function ns.ShouldShow(db,state,preview)
    if preview then return true end
    if not db.enabled then return false end
    return db.visibility=="always" or (db.visibility=="target" and state and state.target==true)
        or (db.visibility=="combat" and state and state.inCombat==true) or false
end
function ns.SelectRank(ranks, learned)
    for i=#ranks,1,-1 do if learned[ranks[i]] then return ranks[i] end end
end

-- SPDX-License-Identifier: MIT
local _, ns = ...
ns.version = "1.5.0"
-- Rank order is explicit. Spell IDs are facts checked against WoWSims Forever
-- 00fecd9c spell_data_auto_gen.go; never sort by ID or localized rank text.
ns.spells = {
    auto = {75}, mark = {1130,14323,14324,14325},
    sting = {1978,13549,13550,13551,13552,13553,13554,13555,25295},
    arcane = {3044,14281,14282,14283,14284,14285,14286,14287},
    aimed = {19434,20900,20901,20902,20903,20904},
    sniper = {1310687,1310785,1310786}, multi = {2643}, volley = {1510,14294,14295},
    hawk = {1293241,1293525,1293526,1293527}, wrath = {19574}, rapid = {3045},
    -- Learned-only compatibility alias; prefer Forever's canonical 20554.
    berserking = {26297,20554},
    raptor = {2973,14260,14261,14262,14263,14264,14265,14266},
    mongoose = {1495,14269,14270,14271}, strider = {1317257},
    immolation = {13795,14302,14303,14304,14305}, explosive = {13813,14316,14317},
}
ns.byID = {}
for key, ranks in pairs(ns.spells) do for _, id in ipairs(ranks) do ns.byID[id] = key end end
ns.castTime = {aimed=true, sniper=true, multi=true, volley=true}
ns.selfSpell = {berserking=true,rapid=true, wrath=true, immolation=true, explosive=true}
ns.burstOrder={"berserking","rapid","wrath"}
ns.reminderOrder={"berserking","rapid","wrath","mark"}
ns.burstOption={berserking="burstRacial",rapid="burstRapid",wrath="burstWrath"}
ns.futureKeys={"hawk","arcane","aimed","sniper","multi","volley"}
-- Observed-cast estimates, not live guardian counts. All four Hawk ranks have cap 2.
ns.hawkFlight=1;ns.hawkLifetime=18;ns.hawkSharedWindow=6;ns.hawkLead=.2
ns.meleeSpell = {raptor=true, mongoose=true, strider=true, immolation=true, explosive=true}
ns.family = {hawk={"hawk","arcane"}, arcane={"hawk","arcane"},
    aimed={"aimed","multi"}, multi={"aimed","multi"},
    immolation={"immolation","explosive"}, explosive={"immolation","explosive"}}
ns.defaults = {spec="auto", mode="balanced", targets=1, cooldowns=true,
    traps=false, weave="normal", enabled=true, locked=false, x=36, y=-80,
    mainSize=56,burstSize=32,burstSpacing=8,rowGap=12,iconLayoutVersion=1,
    visibility="target",layoutVersion=2,displayVersion=2,
    stableRecommendations=true,burstRacial=true,burstRapid=true,burstWrath=true,
    markReminder="priority",markInCombat=false,
    stingEnabled=true,stingIdle=false,stingX=140,stingY=-100,stingSize=44,
    stingRefreshTime=10,stingOpening=true,stingOpeningHealth=5000,stingSkipElementals=false,auxiliaryLayoutVersion=0}
ns.optionBounds={mainSize={24,160},burstSize={12,96},burstSpacing={0,40},rowGap={0,80},x={-4000,4000},y={-4000,4000}}
ns.optionBounds.stingX={-4000,4000};ns.optionBounds.stingY={-4000,4000};ns.optionBounds.stingSize={16,128}
ns.optionBounds.stingRefreshTime={1,60};ns.optionBounds.stingOpeningHealth={1,10000000}
ns.layoutKeys={"x","y","mainSize","burstSize","burstSpacing","rowGap","stingX","stingY","stingSize"}
ns.positionKeys={x=true,y=true,stingX=true,stingY=true}
for i,key in ipairs(ns.reminderOrder) do
    for _,axis in ipairs({"X","Y"}) do
        local field=key..axis
        ns.defaults[field]=axis=="X" and ns.defaults.x+(i-2.5)*(ns.defaults.burstSize+ns.defaults.burstSpacing)
            or ns.defaults.y-ns.defaults.mainSize/2-ns.defaults.rowGap-ns.defaults.burstSize/2
        ns.optionBounds[field]={-4000,4000};ns.positionKeys[field]=true
        ns.layoutKeys[#ns.layoutKeys+1]=field
    end
end
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
    if out.markReminder~="off" and out.markReminder~="priority" and out.markReminder~="all" then out.markReminder="priority" end
    local function Number(v,fallback)
        if type(v)~="number" or v~=v or math.abs(v)==math.huge then return fallback end
        return v
    end
    local legacy=raw.iconLayoutVersion~=1 and (raw.scale~=nil or raw.x~=nil or raw.y~=nil or raw.layoutVersion~=nil or raw.displayVersion~=nil)
    if legacy then
        local scale=math.max(.6,math.min(2,Number(raw.scale,1)))
        local x=math.max(-4000,math.min(4000,Number(raw.x,180)))
        local y=math.max(-4000,math.min(4000,Number(raw.y,-130)))
        local w,h,left,top,m,b,gap=370,222,12,61,52,30,12
        if raw.displayVersion==2 then w,h,left,top,m,b,gap=360,raw.showDetails==true and 276 or 172,8,8,56,32,26
        elseif raw.layoutVersion==2 then w,h,left,top,m,b=400,270,12,66,56,32 end
        if raw.layoutVersion~=2 and raw.displayVersion~=2 then x=x*scale;y=y*scale end
        -- Translate with the old unrounded dimensions before rounding new sizes.
        out.x=x+(left+m/2-w/2)*scale;out.y=y+(h/2-top-m/2)*scale
        out.mainSize=m*scale;out.burstSize=b*scale;out.burstSpacing=8*scale;out.rowGap=gap*scale
    end
    out.iconLayoutVersion=1
    for k,bounds in pairs(ns.optionBounds) do
        out[k]=Number(out[k],ns.defaults[k])
        out[k]=math.max(bounds[1],math.min(bounds[2],out[k]))
        if not ns.positionKeys[k] then out[k]=math.floor(out[k]+0.5) end
    end
    out.layoutVersion=2
    if raw.displayVersion~=2 and out.visibility=="always" then out.visibility="target" end
    out.displayVersion=2
    if out.visibility~="always" and out.visibility~="target" and out.visibility~="combat" then out.visibility="target" end
    return out
end
-- x/y locate the main icon centre, not the bounding box centre.
function ns.IconLayout(db,count)
    count=count or 0
    local rowWidth=count>0 and count*db.burstSize+(count-1)*db.burstSpacing or 0
    local w=math.max(db.mainSize,rowWidth)
    local h=db.mainSize+(count>0 and db.rowGap+db.burstSize or 0)
    return {width=w,height=h,mainX=(w-db.mainSize)/2,burstX=(w-rowWidth)/2,
        burstY=-(db.mainSize+db.rowGap),mainOffset=(h-db.mainSize)/2,count=count}
end
function ns.ReminderSlots(db,known)
    local slots={}
    for _,key in ipairs(ns.reminderOrder) do
        local enabled
        if key=="mark" then enabled=db.markReminder~="off"
        else enabled=db.cooldowns and db[ns.burstOption[key]] end
        if enabled and known[key] then slots[#slots+1]=key end
    end
    return slots
end
-- One-time migration and explicit user-requested arrangement share the old row geometry.
function ns.ArrangeAuxiliary(db,known,includeMissing)
    local active=ns.ReminderSlots(db,known);local order={};local included={}
    for _,key in ipairs(active) do order[#order+1]=key;included[key]=true end
    if includeMissing then
        for _,key in ipairs(ns.reminderOrder) do if not included[key] then order[#order+1]=key end end
    end
    local count=#active>0 and #active or #order
    local pitch=db.burstSize+db.burstSpacing
    for i,key in ipairs(order) do
        db[key.."X"]=math.max(-4000,math.min(4000,db.x+(i-(count+1)/2)*pitch))
        db[key.."Y"]=math.max(-4000,math.min(4000,db.y-db.mainSize/2-db.rowGap-db.burstSize/2))
    end
end
function ns.MigrateAuxiliary()
    if ns.db.auxiliaryLayoutVersion==1 then return end
    if not ns.scanComplete or ns.scanPending or ns.LayoutLockedByCombat() then return end
    ns.ArrangeAuxiliary(ns.db,ns.known,true);ns.db.auxiliaryLayoutVersion=1
end
function ns.LayoutGeometry(db,width,height,layout)
    layout=layout or ns.IconLayout(db,0)
    local w,h=layout.width,layout.height
    local scale=math.max(.001,math.min(1,(width-24)/w,(height-24)/h))
    local mx=(width-w*scale)/2-12
    local lo=-height/2+(h-db.mainSize/2)*scale+12
    local hi=height/2-db.mainSize*scale/2-12
    local x=mx>=0 and math.max(-mx,math.min(mx,db.x)) or 0
    local y=lo<=hi and math.max(lo,math.min(hi,db.y)) or layout.mainOffset*scale
    return x,y,scale,x/scale,y/scale-layout.mainOffset
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

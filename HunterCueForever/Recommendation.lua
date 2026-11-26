-- SPDX-License-Identifier: MIT
-- Own presentation policy, not a port of another addon's simulation engine.
local _,ns=...
local EPS=0.000001
local HORIZON=10
function ns.ClearRecommendation() ns.recommendationState={} end
ns.ClearRecommendation()
function ns.CopyRecommendationState()
    local out={}
    for k,v in pairs(ns.recommendationState) do
        if type(v)=="table" then local c={};for a,b in pairs(v) do c[a]=b end;out[k]=c
        else out[k]=v end
    end
    return out
end
local function Copy(out)
    return {key=out.key,reason=out.reason or "等待",move=out.move or ""}
end
local function Context(s)
    return table.concat({s.generation or 0,s.spec or "",s.mode or "",s.targets or 1,
        s.weave or "",s.traps and "1" or "0"},"|")
end
local function Valid(s,item,waiting)
    return item and s.spells[item.key] and s.spells[item.key].id==item.id and ns.ChoiceValid(s,item.key,waiting)
end
local function CorePreempts(s,item,out)
    if not item or out.key==item.key or not ns.ChoiceValid(s,out.key,false) then return false end
    return (s.spec=="bm" and item.key=="aimed" and (out.key=="hawk" or out.key=="arcane"))
        or (s.spec=="mm" and item.key=="aimed" and out.key=="arcane")
        or (s.spec=="mm" and item.key=="sniper" and (out.key=="aimed" or out.key=="arcane"))
end
function ns.FutureState(s,delay)
    local future={};for k,v in pairs(s) do future[k]=v end
    future.now=(s.now or 0)+delay;future.evaluateAt=future.now;future.spells={}
    for k,p in pairs(s.spells) do
        local q={};for field,value in pairs(p) do q[field]=value end
        if p.usable==true and p.oom~=true and not p.blocked and not p.syncing and p.remaining and p.remaining<=delay+EPS then q.ready=true end
        if p.remaining then q.remaining=math.max(0,p.remaining-delay) end
        future.spells[k]=q
    end
    if s.gcdRemaining then future.gcdRemaining=math.max(0,s.gcdRemaining-delay);future.gcd=s.gcd and future.gcdRemaining>EPS or false end
    if s.meleeDwell then future.meleeDwell=s.meleeDwell+delay end
    if s.sinceAuto then future.sinceAuto=s.sinceAuto+delay end
    if s.stingRemaining then future.stingRemaining=math.max(0,s.stingRemaining-delay) end
    return future
end
function ns.PlanWait(s,raw)
    if ns.ChoiceValid(s,raw.key,false) or not s.target or s.casting or s.melee==true then return nil end
    if s.scanBlocked then return nil end
    if s.ranged~=true and not (s.spec=="mm" and s.spells.sniper and s.spells.sniper.range==true) then return nil,"射程未确认，暂停空档预告" end
    if s.gcd and not s.gcdRemaining then return nil,"公共CD时间未知，无法比较未来技能" end
    local times={};local candidates,unknown,unique=0,0,nil
    for _,key in ipairs(ns.futureKeys) do
        local p=s.spells[key]
        if p and ns.ChoiceValid(s,key,true) then
            candidates=candidates+1;unique=key
            if p.remaining==nil then unknown=unknown+1
            elseif p.remaining>0 and p.remaining<=HORIZON then times[#times+1]=p.remaining end
        end
    end
    -- Unknown timers cannot be silently ranked behind known ones. Only one
    -- unambiguous eligible candidate can be previewed without a numeric ETA.
    if unknown>0 then
        local p=unique and s.spells[unique]
        if candidates==1 and p.ownActive==true then
            return {key=unique,id=p.id,wait=true,unknown=true,waitSource=not s.gcd and "own" or nil}
        end
        return nil,"候选冷却先后未知，暂停空档预告"
    end
    table.sort(times)
    for _,time in ipairs(times) do
        local horizon=math.max(time,s.gcd and s.gcdRemaining or 0)
        if horizon>HORIZON then return nil,"下一行动超出10秒预告窗口" end
        local future=ns.FutureState(s,horizon)
        local out=ns.Decide(future)
        local allowed=false;for _,key in ipairs(ns.futureKeys) do if key==out.key then allowed=true end end
        local p=out.key and s.spells[out.key]
        if allowed and p and p.remaining and p.remaining>0 and ns.ChoiceValid(s,out.key,true) then
            return {key=out.key,id=p.id,reason="等待技能 · 保持自动射击",wait=true,remaining=horizon,
                plannedAt=(s.now or 0)+horizon,move=raw.move or ""}
        end
    end
    return nil,"10秒内无满足当前条件的预告技能"
end
local function WaitingOutput(s,raw,item)
    local remaining=s.spells[item.key].remaining
    local planned=item.readyAt or item.plannedAt
    if planned then remaining=math.max(remaining or 0,planned-(s.now or 0)) end
    if remaining and s.gcdRemaining then remaining=math.max(remaining,s.gcdRemaining) end
    if item.unknown or (s.gcd and not s.gcdRemaining) then remaining=nil end
    return {key=item.key,reason="等待技能 · 保持自动射击",move=raw.move or "",wait=true,
        waitRemaining=remaining,waitSource=item.waitSource,unknown=item.unknown}
end
local function HeldOutput(s,raw,item)
    local move=raw.move or ""
    if s.spec=="sv" and ns.castTime[item.key] and s.ranged==true then move="保持远程位置，准备已固定技能" end
    return {key=item.key,reason=item.reason,move=move,locked=true}
end
-- A separate forecast while a cast is in flight; never changes live readiness.
function ns.ProjectCast(s)
    if not s.target or not s.casting or not s.castKey or not ns.castTime[s.castKey]
        or not s.castRemaining or s.castRemaining<=0 or s.castRemaining>HORIZON or not s.castStartedAt
        or not s.gcdKnown or (s.gcd and not s.gcdRemaining) then return nil end
    local horizon=math.max(s.castRemaining,s.gcd and s.gcdRemaining or 0)
    if horizon>HORIZON then return nil end
    local future=ns.FutureState(s,horizon)
    future.casting=false
    local current=s.spells[s.castKey]
    if s.mana then
        if not current or not current.cost then return nil end
        -- Reserve the in-flight cast's cost; do not assume it is already paid or
        -- that future regeneration will fund another spell.
        future.mana=math.max(0,s.mana-current.cost)
    end
    local excluded={[s.castKey]=true}
    for _,key in ipairs(ns.family[s.castKey] or {}) do excluded[key]=true end
    for key,p in pairs(s.spells) do
        local q=future.spells[key]
        if excluded[key] or (future.mana and (not p.cost or p.cost>future.mana)) then
            q.ready=false;q.usable=false;q.remaining=nil
        end
        future.spells[key]=q
    end
    return future,horizon
end
local function CastForecast(s,raw,m)
    m.item=nil;m.waiting=nil
    m.seen=true;m.serial=s.actionSerial;m.gcd=s.gcd;m.gcdStart=s.gcdStart
    m.settleAt=nil;m.spent=nil
    local future,horizon=ns.ProjectCast(s)
    if not future then m.castItem=nil;m.castSource=nil;m.castToken=nil;m.castStartedAt=nil;return Copy(raw) end
    local token=s.castID or s.castStartedAt
    if m.castSource~=s.castKey or m.castToken~=token then m.castItem=nil end
    m.castSource=s.castKey;m.castToken=token;m.castStartedAt=s.castStartedAt
    local item=m.castItem;local out=ns.Decide(future);local gap=ns.PlanWait(future,out)
    for _,key in ipairs(ns.futureKeys) do
        local p=future.spells[key]
        if p and p.ready~=true and p.remaining==nil and ns.ChoiceValid(future,key,true) then
            m.castItem=nil;return Copy(raw)
        end
    end
    local extra=0
    if not ns.ChoiceValid(future,out.key,false) then
        if not gap or gap.unknown or not gap.remaining or horizon+gap.remaining>HORIZON then m.castItem=nil;return Copy(raw) end
        out=gap;extra=gap.remaining
    end
    if s.stableRecommendations==false or not Valid(future,item,false) or CorePreempts(future,item,out) then
        local allowed=false
        for _,key in ipairs(ns.futureKeys) do if key==out.key then allowed=true end end
        item=allowed and ns.ChoiceValid(future,out.key,true) and {key=out.key,id=future.spells[out.key].id,reason=out.reason} or nil
    end
    m.castItem=item;m.seen=true;m.serial=s.actionSerial;m.gcd=s.gcd;m.gcdStart=s.gcdStart
    if not item then return Copy(raw) end
    -- An actually available cast-end choice wins over a previous postcast
    -- wait. Preserve a gap planner's full horizon, not just the own cooldown.
    if item.key~=out.key then extra=0 end
    if horizon+extra>HORIZON then m.castItem=nil;return Copy(raw) end
    return {key=item.key,wait=true,castPreview=true,waitRemaining=horizon+extra,reason="等待当前施法和技能冷却",move=""}
end
local function Recommend(s,raw,memo)
    local m=memo or ns.recommendationState;local now=s.now or 0
    local context=Context(s)
    if m.context~=context or s.stableRecommendations==false then
        for k in pairs(m) do m[k]=nil end;m.context=context
    end
    if s.casting then return CastForecast(s,raw,m) end
    local carry=m.castItem
    local completed=carry and s.lastActionKey==m.castSource and s.lastActionAt
        and m.castStartedAt and s.lastActionAt>=m.castStartedAt
        and now-s.lastActionAt>=0 and now-s.lastActionAt<=.3 and Valid(s,carry,false)
    m.castItem=nil;m.castSource=nil;m.castToken=nil;m.castStartedAt=nil
    if s.stableRecommendations==false then
        local future,why=ns.PlanWait(s,raw)
        if future then return WaitingOutput(s,raw,future) end
        local out=Copy(raw);if why then out.reason=why end;return out
    end
    local action=s.lastActionAt and (not m.seen or m.serial~=s.actionSerial)
    local recentBurst=s.lastBurstAt and now-s.lastBurstAt<0.3
    local newGCD=m.seen and s.gcd and not recentBurst and
        (not m.gcd or (s.gcdStart and m.gcdStart and s.gcdStart>m.gcdStart+0.05))
    if action or newGCD or completed then
        m.item=nil;m.waiting=nil
        m.settleAt=(action or completed) and s.lastActionAt or now
        m.spent=completed and carry.key or action and s.lastActionKey or nil
    end
    m.seen=true;m.serial=s.actionSerial;m.gcd=s.gcd;m.gcdStart=s.gcdStart
    if not s.target or s.casting then m.item=nil;m.waiting=nil;return Copy(raw) end
    local syncing=(m.settleAt and now-m.settleAt<0.2-EPS) or (s.selectionBlockedUntil and now<s.selectionBlockedUntil)
    if syncing then
        m.item=nil;m.waiting=nil
        local excluded={[s.lastActionKey or ""]=true}
        for _,k in ipairs(ns.family[s.lastActionKey] or {}) do excluded[k]=true end
        if raw.key and not excluded[raw.key] and ns.ChoiceValid(s,raw.key,false) then return Copy(raw) end
        local future=ns.PlanWait(s,{reason="同步中"})
        if future and not excluded[future.key] then return WaitingOutput(s,raw,future) end
        return {reason="正在确认下一技能…",move=""}
    end
    if CorePreempts(s,m.item,raw) then m.item=nil end
    if m.item and not Valid(s,m.item,false) then m.item=nil end
    if m.item then
        local item=m.item;local cap=item.at+2.5
        if s.gcd then
            item.sawGCD=true
            item.untilTime=math.min(cap,s.gcdRemaining and now+s.gcdRemaining+0.35 or cap)
        elseif item.sawGCD then item.sawGCD=false;item.untilTime=math.min(cap,now+0.35) end
        if now<item.untilTime-EPS and now<cap-EPS then return HeldOutput(s,raw,item) end
        m.item=nil
    end
    if ns.ChoiceValid(s,raw.key,false) then
        m.waiting=nil
        m.item={key=raw.key,id=s.spells[raw.key].id,reason=raw.reason,at=now,sawGCD=s.gcd,
            untilTime=now+(s.gcd and (s.gcdRemaining and math.min(2.5,s.gcdRemaining+0.35) or 2.5) or 0.35)}
        return HeldOutput(s,raw,m.item)
    end
    local future,why=ns.PlanWait(s,raw)
    if m.waiting then
        local item=m.waiting;local p=s.spells[item.key]
        local delay=p and p.remaining and math.max(p.remaining,s.gcdRemaining or 0)
        if future and future.key==item.key and not future.unknown and not item.unknown and Valid(s,item,true)
            and delay and delay>=0 and delay<=HORIZON and math.abs(future.plannedAt-item.readyAt)<=EPS
            and now<item.at+HORIZON+.1 and now+delay<=item.readyAt+0.15 then return WaitingOutput(s,raw,item) end
        m.waiting=nil
    end
    if future then
        future.at=now;future.readyAt=future.remaining and now+future.remaining;m.waiting=future
        return WaitingOutput(s,raw,future)
    end
    local out=Copy(raw);if why then out.reason=why end;return out
end
-- Conditional usability is used only in a cloned preview state. The adapter's
-- actual usable/ready facts and Engine's live predicates remain authoritative.
function ns.GCDPreviewState(s)
    if not s.gcd then return s end
    local out
    for key,p in pairs(s.spells) do
        if p.gcdPreview and not p.blocked and not p.syncing then
            if not out then out={};for k,v in pairs(s) do out[k]=v end;out.spells={};for k,v in pairs(s.spells) do out.spells[k]=v end end
            local q={};for k,v in pairs(p) do q[k]=v end
            q.usable=true;q.ready=true;out.spells[key]=q
        end
    end
    return out or s
end
function ns.Recommend(s,raw,memo)
    local preview=ns.GCDPreviewState(s)
    if preview~=s then raw=ns.Decide(preview) end
    local out=Recommend(preview,raw,memo)
    local p=out.key and s.spells[out.key]
    if p and out.key~="auto" then
        out.provisional=p.gcdPreview==true
        if not out.castPreview and (s.gcd or s.gcdKnown==false) then
            out.wait=true
            if s.gcd and s.gcdRemaining and p.remaining then out.waitRemaining=math.max(out.waitRemaining or 0,s.gcdRemaining,p.remaining)
            else out.waitRemaining=nil end
            out.waitSource=out.waitRemaining==nil and s.gcd and (p.ownClear==true or p.remaining==0) and "gcd" or nil
        end
        if out.provisional then out.wait=true end
    end
    return out
end

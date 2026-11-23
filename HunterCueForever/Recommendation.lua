-- SPDX-License-Identifier: MIT
-- Own presentation policy, not a port of another addon's simulation engine.
local _,ns=...
local EPS=0.000001
function ns.ClearRecommendation() ns.recommendationState={} end
ns.ClearRecommendation()
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
function ns.PlanWait(s,raw)
    if raw.key~="auto" or not s.target or s.casting or s.ranged~=true or s.melee==true then return nil end
    local times={}
    for _,key in ipairs(ns.futureKeys) do
        local p=s.spells[key]
        if p and p.usable==true and p.remaining and p.remaining>0 and p.remaining<=6 then times[#times+1]=p.remaining end
    end
    table.sort(times)
    for _,time in ipairs(times) do
        local future={};for k,v in pairs(s) do future[k]=v end;future.spells={}
        for k,p in pairs(s.spells) do
            local q={};for field,value in pairs(p) do q[field]=value end
            if p.usable==true and p.remaining and p.remaining<=time+EPS then q.ready=true end
            future.spells[k]=q
        end
        local out=ns.Decide(future)
        local allowed=false;for _,key in ipairs(ns.futureKeys) do if key==out.key then allowed=true end end
        local p=out.key and s.spells[out.key]
        if allowed and p and p.remaining and p.remaining>0 and ns.ChoiceValid(s,out.key,true) then
            return {key=out.key,id=p.id,reason="等待技能 · 保持自动射击",wait=true,remaining=p.remaining,move=raw.move or ""}
        end
    end
end
local function WaitingOutput(s,raw,item)
    return {key=item.key,reason="等待技能 · 保持自动射击",move=raw.move or "",wait=true,waitRemaining=s.spells[item.key].remaining}
end
local function HeldOutput(s,raw,item)
    local move=raw.move or ""
    if s.spec=="sv" and ns.castTime[item.key] and s.ranged==true then move="保持远程位置，准备已固定技能" end
    return {key=item.key,reason=item.reason,move=move,locked=true}
end
function ns.Recommend(s,raw,memo)
    local m=memo or ns.recommendationState;local now=s.now or 0
    local context=Context(s)
    if m.context~=context or s.stableRecommendations==false then
        for k in pairs(m) do m[k]=nil end;m.context=context
    end
    if s.stableRecommendations==false then
        local future=ns.PlanWait(s,raw)
        return future and WaitingOutput(s,raw,future) or Copy(raw)
    end
    local action=s.lastActionAt and (not m.seen or m.serial~=s.actionSerial)
    local recentBurst=s.lastBurstAt and now-s.lastBurstAt<0.3
    local newGCD=m.seen and s.gcd and not recentBurst and
        (not m.gcd or (s.gcdStart and m.gcdStart and s.gcdStart>m.gcdStart+0.05))
    if action or newGCD then
        m.item=nil;m.waiting=nil
        m.settleAt=action and s.lastActionAt or now;m.spent=action and s.lastActionKey or nil
    end
    m.seen=true;m.serial=s.actionSerial;m.gcd=s.gcd;m.gcdStart=s.gcdStart
    if not s.target or s.casting then m.item=nil;m.waiting=nil;return Copy(raw) end
    local syncing=(m.settleAt and now-m.settleAt<0.2-EPS) or (s.selectionBlockedUntil and now<s.selectionBlockedUntil)
    if syncing then
        m.item=nil;m.waiting=nil
        if s.gcd or not s.gcdKnown then
            return {key=m.spent,settling=true,reason=m.spent and "已施放 · 确认下一技能…" or "正在确认下一技能…",move=""}
        end
        -- Already free to act: show an eligible raw action without latching a
        -- transient fallback while cast-family state is still synchronizing.
        return Copy(raw)
    end
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
    if m.waiting then
        local item=m.waiting;local p=s.spells[item.key]
        if Valid(s,item,true) and p.remaining and p.remaining>0 and p.remaining<=6
            and now<item.at+6.1 and now+p.remaining<=item.readyAt+0.15 then return WaitingOutput(s,raw,item) end
        m.waiting=nil
    end
    local future=ns.PlanWait(s,raw)
    if future then
        future.at=now;future.readyAt=now+future.remaining;m.waiting=future
        return WaitingOutput(s,raw,future)
    end
    return Copy(raw)
end

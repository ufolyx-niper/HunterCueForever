-- SPDX-License-Identifier: MIT
-- Pure policy over sanitized snapshots. Selection, retention and prediction share these rules.
local _,ns=...
local EPS=0.000001
local function Ready(s,k,waiting)
    local p=s.spells[k]
    if not p or p.oom==true or p.blocked or p.syncing then return false end
    if waiting then if p.usable~=true then return false end
    elseif p.ready~=true then return false end
    if s.mana and p.cost and s.mana<p.cost then return false end
    if not ns.selfSpell[k] and p.range~=true then
        if not (k=="volley" and p.range==nil and s.ranged==true) then return false end
    end
    if ns.meleeSpell[k] and s.melee~=true then return false end
    local playerWillStop = s.spec=="mm" and k=="aimed"
    if ns.castTime[k] and not playerWillStop and s.moving~=false then return false end
    if k=="raptor" and p.queued~=false then return false end
    return true
end
function ns.ActionTime(s,k,waiting)
    if s.evaluateAt then return s.evaluateAt end
    if s.gcd and not s.gcdRemaining then return nil end
    local delay=s.gcd and s.gcdRemaining or 0
    local p=k and s.spells[k]
    if waiting and p and p.remaining then delay=math.max(delay,p.remaining) end
    return (s.now or 0)+delay
end
function ns.HawkCoverage(s,at)
    local count,earliest=0,nil
    for _,h in ipairs(s.hawks or {}) do
        if at and h.arrives<=at and h.expires>at then count=count+1;earliest=math.min(earliest or h.expires,h.expires) end
    end
    return count==2,earliest,count -- diagnostics only, never cadence eligibility
end
local function Core(s)
    if s.targets>=6 and s.spells.volley then return "volley" end
    if s.targets>=3 and s.spells.multi then return "multi" end
    if s.spec=="bm" and s.spells.hawk then return s.hawkPhase==2 and "arcane" or "hawk" end
    if s.spec=="sv" and s.weave~="aggressive" and s.spells.aimed then return "aimed" end
    return "arcane"
end
local function Spend(s,k,floor,waiting)
    if s.mode=="burst" or not s.mana or not s.maxMana or s.maxMana<=0 then return true end
    if s.mana/s.maxMana*100<floor then return false end
    local p=s.spells[k];if not p.cost then return true end
    local delay=math.max(0,(ns.ActionTime(s,k,waiting) or (s.now or 0))-(s.now or 0))
    local coreKey=Core(s);local core=s.spells[coreKey]
    local reserve=coreKey~=k and core and core.cost or 0
    if s.spec=="bm" and s.spells.hawk and s.hawkPhase==nil then
        reserve=math.max(s.spells.hawk.cost or 0,s.spells.arcane and s.spells.arcane.cost or 0)
    end
    local sting=s.spells.sting
    if s.stingEnabled~=false and sting and sting.cost and
        (s.sting~=true or s.stingEstimated or not s.stingRemaining or s.stingRemaining<=delay+2) then
        reserve=reserve+sting.cost
    end
    local recovery=0
    if core and core.remaining and s.regen then
        recovery=math.max(0,s.regen)*math.min(2,math.max(0,core.remaining-delay))
    end
    return s.mana-p.cost+recovery>=reserve
end
function ns.PolicyAllows(s,k,waiting)
    if ns.meleeSpell[k] then
        if s.spec~="sv" or (s.meleeDwell and s.meleeDwell>1.5) then return false end
        return (k~="immolation" and k~="explosive") or (s.traps==true and s.mode~="conserve")
    end
    local conserve=s.mode=="conserve";local floor=0
    if k=="multi" or k=="volley" then
        if s.targets<3 then return false end
        floor=conserve and 25 or 0
    elseif k=="hawk" then
        if s.spec~="bm" then return false end
        if s.hawkUnknown or s.hawkPhase==nil or (s.hawkPhase==2 and (s.spells.arcane or s.arcaneUnknown)) then return false end
        floor=conserve and 30 or 0
    elseif k=="arcane" then
        if s.spec=="bm" then
            if s.hawkUnknown or (s.spells.hawk and s.hawkPhase~=2) then return false end
            floor=conserve and 30 or 0
        else
            if s.spec=="generic" and (s.spells.hawk or s.hawkUnknown) then return false end
            floor=conserve and 15 or 0
        end
        if s.spec=="sv" and s.weave~="aggressive" then
            local a=s.spells.aimed
            if a and (Ready(s,"aimed",false) or Ready(s,"aimed",true)) and ns.PolicyAllows(s,"aimed",waiting) then
                local remaining=a.remaining or (a.ready and 0)
                local at=ns.ActionTime(s,k,waiting)
                if remaining and at and remaining-(at-(s.now or 0))<=.5+EPS then return false end
            end
        end
    elseif k=="aimed" then
        if (s.spec=="bm" or s.spec=="mm") and conserve then return false end
        if s.spec=="sv" then
            if s.weave=="aggressive" then return false end
            floor=conserve and 15 or 0
        else floor=20 end
    elseif k=="sniper" then
        if s.spec~="mm" or s.mmSniper==false then return false end
        floor=conserve and 15 or 0
    else return false end
    return Spend(s,k,floor,waiting)
end
function ns.ChoiceValid(s,k,waiting)
    if s.scanBlocked or not s.target or s.casting or not k or not Ready(s,k,waiting) then return false end
    if waiting and not ns.ActionTime(s,k,true) then return false end
    return ns.PolicyAllows(s,k,waiting)
end
function ns.BurstReady(s)
    local ready={}
    if s.scanBlocked or not s.cooldowns or s.playerAlive~=true then return ready end
    for _,key in ipairs(ns.burstOrder) do
        local p=s.spells and s.spells[key]
        if s[ns.burstOption[key]]~=false and p and p.burstReady==true and (key~="wrath" or s.pet==true) then ready[key]=true end
    end
    return ready
end
function ns.MarkReminderReady(s)
    local p=s.spells and s.spells.mark
    if s.markReminder=="off" or not s.markReminder or not s.target or s.playerAlive~=true then return false end
    if not p or p.burstReady~=true or p.range~=true then return false end
    if s.mark~=false or s.markEstimated or s.markPending or s.markBackoff then return false end
    if not s.markInCombat and (s.inCombat~=false or s.targetInCombat~=false) then return false end
    if s.markReminder=="priority" then
        return s.classification=="elite" or s.classification=="rareelite" or s.classification=="worldboss"
    end
    return s.markReminder=="all"
end
function ns.Decide(s)
    local out={reason="等待可用技能",move=""}
    if s.scanBlocked then out.reason="正在确认天赋与技能";return out end
    if not s.target then out.reason="选择存活的敌对目标";return out end
    if s.casting then out.reason="施法/引导中 · 不要打断";return out end
    local function Pick(k,reason)
        if ns.ChoiceValid(s,k,false) then out.key=k;out.reason=reason;return true end
        return false
    end
    if s.spec~="sv" and s.melee==true and s.ranged==false then out.move="拉开距离，回到远程射程" end
    if s.melee==false and s.ranged==false and not (s.spec=="mm" and s.spells.sniper and s.spells.sniper.range==true) then out.reason="调整到技能射程";out.move="死区或距离过远：核对位置";return out end
    if s.spec=="sv" and s.melee==true then
        local queued=s.spells.raptor and s.spells.raptor.queued
        if s.meleeDwell and s.meleeDwell>1.5 then
            out.move=queued==true and "猛禽已排队：完成挥击再回远程" or "回到远程 · 准备下一次自动射击"
            return out
        end
        out.move=queued==true and "猛禽已排队：完成挥击再回远程" or "近战一击后回远程（走位由你控制）"
        if Pick("mongoose","消耗猫鼬触发") or Pick("raptor","近战窗口") or Pick("strider","近战窗口") then return out end
        if Pick(s.targets>1 and "explosive" or "immolation","近战陷阱（已手动允许）") then return out end
        out.reason="完成近战挥击后撤出";return out
    end
    if s.spec=="sv" then
        out.move="手动穿插：射击后接近，近战一击后撤出"
        if s.ranged~=true or s.melee==nil then out.move="射程未知：手动判断穿插" end
        local a,c=s.spells.aimed,s.spells.arcane
        if s.ranged==true and s.sinceAuto and s.sinceAuto>=0 and s.sinceAuto<.8
            and a and a.remaining and a.remaining>1.5 and c and c.remaining and c.remaining>1.5 then
            out.move="自动射击已出手 · 可进近战打一轮"
        end
    end
    if s.targets>=3 then
        local order=s.targets>=6 and {"volley","multi"} or {"multi","volley"}
        for _,k in ipairs(order) do if Pick(k,"群体优先 · 注意控场目标") then return out end end
    end
    if s.spec=="bm" then
        if Pick("arcane","两鹰一奥术 · 奥术阶段") or Pick("hawk","两鹰一奥术 · 雄鹰阶段")
            or Pick("aimed","瞄准填充") then return out end
    elseif s.spec=="mm" then
        if Pick("arcane","奥术优先") or Pick("aimed","瞄准射击") or Pick("sniper","狙击填充") then return out end
    elseif s.spec=="generic" then
        if Pick("arcane","专精待确认 · 通用远程") or Pick("aimed","专精待确认 · 瞄准") then return out end
    elseif s.spec=="sv" then
        if Pick("aimed","常规穿插 · 瞄准窗口") or Pick("arcane","远程瞬发窗口") or Pick("multi","积极穿插 · 多重窗口") then return out end
    end
    if not s.readiness then out.reason="技能状态不可读 · 手动按参考条输出"
    elseif s.ranged==true then out.key=s.spells.auto and "auto" or nil;out.reason="自动射击 / 等待回蓝或冷却"
    elseif s.ranged==nil then out.reason="射程未知 · 核对目标位置"
    elseif s.melee==true and s.spec~="sv" then out.reason="拉开到远程射程" end
    return out
end

-- SPDX-License-Identifier: MIT
-- Pure policy: receives ONLY sanitized data. No game API access in this file.
local _, ns = ...
local function Ready(s,k)
    local p=s.spells[k]
    if not p or p.ready~=true then return false end
    -- Volley targets a location, so the API can legitimately return nil.
    -- A positive ranged-shot probe is a conservative target-distance check;
    -- the player still chooses the ground location. Explicit false is never overridden.
    if not ns.selfSpell[k] and p.range~=true then
        if not (k=="volley" and p.range==nil and s.ranged==true) then return false end
    end
    if ns.meleeSpell[k] and s.melee~=true then return false end
    if ns.castTime[k] and s.moving~=false then return false end
    if k=="raptor" and p.queued~=false then return false end
    return true
end
local function Spend(s,k,floor,core)
    if s.mode=="burst" or not s.mana or not s.maxMana or s.maxMana<=0 then return true end
    if s.mana/s.maxMana*100 < floor then return false end
    local p=s.spells[k];local reserve=core and s.spells[core]
    if p and p.cost and reserve and reserve.cost and s.regen then
        return s.mana-p.cost+s.regen*2 >= reserve.cost
    end
    return true
end
function ns.Decide(s)
    local out={reason="等待可用技能",move=""}
    if not s.target then out.reason="选择存活的敌对目标";return out end
    if s.casting then out.reason="施法/引导中 · 不要打断";return out end
    if s.spec~="sv" and s.melee==true and s.ranged==false then out.move="拉开距离，回到远程射程" end
    if s.cooldowns then
        if s.spec=="bm" and s.pet and Ready(s,"wrath") then out.burst="wrath"
        elseif s.ranged==true and Ready(s,"rapid") then out.burst="rapid" end
    end
    local function Pick(k,reason)
        if Ready(s,k) then out.key=k;out.reason=reason;return true end
        return false
    end
    -- Unknown auras are NOT absence. Separate indicators remain visible.
    if s.mark==false and not s.markBackoff and Pick("mark","补猎人印记") then return out end
    if s.sting==false and not s.stingBackoff and Pick("sting",s.stingEstimated and "钉刺估时到期 · 核对目标" or "补毒蛇钉刺") then return out end
    if s.melee==false and s.ranged==false then
        out.reason="调整到技能射程";out.move="死区或距离过远：核对位置";return out
    end
    if s.spec=="sv" and s.melee==true then
        if s.meleeDwell and s.meleeDwell>1.5 and (not s.spells.raptor or s.spells.raptor.queued==false) then
            out.move="回到远程 · 准备下一次自动射击";return out
        end
        out.move="近战一击后回远程（走位由你控制）"
        if s.spells.raptor and s.spells.raptor.queued then out.move="猛禽已排队：完成挥击再回远程" end
        if Pick("mongoose","消耗猫鼬触发") or Pick("raptor","近战窗口") or Pick("strider","近战窗口") then return out end
        if s.traps and s.mode~="conserve" and Pick(s.targets>1 and "explosive" or "immolation","近战陷阱（已手动允许）") then return out end
        out.reason="完成近战挥击后撤出";return out
    end
    if s.spec=="sv" then
        out.move="手动穿插：射击后接近，近战一击后撤出"
        if s.ranged~=true or s.melee==nil then out.move="射程未知：手动判断穿插" end
        local a=s.spells.aimed;local c=s.spells.arcane
        if s.ranged==true and s.sinceAuto and s.sinceAuto>=0 and s.sinceAuto<0.8
            and a and a.remaining and a.remaining>1.5 and c and c.remaining and c.remaining>1.5 then
            out.move="自动射击已出手 · 可进近战打一轮"
        end
    end
    if s.targets>=3 then
        local order=s.targets>=6 and {"volley","multi"} or {"multi","volley"}
        for _,k in ipairs(order) do
            if (s.mode~="conserve" or Spend(s,k,25,"sting")) and Pick(k,"群体优先 · 注意控场目标") then return out end
        end
    end
    if s.spec=="bm" then
        local conserve=s.mode=="conserve"
        if Spend(s,"hawk",conserve and 30 or 0,"sting") then
            -- If Arcane is unavailable, use Hawk; never stall on an unlearned cycle step.
            if (s.hawkCount or 0)>=2 and Pick("arcane","两次雄鹰后穿插奥术") then return out end
            if Pick("hawk","召唤雄鹰") then return out end
            if not s.spells.hawk and Pick("arcane","尚未学会雄鹰 · 奥术填充") then return out end
        end
        if not conserve and Spend(s,"aimed",20,"hawk") and Pick("aimed","瞄准填充") then return out end
    elseif s.spec=="mm" then
        local conserve=s.mode=="conserve"
        if Spend(s,"arcane",conserve and 15 or 0,"sting") and Pick("arcane","奥术优先") then return out end
        if not conserve and Spend(s,"aimed",20,"sting") and Pick("aimed","瞄准射击") then return out end
        if Spend(s,"sniper",conserve and 15 or 0,"sting") and Pick("sniper","狙击填充") then return out end
    else
        local aggressive=s.weave=="aggressive"
        if not aggressive and Spend(s,"aimed",s.mode=="conserve" and 15 or 0,"sting") and Pick("aimed","常规穿插 · 瞄准窗口") then return out end
        if Spend(s,"arcane",s.mode=="conserve" and 15 or 0,"sting") and Pick("arcane","远程瞬发窗口") then return out end
        if aggressive and s.mode~="conserve" and Pick("multi","积极穿插 · 多重窗口") then return out end
    end
    if not s.readiness then out.reason="技能状态不可读 · 手动按参考条输出"
    elseif s.ranged==true then
        out.key=s.spells.auto and "auto" or nil
        out.reason=s.moving and "停步自动射击" or "自动射击 / 等待回蓝或冷却"
    elseif s.ranged==nil then out.reason="射程未知 · 核对目标位置"
    elseif s.melee==true and s.spec~="sv" then out.reason="拉开到远程射程" end
    return out
end

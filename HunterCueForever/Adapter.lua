-- SPDX-License-Identifier: MIT
-- All game-state reads and event payloads terminate in this guarded adapter.
local _, ns = ...
function ns.Clean(v)
    if issecretvalue and issecretvalue(v) then return nil,false end
    return v,true
end
local function Call(fn,...)
    if type(fn)~="function" then return nil,false end
    local ok,v=pcall(fn,...)
    if not ok then return nil,false end
    return ns.Clean(v)
end
local function Pair(fn,...)
    if type(fn)~="function" then return nil,nil,false end
    local ok,a,b=pcall(fn,...)
    if not ok then return nil,nil,false end
    local av,ar=ns.Clean(a);local bv,br=ns.Clean(b)
    return av,bv,ar and br
end
local function Field(t,k)
    local v,readable=ns.Clean(t)
    if not readable or type(v)~="table" then return nil,false end
    return Call(function() return v[k] end)
end
local function Num(v)
    if type(v)=="number" and v==v and math.abs(v)<1e15 then return v end
end
local function Now() return Call(GetTime) or 0 end
local function CastInfo(now)
    if type(UnitCastingInfo)~="function" then return nil,false end
    local ok,name,_,_,started,ends,_,castID,_,spellID=pcall(UnitCastingInfo,"player")
    if not ok then return nil,false end
    local readable;name,readable=ns.Clean(name)
    if not readable then return nil,false end
    started=Num(ns.Clean(started));ends=Num(ns.Clean(ends));spellID=Num(ns.Clean(spellID))
    castID=ns.Clean(castID)
    if type(castID)~="string" and type(castID)~="number" then castID=nil end
    local key=spellID and ns.byID[spellID]
    if type(name)=="string" and started and ends and started<=ends and started/1000<=now
        and ends/1000>now and ends/1000-now<=6 and key and ns.castTime[key] then
        return name,true,key,ends/1000-now,started/1000,castID
    end
    return name,true
end
local function SpellAPI(name,...)
    return Call(C_Spell and C_Spell[name],...)
end
ns.known={};ns.cooldownCache={};ns.fences={};ns.pending={};ns.inferred={};ns.attempts={};ns.generation=0
function ns.ResetTracking()
    ns.cooldownCache={};ns.fences={};ns.pending={};ns.inferred={};ns.attempts={}
    ns.hawkCount=0;ns.lastHawk=nil;ns.lastAuto=nil;ns.meleeSince=nil;ns.lastError=nil;ns.generation=ns.generation+1
    ns.actionSerial=(ns.actionSerial or 0)+1;ns.lastActionAt=nil;ns.lastActionKey=nil;ns.lastBurstAt=nil
    if ns.ClearRecommendation then ns.ClearRecommendation() end
end
function ns.ScanSpells()
    if Call(InCombatLockdown)==true then ns.scanPending=true;ns.scanComplete=false;return end
    ns.known={};ns.ids={}
    local readable=true
    for key,ranks in pairs(ns.spells) do
        local learned={}
        for _,id in ipairs(ranks) do
            local yes,ok=Call(IsPlayerSpell,id)
            if not ok then yes=Call(C_SpellBook and C_SpellBook.IsSpellKnown,id) end
            if type(yes)~="boolean" then readable=false end
            if yes==true then learned[id]=true end
        end
        local id=ns.SelectRank(ranks,learned)
        if id then ns.known[key]=id;ns.ids[id]=key end
    end
    ns.scanPending=false;ns.scanComplete=readable and next(ns.known)~=nil;ns.ResetTracking()
    if ns.ApplyUI then ns.ApplyUI() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end
function ns.Profile()
    if ns.db.spec~="auto" then return ns.db.spec end
    if ns.known.wrath then return "bm" end
    if ns.known.strider then return "sv" end
    if ns.known.sniper then return "mm" end
    return "bm" -- basic leveling profile; unavailable talents are always filtered.
end
local function Cooldown(id)
    local info,ok=SpellAPI("GetSpellCooldown",id)
    if not ok or type(info)~="table" then return {} end
    local rate,readable=Field(info,"modRate")
    if readable and rate==nil then rate=1 end -- compatibility for APIs without this field
    return {active=Field(info,"isActive"),enabled=Field(info,"isEnabled"),rate=Num(rate),
        start=Num(Field(info,"startTime")),duration=Num(Field(info,"duration"))}
end
local function Remaining(cd,now)
    if cd.enabled~=true then return nil end
    if cd.active==false then return 0 end
    if cd.active==true and cd.start and cd.duration and cd.rate==1 then return math.max(0,cd.start+cd.duration-now) end
end
-- The isOnGCD flag is sampled only from its documented event context.
function ns.CooldownEvent()
    local now=Now()
    for key,id in pairs(ns.known) do
        local info=SpellAPI("GetSpellCooldown",id)
        ns.cooldownCache[key]={id=id,stamp=now,gcd=Field(info,"isOnGCD")}
    end
end
local function Availability(key,id,gcd,now)
    local usable,oom,ok=Pair(C_Spell and C_Spell.IsSpellUsable,id)
    if not ok then return nil,nil,nil,nil,nil end
    if usable~=true or oom==true then return false,nil,oom,usable,false end
    if ns.fences[key] and now<ns.fences[key] then return false,nil,oom,usable,false end
    local cd=Cooldown(id);local remaining=Remaining(cd,now)
    if cd.enabled==false then return false,remaining,oom,usable,false end
    if cd.enabled~=true then return nil,remaining,oom,usable,nil end
    if cd.active==false then return true,0,oom,usable,true end
    if cd.active~=true then return nil,remaining,oom,usable,nil end
    local gcdOnly=false
    if gcd.active==true then
        if cd.start and cd.duration and cd.rate and gcd.start and gcd.duration and gcd.rate then
            gcdOnly=cd.start==gcd.start and cd.duration==gcd.duration and cd.rate==gcd.rate
        else
            local cache=ns.cooldownCache[key]
            gcdOnly=cache and cache.id==id and now-cache.stamp<=2 and cache.gcd==true or false
        end
    end
    local gcdRemaining=Remaining(gcd,now)
    -- Forecast applies ONLY to the main next action, never to the burst row.
    local future=gcd.active==true and remaining and gcdRemaining and remaining<=gcdRemaining+0.001
    return gcdOnly or future or false,remaining,oom,usable,gcdOnly
end
local function Cost(id)
    local costs=SpellAPI("GetSpellPowerCost",id)
    if type(costs)~="table" then return nil end
    for i=1,8 do
        local row=Field(costs,i)
        if not row then break end
        if Field(row,"type")==0 then return Num(Field(row,"cost")) end
    end
end
local function Aura(key)
    if Call(C_Secrets and C_Secrets.ShouldAurasBeSecret)==true then return nil end
    local unknown=false
    for i=1,40 do
        local a,ok=Call(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex,"target",i,
            key=="mark" and "HARMFUL" or "HARMFUL|PLAYER")
        if not ok then return nil end
        if a==nil then if unknown then return nil end;return false end
        local id,readable=Field(a,"spellId")
        if not readable then unknown=true
        elseif id and ns.byID[id]==key then return true end
    end
    return nil -- bounded/partial enumeration cannot prove absence.
end
local function TargetIdentity()
    local guid=Call(UnitGUID,"target")
    local name,realm=Pair(UnitName,"target")
    if type(guid)~="string" or type(name)~="string" then return nil end
    return {guid=guid,name=name,full=type(realm)=="string" and realm~="" and name.."-"..realm or name}
end
function ns.TargetChanged()
    ns.generation=ns.generation+1;ns.inferred={};ns.pending={};ns.attempts={};ns.meleeSince=nil;ns.lastAuto=nil
    if ns.ClearRecommendation then ns.ClearRecommendation() end
end
function ns.Sent(unit,targetName,guid,id)
    unit=ns.Clean(unit);targetName=ns.Clean(targetName);guid=ns.Clean(guid);id=ns.Clean(id)
    if unit~="player" or type(guid)~="string" or type(id)~="number" then return end
    local key=ns.byID[id]
    if key~="mark" and key~="sting" then return end
    local target=TargetIdentity()
    if not target or (targetName~=target.name and targetName~=target.full) then return end
    for _,token in ipairs({"mouseover","focus"}) do
        local otherName=Call(UnitName,token);local otherGUID=Call(UnitGUID,token)
        if otherName==target.name and otherGUID and otherGUID~=target.guid then return end
    end
    ns.pending[guid]={key=key,target=target.guid,generation=ns.generation,at=Now()}
    local n=0;for k,v in pairs(ns.pending) do
        n=n+1;if Now()-v.at>10 or n>16 then ns.pending[k]=nil end
    end
end
function ns.Succeeded(unit,guid,id)
    unit=ns.Clean(unit);guid=ns.Clean(guid);id=ns.Clean(id)
    if unit~="player" or type(id)~="number" then return end
    local key=ns.byID[id];if not key then return end
    local now=Now()
    local isBurst=ns.burstOption[key]~=nil
    for _,k in ipairs(ns.family[key] or {key}) do ns.cooldownCache[k]=nil;ns.fences[k]=now+(isBurst and 1 or 0.25) end
    if isBurst then ns.lastBurstAt=now
    elseif key~="auto" then
        ns.actionSerial=(ns.actionSerial or 0)+1;ns.lastActionAt=now
        ns.lastActionKey=(key~="mark" and key~="sting") and key or nil -- Independent monitors never occupy the spent main icon.
    end
    if key=="hawk" then ns.hawkCount=math.min(2,(ns.hawkCount or 0)+1);ns.lastHawk=now
    elseif key=="arcane" then ns.hawkCount=0
    elseif key=="auto" then ns.lastAuto=now end
    if type(guid)~="string" then return end
    local sent=ns.pending[guid];ns.pending[guid]=nil
    if not sent or sent.key~=key or sent.generation~=ns.generation or now-sent.at>10 then return end
    local target=TargetIdentity()
    if target and target.guid==sent.target then
        ns.inferred[key]={expires=now+(key=="sting" and 15 or 120),target=target.guid,generation=ns.generation}
        local previous=ns.attempts[key]
        ns.attempts[key]={at=now,failures=previous and previous.failures or 0,
            pauseUntil=previous and previous.pauseUntil or 0,checked=false}
    end
end
local function AuraState(key,now)
    local active=Aura(key)
    local attempt=ns.attempts[key]
    if active==true then ns.attempts[key]=nil;return true,false,false end
    if active==false and attempt then
        if not attempt.checked and now-attempt.at>=2 then
            attempt.checked=true;attempt.failures=math.min(2,attempt.failures+1)
            if attempt.failures>=2 then attempt.pauseUntil=now+20 end
        end
        return false,false,now<attempt.pauseUntil
    end
    if active~=nil then return active,false,false end
    local estimate=ns.inferred[key];local target=TargetIdentity()
    if estimate and target and target.guid==estimate.target and estimate.generation==ns.generation then
        return now<estimate.expires,true
    end
    return nil,false
end
function ns.Snapshot()
    local now=Now();local db=ns.db
    -- Reset the sequence after a long interruption; this is not an active-hawk count.
    if ns.lastHawk and now-ns.lastHawk>18 then ns.hawkCount=0;ns.lastHawk=nil end
    local s={now=now,spells={},spec=ns.Profile(),mode=db.mode,targets=db.targets,
        cooldowns=db.cooldowns,traps=db.traps,weave=db.weave,hawkCount=ns.hawkCount or 0,readiness=false}
    s.generation=ns.generation;s.actionSerial=ns.actionSerial or 0
    s.lastActionAt=ns.lastActionAt;s.lastActionKey=ns.lastActionKey;s.lastBurstAt=ns.lastBurstAt
    s.selectionBlockedUntil=now
    for key,untilTime in pairs(ns.fences) do
        if key~="auto" and not ns.burstOption[key] and ns.known[key] and untilTime>s.selectionBlockedUntil then
            s.selectionBlockedUntil=untilTime
        end
    end
    s.stableRecommendations=db.stableRecommendations
    s.burstRacial=db.burstRacial;s.burstRapid=db.burstRapid;s.burstWrath=db.burstWrath
    s.markReminder=db.markReminder;s.markInCombat=db.markInCombat
    s.classification=Call(UnitClassification,"target");s.targetInCombat=Call(UnitAffectingCombat,"target")
    s.inCombat=ns.enteringCombat==true or Call(InCombatLockdown)==true
    s.playerAlive=Call(UnitIsDeadOrGhost,"player")==false
    s.target=Call(UnitExists,"target")==true and Call(UnitCanAttack,"player","target")==true
        and Call(UnitIsDeadOrGhost,"target")==false and Call(UnitIsPlayer,"target")==false
        and s.playerAlive
    local cast,castOK,castKey,castRemaining,castStartedAt,castID=CastInfo(now)
    local channel,channelOK=Call(UnitChannelInfo,"player")
    s.casting=not castOK or not channelOK or cast~=nil or channel~=nil
    if channelOK and channel==nil and castOK then
        s.castKey=castKey;s.castRemaining=castRemaining;s.castStartedAt=castStartedAt;s.castID=castID
    end
    local speed=Num(Call(GetUnitSpeed,"player"));if speed then s.moving=speed>0 end
    s.mana=Num(Call(UnitPower,"player",0));s.maxMana=Num(Call(UnitPowerMax,"player",0))
    local _,regen=Pair(GetManaRegen);s.regen=Num(regen)
    s.pet=Call(UnitExists,"pet")==true and Call(UnitIsDeadOrGhost,"pet")==false
    local gcd=Cooldown(61304)
    s.gcd=gcd.active==true;s.gcdKnown=gcd.active~=nil;s.gcdStart=gcd.start;s.gcdRemaining=Remaining(gcd,now)
    for key,id in pairs(ns.known) do
        local ready,remaining,oom,usable,burstReady=Availability(key,id,gcd,now)
        local range=SpellAPI("IsSpellInRange",id,"target")
        s.spells[key]={id=id,ready=ready,remaining=remaining,oom=oom,range=range,usable=usable,burstReady=burstReady,
            queued=Call(IsCurrentSpell,id),cost=Cost(id)}
        if key~="auto" and ready~=nil then s.readiness=true end
    end
    local melee=s.spells.raptor or s.spells.mongoose or s.spells.strider
    local ranged=s.spells.arcane or s.spells.auto
    s.melee=melee and melee.range;s.ranged=ranged and ranged.range
    if s.melee==true then ns.meleeSince=ns.meleeSince or now;s.meleeDwell=now-ns.meleeSince
    else ns.meleeSince=nil end
    s.sinceAuto=ns.lastAuto and now-ns.lastAuto
    s.mark,s.markEstimated,s.markBackoff=AuraState("mark",now)
    s.sting,s.stingEstimated,s.stingBackoff=AuraState("sting",now)
    s.markPending=ns.attempts.mark~=nil and now-ns.attempts.mark.at<2
    s.stingPending=ns.attempts.sting~=nil and now-ns.attempts.sting.at<2
    return s
end
function ns.SpellName(key)
    local id=ns.known[key] or (ns.spells[key] and ns.spells[key][1])
    return (id and SpellAPI("GetSpellName",id)) or key or "等待"
end
function ns.SpellIcon(key)
    local id=ns.known[key] or (ns.spells[key] and ns.spells[key][1])
    return (id and SpellAPI("GetSpellTexture",id)) or 134400
end
function ns.DrawCooldown(frame,key)
    local id=key and ns.known[key]
    if id and C_Spell and C_Spell.GetSpellCooldownDuration and frame.SetCooldownFromDurationObject then
        local object=SpellAPI("GetSpellCooldownDuration",id,false)
        if object then
            local ok=pcall(frame.SetCooldownFromDurationObject,frame,object)
            if ok then return end
        end
    end
    frame:Clear()
end
function ns.SavePosition(x,y)
    ns.db.x=x;ns.db.y=y
end
function ns.LayoutLockedByCombat() return ns.enteringCombat==true or Call(InCombatLockdown)~=false end
local function Say(text) print("|cff75c9ffHunterCue:|r "..text) end
function ns.Command(message)
    if not ns.db then Say("需要 Forever 客户端上的猎人角色。");return end
    local cmd,arg=message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd=="" or cmd=="config" or cmd=="options" then
        if ns.LayoutLockedByCombat() then Say("请脱战后打开设置。");return end
        if ns.OpenOptions then ns.OpenOptions() end;return
    elseif cmd=="spec" and ns.specNames[arg] then ns.db.spec=arg;ns.ResetTracking()
    elseif cmd=="mode" and arg=="next" then
        ns.db.mode=({balanced="conserve",conserve="burst",burst="balanced"})[ns.db.mode]
    elseif cmd=="targets" and arg=="next" then ns.db.targets=({[1]=3,[3]=6,[6]=1})[ns.db.targets]
    elseif cmd=="mode" and ns.modeNames[arg] then ns.db.mode=arg
    elseif cmd=="targets" and (arg=="1" or arg=="3" or arg=="6") then ns.db.targets=tonumber(arg)
    elseif cmd=="weave" and (arg=="normal" or arg=="aggressive") then ns.db.weave=arg;ns.ResetTracking()
    elseif (cmd=="burst" or cmd=="traps") and (arg=="on" or arg=="off") then
        ns.db[cmd=="burst" and "cooldowns" or "traps"]=arg=="on"
    elseif cmd=="stable" and (arg=="on" or arg=="off") then ns.db.stableRecommendations=arg=="on"
    elseif cmd=="show" then ns.db.enabled=true
    elseif cmd=="hide" then ns.db.enabled=false
    elseif cmd=="lock" then
        if ns.LayoutLockedByCombat() then Say("请脱战后调整布局。");return end
        ns.db.locked=not ns.db.locked
    elseif cmd=="reset" then
        if ns.LayoutLockedByCombat() then Say("请脱战后重置。");return end
        ns.OpenOptions();ns.resetArmed=true;ns.RefreshOptions();return
    elseif cmd=="scale" then
        Say("请用 /hcf 设置里的主图标/爆发图标大小，现已独立调整。");return
    elseif cmd=="pos" then
        local x,y=arg:match("^([+-]?%d+)%s+([+-]?%d+)$")
        if not ns.LayoutLockedByCombat() and x and y and math.abs(tonumber(x))<=4000 and math.abs(tonumber(y))<=4000 then ns.SavePosition(tonumber(x),tonumber(y)) end
    elseif cmd=="status" then
        local s=ns.Snapshot();local count=0;for _ in pairs(ns.known) do count=count+1 end
        Say(ns.version.." / "..s.spec.." / "..s.mode.." / 已学技能组 "..count)
        Say("蓝量:"..(s.mana and "可读" or "受限").." 回蓝:"..(s.regen and "可读" or "受限")
            .." 技能状态:"..(s.readiness and "可读" or "不可读").." 射程:"..(s.ranged==nil and "未知" or "可读")
            .." 钉刺:"..(s.sting==nil and "未知" or s.stingEstimated and "估算" or "可读"))
        if #ns.missingEvents>0 then Say("未注册事件："..table.concat(ns.missingEvents,", ")) end
        if ns.lastError then Say("最近一次状态/界面更新失败；请 /reload 后再次检查。");end
        return
    else
        Say("/hcf 打开设置；/hcf spec auto|bm|mm|sv · mode balanced|conserve|burst · targets 1|3|6")
        Say("/hcf weave normal|aggressive · burst on|off · traps on|off · show|hide|lock|reset|status · pos x y")
        Say("/hcf config 打开设置并独立调整图标大小/间距 · /hcf help 查看命令")
        Say("/hcf stable on|off 固定推荐 · /hcf targets next 或 /hcf mode next 战斗中切换")
        return
    end
    if ns.ApplyUI then ns.ApplyUI() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end
local events=CreateFrame("Frame")
ns.events=events
ns.missingEvents={}
local function Register(method,event,...)
    local ok=pcall(method,events,event,...)
    if not ok then ns.missingEvents[#ns.missingEvents+1]=event end
end
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","PLAYER_TARGET_CHANGED","PLAYER_DEAD",
    "SPELLS_CHANGED","PLAYER_TALENT_UPDATE","CHARACTER_POINTS_CHANGED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED",
    "UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED","SPELL_UPDATE_COOLDOWN"}) do Register(events.RegisterEvent,event) end
Register(events.RegisterUnitEvent,"UNIT_SPELLCAST_SENT","player")
Register(events.RegisterUnitEvent,"UNIT_SPELLCAST_SUCCEEDED","player")
local function Event(_,event,...)
    -- Event name is also sanitized before use, just like event payloads.
    event=ns.Clean(event);if not event then return end
    if event=="PLAYER_LOGIN" then
        local _,class=Pair(UnitClass,"player")
        local ok,_,_,_,interface=pcall(GetBuildInfo)
        interface=ns.Clean(interface)
        if not ok or class~="HUNTER" or type(interface)~="number" or interface<16000 or interface>=20000 then return end
        ns.db=ns.Settings(HunterCueForeverDB);HunterCueForeverDB=ns.db;ns.ScanSpells()
        if ns.CreateUI then ns.CreateUI() end
        if ns.InitSting then ns.InitSting() end
        if ns.InitOptions then ns.InitOptions() end
        return
    end
    if not ns.db then return end
    if event=="PLAYER_REGEN_ENABLED" or event=="PLAYER_ENTERING_WORLD" then ns.enteringCombat=nil end
    if event=="PLAYER_REGEN_ENABLED" or event=="PLAYER_REGEN_DISABLED" then ns.layoutRefreshPending=true end
    if event=="PLAYER_REGEN_DISABLED" then
        ns.enteringCombat=true -- Lockdown can still be false inside this event callback.
        if ns.EndPreview then ns.EndPreview() end
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif event=="UI_SCALE_CHANGED" or event=="DISPLAY_SIZE_CHANGED" then
        if ns.ApplyUI then ns.ApplyUI() end
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif event=="UNIT_SPELLCAST_SENT" then ns.Sent(...)
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then ns.Succeeded(...)
    elseif event=="SPELL_UPDATE_COOLDOWN" then ns.CooldownEvent()
    elseif event=="PLAYER_TARGET_CHANGED" then ns.TargetChanged()
    elseif event=="PLAYER_DEAD" or event=="PLAYER_ENTERING_WORLD" then ns.ResetTracking()
    elseif event=="SPELLS_CHANGED" or event=="PLAYER_TALENT_UPDATE" or event=="CHARACTER_POINTS_CHANGED"
        or (event=="PLAYER_REGEN_ENABLED" and ns.scanPending) then ns.ScanSpells() end
    if event=="PLAYER_REGEN_ENABLED" and ns.RefreshOptions then ns.RefreshOptions() end
end
events:SetScript("OnEvent",function(...)
    local ok=pcall(Event,...)
    if not ok then ns.lastError=true end -- no secret-bearing error string is persisted/printed.
end)
local elapsedTotal=0
events:SetScript("OnUpdate",function(_,elapsed)
    if not ns.db then return end
    elapsedTotal=elapsedTotal+elapsed;if elapsedTotal<0.1 then return end;elapsedTotal=0
    local ok=pcall(function()
        local locked=ns.LayoutLockedByCombat()
        if ns.layoutRefreshPending or locked~=ns.lastLayoutLock then
            ns.layoutRefreshPending=nil;ns.lastLayoutLock=locked;if ns.RefreshOptions then ns.RefreshOptions() end
        end
        local s=ns.Snapshot();ns.UpdateUI(s,ns.Recommend(s,ns.Decide(s)))
    end)
    if not ok then ns.ClearRecommendation();ns.lastError=true;if ns.ShowError then ns.ShowError() end end
end)
SLASH_HUNTERCUEFOREVER1="/hcf"
SlashCmdList.HUNTERCUEFOREVER=ns.Command

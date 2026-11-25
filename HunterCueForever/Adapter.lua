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
local function ReadField(t,k) return t[k] end
local function Field(t,k)
    local v,readable=ns.Clean(t)
    if not readable or type(v)~="table" then return nil,false end
    return Call(ReadField,v,k)
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
ns.usableHistory={};ns.gcdPreviewSamples=0
ns.hawks={};ns.seenSuccess={}
local function TrimRecords(records,now)
    local count,oldest,oldestAt=0,nil,nil
    for k,v in pairs(records) do
        local at=type(v)=="table" and v.at or v
        if now-at>10 then records[k]=nil
        else
            count=count+1
            if not oldestAt or at<oldestAt then oldest=k;oldestAt=at end
        end
    end
    if count>32 and oldest then records[oldest]=nil end
end
function ns.ResetHawks(phase)
    ns.hawkState=ns.HawkTracker and ns.HawkTracker.New(Now(),phase) or nil
    ns.hawks=ns.hawkState and ns.hawkState.records or {}
end
function ns.PruneHawks(now)
    if ns.hawkState then ns.HawkTracker.Tick(ns.hawkState,now);ns.hawks=ns.hawkState.records end
end
function ns.SaveHawks()
    if ns.hawkState then HunterCueHawkState=ns.HawkTracker.Export(ns.hawkState,Now(),Num(Call(GetServerTime))) end
end
function ns.ResetTracking(full)
    ns.usableHistory={}
    ns.cooldownCache={};ns.fences={};ns.pending={};ns.inferred={};ns.attempts={}
    if full then ns.ResetHawks(0);ns.seenSuccess={} end
    ns.lastAuto=nil;ns.meleeSince=nil;ns.lastError=nil;ns.generation=ns.generation+1
    ns.actionSerial=(ns.actionSerial or 0)+1;ns.lastActionAt=nil;ns.lastActionKey=nil;ns.lastBurstAt=nil
    if ns.ClearRecommendation then ns.ClearRecommendation() end
end
local function CommitSpells(known,ids,uncertain,readable)
    local mapChanged=false
    for key,id in pairs(known) do if ns.known[key]~=id then mapChanged=true end end
    for key,id in pairs(ns.known) do if known[key]~=id then mapChanged=true end end
    ns.known=known;ns.ids=ids;ns.unknownSpells=uncertain;ns.scanDegraded=not readable
    if mapChanged or ns.talentSwitchPending then ns.ResetTracking() end
    ns.talentSwitchPending=nil;ns.scanCandidate=nil
    if next(known) and not known.hawk and not uncertain.hawk then ns.ResetHawks(0) end
end
function ns.ResolvePendingScan()
    local c=ns.scanCandidate
    if ns.talentSwitchPending and c and (ns.enteringCombat==true or Call(InCombatLockdown)==true) then
        -- Use the already sanitized positive map; never keep old-talent skills
        -- or blank the entire fight while waiting for a protected rescan.
        CommitSpells(c.known,c.ids,c.uncertain,false);ns.scanPending=true
    end
end
function ns.ScanSpells(switch)
    local now=Now()
    if Call(InCombatLockdown)==true then ns.scanPending=true;return end
    if switch and not ns.talentSwitchPending then ns.talentSwitchPending=true;ns.scanTries=0;ns.ClearRecommendation() end
    local known,ids,uncertain={},{},{};local readable=true
    for key,ranks in pairs(ns.spells) do
        local learned={}
        for _,id in ipairs(ranks) do
            local yes=Call(IsPlayerSpell,id)
            if type(yes)~="boolean" then yes=Call(C_SpellBook and C_SpellBook.IsSpellKnown,id) end
            if type(yes)~="boolean" then readable=false;uncertain[key]=true end
            if yes==true then learned[id]=true end
        end
        local id=ns.SelectRank(ranks,learned)
        if id then known[key]=id;ids[id]=key end
    end
    if not next(known) then
        -- A transient empty spellbook cannot prove a talent was unlearned.
        readable=false;for key in pairs(ns.spells) do uncertain[key]=true end
    end
    ns.scanCandidate={known=known,ids=ids,uncertain=uncertain}
    local changed=false
    for key,id in pairs(known) do if ns.known[key]~=id then changed=true end end
    for key in pairs(ns.known) do if not known[key] and not uncertain[key] then changed=true end end
    ns.scanTries=(ns.scanTries or 0)+1
    ns.scanPending=not readable;ns.scanComplete=readable and next(known)~=nil
    if not readable and next(ns.known) and (changed or ns.talentSwitchPending) and ns.scanTries<3 then
        ns.talentSwitchPending=true;ns.nextScan=now+.5;return
    end
    if readable or changed or ns.talentSwitchPending or not next(ns.known) or ns.scanTries>=3 then
        CommitSpells(known,ids,uncertain,readable)
    end
    ns.nextScan=not readable and now+(ns.scanTries<3 and .5 or 5) or nil
    if readable then ns.scanTries=0 end
    if ns.ApplyUI then ns.ApplyUI() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end
function ns.Profile()
    if ns.db.spec~="auto" then return ns.db.spec end
    if ns.known.wrath then return "bm" end
    if ns.known.strider then return "sv" end
    if ns.known.sniper then return "mm" end
    local u=ns.unknownSpells or {}
    if u.wrath or u.strider or u.sniper then return "generic" end
    return "bm"
end
-- Totem identities do not enter the cast-success byID map.
local hawkIdentity={[1293248]=true,[1312639]=true}
for _,id in ipairs(ns.spells.hawk) do hawkIdentity[id]=true end
function ns.ReadHawkSlots(changedSlot,force)
    if not ns.hawkState then return end
    local now=Now()
    if not force and ns.nextHawkScan and now<ns.nextHawkScan then ns.PruneHawks(now);return end
    ns.nextHawkScan=now+.25
    local count=Num(Call(GetNumTotemSlots));local complete=true
    if not count or count<1 or count>16 or count%1~=0 then
        count=Num(ns.Clean(MAX_TOTEMS))
        if not count or count<1 or count>16 or count%1~=0 then count=4;complete=false end
    end
    local names,icons={},{}
    for _,id in ipairs(ns.spells.hawk) do
        local name=SpellAPI("GetSpellName",id);local icon=Num(SpellAPI("GetSpellTexture",id))
        if type(name)=="string" then names[name]=true end
        if icon and icon~=134400 then icons[icon]=true end
    end
    names.Hawk=true;names["雄鹰"]=true;names["鹰"]=true
    local rows={}
    for slot=1,count do
        local row={kind="unknown"};rows[slot]=row
        if type(GetTotemInfo)=="function" then
            local ok,have,name,start,duration,icon,rate,id=pcall(GetTotemInfo,slot)
            if ok then
                have=ns.Clean(have);name=ns.Clean(name);start=Num(ns.Clean(start));duration=Num(ns.Clean(duration))
                icon=Num(ns.Clean(icon));local rateOK;rate,rateOK=ns.Clean(rate);id=Num(ns.Clean(id))
                if have==false then row.kind="empty"
                elseif have==true and ((id and hawkIdentity[id]) or (type(name)=="string" and names[name]) or (icon and icons[icon])) then
                    row.kind="hawk"
                    if start and start>=0 and start<=now+1 then row.start=start end
                    if duration and duration>0 and duration<=120 then row.duration=duration end
                    if row.start and row.duration and rateOK and (rate==nil or rate==1) then row.expires=start+duration end
                elseif have==true and id and (ns.byID[id]=="immolation" or ns.byID[id]=="explosive") then row.kind="other" end
            end
        end
        if row.kind=="unknown" then complete=false end
    end
    ns.HawkTracker.Observe(ns.hawkState,rows,complete,Num(ns.Clean(changedSlot)),now)
    ns.hawks=ns.hawkState.records
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
local function Duration(id,ignoreGCD)
    local object=SpellAPI("GetSpellCooldownDuration",id,ignoreGCD)
    if not object then return nil,nil,nil end
    local zero=Call(function() return object:IsZero() end)
    local remaining=Num(Call(function() return object:GetRemainingDuration() end))
    if remaining and remaining<0 then remaining=nil end
    if type(zero)~="boolean" then zero=nil end
    return object,zero,remaining
end
local function Availability(key,id,gcd,now)
    local usable,oom,ok=Pair(C_Spell and C_Spell.IsSpellUsable,id)
    local cd=Cooldown(id);local remaining=Remaining(cd,now)
    local main=false;for _,k in ipairs(ns.futureKeys) do if k==key then main=true end end
    local object,zero,ownRemaining
    if main then object,zero,ownRemaining=Duration(id,true) end
    local gcdOnly=false
    if gcd.active==true then
        if cd.start and cd.duration and cd.rate and gcd.start and gcd.duration and gcd.rate then
            gcdOnly=cd.start==gcd.start and cd.duration==gcd.duration and cd.rate==gcd.rate
        else
            local cache=ns.cooldownCache[key]
            gcdOnly=cache and cache.id==id and now-cache.stamp<=2 and cache.gcd==true or false
        end
    end
    local facts={ownDuration=object,syncing=ns.fences[key]~=nil and now<ns.fences[key]}
    if zero==true then remaining=0;gcdOnly=gcd.active==true;facts.ownClear=true;facts.ownActive=false
    elseif zero==false then
        facts.ownClear=false;facts.ownActive=true
        -- The ordinary timer may be reporting only GCD. A native nonzero
        -- own cooldown outranks that classification, including stale flags.
        remaining=ownRemaining or (not gcdOnly and remaining or nil);gcdOnly=false
    else
        if ownRemaining then remaining=ownRemaining end
        if gcdOnly or cd.active==false then facts.ownClear=true;facts.ownActive=false
        elseif cd.active==true then facts.ownClear=false;facts.ownActive=true end
    end
    facts.blocked=not ok or cd.enabled~=true or facts.syncing
    local previous=ns.usableHistory[key]
    if main and usable==true and oom==false and not facts.blocked then
        ns.usableHistory[key]={id=id,at=now}
    elseif main and usable==false and oom==false and ok and gcd.active==true and gcdOnly and not facts.blocked
        and previous and previous.id==id and now>=previous.at and now-previous.at<=2.5 then
        facts.gcdPreview=true;ns.gcdPreviewSamples=ns.gcdPreviewSamples+1
    elseif main then ns.usableHistory[key]=nil end
    -- Keep the live usability fact false. Only the separate preview clone may
    -- use gcdPreview, and only until this GCD ends and facts are read again.
    if not ok then return nil,remaining,oom,usable,nil,facts end
    if usable~=true or oom==true or facts.syncing or cd.enabled==false then return false,remaining,oom,usable,false,facts end
    if cd.enabled~=true then return nil,remaining,oom,usable,nil,facts end
    if facts.ownClear then return true,0,oom,usable,true,facts end
    if cd.active~=true and facts.ownActive~=true then return nil,remaining,oom,usable,nil,facts end
    local gcdRemaining=gcd.remaining or Remaining(gcd,now)
    local future=gcd.active==true and remaining and gcdRemaining and remaining<=gcdRemaining+0.001
    return gcdOnly or future or false,remaining,oom,usable,gcdOnly,facts
end
-- Burst reminders describe OWN cooldown readiness, not the next main action.
-- A readable native ignore-GCD result outranks timing/cache heuristics.
local function BurstAvailability(key,id,gcd,now,usable,oom)
    if ns.fences[key] and now<ns.fences[key] then return false,"施放后同步" end
    if type(usable)~="boolean" or type(oom)~="boolean" then return nil,"可用性或资源未知" end
    if oom then return false,"资源不足" end
    local cd=Cooldown(id)
    if cd.enabled==false then return false,"技能未启用" end
    if cd.enabled~=true then return nil,"冷却启用状态未知" end
    local duration=SpellAPI("GetSpellCooldownDuration",id,true)
    local clear=duration and Call(function() return duration:IsZero() end)
    local source
    if type(clear)=="boolean" then
        source=clear and "原生：自身冷却就绪" or "原生：自身冷却中"
    elseif cd.active==false then
        clear=true;source="备用：无冷却"
    elseif cd.active==true and gcd.active==true then
        if cd.start and cd.duration and cd.rate and gcd.start and gcd.duration and gcd.rate then
            clear=cd.start==gcd.start and cd.duration==gcd.duration and cd.rate==gcd.rate
            source=clear and "备用：仅公共CD" or "备用：自身冷却中"
        else
            local cache=ns.cooldownCache[key]
            clear=cache and cache.id==id and now-cache.stamp<=2 and cache.gcd==true or false
            source=clear and "备用：公共CD事件" or "自身冷却无法确认"
        end
    else
        clear=false;source="自身冷却未就绪或未知"
    end
    if not clear then return false,source end
    if usable then return true,source end
    if gcd.active==true then return true,source.." / 公共CD保留" end
    return false,"非公共CD期间不可用"
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
        elseif id and ns.byID[id]==key then
            local expires=Num(Field(a,"expirationTime"))
            return true,expires and math.max(0,expires-Now()) or nil
        end
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
    ns.usableHistory={}
    ns.generation=ns.generation+1;ns.inferred={};ns.pending={};ns.attempts={};ns.meleeSince=nil;ns.lastAuto=nil
    if ns.ClearRecommendation then ns.ClearRecommendation() end
end
function ns.Sent(unit,targetName,guid,id)
    unit=ns.Clean(unit);targetName=ns.Clean(targetName);guid=ns.Clean(guid);id=ns.Clean(id)
    if unit~="player" or type(guid)~="string" or type(id)~="number" then return end
    local key=ns.byID[id]
    if key~="mark" and key~="sting" then return end
    local target=TargetIdentity()
    if not target or not targetName then return end
    if targetName~=target.name and targetName~=target.full then return end
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
    if key~="auto" and type(guid)=="string" then
        if ns.seenSuccess[guid] and now-ns.seenSuccess[guid]<=10 then return end
        ns.seenSuccess[guid]=now;TrimRecords(ns.seenSuccess,now)
    end
    if (key=="hawk" or key=="arcane") and ns.hawkState and ns.hawkState.lastSuccess
        and now>=ns.hawkState.lastSuccess and now-ns.hawkState.lastSuccess<.15 then return end
    local isBurst=ns.burstOption[key]~=nil
    for _,k in ipairs(ns.family[key] or {key}) do ns.cooldownCache[k]=nil;ns.fences[k]=now+(isBurst and 1 or 0.25) end
    if isBurst then ns.lastBurstAt=now
    elseif key~="auto" then
        ns.actionSerial=(ns.actionSerial or 0)+1;ns.lastActionAt=now
        ns.lastActionKey=(key~="mark" and key~="sting") and key or nil -- Independent monitors never occupy the spent main icon.
    end
    if key=="hawk" or key=="arcane" then
        if ns.hawkState then ns.HawkTracker.Success(ns.hawkState,key,now);ns.hawks=ns.hawkState.records;ns.SaveHawks() end
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
    local active,remaining=Aura(key)
    local attempt=ns.attempts[key]
    if active==true then ns.attempts[key]=nil;return true,false,false,remaining end
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
local function ProbeRange(spells,keys)
    local yes,no,unknown,any=false,false,false,false
    for _,key in ipairs(keys) do
        local p=spells[key]
        if p then
            any=true
            if p.range==true then yes=true elseif p.range==false then no=true else unknown=true end
        end
    end
    if yes and not no then return true end
    if any and no and not yes and not unknown then return false end
    return nil -- Conflicting explicit probes and unknown-only evidence are not a distance proof.
end
function ns.ResetTargets(hard)
    ns.targetScan=nil
    if hard~=false then ns.targetEstimate=ns.TargetEstimator and ns.TargetEstimator.New() or nil end
end
local function TargetScan(probes)
    local result={count=0,unknown=0,calls=0,reason="未确认当前目标的姓名板"}
    local plates=Call(C_NamePlate and C_NamePlate.GetNamePlates)
    if type(plates)~="table" then result.reason="姓名板列表不可读";return result end
    local size=Num(Call(function() return #plates end))
    if not size or size<0 then result.reason="姓名板列表不可读";return result end
    local units,seen={},{};local anchor
    result.partial=size>80
    for i=1,math.min(size,80) do
        local plate=Field(plates,i);local unit=Field(plate,"namePlateUnitToken")
        if type(unit)~="string" or not unit:match("^nameplate%d+$") then
            result.reason="姓名板单位不可读";return result
        end
        if not seen[unit] then
            seen[unit]=true;units[#units+1]=unit
            if Call(UnitIsUnit,unit,"target")==true then anchor=unit end
        end
    end
    if not anchor then return result end
    local own={"player"};local team={}
    if Call(UnitExists,"pet")==true then own[#own+1]="pet" end
    local raid=Call(IsInRaid)
    if raid==nil then result.partial=true end
    if raid~=nil then
        local prefix=raid and "raid" or "party"
        for i=1,raid and 40 or 4 do
            local unit=prefix..i;local exists=Call(UnitExists,unit)
            if exists==true then
                team[#team+1]=unit
                if Call(UnitExists,prefix.."pet"..i)==true then team[#team+1]=prefix.."pet"..i end
            elseif exists==nil then result.partial=true end
        end
    end
    local checks={{UnitExists,true},{UnitIsDeadOrGhost,false},{UnitIsPlayer,false},{UnitAffectingCombat,true}}
    local function Eligible(unit)
        for _,probe in ipairs(checks) do
            local value=Call(probe[1],unit)
            if value==nil then return nil end
            if value~=probe[2] then return false end
        end
        local attack=Call(UnitCanAttack,"player",unit)
        if attack==false then return false end
        if attack~=true then return nil end
        local unknown=false
        for _,id in ipairs(probes) do
            local value=SpellAPI("IsSpellInRange",id,unit)
            if value==true then return true end
            if value~=false then unknown=true end
        end
        if unknown then return nil end
        return false
    end
    local function Threat(unit,engagers)
        local unknown=false
        for _,who in ipairs(engagers) do
            if result.calls>=512 then result.partial=true;return nil end
            result.calls=result.calls+1
            local value,readable=Call(UnitThreatSituation,who,unit)
            if readable and type(value)=="number" and value>=0 and value<=3 and value==math.floor(value) then return true end
            if not readable or value~=nil then unknown=true end
        end
        if unknown then return nil end
        return false
    end
    if Eligible(anchor)~=true then result.reason="当前目标范围或交战状态未确认";return result end
    local a=Threat(anchor,own)
    if a~=true then a=Threat(anchor,team) end
    if a~=true then result.reason="未确认当前目标与本队交战";return result end
    result.count=1;result.valid=true;result.reason="已确认交战目标（估算）"
    local pending={}
    -- First cover all player/pet engagements, so foreign raid combat cannot
    -- consume the full budget before our own pack is considered.
    for _,unit in ipairs(units) do
        if unit~=anchor then
            local eligible=Eligible(unit)
            if eligible==true then
                local ownThreat=Threat(unit,own)
                if ownThreat==true then result.count=result.count+1
                else pending[#pending+1]={unit=unit,unknown=ownThreat==nil} end
            elseif eligible==nil then result.unknown=result.unknown+1 end
            if result.count>=6 then return result end
        end
    end
    for i,p in ipairs(pending) do
        local threat=Threat(p.unit,team)
        if threat==true then result.count=result.count+1
        elseif threat==nil or p.unknown then result.unknown=result.unknown+1 end
        if result.count>=6 then return result end
        if result.calls>=512 then
            result.partial=true;result.unknown=result.unknown+#pending-i;break
        end
    end
    return result
end
function ns.EffectiveTargets(s)
    local mode=ns.db.targets
    if mode~=0 then
        ns.targetStatus={count=mode,effective=mode,reason="手动"};return mode
    end
    local T=ns.TargetEstimator
    if not T then ns.targetStatus={count=0,effective=1,reason="请完全退出并重启游戏，加载自动目标模块"};return 1 end
    ns.targetEstimate=ns.targetEstimate or T.New()
    if not s.inCombat or not s.playerAlive then ns.ResetTargets() end
    if not s.inCombat or not s.target or s.targetInCombat~=true or s.scanBlocked or (s.ranged~=true and s.melee~=true) then
        ns.targetScan=nil
        T.Suspend(ns.targetEstimate,s.now)
        ns.targetStatus={count=0,effective=1,reason="当前目标、交战或射程未确认，回退单体"};return 1
    end
    local probes={};local ranged=ns.known.arcane or ns.known.auto
    if ranged then probes[#probes+1]=ranged end
    for _,key in ipairs({"raptor","mongoose","strider"}) do if ns.known[key] then probes[#probes+1]=ns.known[key] end end
    local key=table.concat(probes,":");local c=ns.targetScan
    if not c or c.key~=key or s.now<c.at or s.now-c.at>=.5 then
        c=TargetScan(probes);c.at=s.now;c.key=key;ns.targetScan=c
        if c.valid then
            c.effective=T.Observe(ns.targetEstimate,s.now,c.count)
            if c.count>=3 and c.effective<(c.count>=6 and 6 or 3) then c.reason="等待连续确认" end
        else ns.targetEstimate=T.New();c.effective=1 end
    end
    ns.targetStatus=c
    return c.effective
end
function ns.TargetStatusText()
    local t=ns.targetStatus or {count=0,effective=1,reason="等待采样"}
    return (ns.db.targets==0 and "自动估算" or "手动").." / 确认 "..t.count..(t.count>=6 and "+" or "")
        .." / 当前策略 "..t.effective.." / "..t.reason
        ..((t.unknown or 0)>0 and " / 未确认 "..t.unknown or "")..(t.partial and " / 部分采样" or "")
end
function ns.Snapshot()
    local now=Now();local db=ns.db
    ns.ResolvePendingScan()
    ns.ReadHawkSlots()
    local s={now=now,spells={},spec=ns.Profile(),mode=db.mode,targets=db.targets,
        cooldowns=db.cooldowns,traps=db.traps,weave=db.weave,hawks={},readiness=false,stingEnabled=db.stingEnabled}
    for _,h in ipairs(ns.hawks) do s.hawks[#s.hawks+1]={arrives=h.arrives,expires=h.expires} end
    s.hawkPhase=ns.hawkState and ns.hawkState.phase
    s.hawkUnknown=not ns.known.hawk and ns.unknownSpells and ns.unknownSpells.hawk
    s.arcaneUnknown=not ns.known.arcane and ns.unknownSpells and ns.unknownSpells.arcane
    s.scanBlocked=ns.talentSwitchPending==true;s.mmSniper=db.mmSniper
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
    local dead=Call(UnitIsDeadOrGhost,"player")
    local feigning=Call(UnitIsFeignDeath,"player")
    s.playerAlive=dead==false and feigning~=true
    -- PLAYER_DEAD is authoritative. A snapshot cannot distinguish Feign Death
    -- when the dedicated predicate is missing or protected, so retain history.
    if dead==true and feigning==false then ns.ResetHawks(0);s.hawks={};s.hawkPhase=0 end
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
    local gcdObject,_,gcdTime=Duration(61304,false)
    gcd.remaining=gcdTime or Remaining(gcd,now)
    s.gcd=gcd.active==true;s.gcdKnown=gcd.active~=nil;s.gcdStart=gcd.start;s.gcdRemaining=gcd.remaining;s.gcdDuration=gcdObject
    for key,id in pairs(ns.known) do
        local ready,remaining,oom,usable,burstReady,facts=Availability(key,id,gcd,now)
        local burstReason
        if ns.burstOption[key] then burstReady,burstReason=BurstAvailability(key,id,gcd,now,usable,oom) end
        local range=SpellAPI("IsSpellInRange",id,"target")
        s.spells[key]={id=id,ready=ready,remaining=remaining,oom=oom,range=range,usable=usable,burstReady=burstReady,burstReason=burstReason,
            queued=Call(IsCurrentSpell,id),cost=Cost(id)}
        for k,v in pairs(facts or {}) do s.spells[key][k]=v end
        if key~="auto" and ready~=nil then s.readiness=true end
    end
    s.melee=ProbeRange(s.spells,{"raptor","mongoose","strider"})
    s.ranged=ProbeRange(s.spells,{"arcane","auto"})
    s.targets=ns.EffectiveTargets(s)
    if s.melee==true then ns.meleeSince=ns.meleeSince or now;s.meleeDwell=now-ns.meleeSince
    else ns.meleeSince=nil end
    s.sinceAuto=ns.lastAuto and now-ns.lastAuto
    s.mark,s.markEstimated,s.markBackoff=AuraState("mark",now)
    s.sting,s.stingEstimated,s.stingBackoff,s.stingRemaining=AuraState("sting",now)
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
function ns.DrawMainCooldown(frame,key,s,out,preview)
    local now=s.now or Now();local remaining=out.waitRemaining
    if preview then remaining=2 end
    local shown=false
    if (out.wait or preview) and type(remaining)=="number" and remaining>0 then
        local timerKey=key..":"..tostring(ns.known[key] or 0)
        local ending=now+remaining
        if preview then timerKey="preview";ending=now+2 end
        if frame.hcfTimerKey~=timerKey or not frame.hcfTimerEnd or math.abs(frame.hcfTimerEnd-ending)>.05 then
            frame.hcfTimerKey=timerKey;frame.hcfTimerEnd=ending;frame.hcfTimerStart=now
        end
        shown=pcall(frame.SetCooldown,frame,frame.hcfTimerStart,frame.hcfTimerEnd-frame.hcfTimerStart)
    else
        frame.hcfTimerKey=nil;frame.hcfTimerEnd=nil;frame.hcfTimerStart=nil
        local p=s.spells and s.spells[key]
        local object=out.waitSource=="gcd" and s.gcdDuration or out.waitSource=="own" and p and p.ownDuration
        if out.wait and object and frame.SetCooldownFromDurationObject then
            shown=pcall(frame.SetCooldownFromDurationObject,frame,object)
        end
    end
    if not shown then frame:Clear() end
    frame:SetHideCountdownNumbers(not (ns.db.previewNumbers and shown and (out.wait or preview)))
end
function ns.SavePosition(x,y)
    ns.db.x=x;ns.db.y=y
end
function ns.LayoutLockedByCombat() return ns.enteringCombat==true or Call(InCombatLockdown)~=false end
local function Say(text) print("|cff75c9ffHunterCue:|r "..text) end
function ns.HawkStatus()
    if not ns.HawkTracker then Say("请完全退出并重启游戏，加载新版雄鹰模块。");return end
    local t=ns.hawkState;if not t then return end
    Say("雄鹰阶段："..(t.phase==nil and "未知，等待实际施放或消失确认" or t.phase==2 and "下一发奥术" or "下一发雄鹰").." / "..t.reason)
    for i,h in ipairs(t.records) do Say("鹰 "..i.."："..h.source.." / "..string.format("%.1f",math.max(0,h.expires-Now())).." 秒 / 槽 "..(h.slot or "未知")) end
end
function ns.Command(message)
    if not ns.db then Say("需要 Forever 客户端上的猎人角色。");return end
    local cmd,arg=message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd=="" or cmd=="config" or cmd=="options" then
        if ns.LayoutLockedByCombat() then Say("请脱战后打开设置。");return end
        if ns.OpenOptions then ns.OpenOptions() end;return
    elseif cmd=="spec" and ns.specNames[arg] then ns.db.spec=arg;ns.ResetTracking()
    elseif cmd=="mode" and arg=="next" then
        ns.db.mode=({balanced="conserve",conserve="burst",burst="balanced"})[ns.db.mode]
    elseif cmd=="targets" and arg=="next" then ns.db.targets=({[0]=1,[1]=3,[3]=6,[6]=0})[ns.db.targets];ns.ResetTargets()
    elseif cmd=="targets" and arg=="auto" then ns.db.targets=0;ns.ResetTargets()
    elseif cmd=="mode" and ns.modeNames[arg] then ns.db.mode=arg
    elseif cmd=="targets" and (arg=="1" or arg=="3" or arg=="6") then ns.db.targets=tonumber(arg);ns.ResetTargets()
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
    elseif cmd=="hawks" then ns.ReadHawkSlots(nil,true);ns.HawkStatus();return
    elseif cmd=="status" then
        local s=ns.Snapshot();local count=0;for _ in pairs(ns.known) do count=count+1 end
        Say(ns.version.." / "..s.spec.." / "..s.mode.." / 已学技能组 "..count)
        Say(ns.TargetStatusText())
        local nextAction=ns.Recommend(s,ns.Decide(s),ns.CopyRecommendationState())
        Say("下一技能："..(nextAction.key and nextAction.key~="auto" and ns.SpellName(nextAction.key) or "未确认")
            ..(nextAction.waitRemaining and (" / 等待 "..string.format("%.1f",nextAction.waitRemaining).." 秒")
                or nextAction.wait and " / 等待时间不可计算" or "")
            .." / "..(nextAction.reason or "等待").." / GCD条件预告采样 "..ns.gcdPreviewSamples)
        ns.HawkStatus()
        if ns.scanDegraded then Say("技能扫描部分受限：仅使用确认已学技能；可手动选择专精。") end
        Say("蓝量:"..(s.mana and "可读" or "受限").." 回蓝:"..(s.regen and "可读" or "受限")
            .." 技能状态:"..(s.readiness and "可读" or "不可读").." 射程:"..(s.ranged==nil and "未知" or "可读")
            .." 钉刺:"..(s.sting==nil and "未知" or s.stingEstimated and "估算" or "可读"))
        for _,key in ipairs(ns.burstOrder) do
            local p=s.spells[key]
            if p then Say(ns.SpellName(key).."："..(p.burstReason or "未知")
                ..(key=="wrath" and not s.pet and " / 无存活宠物" or "")) end
        end
        if #ns.missingEvents>0 then Say("未注册事件："..table.concat(ns.missingEvents,", ")) end
        if ns.lastError then Say("最近一次状态/界面更新失败；请 /reload 后再次检查。");end
        return
    else
        Say("/hcf 打开设置；/hcf spec auto|bm|mm|sv · mode balanced|conserve|burst · targets auto|1|3|6")
        Say("/hcf weave normal|aggressive · burst on|off · traps on|off · show|hide|lock|reset|status · pos x y")
        Say("/hcf config 打开设置并独立调整图标大小/间距 · /hcf help 查看命令")
        Say("/hcf stable on|off 固定推荐 · /hcf targets next 或 /hcf mode next 战斗中切换")
        return
    end
    if cmd=="targets" then ns.Snapshot();Say(ns.TargetStatusText()) end
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
    "UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED","SPELL_UPDATE_COOLDOWN","PLAYER_TOTEM_UPDATE","PLAYER_LOGOUT","ACTIVE_TALENT_GROUP_CHANGED",
    "GROUP_ROSTER_UPDATE","UNIT_PET"}) do Register(events.RegisterEvent,event) end
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
        ns.db=ns.Settings(HunterCueForeverDB);HunterCueForeverDB=ns.db
        ns.ResetHawks(nil)
        if ns.HawkTracker then ns.hawkState=ns.HawkTracker.Restore(HunterCueHawkState,Now(),Num(Call(GetServerTime))) or ns.hawkState end
        ns.hawks=ns.hawkState and ns.hawkState.records or {};ns.ScanSpells();ns.ReadHawkSlots(nil,true)
        if ns.CreateUI then ns.CreateUI() end
        if ns.InitSting then ns.InitSting() end
        if ns.InitOptions then ns.InitOptions() end
        return
    end
    if not ns.db then return end
    if event=="GROUP_ROSTER_UPDATE" or event=="UNIT_PET" then ns.ResetTargets(false);return end
    if event=="PLAYER_TARGET_CHANGED" then
        ns.ResetTargets(false)
        if ns.targetEstimate and ns.TargetEstimator then ns.TargetEstimator.CancelUpgrade(ns.targetEstimate) end
    elseif event=="PLAYER_DEAD" or event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED" or event=="PLAYER_REGEN_DISABLED" then ns.ResetTargets() end
    if event=="PLAYER_REGEN_ENABLED" or event=="PLAYER_ENTERING_WORLD" then ns.enteringCombat=nil end
    if event=="PLAYER_REGEN_ENABLED" or event=="PLAYER_REGEN_DISABLED" then ns.layoutRefreshPending=true end
    if event=="PLAYER_REGEN_DISABLED" then
        ns.enteringCombat=true -- Lockdown can still be false inside this event callback.
        ns.ResolvePendingScan()
        if ns.EndPreview then ns.EndPreview() end
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif event=="UI_SCALE_CHANGED" or event=="DISPLAY_SIZE_CHANGED" then
        if ns.ApplyUI then ns.ApplyUI() end
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif event=="UNIT_SPELLCAST_SENT" then ns.Sent(...)
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then ns.Succeeded(...)
    elseif event=="SPELL_UPDATE_COOLDOWN" then ns.CooldownEvent()
    elseif event=="PLAYER_TARGET_CHANGED" then ns.TargetChanged()
    elseif event=="PLAYER_LOGOUT" then ns.SaveHawks()
    elseif event=="PLAYER_TOTEM_UPDATE" then local slot=...;ns.ReadHawkSlots(slot,true)
    elseif event=="PLAYER_DEAD" then ns.ResetTracking(true);ns.SaveHawks()
    elseif event=="PLAYER_ENTERING_WORLD" then
        local initial,reloading=...;initial=ns.Clean(initial);reloading=ns.Clean(reloading)
        if initial==true and reloading~=true then ns.ResetHawks(0) end
        ns.ResetTracking();ns.ScanSpells();ns.ReadHawkSlots(nil,true)
    elseif event=="ACTIVE_TALENT_GROUP_CHANGED" or event=="PLAYER_TALENT_UPDATE" then ns.ScanSpells(true)
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
        if ns.nextScan and Now()>=ns.nextScan and not locked then ns.ScanSpells() end
        local s=ns.Snapshot();ns.UpdateUI(s,ns.Recommend(s,ns.Decide(s)))
    end)
    if not ok then ns.ClearRecommendation();ns.lastError=true;if ns.ShowError then ns.ShowError() end end
end)
SLASH_HUNTERCUEFOREVER1="/hcf"
SlashCmdList.HUNTERCUEFOREVER=ns.Command

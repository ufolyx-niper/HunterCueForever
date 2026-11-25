-- SPDX-License-Identifier: MIT
-- Original guardian/cadence model. Inputs are sanitized by Adapter.lua.
local _,ns=...
local H={};ns.HawkTracker=H
local function Number(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
local function Phase(n) return n==nil or n==0 or n==1 or n==2 end
function H.New(now,phase)
    return {records={},retired={},phase=phase,reason="initial",born=now,quietAt=now,
        graceUntil=now+2,maxDuration=18,supported=false,revision=0}
end
local function Changed(t,reason) t.revision=t.revision+1;t.reason=reason end
local function Repair(t)
    if t.phase~=nil then t.phase=math.min(t.phase,#t.records) end
end
local function Remove(t,index,now,replacement)
    local h=table.remove(t.records,index)
    if replacement and h.slot then t.retired[h.slot]={start=h.nativeStart,untilTime=now+6,record=h} end
    if not replacement then Repair(t) end
    Changed(t,replacement and "replacement" or "expired-or-gone")
end
local function Oldest(t)
    local oldest=1
    for i,h in ipairs(t.records) do if h.castAt<t.records[oldest].castAt then oldest=i end end
    return oldest
end
function H.Tick(t,now)
    for slot,r in pairs(t.retired) do if now>=r.untilTime then t.retired[slot]=nil end end
    for i=#t.records,1,-1 do
        local h=t.records[i]
        if h.source=="pending" and now>=h.castAt+5 then
            h.source="cast";h.expires=h.castAt+18;Changed(t,"arrival-timeout")
        end
        if now>=h.expires and not (h.lastSeen and now-h.lastSeen<=.4) then Remove(t,i,now,false) end
    end
    if t.phase==nil and #t.records==0 and now-t.quietAt>=t.maxDuration+1 then
        t.phase=0;Changed(t,"quiet-expiry")
    end
end
function H.Success(t,key,now)
    if key~="hawk" and key~="arcane" then return false end
    if t.lastSuccess and now>=t.lastSuccess and now-t.lastSuccess<.15 then return false end
    H.Tick(t,now);t.lastSuccess=now;t.quietAt=now;t.observed=true
    if key=="arcane" then t.phase=0;Changed(t,"arcane-success");return true end
    local adopt
    for _,h in ipairs(t.records) do
        if h.unclaimed and h.nativeStart and math.abs(h.nativeStart-now)<=1
            and h.firstSeen and now-h.firstSeen<=.3 then adopt=h;break end
    end
    if adopt then adopt.unclaimed=nil;adopt.castAt=now
    else
        if #t.records>=2 then Remove(t,Oldest(t),now,true) end
        t.records[#t.records+1]={castAt=now,arrives=now+1,expires=now+19,source="pending"}
    end
    t.phase=math.min(2,(t.phase or 0)+1);Changed(t,"hawk-success");return true
end
local function Pending(t,now,nativeStart)
    for _,h in ipairs(t.records) do
        if not h.slot and h.source=="pending" and now>=h.castAt and now-h.castAt<=5
            and (not nativeStart or nativeStart>=h.castAt-1) then return h end
    end
end
function H.Observe(t,rows,complete,changedSlot,now)
    local allEmpty=complete;local positives=0
    -- Do not expire before processing current positive observations.
    for slot,row in ipairs(rows) do
        local retired=t.retired[slot]
        local oldIdentity=retired and not retired.departed and (not row.start or not retired.start or row.start==retired.start)
        if row.kind~="empty" and row.kind~="other" then allEmpty=false end
        if row.kind=="hawk" then
            positives=positives+1;t.supported=true
            if row.duration then t.maxDuration=math.max(t.maxDuration,row.duration) end
            if not oldIdentity then
                t.retired[slot]=nil
                local h
                for _,v in ipairs(t.records) do if v.slot==slot then h=v;break end end
                if h and row.start and h.nativeStart and row.start~=h.nativeStart then
                    -- A slot replaced its old occupant; adopt a pending cast first.
                    local pending=Pending(t,now,row.start)
                    if pending and pending~=h then
                        for i,v in ipairs(t.records) do if v==h then Remove(t,i,now,true);break end end
                        h=pending
                        -- The slot reused may differ from our oldest-record estimate.
                        -- Restore that estimated survivor unless its departure is known.
                        for oldSlot,r in pairs(t.retired) do
                            if oldSlot~=slot and #t.records<2 and not r.departed and r.record.expires>now then
                                t.records[#t.records+1]=r.record;t.retired[oldSlot]=nil
                            end
                        end
                        t.retired[slot]=nil -- the new occupant is now identified
                    end
                end
                h=h or Pending(t,now,row.start)
                if not h then
                    if #t.records>=2 then Remove(t,Oldest(t),now,true) end
                    h={castAt=row.start or now,arrives=row.start or now,expires=now+t.maxDuration,
                        firstSeen=now,unclaimed=true,source="game"}
                    t.records[#t.records+1]=h
                    -- Physical presence never proves where H/H/A left off.
                    if not t.observed then t.phase=nil end
                    Changed(t,"recovered-presence")
                end
                h.slot=slot;h.lastSeen=now;h.emptySince=nil
                if row.start then h.nativeStart=row.start end
                if row.expires then h.expires=row.expires;h.arrives=row.start;h.source="game"
                elseif h.source=="pending" then h.expires=now+18;h.arrives=now;h.source="event" end
            end
        elseif row.kind=="empty" or row.kind=="other" then
            if retired then
                -- Departure may precede arrival of the replacement in this slot.
                retired.departed=true
            elseif now>=t.graceUntil then
                for i=#t.records,1,-1 do
                    local h=t.records[i]
                    if h.slot==slot and h.source~="pending" then
                        h.emptySince=h.emptySince or now
                        if now-h.emptySince>=.2 then Remove(t,i,now,false) end
                    end
                end
            end
        else
            -- Unknown is never proof of disappearance. Break negative continuity.
            for _,h in ipairs(t.records) do if h.slot==slot then h.emptySince=nil end end
            if changedSlot==slot and not retired then
                local occupied=false
                for _,h in ipairs(t.records) do if h.slot==slot then occupied=true end end
                local h=not occupied and Pending(t,now)
                if h then
                    h.slot=slot;h.arrives=now;h.expires=now+18;h.source="event"
                    Changed(t,"arrival-inferred")
                end
            end
        end
    end
    if allEmpty and t.supported and now>=t.graceUntil then
        t.emptySince=t.emptySince or now
        if now-t.emptySince>=.2 then
            for i=#t.records,1,-1 do
                local h=t.records[i]
                if not h.slot and now-h.castAt>=5 then Remove(t,i,now,false) end
            end
            if #t.records==0 and t.phase==nil then t.phase=0;Changed(t,"confirmed-empty") end
        end
    else t.emptySince=nil end
    Repair(t);H.Tick(t,now)
end
function H.Export(t,now,wall)
    if not Number(wall) then return nil end
    H.Tick(t,now)
    local saved={version=1,phase=t.phase,observed=t.observed==true,now=now,wall=wall,
        maxDuration=t.maxDuration,supported=t.supported,records={}}
    for _,h in ipairs(t.records) do
        local copy={};for _,key in ipairs({"castAt","arrives","expires","slot","nativeStart","source"}) do copy[key]=h[key] end
        saved.records[#saved.records+1]=copy
    end
    return saved
end
function H.Restore(saved,now,wall)
    if type(saved)~="table" or saved.version~=1 or not Phase(saved.phase)
        or not Number(wall) or not Number(saved.now) or not Number(saved.wall)
        or not Number(saved.maxDuration) or saved.maxDuration<18 or saved.maxDuration>120
        or type(saved.records)~="table" or #saved.records>2 then return nil end
    for key in pairs(saved.records) do
        if not Number(key) or key%1~=0 or key<1 or key>#saved.records then return nil end
    end
    if saved.phase and saved.phase>#saved.records then return nil end
    local delta=now-saved.now;local real=wall-saved.wall
    if delta<0 or real<0 or math.abs(delta-real)>2 or delta>30 then return nil end
    local t=H.New(now,saved.phase);t.maxDuration=saved.maxDuration;t.supported=saved.supported==true
    t.observed=saved.observed==true;t.reason="restored"
    local slots={}
    for i,h in ipairs(saved.records) do
        if type(h)~="table" or not Number(h.castAt) or not Number(h.arrives) or not Number(h.expires)
            or h.castAt>now+1 or h.castAt<saved.now-125 or h.expires<h.castAt or h.expires>h.castAt+126
            or h.arrives<h.castAt-1 or h.arrives>h.expires
            or (h.slot~=nil and (not Number(h.slot) or h.slot<1 or h.slot>16 or h.slot%1~=0))
            or (h.nativeStart~=nil and not Number(h.nativeStart))
            or not ({pending=true,cast=true,event=true,game=true,cached=true})[h.source] then return nil end
        if h.slot and slots[h.slot] then return nil end
        if h.slot then slots[h.slot]=true end
        t.records[i]={castAt=h.castAt,arrives=h.arrives,expires=h.expires,slot=h.slot,
            nativeStart=h.nativeStart,source=h.source=="pending" and "pending" or "cached"}
    end
    H.Tick(t,now)
    return t
end

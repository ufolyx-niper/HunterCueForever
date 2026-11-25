-- SPDX-License-Identifier: MIT
-- Confirmed lower-bound categories, not an exact count of AoE hits.
local _,ns=...
local T={};ns.TargetEstimator=T
function T.New() return {effective=1} end
function T.CancelUpgrade(t) t.threeSince=nil;t.sixSince=nil end
function T.Suspend(t,now)
    T.CancelUpgrade(t)
    if not t.last or now<t.last or now-t.last>1.001 then t.effective=1;t.last=nil end
    return 1
end
function T.Observe(t,now,count)
    if not t.last or now<t.last or now-t.last>1.001 then
        t.effective=1;T.CancelUpgrade(t)
    end
    t.last=now
    local category=count>=6 and 6 or count>=3 and 3 or 1
    if category<t.effective then t.effective=category end
    -- Each threshold has its own continuous evidence. A fluctuating sixth
    -- enemy must not erase the already continuous evidence for three.
    if count>=3 then t.threeSince=t.threeSince or now else t.threeSince=nil end
    if count>=6 then t.sixSince=t.sixSince or now else t.sixSince=nil end
    if t.sixSince and now-t.sixSince>=1-.000001 then t.effective=6
    elseif t.threeSince and now-t.threeSince>=1-.000001 then t.effective=math.max(3,t.effective) end
    return t.effective
end

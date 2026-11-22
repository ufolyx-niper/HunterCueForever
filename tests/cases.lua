local n=0
local function check(v,msg) n=n+1;assert(v,msg or ("case "..n)) end
local function fixture(spec)
    local s={spec=spec,mode="balanced",weave="normal",targets=1,target=true,moving=false,
        casting=false,melee=false,ranged=true,mark=true,sting=true,readiness=true,
        mana=4000,maxMana=4000,regen=20,pet=true,cooldowns=true,hawkCount=0,spells={}}
    for k,ids in pairs(NS.spells) do s.spells[k]={id=ids[1],ready=true,range=true,cost=100,remaining=5,queued=false} end
    return s
end
local s=fixture("bm")
check(NS.Decide(s).key=="hawk","BM first hawk")
s.hawkCount=2;check(NS.Decide(s).key=="arcane","BM third shared cast")
s.spells.arcane=nil;check(NS.Decide(s).key=="hawk","unknown arcane never stalls")
s.mode="conserve";s.mana=100;check(NS.Decide(s).key=="auto","BM low mana preserve")
s.mana=nil;check(NS.Decide(s).key=="hawk","manual conserve works with secret mana")
s=fixture("mm");check(NS.Decide(s).key=="arcane","MM arcane")
s.spells.arcane.ready=false;check(NS.Decide(s).key=="aimed","MM aimed")
s.mode="conserve";check(NS.Decide(s).key=="sniper","conserve skips aimed")
s.moving=true;check(NS.Decide(s).key=="auto","do not hardcast moving")
s=fixture("sv");check(NS.Decide(s).key=="aimed","SV normal ranged")
s.weave="aggressive";check(NS.Decide(s).key=="arcane","SV aggressive")
s.melee=true;s.ranged=false;check(NS.Decide(s).key=="mongoose","SV proc first")
s.spells.mongoose.ready=false;check(NS.Decide(s).key=="raptor","SV raptor")
s.spells.raptor.queued=true;check(NS.Decide(s).key=="strider","queued raptor not repeated")
s.spells.raptor.queued=false;s.meleeDwell=2;check(NS.Decide(s).key==nil and NS.Decide(s).move~="","SV dwell retreat")
s=fixture("sv");s.ranged=false;s.melee=false;check(NS.Decide(s).reason=="调整到技能射程","dead zone explicit")
s.ranged=nil;s.melee=nil;for _,p in pairs(s.spells) do p.range=nil end
check(NS.Decide(s).key==nil,"unknown range not far")
s=fixture("sv");s.sinceAuto=0.3;check(NS.Decide(s).move:find("可进近战")~=nil,"fresh shot window")
s.sinceAuto=2;check(not NS.Decide(s).move:find("可进近战"),"stale shot no window")
s=fixture("mm");s.targets=6;s.spells.volley.range=nil
check(NS.Decide(s).key=="volley","ground volley accepts positive ranged probe")
s.ranged=nil;for _,p in pairs(s.spells) do p.range=nil end
check(NS.Decide(s).key==nil,"ground volley not guessed with unknown ranged probe")
for _,spec in ipairs({"bm","mm","sv"}) do
    s=fixture(spec);s.targets=3;check(NS.Decide(s).key=="multi",spec.." small cleave")
    s.targets=6;check(NS.Decide(s).key=="volley",spec.." AOE")
    s.casting=true;local o=NS.Decide(s);check(o.key==nil and o.burst==nil and o.move=="","never interrupt channel")
    s.casting=false;s.mark=false;check(NS.Decide(s).key=="mark","confirmed absent mark")
    s.mark=nil;s.sting=nil;check(NS.Decide(s).key=="volley","unknown aura never locks rotation")
end
check(NS.SelectRank({10,3,7},{[10]=true,[7]=true})==7,"rank order not numeric")
check(NS.Settings({spec="bad",mode="bad",targets=8,scale=0/0}).spec=="auto","settings validate")
local saved=NS.Settings({enabled=false,cooldowns=false});saved=NS.Settings(saved)
check(saved.enabled==false and saved.cooldowns==false,"saved false round trips")
s=fixture("bm");s.melee=true;s.ranged=false
for k,p in pairs(s.spells) do if not NS.selfSpell[k] then p.range=false end end
check(NS.Decide(s).move=="拉开距离，回到远程射程","BM minimum-range cue")
s=fixture("sv");s.melee=true;s.ranged=false;s.spells.mongoose.ready=false;s.spells.raptor.queued=nil
check(NS.Decide(s).key=="strider","unknown raptor queue not toggled")
for _,ids in pairs(NS.spells) do for _,id in ipairs(ids) do LEARNED[id]=true end end
NS.events.scripts.OnEvent(NS.events,"PLAYER_LOGIN")
check(NS.db and HunterCueForeverFrame,"UI initializes")
check(NS.known.sting==25295,"highest learned book rank")
LEARNED[25295]=false;NS.ScanSpells();check(NS.known.sting==13555,"trainer rank without book")
NS.Command("spec mm");NS.Command("mode conserve");NS.Command("targets 3")
check(NS.db.spec=="mm" and NS.db.mode=="conserve" and NS.db.targets==3,"controls persist")
NS.Command("weave aggressive");check(NS.db.weave=="aggressive","weaving control")
NS.Command("hide");NS.events.scripts.OnUpdate(NS.events,0.2);check(not HunterCueForeverFrame.shown,"hide")
NS.Command("show");NS.events.scripts.OnUpdate(NS.events,0.2);check(HunterCueForeverFrame.shown,"show")
check(not NS.lastError,"adapter/UI integration")
-- Cooldown snapshots, GCD-only vs real, expiry and actual cooldown completion.
local aid=NS.known.arcane;local nid=NS.known.sniper
CD[aid]={isActive=true,isEnabled=true,startTime=SECRET,duration=SECRET,isOnGCD=false}
CD[nid]={isActive=true,isEnabled=true,startTime=SECRET,duration=SECRET,isOnGCD=true}
CD[61304]={isActive=true,isEnabled=true,startTime=SECRET,duration=SECRET}
NS.CooldownEvent();local snap=NS.Snapshot()
check(snap.spells.arcane.ready==false and snap.spells.sniper.ready==true,"GCD classification")
CD[aid]={isActive=false,isEnabled=true,startTime=0,duration=0}
check(NS.Snapshot().spells.arcane.ready==true,"real cooldown ends before GCD")
NOW=103;check(NS.Snapshot().spells.sniper.ready==false,"stale cache rejected")
NS.CooldownEvent();NS.Succeeded("player","c",nid)
check(NS.Snapshot().spells.sniper.ready==false,"success invalidates cached GCD-ready")
NOW=104;CD={};NS.ResetTracking()
-- Mixed-type secret booleans must be sanitized even though Lua itself will not throw.
for _,id in pairs(NS.known) do USABLE[id]=SECRET;RANGE[id]=SECRET end
MANA=SECRET;REGEN=SECRET;MOVING=SECRET;AURA_SECRET=true
snap=NS.Snapshot();check(snap.mana==nil and snap.regen==nil and snap.moving==nil,"numeric secrets")
check(snap.spells.arcane.ready==nil and snap.ranged==nil and snap.sting==nil,"boolean and aura secrets")
check(NS.Decide(snap).key==nil,"no fabricated skill under unreadable states")
NS.events.scripts.OnUpdate(NS.events,0.2);check(not NS.lastError,"secret UI path")
USABLE={};RANGE={};MANA=3000;REGEN=10;MOVING=0
-- Successful sent events are bounded estimates, not guaranteed hits.
NS.Sent("player","Mob A","a",13555);NS.Succeeded("player","a",13555)
snap=NS.Snapshot();check(snap.sting==true and snap.stingEstimated,"inferred aura labelled")
NS.TargetChanged();snap=NS.Snapshot();check(snap.sting==nil,"target switch clears estimates")
NS.Sent("player","Mob B","b",13555);NS.Succeeded("player","b",13555)
check(NS.Snapshot().sting==nil,"mouseover cast not applied to target")
NS.Sent("player","Mob A","c",13555);NS.TargetChanged();NS.Succeeded("player","c",13555)
check(NS.Snapshot().sting==nil,"SENT then switch then success")
NS.Sent("player","Mob A",SECRET,13555);NS.Succeeded("player",SECRET,SECRET)
check(next(NS.pending)==nil,"secret cast payload ignored")
NS.Sent("player","Mob A","d",13555);NS.Succeeded("player","d",13555)
AURA_SECRET=false;AURAS={};check(NS.Snapshot().sting==false,"readable aura absence beats estimate (miss/dispel)")
AURAS={{spellId=SECRET}};check(NS.Snapshot().stingEstimated==true,"partial aura scan not absence")
NS.ResetTracking();check(NS.Snapshot().sting==nil,"unknown after reset")
AURAS={};AURA_SECRET=false
NS.Succeeded("player","h1",1293241);NS.Succeeded("player","h2",1293241);check(NS.hawkCount==2,"hawk cycle")
NS.Succeeded("player","ar",3044);check(NS.hawkCount==0,"arcane resets cycle")
NS.ResetTracking();check(NS.lastAuto==nil and NS.hawkCount==0,"reset state")
NS.Succeeded("player","h3",1293241);NOW=NOW+31;NS.Snapshot();check(NS.hawkCount==0,"long pause resets sequence")
local oldCost=C_Spell.GetSpellPowerCost;C_Spell.GetSpellPowerCost=function() return SECRET end
check(NS.Snapshot().spells.arcane.cost==nil,"secret cost table")
C_Spell.GetSpellPowerCost=oldCost
local oldCooldown=C_Spell.GetSpellCooldown;C_Spell.GetSpellCooldown=function() return SECRET end
check(NS.Snapshot().spells.arcane.ready==nil,"secret cooldown object")
C_Spell.GetSpellCooldown=oldCooldown
CAST=SECRET;check(NS.Snapshot().casting==true,"secret casting state waits");CAST=nil
NAMES.mouseover=NAMES.target;GUIDS.mouseover="another-same-name"
NS.Sent("player","Mob A","dup",13555);check(NS.pending.dup==nil,"duplicate-name mouseover ambiguity")
NAMES.mouseover="Mob C"
NS.TargetChanged();AURAS={};AURA_SECRET=false
NS.Sent("player","Mob A","fail1",13555);NS.Succeeded("player","fail1",13555)
NOW=NOW+1.6;check(NS.Snapshot().stingBackoff==false,"first unconfirmed cast no backoff")
NS.Sent("player","Mob A","fail2",13555);NS.Succeeded("player","fail2",13555)
NOW=NOW+1.6;check(NS.Snapshot().stingBackoff==true,"second unconfirmed cast backs off")
local absent=fixture("mm");absent.sting=false;absent.stingBackoff=true
check(NS.Decide(absent).key=="arcane","backoff never locks main icon")
NOW=NOW+21;check(NS.Snapshot().stingBackoff==false,"backoff expires")
AURAS={{spellId=13555}};check(NS.Snapshot().sting==true and NS.attempts.sting==nil,"actual aura clears backoff")
NS.Command("reset");NS.events.scripts.OnUpdate(NS.events,0.2);check(not NS.lastError,"final UI update")
print("PASS: "..n.." Lua assertions")

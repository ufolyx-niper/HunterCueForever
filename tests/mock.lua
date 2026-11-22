NS={}
NOW=100
SECRET=setmetatable({}, {__index=function() error("secret indexing") end,
    __add=function() error("secret math") end,__lt=function() error("secret order") end,
    __tostring=function() error("secret conversion") end})
function issecretvalue(x) return rawequal(x,SECRET) end
-- Sentinels cannot intercept truth tests/mixed equality; tests below assert
-- the guard returns unknown for each API field, not that Lua emulates WoW secrets.
LEARNED={};CD={};USABLE={};RANGE={};AURAS={};GUIDS={target="target-A",focus="focus-B",mouseover="mouse-C"}
NAMES={target="Mob A",focus="Mob B",mouseover="Mob C"}
MANA=3000;MAXMANA=4000;REGEN=10;MOVING=0;CAST=nil;CHANNEL=nil;AURA_SECRET=false;CLASS="HUNTER";BUILD=16001
function GetTime() return NOW end
function InCombatLockdown() return false end
function IsPlayerSpell(id) return LEARNED[id]==true end
function UnitClass() return "Hunter",CLASS end
function GetBuildInfo() return "1.60.1","71037","",BUILD end
function UnitExists(unit) return unit=="target" or unit=="player" or unit=="pet" end
function UnitCanAttack() return true end
function UnitIsDeadOrGhost() return false end
function UnitIsPlayer() return false end
function UnitGUID(unit) return GUIDS[unit] end
function UnitName(unit) return NAMES[unit],"" end
function UnitCastingInfo() return CAST end
function UnitChannelInfo() return CHANNEL end
function UnitPower() return MANA end
function UnitPowerMax() return MAXMANA end
function GetManaRegen() return 30,REGEN end
function GetUnitSpeed() return MOVING end
function IsCurrentSpell() return false end
C_Secrets={ShouldAurasBeSecret=function() return AURA_SECRET end}
C_UnitAuras={GetAuraDataByIndex=function(unit,i,filter) return AURAS[i] end}
C_Spell={GetSpellCooldown=function(id) return CD[id] or {isActive=false,isEnabled=true,startTime=0,duration=0} end,
    IsSpellUsable=function(id) local v=USABLE[id];if v==nil then return true,false end;return v,false end,
    IsSpellInRange=function(id) if RANGE[id]~=nil then return RANGE[id] end;return true end,
    GetSpellPowerCost=function() return {{type=0,cost=100}} end,
    GetSpellName=function(id) return "spell-"..id end,GetSpellTexture=function() return 134400 end,
    GetSpellCooldownDuration=function() return {} end}
SlashCmdList={}
local methods={}
local function new()
    return setmetatable({scripts={},shown=true}, {__index=function(t,k) return methods[k] or function() end end})
end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:RegisterEvent(event) if UNKNOWN_EVENT==event then error("Unknown event") end end
function methods:CreateTexture() return new() end
function methods:CreateFontString() return new() end
function methods:GetFont() return "mock",12,"" end
function methods:GetCenter() return 500,400 end
function methods:SetText(v) assert(not issecretvalue(v));self.text=v end
function methods:SetTexture(v) assert(not issecretvalue(v));self.texture=v end
function methods:SetShown(v) assert(not issecretvalue(v));self.shown=v end
function methods:IsShown() return self.shown end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function CreateFrame(_,name) local f=new();if name then _G[name]=f end;return f end
UIParent=new()

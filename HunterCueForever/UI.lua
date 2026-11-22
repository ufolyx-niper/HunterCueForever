-- SPDX-License-Identifier: MIT
-- Owned, non-secure display only. Game-state reads live in Adapter.lua.
local _,ns=...
local root,icon,nameText,reasonText,moveText,statusText,maintenance,burstIcon,burstText,cd,burstCD
local controls={}
local function Text(parent,size,x,y,width)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f:SetPoint("TOPLEFT",x,y);f:SetWidth(width);f:SetJustifyH("LEFT")
    local font,_,flags=f:GetFont();f:SetFont(font,size,flags)
    return f
end
local function Button(key,x,y,width,click)
    local b=CreateFrame("Button",nil,root,"UIPanelButtonTemplate")
    b:SetSize(width,22);b:SetPoint("TOPLEFT",x,y);b:SetScript("OnClick",click);controls[key]=b
end
local function Cycle(field,values,cmd)
    local current=ns.db[field];local index=1
    for i,v in ipairs(values) do if v==current then index=i%#values+1;break end end
    ns.Command(cmd.." "..tostring(values[index]))
end
function ns.ApplyUI()
    if not root then return end
    root:ClearAllPoints();root:SetPoint("CENTER",UIParent,"CENTER",ns.db.x,ns.db.y)
    root:SetScale(ns.db.scale)
    controls.spec:SetText("专精 "..ns.specNames[ns.db.spec])
    controls.mode:SetText(ns.modeNames[ns.db.mode])
    controls.targets:SetText(ns.db.targets==1 and "单体" or ns.db.targets.."+ 目标")
    controls.burst:SetText("爆发 "..(ns.db.cooldowns and "开" or "关"))
    controls.traps:SetText("陷阱 "..(ns.db.traps and "开" or "关"))
    controls.weave:SetText(ns.db.weave=="normal" and "常规穿插" or "积极穿插")
    root:SetShown(ns.db.enabled)
end
function ns.CreateUI()
    if root then return end
    root=CreateFrame("Frame","HunterCueForeverFrame",UIParent,"BackdropTemplate")
    root:SetSize(370,222);root:SetFrameStrata("MEDIUM")
    root:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    root:SetBackdropColor(0.025,0.045,0.065,0.92);root:SetBackdropBorderColor(0.22,0.48,0.58,1)
    root:SetMovable(true);root:EnableMouse(true);root:RegisterForDrag("LeftButton");root:SetClampedToScreen(true)
    root:SetScript("OnDragStart",function(self) if not ns.db.locked then self:StartMoving() end end)
    root:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local x,y=self:GetCenter();local ux,uy=UIParent:GetCenter()
        if x and y and ux and uy then ns.SavePosition(x-ux,y-uy);ns.ApplyUI() end
    end)
    local title=Text(root,13,12,-9,345);title:SetText("HUNTER CUE  ·  Forever");title:SetTextColor(0.5,0.85,1)
    Button("spec",12,-30,116,function() Cycle("spec",{"auto","bm","mm","sv"},"spec") end)
    Button("mode",134,-30,104,function() Cycle("mode",{"balanced","conserve","burst"},"mode") end)
    Button("targets",244,-30,112,function() Cycle("targets",{1,3,6},"targets") end)
    icon=root:CreateTexture(nil,"ARTWORK");icon:SetSize(52,52);icon:SetPoint("TOPLEFT",12,-61);icon:SetTexCoord(0.08,0.92,0.08,0.92)
    cd=CreateFrame("Cooldown",nil,root,"CooldownFrameTemplate");cd:SetAllPoints(icon)
    nameText=Text(root,16,76,-62,220);nameText:SetTextColor(1,0.87,0.5)
    reasonText=Text(root,12,76,-86,220);reasonText:SetHeight(32);reasonText:SetTextColor(0.9,0.92,0.95)
    burstIcon=root:CreateTexture(nil,"ARTWORK");burstIcon:SetSize(30,30);burstIcon:SetPoint("TOPRIGHT",-14,-62)
    burstCD=CreateFrame("Cooldown",nil,root,"CooldownFrameTemplate");burstCD:SetAllPoints(burstIcon)
    burstText=Text(root,10,311,-96,50);burstText:SetText("爆发");burstText:SetTextColor(1,0.6,0.2)
    maintenance=Text(root,11,12,-121,344);maintenance:SetHeight(28)
    moveText=Text(root,11,12,-148,344);moveText:SetHeight(28);moveText:SetTextColor(0.5,0.85,1)
    statusText=Text(root,10,12,-176,344);statusText:SetHeight(19);statusText:SetTextColor(0.65,0.7,0.75)
    Button("burst",12,-196,90,function() ns.Command("burst "..(ns.db.cooldowns and "off" or "on")) end)
    Button("traps",108,-196,90,function() ns.Command("traps "..(ns.db.traps and "off" or "on")) end)
    Button("weave",204,-196,152,function() Cycle("weave",{"normal","aggressive"},"weave") end)
    ns.ApplyUI()
end
local function AuraLabel(value,estimated,backoff)
    if backoff then return "连续未确认生效 · 暂缓提示" end
    if value==nil then return "未知，请自行维持" end
    if estimated then return value and "估时中（未核实命中）" or "估时到期" end
    return value and "存在" or "缺失"
end
function ns.UpdateUI(s,out)
    if not root then return end
    root:SetShown(ns.db.enabled);if not ns.db.enabled then return end
    icon:SetTexture(ns.SpellIcon(out.key));icon:SetDesaturated(out.key==nil)
    nameText:SetText(out.key and ns.SpellName(out.key) or "等待")
    reasonText:SetText((s.gcd and out.key and "下一技能 · " or "")..out.reason);ns.DrawCooldown(cd,out.key)
    maintenance:SetText("印记："..AuraLabel(s.mark,s.markEstimated,s.markBackoff).."\n钉刺："..AuraLabel(s.sting,s.stingEstimated,s.stingBackoff))
    if out.burst then
        burstIcon:SetTexture(ns.SpellIcon(out.burst));burstIcon:Show();burstText:Show();ns.DrawCooldown(burstCD,out.burst)
    else burstIcon:Hide();burstText:Hide();burstCD:Clear() end
    moveText:SetText(out.move~="" and out.move or (s.spec=="bm" and not s.pet and "兽王：请召出存活的宠物" or ""))
    local mana=(s.mana and s.maxMana and s.maxMana>0) and ("蓝量 "..math.floor(s.mana/s.maxMana*100).."%") or "蓝量受限 · 手动省蓝"
    statusText:SetText(ns.specNames[s.spec].." · "..mana..(ns.lastError and " · 诊断异常 /hcf status" or ""))
end
function ns.ShowError()
    if root then nameText:SetText("状态暂不可用");reasonText:SetText("/hcf status 查看诊断；/reload 重载")
        icon:SetTexture(134400);cd:Clear();moveText:SetText("");burstIcon:Hide();burstText:Hide();burstCD:Clear() end
end

-- SPDX-License-Identifier: MIT
local _,ns=...
local root,icon,nameText,reasonText,moveText,statusText,maintenance,burstIcon,burstText,cd,burstCD,previewText
local controls,fonts={},{}
local lastState,lastOutput={},{reason="选择敌对目标",move=""}
local function Text(parent,size,x,y,width,height)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f:SetPoint("TOPLEFT",x,y);f:SetWidth(width);f:SetJustifyH("LEFT");f:SetHeight(height or 22)
    fonts[#fonts+1]={f,size};return f
end
local function Button(key,x,y,width,click)
    local b=CreateFrame("Button",nil,root,"UIPanelButtonTemplate")
    b:SetSize(width,24);b:SetPoint("TOPLEFT",x,y);b:SetScript("OnClick",click);controls[key]=b
end
local function Cycle(field,values,cmd)
    local index=1
    for i,v in ipairs(values) do if v==ns.db[field] then index=i%#values+1;break end end
    ns.Command(cmd.." "..tostring(values[index]))
end
local function AuraLabel(v,estimate,backoff)
    if backoff then return "连续未确认生效 · 暂缓提示" end
    if v==nil then return "未知，请自行维持" end
    if estimate then return v and "估时中（未核实命中）" or "估时到期" end
    return v and "存在" or "缺失"
end
local function Render()
    if not root then return end
    local preview=ns.preview==true
    root:SetFrameStrata(preview and "DIALOG" or "MEDIUM")
    root:SetShown(ns.ShouldShow(ns.db,lastState,preview))
    if not root:IsShown() then return end
    previewText:SetShown(preview)
    if preview then
        root:Raise()
        icon:SetTexture(ns.SpellIcon("arcane"));icon:SetDesaturated(false)
        nameText:SetText("奥术射击 · 示例")
        reasonText:SetText("预览中：调整位置与大小，不代表实时建议")
        maintenance:SetText("印记：示例存在\n钉刺：示例存在")
        moveText:SetText("走位说明示例：近战一击后回到远程")
        statusText:SetText("脱战预览 · 关闭设置后恢复真实显示")
        burstIcon:SetTexture(ns.SpellIcon("rapid"));burstIcon:Show();burstText:Show()
        cd:Clear();burstCD:Clear();return
    end
    local s,out=lastState,lastOutput
    icon:SetTexture(ns.SpellIcon(out.key));icon:SetDesaturated(out.key==nil)
    nameText:SetText(out.key and ns.SpellName(out.key) or "等待")
    reasonText:SetText((s.gcd and out.key and "下一技能 · " or "")..out.reason);ns.DrawCooldown(cd,out.key)
    maintenance:SetText("印记："..AuraLabel(s.mark,s.markEstimated,s.markBackoff).."\n钉刺："..AuraLabel(s.sting,s.stingEstimated,s.stingBackoff))
    if out.burst then burstIcon:SetTexture(ns.SpellIcon(out.burst));burstIcon:Show();burstText:Show();ns.DrawCooldown(burstCD,out.burst)
    else burstIcon:Hide();burstText:Hide();burstCD:Clear() end
    moveText:SetText(out.move~="" and out.move or (s.spec=="bm" and not s.pet and "兽王：请召出存活的宠物" or ""))
    local mana=(s.mana and s.maxMana and s.maxMana>0) and ("蓝量 "..math.floor(s.mana/s.maxMana*100).."%") or "蓝量受限 · 手动省蓝"
    statusText:SetText((ns.specNames[s.spec] or "猎人").." · "..mana..(ns.lastError and " · /hcf status 查看诊断" or ""))
end
function ns.ApplyUI()
    if not root then return end
    local x,y,scale,ax,ay=ns.LayoutGeometry(ns.db,UIParent:GetWidth(),UIParent:GetHeight())
    ns.appliedX=x;ns.appliedY=y;ns.appliedScale=scale
    root:SetScale(scale);root:ClearAllPoints();root:SetPoint("CENTER",UIParent,"CENTER",ax,ay)
    root:SetBackdropColor(0.025,0.045,0.065,ns.db.opacity)
    for _,entry in ipairs(fonts) do local font,_,flags=entry[1]:GetFont();entry[1]:SetFont(font,entry[2]*ns.db.fontScale,flags) end
    controls.spec:SetText("专精 "..ns.specNames[ns.db.spec]);controls.mode:SetText(ns.modeNames[ns.db.mode])
    controls.targets:SetText(ns.db.targets==1 and "单体" or ns.db.targets.."+ 目标")
    Render()
end
function ns.EndPreview()
    ns.preview=false;Render()
end
function ns.TogglePreview()
    if ns.LayoutLockedByCombat() then ns.EndPreview();return false end
    ns.preview=not ns.preview;Render();return true
end
function ns.CreateUI()
    if root then return end
    root=CreateFrame("Frame","HunterCueForeverFrame",UIParent,"BackdropTemplate");ns.hud=root
    root:SetSize(400,270);root:SetFrameStrata("MEDIUM");root:SetClampedToScreen(true)
    root:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    root:SetBackdropBorderColor(0.22,0.48,0.58,1);root:SetMovable(true)
    local header=CreateFrame("Button",nil,root);ns.dragHandle=header
    header:SetPoint("TOPLEFT",8,-4);header:SetSize(290,26);header:EnableMouse(true);header:RegisterForDrag("LeftButton");header:RegisterForClicks("RightButtonUp")
    header:SetScript("OnClick",function() ns.Command("config") end)
    header:SetScript("OnDragStart",function() if not ns.db.locked and not ns.LayoutLockedByCombat() then root:StartMoving() end end)
    header:SetScript("OnDragStop",function()
        root:StopMovingOrSizing()
        local x,y=root:GetCenter();local px,py=UIParent:GetCenter()
        if x and y and px and py then
            ns.SavePosition(ns.CenterToParent(x,y,root:GetEffectiveScale(),UIParent:GetEffectiveScale(),px,py))
            ns.ApplyUI();if ns.RefreshOptions then ns.RefreshOptions() end
        end
    end)
    local title=Text(root,12,12,-8,285,20);title:SetText("HUNTER CUE · 拖动标题 / 右键设置");title:SetTextColor(0.5,0.85,1)
    Button("settings",312,-5,76,function() ns.Command("config") end);controls.settings:SetText("设置")
    Button("spec",12,-33,124,function() Cycle("spec",{"auto","bm","mm","sv"},"spec") end)
    Button("mode",142,-33,116,function() Cycle("mode",{"balanced","conserve","burst"},"mode") end)
    Button("targets",264,-33,124,function() Cycle("targets",{1,3,6},"targets") end)
    icon=root:CreateTexture(nil,"ARTWORK");icon:SetSize(56,56);icon:SetPoint("TOPLEFT",12,-66);icon:SetTexCoord(.08,.92,.08,.92)
    cd=CreateFrame("Cooldown",nil,root,"CooldownFrameTemplate");cd:SetAllPoints(icon)
    nameText=Text(root,16,80,-66,248,24);nameText:SetTextColor(1,.87,.5)
    reasonText=Text(root,12,80,-94,248,42);reasonText:SetTextColor(.9,.92,.95)
    local burstButton=CreateFrame("Button",nil,root);burstButton:SetSize(32,32);burstButton:SetPoint("TOPRIGHT",-12,-66)
    burstIcon=burstButton:CreateTexture(nil,"ARTWORK");burstIcon:SetAllPoints(burstButton)
    burstCD=CreateFrame("Cooldown",nil,burstButton,"CooldownFrameTemplate");burstCD:SetAllPoints(burstButton)
    burstText=Text(root,10,352,-102,42,20);burstText:SetText("爆发");burstText:SetTextColor(1,.6,.2)
    burstButton:SetScript("OnEnter",function(self)
        local key=ns.preview and "rapid" or lastOutput.burst
        if key and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(ns.SpellName(key));GameTooltip:AddLine("爆发建议；自行按动作条施放",1,1,1,true);GameTooltip:Show() end
    end)
    burstButton:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    maintenance=Text(root,11,12,-140,376,38)
    moveText=Text(root,11,12,-182,376,34);moveText:SetTextColor(.5,.85,1)
    statusText=Text(root,10,12,-222,376,32);statusText:SetTextColor(.65,.7,.75)
    previewText=Text(root,10,12,-256,376,14);previewText:SetText("预览 · 非实时建议");previewText:SetTextColor(1,.65,.2)
    ns.hudControls=controls;ns.hudLabels={name=nameText,reason=reasonText,status=statusText,preview=previewText}
    ns.ApplyUI()
end
function ns.UpdateUI(s,out)
    lastState=s;lastOutput=out
    if s.inCombat then ns.preview=false end
    Render()
end
function ns.ShowError()
    if ns.preview then Render();return end
    lastOutput={reason="/hcf status 查看诊断；/reload 重载",move=""};Render()
    if root and root:IsShown() then nameText:SetText("状态暂不可用") end
end

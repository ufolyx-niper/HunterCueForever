-- SPDX-License-Identifier: MIT
local _,ns=...
local root,mainButton,icon,nameText,reasonText,moveText,statusText,maintenance,cd,previewText,burstLabel
local fonts,burstButtons={},{}
local lastState,lastOutput={},{reason="选择敌对目标",move=""}
local displayedKey,displayedID,wasPreview
local function Text(parent,size,x,y,width,height)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f:SetPoint("TOPLEFT",x,y);f:SetWidth(width);f:SetJustifyH("LEFT");f:SetHeight(height or 22)
    fonts[#fonts+1]={f,size};return f
end
local function AuraLabel(v,estimate,backoff,pending)
    if pending then return "等待生效确认" end
    if backoff then return "连续未确认生效 · 暂缓提示" end
    if v==nil then return "未知，请自行维持" end
    if estimate then return v and "估时中（未核实命中）" or "估时到期" end
    return v and "存在" or "缺失"
end
local function RenderBursts(preview)
    local ready=ns.BurstReady(lastState);local slot,visible=0,0
    for _,key in ipairs(ns.burstOrder) do
        local button=burstButtons[key]
        local enabled=ns.db.cooldowns and ns.db[ns.burstOption[key]] and ns.known[key]~=nil
        if enabled then
            -- Assign slots by enabled/learned spell, not by readiness: no sliding icons.
            button:ClearAllPoints();button:SetPoint("TOPLEFT",root,"TOPLEFT",8+slot*40,-90);slot=slot+1
        end
        local shown=enabled and (preview or ready[key]==true)
        button:SetShown(shown);button:EnableMouse(shown and not preview and not lastState.inCombat)
        if shown then button.icon:SetTexture(ns.SpellIcon(key));visible=visible+1 end
    end
    burstLabel:SetShown(visible>0);burstLabel:SetText(preview and "爆发示例" or "爆发就绪")
end
local function Render()
    if not root then return end
    local preview=ns.preview==true
    root:SetFrameStrata(preview and "DIALOG" or "MEDIUM")
    root:SetShown(ns.ShouldShow(ns.db,lastState,preview));if not root:IsShown() then return end
    root:EnableMouse(preview);mainButton:EnableMouse(not preview and not lastState.inCombat)
    previewText:SetShown(preview);maintenance:SetShown(ns.db.showDetails);statusText:SetShown(ns.db.showDetails)
    if preview then
        if not wasPreview then root:Raise() end;wasPreview=true
        icon:SetTexture(ns.SpellIcon("arcane"));icon:SetDesaturated(false)
        nameText:SetText("奥术射击 · 示例");reasonText:SetText("布局预览，不代表实时建议")
        maintenance:SetText("印记：示例存在\n钉刺：示例存在")
        moveText:SetText("示例：完成近战一击后回到远程")
        statusText:SetText("预览 · 关闭设置后恢复真实显示")
        RenderBursts(true);cd:Clear();return
    end
    local s,out=lastState,lastOutput
    local id=out.key and ns.known[out.key]
    if wasPreview or displayedKey~=out.key or displayedID~=id then
        icon:SetTexture(ns.SpellIcon(out.key));displayedKey=out.key;displayedID=id
    end
    wasPreview=false;icon:SetDesaturated(out.key==nil or out.wait==true or out.settling==true)
    local name=out.key and ns.SpellName(out.key) or "等待"
    nameText:SetText(name..(out.settling and out.key and " · 已施放" or out.wait and " · 预告" or ""))
    if out.wait then reasonText:SetText(string.format("还需 %.1f 秒 · 保持自动射击",out.waitRemaining))
    else reasonText:SetText((out.locked and "已固定 · " or s.gcd and out.key and not out.settling and "下一技能 · " or "")..out.reason) end
    ns.DrawCooldown(cd,out.key)
    maintenance:SetText("印记："..AuraLabel(s.mark,s.markEstimated,s.markBackoff,s.markPending).."\n钉刺："..AuraLabel(s.sting,s.stingEstimated,s.stingBackoff,s.stingPending))
    RenderBursts(false)
    moveText:SetText(out.move~="" and out.move or (s.spec=="bm" and not s.pet and "请召出存活的宠物" or ""))
    local mana=(s.mana and s.maxMana and s.maxMana>0) and ("蓝量 "..math.floor(s.mana/s.maxMana*100).."%") or "蓝量受限 · 手动省蓝"
    statusText:SetText((ns.specNames[s.spec] or "猎人").." · "..mana..(ns.lastError and " · /hcf status" or ""))
end
function ns.ApplyUI()
    if not root then return end
    local w,h=ns.HudSize(ns.db);root:SetSize(w,h)
    local x,y,scale,ax,ay=ns.LayoutGeometry(ns.db,UIParent:GetWidth(),UIParent:GetHeight())
    ns.appliedX=x;ns.appliedY=y;ns.appliedScale=scale
    root:SetScale(scale);root:ClearAllPoints();root:SetPoint("CENTER",UIParent,"CENTER",ax,ay)
    root:SetBackdropColor(.025,.045,.065,ns.db.opacity)
    for _,entry in ipairs(fonts) do local font,_,flags=entry[1]:GetFont();entry[1]:SetFont(font,entry[2]*ns.db.fontScale,flags) end
    previewText:ClearAllPoints();previewText:SetPoint("TOPLEFT",8,-(h-16))
    Render()
end
local function AbortDrag()
    if ns.dragging then
        root:StopMovingOrSizing();root:SetUserPlaced(false);ns.dragging=false;ns.ApplyUI()
    end
end
function ns.EndPreview() ns.preview=false;AbortDrag();Render() end
function ns.TogglePreview()
    if ns.LayoutLockedByCombat() then ns.EndPreview();return false end
    ns.preview=not ns.preview;if not ns.preview then AbortDrag() end;Render();return true
end
function ns.CreateUI()
    if root then return end
    root=CreateFrame("Frame","HunterCueForeverFrame",UIParent,"BackdropTemplate");ns.hud=root
    root:SetFrameStrata("MEDIUM");root:SetClampedToScreen(true);root:SetMovable(true);root:SetUserPlaced(false)
    root:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    root:SetBackdropBorderColor(.22,.48,.58,1);root:RegisterForDrag("LeftButton");ns.dragHandle=root
    root:SetScript("OnDragStart",function()
        if ns.preview and not ns.db.locked and not ns.LayoutLockedByCombat() then ns.dragging=true;root:StartMoving() end
    end)
    root:SetScript("OnDragStop",function()
        if not ns.dragging then return end
        if ns.LayoutLockedByCombat() then AbortDrag();return end
        root:StopMovingOrSizing();ns.dragging=false;root:SetUserPlaced(false)
        local x,y=root:GetCenter();local px,py=UIParent:GetCenter()
        if x and y and px and py then
            ns.SavePosition(ns.CenterToParent(x,y,root:GetEffectiveScale(),UIParent:GetEffectiveScale(),px,py))
            ns.ApplyUI();if ns.RefreshOptions then ns.RefreshOptions() end
        end
    end)
    mainButton=CreateFrame("Button",nil,root);mainButton:SetSize(56,56);mainButton:SetPoint("TOPLEFT",8,-8)
    mainButton:RegisterForClicks("RightButtonUp");mainButton:SetScript("OnClick",function() ns.Command("config") end)
    ns.mainButton=mainButton
    mainButton:SetScript("OnEnter",function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText("HunterCue Forever")
            GameTooltip:AddLine((ns.specNames[lastState.spec] or "猎人").." · "..ns.modeNames[ns.db.mode].." · "..ns.db.targets.." 目标",1,1,1,true)
            GameTooltip:AddLine("右键打开设置；/hcf targets next 切换目标数",.6,.85,1,true);GameTooltip:Show()
        end
    end)
    mainButton:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    icon=mainButton:CreateTexture(nil,"ARTWORK");mainButton.icon=icon;icon:SetAllPoints(mainButton);icon:SetTexCoord(.08,.92,.08,.92)
    cd=CreateFrame("Cooldown",nil,root,"CooldownFrameTemplate");cd:SetAllPoints(mainButton)
    nameText=Text(root,16,76,-8,276,24);nameText:SetTextColor(1,.87,.5)
    reasonText=Text(root,12,76,-36,276,44);reasonText:SetTextColor(.9,.92,.95)
    for _,key in ipairs(ns.burstOrder) do
        local spellKey=key
        local b=CreateFrame("Button",nil,root,"BackdropTemplate");b:SetSize(32,32)
        b:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});b:SetBackdropBorderColor(1,.75,.2,1)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetPoint("TOPLEFT",2,-2);b.icon:SetPoint("BOTTOMRIGHT",-2,2);b.icon:SetTexCoord(.08,.92,.08,.92)
        b:SetScript("OnEnter",function(self)
            if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(ns.SpellName(spellKey));GameTooltip:AddLine("自身冷却就绪；按游戏限制自行施放",1,1,1,true);GameTooltip:Show() end
        end)
        b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        b:SetScript("OnHide",function(self) if GameTooltip and GameTooltip:GetOwner()==self then GameTooltip:Hide() end end)
        b:Hide();burstButtons[key]=b
    end
    ns.burstButtons=burstButtons
    burstLabel=Text(root,10,132,-96,220,22);burstLabel:SetTextColor(1,.75,.2)
    moveText=Text(root,11,8,-130,344,26);moveText:SetTextColor(.5,.85,1)
    maintenance=Text(root,11,8,-174,344,38)
    statusText=Text(root,10,8,-218,344,32);statusText:SetTextColor(.65,.7,.75)
    previewText=Text(root,10,8,-156,344,14);previewText:SetText("预览：拖动面板（需解锁）");previewText:SetTextColor(1,.65,.2)
    ns.hudLabels={name=nameText,reason=reasonText,status=statusText,preview=previewText,maintenance=maintenance}
    ns.ApplyUI()
end
function ns.UpdateUI(s,out)
    lastState=s;lastOutput=out
    if s.inCombat and ns.preview then ns.EndPreview() end
    Render()
end
function ns.ShowError()
    if ns.preview then Render();return end
    lastOutput={reason="/hcf status 查看诊断；/reload 重载",move=""};Render()
    if root and root:IsShown() then nameText:SetText("状态暂不可用") end
end

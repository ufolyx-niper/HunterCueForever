-- SPDX-License-Identifier: MIT
-- Icon surface with optional native waiting numbers; no explanatory HUD text.
local _,ns=...
local root,group,mainButton,icon,cd
local buttons,slots={},{}
local layout
local lastState,lastOutput={},{}
local displayedKey,displayedID,wasPreview
local renderFault=false
local function Render()
    if not root then return end
    if ns.RefreshEditControls then ns.RefreshEditControls() end
    if ns.UpdateStingPreview then ns.UpdateStingPreview() end
    local preview=ns.preview==true
    local visible=ns.ShouldShow(ns.db,lastState,preview) and (not renderFault or preview)
    root:SetFrameStrata(preview and "DIALOG" or "MEDIUM")
    root:SetShown(visible)
    group:SetFrameStrata(preview and "DIALOG" or "MEDIUM")
    group:SetShown(visible and #slots>0);group:EnableMouse(preview)
    root:EnableMouse(preview)
    local key=preview and "arcane" or lastOutput.key
    if key=="mark" or key=="sting" or key=="auto" then key=nil end
    mainButton:SetShown(visible and key~=nil);mainButton:EnableMouse(visible and key~=nil and not preview and not lastState.inCombat)
    if key then
        local id=ns.known[key]
        if key~=displayedKey or id~=displayedID or preview~=wasPreview then
            icon:SetTexture(ns.SpellIcon(key));displayedKey=key;displayedID=id
        end
        icon:SetDesaturated(not preview and (lastOutput.wait==true or lastOutput.settling==true))
        local timed=ns.DrawMainCooldown(cd,key,lastState,lastOutput,preview)
        ns.unknownClock:SetShown(visible and not preview and lastOutput.wait==true and not timed)
        local font=cd.GetCountdownFontString and cd:GetCountdownFontString()
        if font and font.GetFont and font.SetFont and (font~=cd.hcfFontObject or cd.hcfFontSize~=ns.db.previewFontSize) then
            local path,_,flags=font:GetFont()
            if path and font:SetFont(path,ns.db.previewFontSize,flags)~=false then
                cd.hcfFontObject=font;cd.hcfFontSize=ns.db.previewFontSize
            end
        end
    else ns.unknownClock:Hide();cd:Clear();displayedKey=nil;displayedID=nil end
    if preview and not wasPreview then root:Raise() end
    wasPreview=preview
    local ready=ns.BurstReady(lastState);ready.mark=ns.MarkReminderReady(lastState)
    local enabled={};for _,k in ipairs(slots) do enabled[k]=true end
    for _,k in ipairs(ns.reminderOrder) do
        local b=buttons[k]
        local shown=visible and enabled[k] and (preview or ready[k]==true) or false
        b:SetFrameStrata(preview and "DIALOG" or "MEDIUM")
        b:SetShown(shown);b:EnableMouse(shown and not preview and not lastState.inCombat)
        if shown then b.icon:SetTexture(ns.SpellIcon(k)) end
        if ns.burstOption[k] then ns.SetGlow(b,shown and ns.db.burstGlow,b.visualSize or ns.db.burstSize) end
    end
end
function ns.ApplyUI()
    if not root then return end
    ns.MigrateGroup()
    layout=ns.IconLayout(ns.db,0);ns.hudLayout=layout
    root:SetSize(layout.width,layout.height)
    local x,y,fit,ax,ay=ns.LayoutGeometry(ns.db,UIParent:GetWidth(),UIParent:GetHeight(),layout)
    ns.appliedX=x;ns.appliedY=y;ns.appliedScale=fit
    if not ns.dragging then root:SetScale(fit);root:ClearAllPoints();root:SetPoint("CENTER",UIParent,"CENTER",ax,ay) end
    mainButton:SetSize(ns.db.mainSize,ns.db.mainSize);mainButton:ClearAllPoints()
    mainButton:SetPoint("TOPLEFT",root,"TOPLEFT",layout.mainX,0)
    if not ns.groupDragging then
        slots=ns.ReminderSlots(ns.db,ns.known)
        local gl=ns.GroupLayout(ns.db,#slots);ns.groupLayout=gl
        local gx,gy=ns.GroupOrigin(ns.db,ns.known)
        local x,y,scale,ax,ay=ns.GroupGeometry(gx,gy,UIParent:GetWidth(),UIParent:GetHeight(),gl)
        ns.groupAppliedX=x;ns.groupAppliedY=y;ns.groupAppliedScale=scale
        group:SetSize(gl.width,gl.height);group:SetScale(scale);group:ClearAllPoints()
        group:SetPoint("CENTER",UIParent,"CENTER",ax,ay)
        for i,k in ipairs(slots) do
            local b=buttons[k];b.visualSize=gl.size;b:SetSize(gl.size,gl.size);b:ClearAllPoints()
            b:SetPoint("CENTER",group,"CENTER",gl.firstOffset+gl.dir*(i-1)*gl.pitch,0)
        end
    end
    if ns.ApplySting then ns.ApplySting() end
    Render()
end
local function AbortDrag()
    if ns.dragging then root:StopMovingOrSizing();root:SetUserPlaced(false);ns.dragging=false;ns.ApplyUI() end
    if ns.groupDragging then group:StopMovingOrSizing();group:SetUserPlaced(false);ns.groupDragging=false;ns.ApplyUI() end
end
function ns.EndPreview()
    ns.preview=false;AbortDrag()
    if ns.StopStingDrag then ns.StopStingDrag(false) end
    Render()
end
function ns.FinishPreview()
    if ns.dragging then root:GetScript("OnDragStop")(root) end
    if ns.groupDragging then group:GetScript("OnDragStop")(group) end
    if ns.StopStingDrag then ns.StopStingDrag(true) end
    ns.EndPreview()
    if ns.RefreshOptions then ns.RefreshOptions() end
end
function ns.TogglePreview()
    if ns.LayoutLockedByCombat() then ns.EndPreview();return false end
    if ns.preview then ns.EndPreview() else ns.preview=true;Render() end;return true
end
local function OpenSettings() ns.Command("config") end
function ns.CreateUI()
    if root then return end
    root=CreateFrame("Frame","HunterCueForeverFrame",UIParent);ns.hud=root;ns.dragHandle=root
    root:SetMovable(true);root:SetUserPlaced(false);root:SetClampedToScreen(true);root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart",function()
        if ns.preview and not ns.db.locked and not ns.LayoutLockedByCombat() then ns.dragging=true;root:StartMoving() end
    end)
    root:SetScript("OnDragStop",function()
        if not ns.dragging then return end
        if ns.LayoutLockedByCombat() then AbortDrag();return end
        root:StopMovingOrSizing();root:SetUserPlaced(false);ns.dragging=false
        local x,y=root:GetCenter();local px,py=UIParent:GetCenter()
        if x and y and px and py then
            local dx,dy=ns.CenterToParent(x,y,root:GetEffectiveScale(),UIParent:GetEffectiveScale(),px,py)
            ns.SavePosition(dx,dy+layout.mainOffset*ns.appliedScale)
            ns.ApplyUI();if ns.RefreshOptions then ns.RefreshOptions() end
        end
    end)
    mainButton=CreateFrame("Button",nil,root);ns.mainButton=mainButton
    mainButton:RegisterForClicks("RightButtonUp");mainButton:SetScript("OnClick",OpenSettings)
    icon=mainButton:CreateTexture(nil,"ARTWORK");mainButton.icon=icon;icon:SetAllPoints(mainButton);icon:SetTexCoord(.08,.92,.08,.92)
    cd=CreateFrame("Cooldown",nil,mainButton,"CooldownFrameTemplate");cd:SetAllPoints(mainButton);ns.mainCooldown=cd
    local overlay=CreateFrame("Frame",nil,mainButton)
    overlay:SetAllPoints(mainButton)
    overlay:SetFrameLevel(cd:GetFrameLevel()+1)
    overlay:EnableMouse(false)
    local badge=overlay:CreateTexture(nil,"OVERLAY")
    badge:SetTexture(134400)
    badge:SetVertexColor(1,.72,.25)
    badge:SetSize(14,14)
    badge:SetPoint("TOPRIGHT",mainButton,"TOPRIGHT",-1,-1)
    badge:Hide()
    ns.unknownClock=badge
    cd:SetDrawSwipe(true)
    cd.noCooldownCount=true;cd:SetHideCountdownNumbers(true);cd:SetDrawEdge(false);cd:SetDrawBling(false)
    group=CreateFrame("Frame","HunterCueForeverBurstGroup",UIParent);ns.burstGroup=group
    group:SetMovable(true);group:SetUserPlaced(false);group:SetClampedToScreen(true);group:RegisterForDrag("LeftButton")
    group:SetScript("OnDragStart",function()
        if ns.preview and not ns.db.locked and not ns.LayoutLockedByCombat() then ns.groupDragging=true;group:StartMoving() end
    end)
    group:SetScript("OnDragStop",function()
        if not ns.groupDragging then return end
        if ns.LayoutLockedByCombat() then AbortDrag();return end
        group:StopMovingOrSizing();group:SetUserPlaced(false);ns.groupDragging=false
        local x,y=group:GetCenter();local px,py=UIParent:GetCenter()
        if x and y and px and py then
            x,y=ns.CenterToParent(x,y,group:GetEffectiveScale(),UIParent:GetEffectiveScale(),px,py)
            ns.db.burstX=math.max(-4000,math.min(4000,x+ns.groupLayout.firstOffset*ns.groupAppliedScale))
            ns.db.burstY=math.max(-4000,math.min(4000,y))
            ns.db.groupLayoutVersion=1 -- A deliberate drag overrides any still-pending automatic migration.
        end
        ns.ApplyUI();if ns.RefreshOptions then ns.RefreshOptions() end
    end)
    for _,key in ipairs(ns.reminderOrder) do
        local b=CreateFrame("Button",nil,group);b:RegisterForClicks("RightButtonUp");b:SetScript("OnClick",OpenSettings)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetAllPoints(b);b.icon:SetTexCoord(.08,.92,.08,.92)
        if ns.burstOption[key] then ns.CreateGlow(b,ns.db.burstSize) end
        b:Hide();buttons[key]=b
    end
    ns.burstButtons=buttons;ns.ApplyUI()
end
function ns.UpdateUI(s,out)
    lastState=s;lastOutput=out;renderFault=false
    if s.inCombat and ns.preview then ns.EndPreview() end
    Render()
end
function ns.ShowError()
    renderFault=true
    if ns.preview then Render();return end
    lastOutput={}
    if root then
        root:Hide();group:Hide();mainButton:Hide();ns.unknownClock:Hide();cd:Clear()
        for key,b in pairs(buttons) do
            b:Hide();if ns.burstOption[key] then ns.SetGlow(b,false,b.visualSize or ns.db.burstSize) end
        end
    end
end

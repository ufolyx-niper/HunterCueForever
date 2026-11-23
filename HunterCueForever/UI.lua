-- SPDX-License-Identifier: MIT
-- Icon-only surface. All instructions and diagnostics belong to Options/chat.
local _,ns=...
local root,mainButton,icon,cd
local buttons,slots={},{}
local layout
local lastState,lastOutput={},{}
local displayedKey,displayedID,wasPreview
local renderFault=false
local function Render()
    if not root then return end
    local preview=ns.preview==true
    if renderFault and not preview then root:Hide();return end
    root:SetFrameStrata(preview and "DIALOG" or "MEDIUM")
    root:SetShown(ns.ShouldShow(ns.db,lastState,preview))
    if not root:IsShown() then return end
    root:EnableMouse(preview)
    local key=preview and "arcane" or lastOutput.key
    if key=="mark" then key=nil end
    mainButton:SetShown(key~=nil);mainButton:EnableMouse(key~=nil and not preview and not lastState.inCombat)
    if key then
        local id=ns.known[key]
        if key~=displayedKey or id~=displayedID or preview~=wasPreview then
            icon:SetTexture(ns.SpellIcon(key));displayedKey=key;displayedID=id
        end
        icon:SetDesaturated(not preview and (lastOutput.wait==true or lastOutput.settling==true))
        if preview then cd:Clear() else ns.DrawCooldown(cd,key) end
    else cd:Clear();displayedKey=nil;displayedID=nil end
    if preview and not wasPreview then root:Raise() end
    wasPreview=preview
    local ready=ns.BurstReady(lastState);ready.mark=ns.MarkReminderReady(lastState)
    local enabled={};for _,k in ipairs(slots) do enabled[k]=true end
    for _,k in ipairs(ns.reminderOrder) do
        local b=buttons[k]
        local shown=enabled[k] and (preview or ready[k]==true) or false
        b:SetShown(shown);b:EnableMouse(shown and not preview and not lastState.inCombat)
        if shown then b.icon:SetTexture(ns.SpellIcon(k)) end
    end
end
function ns.ApplyUI()
    if not root then return end
    slots=ns.ReminderSlots(ns.db,ns.known);layout=ns.IconLayout(ns.db,#slots);ns.hudLayout=layout
    root:SetSize(layout.width,layout.height)
    local x,y,fit,ax,ay=ns.LayoutGeometry(ns.db,UIParent:GetWidth(),UIParent:GetHeight(),layout)
    ns.appliedX=x;ns.appliedY=y;ns.appliedScale=fit
    root:SetScale(fit);root:ClearAllPoints();root:SetPoint("CENTER",UIParent,"CENTER",ax,ay)
    mainButton:SetSize(ns.db.mainSize,ns.db.mainSize);mainButton:ClearAllPoints()
    mainButton:SetPoint("TOPLEFT",root,"TOPLEFT",layout.mainX,0)
    for i,k in ipairs(slots) do
        local b=buttons[k];b:SetSize(ns.db.burstSize,ns.db.burstSize);b:ClearAllPoints()
        b:SetPoint("TOPLEFT",root,"TOPLEFT",layout.burstX+(i-1)*(ns.db.burstSize+ns.db.burstSpacing),layout.burstY)
    end
    Render()
end
local function AbortDrag()
    if ns.dragging then root:StopMovingOrSizing();root:SetUserPlaced(false);ns.dragging=false;ns.ApplyUI() end
end
function ns.EndPreview() ns.preview=false;AbortDrag();Render() end
function ns.TogglePreview()
    if ns.LayoutLockedByCombat() then ns.EndPreview();return false end
    ns.preview=not ns.preview;if not ns.preview then AbortDrag() end;Render();return true
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
    cd.noCooldownCount=true;cd:SetHideCountdownNumbers(true);cd:SetDrawEdge(false);cd:SetDrawBling(false)
    for _,key in ipairs(ns.reminderOrder) do
        local b=CreateFrame("Button",nil,root);b:RegisterForClicks("RightButtonUp");b:SetScript("OnClick",OpenSettings)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetAllPoints(b);b.icon:SetTexCoord(.08,.92,.08,.92)
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
    if root then root:Hide();mainButton:Hide();cd:Clear();for _,b in pairs(buttons) do b:Hide() end end
end

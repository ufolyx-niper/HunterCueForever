-- SPDX-License-Identifier: MIT
local _,ns=...
ns.optionViews={}
local enums={spec={"auto","bm","mm","sv"},mode={"balanced","conserve","burst"},
    targets={1,3,6},visibility={"always","target","combat"},weave={"normal","aggressive"}}
local labels={auto="自动识别",bm="兽王",mm="射击",sv="生存 weaving",balanced="均衡",conserve="省蓝",burst="全力",
    always="始终显示",target="有敌对目标时",combat="仅战斗中",normal="常规穿插",aggressive="积极穿插",[1]="单体",[3]="3+ 目标",[6]="6+ 目标"}
local layoutFields={x=true,y=true,scale=true,fontScale=true,opacity=true,locked=true,showDetails=true}
local function ValidNumber(v) return type(v)=="number" and v==v and math.abs(v)<1e10 end
local function Refresh()
    if ns.ApplyUI then ns.ApplyUI() end
    ns.RefreshOptions()
end
function ns.SetPosition(x,y)
    if ns.LayoutLockedByCombat() or not ValidNumber(x) or not ValidNumber(y) or math.abs(x)>4000 or math.abs(y)>4000 then return false end
    ns.SavePosition(x,y);ns.resetArmed=false;Refresh();return true
end
function ns.SetOption(key,value)
    if ns.defaults[key]==nil or key=="layoutVersion" or key=="displayVersion" then return false end
    if layoutFields[key] and ns.LayoutLockedByCombat() then return false end
    if type(value)~=type(ns.defaults[key]) then return false end
    if ns.optionBounds[key] then local b=ns.optionBounds[key];if not ValidNumber(value) or value<b[1] or value>b[2] then return false end end
    if enums[key] then local found=false;for _,v in ipairs(enums[key]) do if v==value then found=true end end;if not found then return false end end
    ns.db[key]=value;ns.resetArmed=false
    if key=="spec" or key=="weave" then ns.ResetTracking() end
    Refresh();return true
end
function ns.ResetLayout()
    if ns.LayoutLockedByCombat() then return false end
    for _,k in ipairs(ns.layoutKeys) do ns.db[k]=ns.defaults[k] end
    ns.resetArmed=false;Refresh();return true
end
function ns.ResetAll()
    if not ns.resetArmed or ns.LayoutLockedByCombat() then return false end
    ns.db=ns.Settings({});HunterCueForeverDB=ns.db;ns.resetArmed=false;ns.EndPreview();ns.ResetTracking();Refresh();return true
end
local function Text(parent,text,x,y,width,size,height)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f:SetPoint("TOPLEFT",x,-y);f:SetWidth(width);f:SetHeight(height or 24);f:SetJustifyH("LEFT")
    local font,_,flags=f:GetFont();f:SetFont(font,size or 12,flags);f:SetText(text);return f
end
local function Button(parent,text,x,y,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",x,-y);b:SetSize(width,26);b:SetText(text);b:SetScript("OnClick",fn);return b
end
local function BuildCanvas(parent)
    local panel=CreateFrame("Frame",nil,parent);panel:Hide()
    local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",0,0);scroll:SetPoint("BOTTOMRIGHT",-28,0)
    local content=CreateFrame("Frame",nil,scroll);content:SetSize(560,1300);scroll:SetScrollChild(content)
    local v={panel=panel,controls={},layoutControls={},refreshing=false};ns.optionViews[#ns.optionViews+1]=v
    local c=v.controls
    Text(content,"HunterCue Forever · 设置",16,12,520,20,28)
    Text(content,"设置与战斗提示分开。/hcf 或脱战右键大图标打开这里；预览中可拖动。",16,46,520,12,32)
    Text(content,"显示与布局",16,88,520,16)
    local function Check(key,label,y,layout)
        local b=CreateFrame("CheckButton",nil,content,"UICheckButtonTemplate")
        b:SetPoint("TOPLEFT",16,-y);b:SetSize(26,26);Text(content,label,48,y+2,490,12,24)
        b:SetScript("OnClick",function(self) if not v.refreshing then ns.SetOption(key,self:GetChecked()==true) end end)
        c[key]=b;if layout then v.layoutControls[#v.layoutControls+1]=b end
    end
    local function Choice(key,label,y)
        Text(content,label,16,y+3,190,12)
        c[key]=Button(content,"",210,y,326,function()
            local values=enums[key];local idx=1
            for i,value in ipairs(values) do if ns.db[key]==value then idx=i%#values+1;break end end
            ns.SetOption(key,values[idx])
        end)
    end
    Check("enabled","显示 HUD（隐藏后仍可用 /hcf 打开设置）",112)
    Check("locked","锁定 HUD 位置（取消锁定后在预览中拖动）",146,true)
    Check("showDetails","在 HUD 显示详细减益/资源状态（默认关闭）",180,true)
    Choice("visibility","显示条件（点击切换）",214)
    local function Slider(key,label,y,low,high,step)
        Text(content,label,16,y,350,12)
        local number=Text(content,"",435,y,100,12)
        local b=CreateFrame("Slider",nil,content)
        b:SetPoint("TOPLEFT",20,-(y+27));b:SetSize(510,18);b:SetOrientation("HORIZONTAL")
        b:EnableMouse(true)
        b:SetMinMaxValues(low,high);b:SetValueStep(step)
        if b.SetObeyStepOnDrag then b:SetObeyStepOnDrag(true) end
        b:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local track=b:CreateTexture(nil,"BACKGROUND");track:SetPoint("LEFT",0,0);track:SetPoint("RIGHT",0,0);track:SetHeight(5);track:SetColorTexture(.18,.34,.42,1)
        b:SetScript("OnValueChanged",function(_,value)
            if not v.refreshing then ns.SetOption(key,math.floor(value/step+0.5)*step) end
        end)
        c[key]=b;c[key.."Label"]=number;v.layoutControls[#v.layoutControls+1]=b
    end
    Slider("scale","整体大小 / 图标 · 60–200%",257,.6,2,.05)
    Slider("fontScale","提示文字大小 · 90–125%",317,.9,1.25,.05)
    Slider("opacity","背景不透明度 · 20–100%（文字不变淡）",377,.2,1,.05)
    Text(content,"位置（相对屏幕中心；屏幕边缘自动限制）",16,443,520,13)
    local function Edit(key,x)
        Text(content,key:upper(),x,476,20,12)
        local b=CreateFrame("EditBox",nil,content,"InputBoxTemplate")
        b:SetPoint("TOPLEFT",x+26,-469);b:SetSize(160,26);b:SetAutoFocus(false);b:SetMaxLetters(12)
        b:SetScript("OnEscapePressed",function(self) self:ClearFocus();ns.RefreshOptions() end)
        c[key]=b
    end
    Edit("x",20);Edit("y",286)
    local function ApplyPosition()
        local ok=ns.SetPosition(tonumber(c.x:GetText()),tonumber(c.y:GetText()))
        c.x:ClearFocus();c.y:ClearFocus()
        if not ok then v.status:SetText("请输入 -4000 至 4000 的有效坐标，并在脱战时调整。") end
    end
    c.x:SetScript("OnEnterPressed",ApplyPosition);c.y:SetScript("OnEnterPressed",ApplyPosition)
    c.apply=Button(content,"应用坐标",16,506,110,ApplyPosition);v.layoutControls[#v.layoutControls+1]=c.apply
    c.center=Button(content,"居中",132,506,80,function() ns.SetPosition(0,0) end);v.layoutControls[#v.layoutControls+1]=c.center
    for i,entry in ipairs({{"左",-10,0},{"右",10,0},{"上",0,10},{"下",0,-10}}) do
        local label,dx,dy=entry[1],entry[2],entry[3]
        local b=Button(content,label,222+(i-1)*79,506,72,function() ns.SetPosition((ns.appliedX or ns.db.x)+dx,(ns.appliedY or ns.db.y)+dy) end)
        v.layoutControls[#v.layoutControls+1]=b;c["nudge"..i]=b
    end
    c.preview=Button(content,"",16,552,250,function() ns.TogglePreview();ns.RefreshOptions() end)
    v.layoutControls[#v.layoutControls+1]=c.preview
    Text(content,"预览只在脱战生效；关页或进战斗自动结束。",280,554,260,11,32)
    c.layoutReset=Button(content,"重置布局",16,596,140,ns.ResetLayout);v.layoutControls[#v.layoutControls+1]=c.layoutReset
    Text(content,"只恢复位置、大小、文字与背景，保留循环偏好。",170,598,365,11,32)
    Text(content,"常规循环与稳定提示",16,646,520,16)
    Choice("spec","专精（点击切换）",678);Choice("mode","输出策略（点击切换）",716);Choice("targets","目标数量（点击切换）",754)
    Check("traps","允许伤害陷阱提示（默认关闭，注意控场怪）",794)
    Choice("weave","穿插方式 · 仅生存",834)
    Check("stableRecommendations","公共 CD 内固定下一技能（推荐）",878)
    Text(content,"原建议失效时仍会纠正；取消勾选则实时更新。\n战斗切换：/hcf targets next 或 /hcf mode next，可手动放入宏。",16,916,520,11,40)
    Text(content,"独立爆发栏 · 冷却中隐藏",16,976,520,16)
    Check("cooldowns","启用下方爆发提醒（不替换大图标）",1008)
    Check("burstRacial","巨魔：狂暴",1042)
    Check("burstRapid","急速射击",1076)
    Check("burstWrath","兽王：狂野怒火",1110)
    Text(content,"只显示已学会且自身冷却就绪的技能；仅公共CD不会让图标闪烁。\n冷却/不可用/信息未知时完全隐藏。声音未启用。",16,1144,520,11,40)
    c.reset=Button(content,"重置全部设置…",16,1200,250,function()
        if ns.LayoutLockedByCombat() then return end
        if ns.resetArmed then ns.ResetAll() else ns.resetArmed=true;ns.RefreshOptions() end
    end);v.layoutControls[#v.layoutControls+1]=c.reset
    v.status=Text(content,"",16,1242,520,12,42)
    function v.Refresh()
        v.refreshing=true
        for _,k in ipairs({"enabled","locked","cooldowns","traps","showDetails","stableRecommendations","burstRacial","burstRapid","burstWrath"}) do c[k]:SetChecked(ns.db[k]) end
        for k in pairs(enums) do c[k]:SetText(labels[ns.db[k]]) end
        for _,k in ipairs({"scale","fontScale","opacity"}) do c[k]:SetValue(ns.db[k]);c[k.."Label"]:SetText(math.floor(ns.db[k]*100+0.5).."%") end
        c.x:SetText(string.format("%.1f",ns.db.x));c.y:SetText(string.format("%.1f",ns.db.y))
        local combat=ns.LayoutLockedByCombat()
        for _,b in ipairs(v.layoutControls) do b:SetEnabled(not combat) end
        c.x:EnableMouse(not combat);c.y:EnableMouse(not combat)
        if combat then c.x:ClearFocus();c.y:ClearFocus() end
        c.weave:SetEnabled(ns.Profile()=="sv")
        for _,key in ipairs(ns.burstOrder) do c[ns.burstOption[key]]:SetEnabled(ns.known[key]~=nil and ns.db.cooldowns) end
        c.preview:SetText(ns.preview and "结束布局预览" or "预览 HUD（无需目标）")
        c.reset:SetText(ns.resetArmed and "确认重置全部设置" or "重置全部设置…")
        local fit=ns.appliedScale and ns.appliedScale<ns.db.scale-0.001
        local positioned=ns.appliedX and (math.abs(ns.appliedX-ns.db.x)>0.1 or math.abs(ns.appliedY-ns.db.y)>0.1)
        v.status:SetText(combat and "战斗中：布局编辑与预览已暂停。" or ns.resetArmed and "再次点击将恢复全部默认，包括循环偏好。关闭页面取消。"
            or fit and ("屏幕空间限制：实际大小 "..math.floor(ns.appliedScale*100+0.5).."%；原始位置已保留")
            or positioned and "位置暂时限制在当前屏幕内；原始坐标已保留。" or "已保存 · 立即生效 · /hcf 可随时找回设置入口")
        v.refreshing=false
    end
    panel:SetScript("OnShow",function() ns.resetArmed=false;v.Refresh() end)
    panel:SetScript("OnHide",function() ns.resetArmed=false;ns.EndPreview() end)
    v.Refresh();return v
end
function ns.RefreshOptions() for _,v in ipairs(ns.optionViews) do v.Refresh() end end
local fallback
local function OpenFallback()
    if not fallback then
        fallback=CreateFrame("Frame","HunterCueForeverOptionsWindow",UIParent,"BackdropTemplate")
        fallback:Hide()
        fallback:SetSize(620,620);fallback:SetPoint("CENTER");fallback:SetFrameStrata("DIALOG");fallback:SetClampedToScreen(true)
        fallback:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        fallback:SetBackdropColor(.035,.045,.065,1);fallback:SetMovable(true);fallback:EnableMouse(true);fallback:RegisterForDrag("LeftButton")
        fallback:SetScript("OnDragStart",function(self) if not ns.LayoutLockedByCombat() then self:StartMoving() end end)
        fallback:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        Text(fallback,"HunterCue Forever",16,10,430,16)
        Button(fallback,"关闭",510,8,90,function() fallback:Hide() end)
        local v=BuildCanvas(fallback);v.panel:SetPoint("TOPLEFT",8,-40);v.panel:SetPoint("BOTTOMRIGHT",-8,8);v.panel:Show()
        fallback:SetScript("OnHide",function() ns.resetArmed=false;ns.EndPreview() end)
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="HunterCueForeverOptionsWindow" end
        ns.fallbackOptions=fallback
    end
    fallback:SetScale(math.min(1,(UIParent:GetWidth()-24)/620,(UIParent:GetHeight()-24)/620))
    fallback:Show();fallback:Raise();ns.RefreshOptions()
end
function ns.InitOptions()
    local v=BuildCanvas(UIParent)
    local ok=pcall(function()
        local category=Settings.RegisterCanvasLayoutCategory(v.panel,"HunterCue Forever")
        Settings.RegisterAddOnCategory(category);ns.optionsCategory=category:GetID()
    end)
    if not ok then ns.optionsCategory=nil end
    v.panel:Hide() -- registration is not a request to open configuration at login
end
function ns.OpenOptions()
    if ns.LayoutLockedByCombat() then return false end
    if ns.optionsCategory and Settings and type(Settings.OpenToCategory)=="function" then
        local ok=pcall(Settings.OpenToCategory,ns.optionsCategory)
        if ok then ns.RefreshOptions();return true end
    end
    OpenFallback();return true
end

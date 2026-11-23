-- SPDX-License-Identifier: MIT
local _,ns=...
ns.optionViews={}
local enums={spec={"auto","bm","mm","sv"},mode={"balanced","conserve","burst"},
    targets={1,3,6},visibility={"always","target","combat"},weave={"normal","aggressive"},markReminder={"off","priority","all"}}
local labels={auto="自动识别",bm="兽王",mm="射击",sv="生存 weaving",balanced="均衡",conserve="省蓝",burst="全力",
    always="始终显示",target="有敌对目标时",combat="仅战斗中",normal="常规穿插",aggressive="积极穿插",off="关闭",priority="精英 / 首领（推荐）",all="所有敌对目标",[1]="单体",[3]="3+ 目标",[6]="6+ 目标"}
local layoutFields={x=true,y=true,mainSize=true,burstSize=true,burstSpacing=true,rowGap=true,locked=true,stingSize=true,stingX=true,stingY=true}
for key in pairs(ns.positionKeys) do layoutFields[key]=true end
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
    if ns.defaults[key]==nil or key=="layoutVersion" or key=="displayVersion" or key=="iconLayoutVersion" or key=="auxiliaryLayoutVersion" then return false end
    if layoutFields[key] and ns.LayoutLockedByCombat() then return false end
    if type(value)~=type(ns.defaults[key]) then return false end
    if ns.optionBounds[key] then local b=ns.optionBounds[key];if not ValidNumber(value) or value<b[1] or value>b[2] then return false end end
    if enums[key] then local found=false;for _,v in ipairs(enums[key]) do if v==value then found=true end end;if not found then return false end end
    if ns.optionBounds[key] and not ns.positionKeys[key] then value=math.floor(value+0.5) end
    ns.db[key]=value;ns.resetArmed=false
    if key=="spec" or key=="weave" then ns.ResetTracking() end
    Refresh();return true
end
function ns.ResetLayout()
    if ns.LayoutLockedByCombat() then return false end
    for _,k in ipairs(ns.layoutKeys) do ns.db[k]=ns.defaults[k] end
    ns.db.auxiliaryLayoutVersion=0
    ns.resetArmed=false;Refresh();return true
end
function ns.ArrangeSmallIcons()
    if ns.LayoutLockedByCombat() then return false end
    ns.ArrangeAuxiliary(ns.db,ns.known,false);Refresh();return true
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
local editBar
function ns.RefreshEditControls()
    if not editBar and ns.preview then
        editBar=CreateFrame("Frame","HunterCueForeverEditControls",UIParent)
        editBar:Hide();editBar:SetSize(400,28);editBar:SetPoint("TOP",UIParent,"TOP",0,-28)
        editBar:SetFrameStrata("FULLSCREEN_DIALOG");editBar:SetClampedToScreen(true)
        editBar.lock=Button(editBar,"",0,0,160,function()
            ns.SetOption("locked",not ns.db.locked)
        end)
        editBar.done=Button(editBar,"完成定位",170,0,110,ns.FinishPreview)
        Button(editBar,"设置",290,0,100,function() ns.OpenOptions() end)
        ns.editControls=editBar
    end
    if editBar then
        editBar:SetShown(ns.preview==true and not ns.LayoutLockedByCombat())
        editBar.lock:SetText(ns.db.locked and "解锁位置" or "锁定位置")
    end
end
function ns.StartPositioning()
    if ns.LayoutLockedByCombat() then return false end
    ns.db.locked=false;ns.preview=true
    ns.ApplyUI();ns.RefreshOptions()
    if SettingsPanel and type(SettingsPanel.Close)=="function" and SettingsPanel:IsShown() then
        pcall(SettingsPanel.Close,SettingsPanel,true)
    end
    if ns.fallbackOptions then ns.fallbackOptions:Hide() end
    return true
end
local function BuildCanvas(parent)
    local panel=CreateFrame("Frame",nil,parent);panel:Hide()
    local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",0,0);scroll:SetPoint("BOTTOMRIGHT",-28,0)
    local content=CreateFrame("Frame",nil,scroll);content:SetSize(560,2070);scroll:SetScrollChild(content)
    local v={panel=panel,controls={},layoutControls={},numericControls={},refreshing=false};ns.optionViews[#ns.optionViews+1]=v
    local c=v.controls
    Text(content,"HunterCue Forever · 设置",16,12,520,20,28)
    Text(content,"纯图标 HUD。每个图标可单独拖动；/hcf 或脱战右键主/爆发/印记打开设置。",16,46,520,12,32)
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
    Choice("visibility","显示条件（点击切换）",182)
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
    Slider("mainSize","主推荐图标大小 · 24–160 px",225,24,160,1)
    Slider("burstSize","下方提醒图标大小 · 12–96 px",285,12,96,1)
    Slider("burstSpacing","排列横向间隔 · 0–40 px（点击一键排列应用）",345,0,40,1)
    Slider("rowGap","排列上下距离 · 0–80 px（点击一键排列应用）",405,0,80,1)
    Text(content,"大图标位置；小图标可逐个拖动",16,471,290,12)
    c.arrange=Button(content,"一键排列小图标",320,463,216,ns.ArrangeSmallIcons)
    v.layoutControls[#v.layoutControls+1]=c.arrange
    local function Edit(key,x)
        Text(content,key:upper(),x,504,20,12)
        local b=CreateFrame("EditBox",nil,content,"InputBoxTemplate")
        b:SetPoint("TOPLEFT",x+26,-497);b:SetSize(160,26);b:SetAutoFocus(false);b:SetMaxLetters(12)
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
    c.apply=Button(content,"应用坐标",16,534,110,ApplyPosition);v.layoutControls[#v.layoutControls+1]=c.apply
    c.center=Button(content,"居中",132,534,80,function() ns.SetPosition(0,0) end);v.layoutControls[#v.layoutControls+1]=c.center
    for i,entry in ipairs({{"左",-10,0},{"右",10,0},{"上",0,10},{"下",0,-10}}) do
        local label,dx,dy=entry[1],entry[2],entry[3]
        local b=Button(content,label,222+(i-1)*79,534,72,function() ns.SetPosition((ns.appliedX or ns.db.x)+dx,(ns.appliedY or ns.db.y)+dy) end)
        v.layoutControls[#v.layoutControls+1]=b;c["nudge"..i]=b
    end
    c.preview=Button(content,"",16,580,250,function() ns.TogglePreview();ns.RefreshOptions() end)
    v.layoutControls[#v.layoutControls+1]=c.preview
    c.position=Button(content,"解锁并定位",280,580,250,ns.StartPositioning)
    v.layoutControls[#v.layoutControls+1]=c.position
    c.layoutReset=Button(content,"重置布局",16,624,140,ns.ResetLayout);v.layoutControls[#v.layoutControls+1]=c.layoutReset
    Text(content,"关闭设置仍可拖动；点屏幕上方“完成”结束。\n进战斗自动退出。重置布局保留循环偏好。",170,620,365,11,44)
    Text(content,"常规循环与稳定提示",16,674,520,16)
    Choice("spec","专精（点击切换）",706);Choice("mode","输出策略（点击切换）",744);Choice("targets","目标数量（点击切换）",782)
    Check("traps","允许伤害陷阱提示（默认关闭，注意控场怪）",822)
    Choice("weave","穿插方式 · 仅生存",862)
    Check("stableRecommendations","公共 CD 内固定下一技能（推荐）",906)
    Text(content,"读条期间灰色图标是下一技能预告：等读条结束，勿打断。\n原建议失效仍会纠正；取消勾选则实时更新。\n战斗切换：/hcf targets next 或 /hcf mode next。",16,944,520,11,52)
    Text(content,"独立爆发栏 · 冷却中隐藏",16,1004,520,16)
    Check("cooldowns","启用下方爆发提醒（不替换大图标）",1036)
    Check("burstRacial","巨魔：狂暴",1070)
    Check("burstRapid","急速射击",1104)
    Check("burstWrath","兽王：狂野怒火",1138)
    Text(content,"只显示已学会且自身冷却就绪的技能；仅公共CD不会让图标闪烁。\n冷却/不可用/信息未知时完全隐藏。声音未启用。",16,1172,520,11,40)
    Text(content,"猎人印记 · 独立提醒，不进入常规大图标",16,1250,520,16)
    Choice("markReminder","印记提醒范围",1286)
    Check("markInCombat","战斗中也提醒（默认关闭，避免切怪时催促转标）",1324)
    Text(content,"默认仅对尚未战斗的精英/首领提醒。已有任何猎人印记、状态未知时不亮。\n此提醒不受爆发栏总开关控制；“仅战斗显示”会隐藏默认的开怪前提醒。\n所有图标仅作提示，仍需自己按技能；不会自动转移或覆盖印记。",16,1358,520,11,64)
    Text(content,"毒蛇钉刺 · 独立监控",16,1450,520,16)
    Check("stingEnabled","启用毒蛇监控（不进入常规大图标）",1482)
    Check("stingIdle","没有补钉刺提示时保留灰色图标（默认隐藏）",1516)
    Slider("stingSize","毒蛇图标大小 · 16–128 px",1554,16,128,1)
    local function NumberField(key,label,y)
        Text(content,label,16,y+3,340,12)
        local b=CreateFrame("EditBox",nil,content,"InputBoxTemplate")
        b:SetPoint("TOPLEFT",370,-y);b:SetSize(160,26);b:SetAutoFocus(false);b:SetMaxLetters(12)
        b:SetScript("OnTextChanged",function(self,userInput) if userInput then self.inputDirty=true end end)
        local function Save(self)
            if v.refreshing or not self.inputDirty then return end
            self.inputDirty=false
            ns.SetOption(key,tonumber(self:GetText()));ns.RefreshOptions()
        end
        b:SetScript("OnEnterPressed",function(self) Save(self);self:ClearFocus() end)
        b:SetScript("OnEditFocusLost",Save)
        b:SetScript("OnEscapePressed",function(self) self.inputDirty=false;self:SetText(tostring(ns.db[key]));self:ClearFocus() end)
        c[key]=b;v.numericControls[#v.numericControls+1]=b
    end
    NumberField("stingX","毒蛇 X · -4000 至 4000",1618)
    NumberField("stingY","毒蛇 Y · -4000 至 4000",1656)
    NumberField("stingRefreshTime","预计剩余击杀时间门槛 · 1–60 秒",1694)
    Check("stingOpening","估不出存活时间时启用开怪血量规则",1732)
    NumberField("stingOpeningHealth","开怪当前血量门槛 · 1–10000000",1770)
    Check("stingSkipElementals","跳过元素生物的补钉刺提醒（按类别，非免疫判断）",1810)
    Text(content,"灰色 + 转圈：已有你的钉刺；亮色：缺失且值得补。无数字/边框。\n只监控当前敌对目标，可单独拖动。关闭设置后仍可继续定位。\n开怪默认血量 5000，估算存活默认 10 秒；不是必中或 DPS 保证。",16,1848,520,11,64)
    c.stingStatus=Text(content,"",16,1920,520,11,48)
    c.reset=Button(content,"重置全部设置…",16,1990,250,function()
        if ns.LayoutLockedByCombat() then return end
        if ns.resetArmed then ns.ResetAll() else ns.resetArmed=true;ns.RefreshOptions() end
    end);v.layoutControls[#v.layoutControls+1]=c.reset
    v.status=Text(content,"",16,2026,520,12,42)
    function v.Refresh()
        v.refreshing=true
        for _,k in ipairs({"enabled","locked","cooldowns","traps","markInCombat","stableRecommendations","burstRacial","burstRapid","burstWrath","stingEnabled","stingIdle","stingOpening","stingSkipElementals"}) do c[k]:SetChecked(ns.db[k]) end
        for k in pairs(enums) do c[k]:SetText(labels[ns.db[k]]) end
        for _,k in ipairs({"mainSize","burstSize","burstSpacing","rowGap","stingSize"}) do c[k]:SetValue(ns.db[k]);c[k.."Label"]:SetText(ns.db[k].." px") end
        c.x:SetText(string.format("%.1f",ns.db.x));c.y:SetText(string.format("%.1f",ns.db.y))
        for _,k in ipairs({"stingX","stingY","stingRefreshTime","stingOpeningHealth"}) do
            c[k].inputDirty=false
            c[k]:SetText(ns.positionKeys[k] and string.format("%.1f",ns.db[k]) or tostring(ns.db[k]))
        end
        c.stingStatus:SetText(ns.stingConflict and "旧 Serpent Sting Hint 正在运行：内置监控已暂停，请停用旧插件并 /reload。"
            or ns.stingUnsupported and "当前客户端原生减益接口不可用，毒蛇监控已停用；常规循环不受影响。"
            or ns.stingInitialized and not ns.stingEstimatorReady and "可显示已有钉刺，但健康曲线接口不可用，无法估算补钉刺提醒。"
            or "原毒蛇插件的设置不会被删除；合并版选项独立保存。总显隐也适用于毒蛇。")
        local combat=ns.LayoutLockedByCombat()
        for _,b in ipairs(v.layoutControls) do b:SetEnabled(not combat) end
        for _,b in ipairs(v.numericControls) do
            b:EnableMouse(not combat);b:EnableKeyboard(not combat)
            if combat then b:ClearFocus() end
        end
        c.x:EnableMouse(not combat);c.y:EnableMouse(not combat)
        if combat then c.x:ClearFocus();c.y:ClearFocus() end
        c.stingOpeningHealth:EnableMouse(not combat and ns.db.stingOpening)
        c.stingOpeningHealth:EnableKeyboard(not combat and ns.db.stingOpening)
        c.weave:SetEnabled(ns.Profile()=="sv")
        c.markInCombat:SetEnabled(ns.db.markReminder~="off")
        for _,key in ipairs(ns.burstOrder) do c[ns.burstOption[key]]:SetEnabled(ns.known[key]~=nil and ns.db.cooldowns) end
        c.preview:SetText(ns.preview and "结束布局预览" or "预览 HUD（无需目标）")
        c.reset:SetText(ns.resetArmed and "确认重置全部设置" or "重置全部设置…")
        local fit=ns.appliedScale and ns.appliedScale<0.999
        local positioned=ns.appliedX and (math.abs(ns.appliedX-ns.db.x)>0.1 or math.abs(ns.appliedY-ns.db.y)>0.1)
        v.status:SetText(combat and "战斗中：布局编辑与预览已暂停。" or ns.resetArmed and "再次点击将恢复全部默认，包括循环偏好。关闭页面取消。"
            or fit and ("屏幕空间限制：实际大小 "..math.floor(ns.appliedScale*100+0.5).."%；原始位置已保留")
            or positioned and "位置暂时限制在当前屏幕内；原始坐标已保留。" or (ns.db.visibility=="combat" and ns.db.markReminder~="off" and not ns.db.markInCombat) and "仅战斗显示会隐藏开怪前印记；可改显隐或允许战斗中提醒。"
            or "已保存 · 立即生效 · /hcf 可随时找回设置入口")
        v.refreshing=false
    end
    panel:SetScript("OnShow",function() ns.resetArmed=false;v.Refresh() end)
    panel:SetScript("OnHide",function() ns.resetArmed=false end)
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
        fallback:SetScript("OnHide",function() ns.resetArmed=false end)
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

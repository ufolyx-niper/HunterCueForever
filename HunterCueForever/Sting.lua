-- SPDX-License-Identifier: GPL-2.0-only
-- Modified 2026-11-22 by ufolyx-niper: HunterCue integration and pure-icon monitoring.
-- Aura clipping after EverAuras, and health-curve projection after Last Breath Forever.
-- Adapted from SerpentStingHint 0.1.4. See THIRD_PARTY.txt and the accompanying licenses.
local addon, ns = ...
-- Called only after the host validates hunter/Forever and loads its settings.
function ns.InitSting()
if ns.stingAnchor then return end

local ICON_SIZE = 44
local SPELL_ICON = "Interface\\Icons\\Ability_Hunter_Quickshot"
local STING_RANKS = {
    [1978] = true, [13549] = true, [13550] = true, [13551] = true, [13552] = true,
    [13553] = true, [13554] = true, [13555] = true, [25295] = true,
}
local FILTER = "HARMFUL|PLAYER"
local ELEMENTAL_TYPE = 4
local LAYOUT_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"
local MIN_TIME = 2
local MIN_HITS = 3
local MIN_LOSS = 0.05
local MAX_IDLE = 5
local OPENING_TIME = 6
local BAND_COUNT = 40
local EPSILON = 0.0000001

local anchor = CreateFrame("Frame", nil, UIParent)
anchor:SetSize(1, 1)
anchor:SetPoint("CENTER", UIParent, "CENTER", 140, -100)
ns.stingAnchor = anchor
local root = CreateFrame("Frame", nil, anchor, LAYOUT_TEMPLATE)
root:SetSize(ICON_SIZE, ICON_SIZE)
root:SetPoint("CENTER", anchor)
root:Hide()
ns.stingRoot = root
local sampleGates = {}
local sampleTime, lastHit, hits
local estimatesVisible = false
local thresholdCurve, transparent, opaque
local elapsedUpdate = 0
local initialized, unsupported, estimatorReady
local timerContainer, missingContainer
local missingClip, targetCreatureType
local openingHighlight, openingEndsAt, targetMaxHealth
local neutral

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function TargetIsAttackable()
    local attackable = UnitCanAttack("player", "target")
    local dead = UnitIsDeadOrGhost("target")
    return not IsSecret(attackable) and attackable == true
        and not IsSecret(dead) and dead == false
end

local function RefreshReminders()
    if not missingClip or not root:IsShown() then return end
    if ns.db.stingSkipElementals and type(UnitCreatureType) == "function" then
        local ok, _, creatureType = pcall(UnitCreatureType, "target")
        if ok and not IsSecret(creatureType) and type(creatureType) == "number" then
            targetCreatureType = creatureType
        end
    end
    missingClip:SetShown(not (ns.db.stingSkipElementals and targetCreatureType == ELEMENTAL_TYPE))
end

local preview = CreateFrame("Frame", nil, UIParent)
ns.stingPreview = preview
preview:SetFrameStrata("DIALOG");preview:SetMovable(true);preview:SetClampedToScreen(true)
preview:SetUserPlaced(false);preview:RegisterForDrag("LeftButton");preview:Hide()
local dragging = false
local Initialize, RefreshTarget
local function LegacyLoaded()
    if not C_AddOns or type(C_AddOns.IsAddOnLoaded)~="function" then return false end
    local ok, loaded=pcall(C_AddOns.IsAddOnLoaded,"SerpentStingHint")
    return ok and not IsSecret(loaded) and loaded==true
end
local function CheckLegacy()
    ns.stingConflict=LegacyLoaded()
    if ns.stingConflict and not ns.stingConflictWarned then
        ns.stingConflictWarned=true
        print("HunterCue：检测到 Serpent Sting Hint，已暂停内置毒蛇监控。请停用旧插件并 /reload。")
    end
end
local function Place(frame)
    local size=ns.db.stingSize
    local mx=math.max(0,(UIParent:GetWidth()-size)/2)
    local my=math.max(0,(UIParent:GetHeight()-size)/2)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER",UIParent,"CENTER",math.max(-mx,math.min(mx,ns.db.stingX)),math.max(-my,math.min(my,ns.db.stingY)))
end
function ns.UpdateStingPreview()
    local editing=ns.preview==true and not ns.LayoutLockedByCombat()
    preview:SetShown(editing and ns.db.stingEnabled and not ns.stingConflict)
    preview:EnableMouse(editing and not ns.db.locked)
    anchor:SetShown(not editing)
    if not ns.LayoutLockedByCombat() and not dragging then
        preview:SetSize(ns.db.stingSize,ns.db.stingSize);Place(preview)
    end
end
function ns.StopStingDrag(save)
    if not dragging then return end
    preview:StopMovingOrSizing();preview:SetUserPlaced(false);dragging=false
    if save and not ns.LayoutLockedByCombat() then
        local x,y=preview:GetCenter();local px,py=UIParent:GetCenter()
        if x and y and px and py then
            x,y=ns.CenterToParent(x,y,preview:GetEffectiveScale(),UIParent:GetEffectiveScale(),px,py)
            ns.db.stingX=math.max(-4000,math.min(4000,x));ns.db.stingY=math.max(-4000,math.min(4000,y))
        end
    end
    ns.ApplySting()
    if ns.RefreshOptions then ns.RefreshOptions() end
end
preview:SetScript("OnDragStart",function()
    if ns.preview and not ns.db.locked and not ns.LayoutLockedByCombat() then dragging=true;preview:StartMoving() end
end)
preview:SetScript("OnDragStop",function() ns.StopStingDrag(true) end)
local function ApplySettings()
    if not ns.LayoutLockedByCombat() then
        -- Keep the native 44/45/1 clipping geometry fixed; size is scale-only.
        root:SetScale(ns.db.stingSize / ICON_SIZE);Place(anchor)
        ns.stingLayoutPending=false
    else
        ns.stingLayoutPending=true
    end
    ns.UpdateStingPreview()
    if neutral then neutral:SetShown(ns.db.stingIdle) end
    if RefreshTarget then RefreshTarget() end
end
function ns.ApplySting()
    local ok=pcall(function()
        if Initialize then Initialize() end
        ApplySettings()
    end)
    if not ok then root:Hide();ns.stingFault=true end
end

local function NewIcon(parent)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(parent)
    icon:SetTexture(SPELL_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return icon
end

NewIcon(preview)

local function NewAuraContainer()
    local container = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
    container:SetPoint("TOPLEFT", root, "TOPLEFT")
    return container
end

local function BuildAuraDisplay()
    neutral = NewIcon(root)
    neutral:SetDesaturated(true)
    neutral:SetVertexColor(0.55, 0.55, 0.55)

    local tracker = NewAuraContainer()
    tracker:SetFrameLevel(root:GetFrameLevel() + 4)
    local slot = tracker:AddAuraSlot("sting-timer", FILTER, {
        candidateFilters = { includeSpellIDs = STING_RANKS },
        initializeFrame = function(button)
            button:ClearAllPoints()
            button:SetAllPoints(root)
            button:SetMouseClickEnabled(false)
            button:EnableMouseMotion(false)
            local icon = NewIcon(button)
            icon:SetDesaturated(true)
            local sweep=CreateFrame("Cooldown",nil,button,"CooldownFrameTemplate")
            sweep:SetAllPoints(button);sweep:SetHideCountdownNumbers(true);sweep.noCooldownCount=true
            sweep:SetDrawEdge(false);sweep:SetDrawBling(false)
            button:SetIcon(icon)
            button:SetDurationCooldown(sweep)
        end,
    })
    assert(slot, "Aura slot unavailable")
    tracker:SetUnit("target")
    tracker:SetEnabled(true)

    local indicator = NewAuraContainer()
    indicator:AddAuraGroup("sting-missing", FILTER, {
        candidateFilters = { includeSpellIDs = STING_RANKS },
        maxFrameCount = 1,
        layout = { elementWidth = ICON_SIZE + 1, elementHeight = ICON_SIZE },
        initializeFrame = function(button)
            button:SetSize(ICON_SIZE + 1, ICON_SIZE)
            button:SetMouseClickEnabled(false)
            button:EnableMouseMotion(false)
        end,
    })
    indicator:SetUnit("target")
    indicator:SetEnabled(true)

    -- The engine gives the group width 1 when empty, or ICON_SIZE + 1 when occupied.
    local missingClip = CreateFrame("Frame", nil, root, LAYOUT_TEMPLATE)
    missingClip:SetFrameLevel(root:GetFrameLevel() + 1)
    missingClip:SetClipsChildren(true)
    missingClip:SetPoint("TOPLEFT", indicator, "TOPRIGHT", -1, 0)
    missingClip:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT")
    timerContainer, missingContainer = tracker, indicator
    return missingClip
end

local function NewColorCurve()
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    return curve
end

local function NewHighlight(parent)
    local highlight = CreateFrame("Frame", nil, parent, LAYOUT_TEMPLATE)
    highlight:SetAllPoints(root)
    NewIcon(highlight)
    return highlight
end

local function BuildEstimateDisplay(missingClip)
    transparent = CreateColor(1, 1, 1, 0)
    opaque = CreateColor(1, 1, 1, 1)
    thresholdCurve = NewColorCurve()
    openingHighlight = NewHighlight(missingClip)
    openingHighlight:Hide()

    for index = 1, BAND_COUNT do
        local lower = (index - 1) / BAND_COUNT
        local upper = index / BAND_COUNT
        local band = NewColorCurve()
        band:AddPoint(0, index == 1 and opaque or transparent)
        if index > 1 then band:AddPoint(lower, opaque) end
        if index < BAND_COUNT then band:AddPoint(upper, transparent) end

        local sampleGate = CreateFrame("Frame", nil, missingClip, LAYOUT_TEMPLATE)
        sampleGate:SetAllPoints(root)
        sampleGate:Hide()
        sampleGates[index] = { band = band, upper = upper, frame = sampleGate, highlight = NewHighlight(sampleGate) }
    end
end

local function HideEstimates()
    if not estimatesVisible then return end
    for _, gate in ipairs(sampleGates) do gate.frame:Hide() end
    estimatesVisible = false
end

local function ResetSample()
    HideEstimates()
    if openingHighlight then openingHighlight:Hide() end
    sampleTime, lastHit, hits = nil, nil, 0
end

local function ApplyHealthCurve(frame, curve)
    -- Alpha is used only by the engine. Its value is never inspected or compared in Lua.
    local color = UnitHealthPercent("target", false, curve)
    local _, _, _, alpha = color:GetRGBA()
    frame:SetAlpha(alpha)
end

local function StartSample(now)
    for _, gate in ipairs(sampleGates) do
        ApplyHealthCurve(gate.frame, gate.band)
    end
    sampleTime, lastHit, hits = now, now, 1
end

local function OpeningThreshold(now)
    if not openingEndsAt then
        local fighting = UnitAffectingCombat("target")
        if not IsSecret(fighting) and fighting == true then openingEndsAt = now + OPENING_TIME end
    end
    if not ns.db.stingOpening or (openingEndsAt and now >= openingEndsAt) then return nil end

    local ok, maximum = pcall(UnitHealthMax, "target")
    if ok and not IsSecret(maximum) and type(maximum) == "number" then
        targetMaxHealth = maximum
    end
    local openingHealth = ns.db.stingOpeningHealth
    if targetMaxHealth and targetMaxHealth >= openingHealth then
        -- Put the float boundary between the two adjacent whole HP values.
        return (openingHealth - 0.5) / targetMaxHealth
    end
end

local function UpdateEstimate(now)
    if not estimatorReady or not root:IsShown() then return end
    if sampleTime and now - lastHit >= MAX_IDLE then
        openingEndsAt = now
        ResetSample()
    end
    local openingThreshold = OpeningThreshold(now)
    local elapsed = sampleTime and now - sampleTime
    if not elapsed or hits < MIN_HITS or elapsed < MIN_TIME then
        openingHighlight:Hide()
        if openingThreshold then
            thresholdCurve:ClearPoints()
            thresholdCurve:AddPoint(0, transparent)
            thresholdCurve:AddPoint(openingThreshold, opaque)
            ApplyHealthCurve(openingHighlight, thresholdCurve)
            openingHighlight:Show()
        end
        return
    end
    openingHighlight:Hide()

    local refreshTime = ns.db.stingRefreshTime
    for _, gate in ipairs(sampleGates) do
        -- Use the top of the sampled health band as the starting share. With a constant
        -- damage rate, time left exceeds 10 s only above this projected health share.
        local lower = refreshTime * gate.upper / (refreshTime + elapsed) + EPSILON
        local enoughLossBelow = gate.upper - MIN_LOSS
        local openingFrom = openingThreshold and math.max(openingThreshold, enoughLossBelow)
        thresholdCurve:ClearPoints()
        thresholdCurve:AddPoint(0, transparent)
        if lower < enoughLossBelow then
            thresholdCurve:AddPoint(lower, opaque)
            if openingFrom ~= enoughLossBelow then
                thresholdCurve:AddPoint(enoughLossBelow, transparent)
            end
        end
        -- Above the loss cutoff, this band still has insufficient data for a TTD estimate.
        if openingFrom and (lower >= enoughLossBelow or openingFrom > enoughLossBelow) then
            thresholdCurve:AddPoint(openingFrom, opaque)
        end
        ApplyHealthCurve(gate.highlight, thresholdCurve)
    end
    if not estimatesVisible then
        for _, gate in ipairs(sampleGates) do gate.frame:Show() end
        estimatesVisible = true
    end
end

RefreshTarget = function()
    local alive=UnitIsDeadOrGhost("player")
    local combat=UnitAffectingCombat("player")
    local visible=ns.db.visibility~="combat" or (not IsSecret(combat) and combat==true)
    root:SetShown(initialized==true and not unsupported and not ns.stingConflict and ns.db.enabled
        and ns.db.stingEnabled and ns.known.sting~=nil and visible
        and not IsSecret(alive) and alive==false and TargetIsAttackable())
    if not root:IsShown() then ResetSample() end
    RefreshReminders()
end

Initialize = function()
    if initialized or unsupported or ns.LayoutLockedByCombat() or ns.stingConflict
        or not ns.db.stingEnabled or not ns.known.sting then return end
    local ok, clip = pcall(function()
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        return BuildAuraDisplay()
    end)
    if not ok then
        unsupported = true
        ns.stingUnsupported=true;root:Hide()
        print("HunterCue：此客户端无法初始化原生毒蛇监控，常规循环仍可使用。")
        return
    end
    missingClip = clip
    if type(UnitHealthPercent) == "function" then
        estimatorReady = pcall(BuildEstimateDisplay, missingClip)
    end
    initialized = true
    ns.stingInitialized=true;ns.stingEstimatorReady=estimatorReady==true
    ApplySettings()
    ResetSample()
    RefreshTarget()
end

local events = CreateFrame("Frame")
ns.stingEvents=events
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
local registered = pcall(events.RegisterUnitEvent, events, "UNIT_COMBAT", "target")
if not registered then pcall(events.RegisterEvent, events, "UNIT_COMBAT") end
if not pcall(events.RegisterUnitEvent, events, "UNIT_MAXHEALTH", "target") then
    pcall(events.RegisterEvent, events, "UNIT_MAXHEALTH")
end
local function Event(_, event, unit, action)
    if event == "ADDON_LOADED" then
        if not IsSecret(unit) and unit=="SerpentStingHint" then CheckLegacy();ns.ApplySting() end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.EndPreview()
        return
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        ns.ApplySting()
        return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        targetCreatureType = nil
        openingEndsAt, targetMaxHealth = nil, nil
        ResetSample()
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        Initialize()
        ApplySettings()
    end
    if not initialized or ns.stingConflict or not ns.db.stingEnabled then return end

    if event == "UNIT_MAXHEALTH" then
        if not IsSecret(unit) and unit == "target" then targetMaxHealth = nil end
        return
    end
    if event ~= "UNIT_COMBAT" then
        if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            openingEndsAt, targetMaxHealth = nil, nil
        elseif event == "PLAYER_REGEN_ENABLED" then
            local fighting = UnitAffectingCombat("target")
            if not IsSecret(fighting) and fighting == false then
                openingEndsAt, targetMaxHealth = nil, nil
            end
        end
        ResetSample()
        RefreshTarget()
        if root:IsShown() then
            timerContainer:UpdateAllAuras()
            missingContainer:UpdateAllAuras()
        end
        return
    end
    if not estimatorReady or IsSecret(unit) or IsSecret(action) or unit ~= "target" or action ~= "WOUND" then return end
    RefreshTarget()
    if not root:IsShown() then return end
    local now = GetTime()
    openingEndsAt = openingEndsAt or now + OPENING_TIME
    if sampleTime and now - lastHit >= MAX_IDLE then openingEndsAt = now end
    if not sampleTime or now - lastHit >= MAX_IDLE then
        ResetSample()
        if not pcall(StartSample, now) then ResetSample() end
    else
        hits, lastHit = hits + 1, now
    end
end
events:SetScript("OnEvent",function(...)
    local ok=pcall(Event,...)
    if not ok then ResetSample();root:Hide();ns.stingFault=true end
end)

events:SetScript("OnUpdate", function(_, elapsed)
    if not initialized then return end
    elapsedUpdate = elapsedUpdate + elapsed
    if elapsedUpdate < 0.2 then return end
    elapsedUpdate = 0
    local ok=pcall(function()
        if ns.stingLayoutPending and not ns.LayoutLockedByCombat() then ApplySettings() end
        RefreshTarget();UpdateEstimate(GetTime())
    end)
    if not ok then ResetSample();root:Hide();ns.stingFault=true else ns.stingFault=false end
end)
CheckLegacy();ns.ApplySting()
end

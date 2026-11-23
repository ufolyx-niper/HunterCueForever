-- SPDX-License-Identifier: MIT
-- Reuse the client's proc-loop template on our own frames, without action-bar hooks.
local _,ns=...
ns.glows={}
function ns.CreateGlow(owner,size)
    if ns.glows[owner] then return ns.glows[owner].frame end
    local state={enabled=false};ns.glows[owner]=state
    local ok=pcall(function()
        local g=CreateFrame("Frame",nil,owner,"ActionButtonSpellAlertTemplate")
        state.frame=g;g:Hide();g:EnableMouse(false)
        assert(g.ProcLoop and g.ProcStartAnim and g.ProcStartFlipbook and g.ProcAltGlow)
        -- Never expose the fixed 150px birth sheet, including on failure.
        g.ProcStartFlipbook:Hide();g.ProcAltGlow:Hide()
        g.ProcStartAnim:Stop();g.ProcLoop:Stop()
        g:SetFrameLevel(owner:GetFrameLevel()+2)
        g:SetSize(size*1.4,size*1.4);state.size=size
        g:SetPoint("CENTER",owner,"CENTER",0,0)
        g:SetScript("OnShow",function(self) self.ProcLoop:Play() end)
        g:SetScript("OnHide",function(self) self.ProcStartAnim:Stop();self.ProcLoop:Stop() end)
    end)
    if not ok then
        state.failed=true;ns.glowUnavailable=true
        if state.frame then pcall(state.frame.Hide,state.frame) end
        return nil
    end
    return state.frame
end
function ns.SetGlow(owner,enabled,size)
    local state=ns.glows[owner]
    if not state then ns.CreateGlow(owner,size);state=ns.glows[owner] end
    if state.failed then return false end
    local ok=pcall(function()
        if state.size~=size then state.frame:SetSize(size*1.4,size*1.4);state.size=size end
        enabled=enabled==true
        if state.enabled~=enabled then
            state.enabled=enabled;state.frame:SetShown(enabled)
        end
    end)
    if not ok then
        state.failed=true;ns.glowUnavailable=true
        pcall(state.frame.Hide,state.frame)
    end
    return ok
end

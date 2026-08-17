-- dungeonjournal/overlay.lua - Pooled checkbox overlays anchored to EJ loot
-- buttons. Discipline: zero writes to Blizzard frames; only SetPoint is called
-- against them. Active overlays are keyed by button identity (the ScrollBox
-- recycles buttons).
local addonName, addon = ...

local DJ = addon.DungeonJournal
if not DJ then return end

local OVERLAY_SIZE = 22
local OVERLAY_PREALLOC = 16
local BORDER_THICKNESS = 1.5

-- Scoot accent green (matches HighScoreWindow title + widget diamond).
local SCOOT_GREEN_R, SCOOT_GREEN_G, SCOOT_GREEN_B = 0.20, 0.90, 0.30

local overlayPool = {}
local activeOverlays = setmetatable({}, { __mode = "k" })  -- [button] = overlay

--------------------------------------------------------------------------------
-- Frame factory
--------------------------------------------------------------------------------

local function CreateOverlayFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(OVERLAY_SIZE, OVERLAY_SIZE)
    -- No strata here on purpose. These decorate the Encounter Journal rather
    -- than the world, so they take their anchor's strata at attach time
    -- (Strata.MatchAnchor in attachOverlay) and are occluded together with the
    -- EJ. The pool hands the same frame to different buttons, so strata belongs
    -- with the anchor, not the factory. See core/strata.lua.
    f:EnableMouse(true)
    f:SetPropagateMouseMotion(true)  -- preserve EJ tooltip + shift-click on the button

    -- Solid black background.
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.92)
    f._bg = bg

    -- Scoot-green border, four edges.
    local border = {}
    local function edge(point1, point2, w, h)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(SCOOT_GREEN_R, SCOOT_GREEN_G, SCOOT_GREEN_B, 1)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        t:SetPoint(point1, f, point1)
        t:SetPoint(point2, f, point2)
        return t
    end
    border.top    = edge("TOPLEFT",    "TOPRIGHT",    nil, BORDER_THICKNESS)
    border.bottom = edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, BORDER_THICKNESS)
    border.left   = edge("TOPLEFT",    "BOTTOMLEFT",  BORDER_THICKNESS, nil)
    border.right  = edge("TOPRIGHT",   "BOTTOMRIGHT", BORDER_THICKNESS, nil)
    f._border = border

    -- Checkmark texture (Blizzard's stock checkbox check, vertex-tinted to scoot
    -- green). Drawn ~1.4x the box so it reads as bold and the checked state is
    -- clearly distinct from empty.
    local check = f:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetSize(OVERLAY_SIZE * 1.4, OVERLAY_SIZE * 1.4)
    check:SetPoint("CENTER", f, "CENTER", 0, 0)
    check:SetVertexColor(SCOOT_GREEN_R, SCOOT_GREEN_G, SCOOT_GREEN_B, 1)
    check:Hide()
    f._check = check

    f:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local btn = self._anchorButton
        local itemID = btn and btn.itemID
        if type(itemID) ~= "number" then return end

        if DJ.IsItemChecked(itemID) then
            local link = btn.link
            local label = (link and tostring(link)) or ("item " .. tostring(itemID))
            local message = string.format("Remove %s from your received list?", label)
            if addon.Dialogs and addon.Dialogs.Confirm then
                addon.Dialogs:Confirm(message, function() DJ.UnmarkItem(itemID) end)
            else
                DJ.UnmarkItem(itemID)
            end
        else
            DJ.MarkItem(itemID)
        end
    end)

    f:Hide()
    return f
end

local function PreallocatePool()
    for _ = 1, OVERLAY_PREALLOC do
        table.insert(overlayPool, CreateOverlayFrame())
    end
end

local function AcquireOverlay()
    local f = table.remove(overlayPool)
    if not f then
        f = CreateOverlayFrame()
    end
    return f
end

local function ReleaseOverlay(f)
    if not f then return end
    f:Hide()
    f:ClearAllPoints()
    f._anchorButton = nil
    if f._check then f._check:Hide() end
    table.insert(overlayPool, f)
end

--------------------------------------------------------------------------------
-- Visual state
--------------------------------------------------------------------------------

local function paintChecked(overlay, isChecked)
    if not overlay then return end
    if overlay._check then
        if isChecked then overlay._check:Show() else overlay._check:Hide() end
    end
end

--------------------------------------------------------------------------------
-- Reconciliation
--------------------------------------------------------------------------------

local function isFeatureEnabled()
    return DJ.IsEnabled and DJ.IsEnabled() or false
end

local function getCurrentInstanceID()
    local ej = _G.EncounterJournal
    if not ej then return nil end
    local id = rawget(ej, "instanceID")
    if type(id) == "number" then return id end
    return nil
end

local function getLootContainer()
    local ej = _G.EncounterJournal
    return ej and ej.encounter and ej.encounter.info
        and ej.encounter.info.LootContainer or nil
end

local function shouldShowFor(button)
    if not button or button:IsForbidden() then return false end
    if type(button.itemID) ~= "number" then return false end
    -- Tab gate: button:IsVisible() walks the parent chain. When the user is on
    -- the Overview / Boss Abilities / Model tabs, LootContainer is hidden, so
    -- the loot rows underneath it report IsVisible() = false even though their
    -- own SetShown state is unchanged.
    if not button:IsVisible() then return false end
    local instanceID = getCurrentInstanceID()
    if not instanceID then return false end
    return DJ.IsCurrentSeasonInstance(instanceID)
end

local function attachOverlay(button)
    local overlay = activeOverlays[button]
    if not overlay then
        overlay = AcquireOverlay()
        activeOverlays[button] = overlay
    end
    overlay._anchorButton = button
    overlay:SetParent(UIParent)
    -- Strata AND level from the row the overlay hangs off: the EJ is a MEDIUM toplevel
    -- panel that ShowUIPanel raises, so inheriting its strata is what makes a
    -- pane opened over the EJ cover these too (core/strata.lua).
    addon.Strata.MatchAnchor(overlay, button, 5)
    overlay:ClearAllPoints()
    -- Overhang just outside the row's left edge, vertically centered.
    overlay:SetPoint("RIGHT", button, "LEFT", -2, 0)
    paintChecked(overlay, DJ.IsItemChecked(button.itemID))
    overlay:Show()
end

local function detachOverlay(button)
    local overlay = activeOverlays[button]
    if not overlay then return end
    activeOverlays[button] = nil
    ReleaseOverlay(overlay)
end

local function refreshButton(button)
    if not button then return end
    if not isFeatureEnabled() or not shouldShowFor(button) then
        detachOverlay(button)
        return
    end
    attachOverlay(button)
end

local function detachAll()
    for button in pairs(activeOverlays) do
        detachOverlay(button)
    end
end

function DJ.RefreshAllVisible()
    local lc = getLootContainer()
    -- Tab gate (cheap path): when the loot panel itself isn't visible, drop
    -- every overlay regardless of what the ScrollBox still has cached.
    if not lc or not lc:IsVisible() then
        detachAll()
        return
    end
    local sb = lc.ScrollBox
    if not sb or not sb.ForEachFrame then return end
    sb:ForEachFrame(refreshButton)
end

--------------------------------------------------------------------------------
-- Hook installation (deferred until Blizzard_EncounterJournal loads)
--------------------------------------------------------------------------------

local _hooked = false
local function installHooks()
    if _hooked then return end
    if type(_G.EncounterJournal_LootUpdate) ~= "function" then return end

    -- Loot data refresh (encounter / difficulty / spec-filter changes)
    hooksecurefunc("EncounterJournal_LootUpdate", function()
        DJ.RefreshAllVisible()
    end)

    -- Tab change refresh: hook OnShow/OnHide of the LootContainer so switching
    -- to Overview / Boss Abilities / Model attaches and detaches the overlays.
    -- LootContainer is a plain Frame, not an EditModeSystemTemplate inheritor —
    -- HookScript here is safe (taint Rule 11 only applies to system templates).
    local lc = getLootContainer()
    if lc then
        lc:HookScript("OnShow", function() DJ.RefreshAllVisible() end)
        lc:HookScript("OnHide", function() detachAll() end)
    end

    -- ScrollBox rebind refresh: the LootContainer.ScrollBox recycles button
    -- frames during scroll, mutating button.itemID via EncounterJournalItemMixin:Init
    -- without firing EncounterJournal_LootUpdate. Without this hook, overlays
    -- keep painting the previous row's checked state on the recycled button.
    -- OnInitializedFrame fires after Init has set button.itemID (vs.
    -- OnAcquiredFrame which fires before — see ScrollBoxListView.lua).
    local sb = lc and lc.ScrollBox
    if sb and ScrollUtil then
        ScrollUtil.AddInitializedFrameCallback(sb, function(_, button)
            refreshButton(button)
        end, sb, true)
        ScrollUtil.AddReleasedFrameCallback(sb, function(_, button)
            detachOverlay(button)
        end, sb)
    end

    _hooked = true
    PreallocatePool()
    DJ.RefreshAllVisible()
end

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loadFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_EncounterJournal" then
        installHooks()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- EJ may already be loaded (UI reload); try once on first PEW.
        installHooks()
    end
end)

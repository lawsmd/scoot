--------------------------------------------------------------------------------
-- overlay.lua - Centered minimap overlay with transparent terrain for node hunting
-- Centers the minimap on screen with transparent terrain for node hunting.
-- Uses C_Minimap.SetDrawGroundTextures(false) to hide terrain while keeping
-- tracking blips, nodes, pins, and player arrow fully visible.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Module state
local overlayButtonFrame = nil
local overlayEventFrame = nil
local darkeningFrame = nil
local wasActiveBeforeCombat = false
local wasActiveBeforeEditMode = false
local originalRotateCVar = nil
local originalDrawGround = nil
local originalGetMinimapShape = nil
local originalMouseEnabled = nil
local editModeHooked = false

-- Mask constants (matching minimap.lua)
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getMinimapDB()
    if not addon.db or not addon.db.profile or not addon.db.profile.components then
        return nil
    end
    return rawget(addon.db.profile.components, "minimapStyle")
end

local function isOverlayCurrentlyActive()
    local db = getMinimapDB()
    return db and db.overlayEnabled and db.overlayActive
end

--------------------------------------------------------------------------------
-- Darkening Overlay (circular, ON TOP of minimap for visible dimming)
-- Two-point anchored to Minimap so it auto-tracks effective size at any scale.
--------------------------------------------------------------------------------

local function EnsureDarkeningOverlay()
    if darkeningFrame then return darkeningFrame end

    darkeningFrame = CreateFrame("Frame", "ScootMinimapDarkening", UIParent)
    darkeningFrame:SetFrameStrata("MEDIUM")
    darkeningFrame:SetFrameLevel(100)
    darkeningFrame:EnableMouse(false)

    local tex = darkeningFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(CIRCLE_MASK)
    tex:SetVertexColor(0, 0, 0, 1)
    tex:SetAllPoints()
    darkeningFrame.tex = tex

    darkeningFrame:Hide()
    addon.RegisterPetBattleFrame(darkeningFrame)
    return darkeningFrame
end

--------------------------------------------------------------------------------
-- Overlay Activation / Deactivation
--------------------------------------------------------------------------------

local function ActivateOverlay(db)
    if not db then return end
    if InCombatLockdown and InCombatLockdown() then return end

    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster
    if not minimap or not cluster then return end

    -- Save current state for restoration (only on first activation)
    if originalRotateCVar == nil then
        local ok, curCVar = pcall(GetCVar, "rotateMinimap")
        originalRotateCVar = ok and curCVar or "0"
    end
    if originalDrawGround == nil then
        local okGround, curGround = pcall(C_Minimap.GetDrawGroundTextures)
        originalDrawGround = okGround and curGround or true
    end

    -- Force rotation on for directional navigation
    pcall(SetCVar, "rotateMinimap", "1")

    -- Hide terrain — blips/nodes/player arrow remain visible (harmless if silently fails)
    pcall(C_Minimap.SetDrawGroundTextures, false)

    -- Force circle shape (overlay is always circular)
    minimap:SetMaskTexture(CIRCLE_MASK)
    if MinimapCompassTexture then MinimapCompassTexture:SetAlpha(0) end

    -- Save and override GetMinimapShape for addon compatibility
    if not originalGetMinimapShape then
        originalGetMinimapShape = _G.GetMinimapShape
    end
    _G.GetMinimapShape = function() return "ROUND" end

    -- HybridMinimap compatibility — force circular
    if HybridMinimap then
        pcall(function()
            HybridMinimap.MapCanvas:SetUseMaskTexture(false)
            if HybridMinimap.CircleMask then
                HybridMinimap.CircleMask:SetTexture(CIRCLE_MASK)
            end
            HybridMinimap.MapCanvas:SetUseMaskTexture(true)
        end)
    end

    local scale = db.overlayScale or 1.0
    local mapOpacity = db.overlayMapOpacity or 0.85

    -- Darkening overlay (circular, anchored to minimap — auto-tracks effective size)
    local darkening = EnsureDarkeningOverlay()
    darkening:SetAlpha(1 - mapOpacity) -- Inverted: low opacity = high darkening
    darkening:ClearAllPoints()
    darkening:SetPoint("TOPLEFT", minimap, "TOPLEFT", 0, 0)
    darkening:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", 0, 0)
    darkening:Show()

    -- Reposition Minimap to screen center
    minimap:ClearAllPoints()
    minimap:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    minimap:SetScale(scale)
    minimap:SetAlpha(db.overlayNodesOpacity or 1.0)

    -- Make minimap fully click-through while overlay is active
    if originalMouseEnabled == nil then
        originalMouseEnabled = minimap:IsMouseEnabled()
    end
    minimap:EnableMouse(false)
    minimap:EnableMouseWheel(false)

    -- Hide Scoot's custom border during overlay
    if addon.SetMinimapBorderHidden then
        addon.SetMinimapBorderHidden(true)
    end

    -- Hide clock, FPS, addon buttons during overlay (keep zone text + coords)
    if addon.SetMinimapOverlayChildrenHidden then
        addon.SetMinimapOverlayChildrenHidden(true)
    end

    -- Hide the empty cluster shell (SetAlpha is NOT overridden by EditModeSystemTemplate)
    cluster:SetAlpha(0)

    -- Persist state
    db.overlayActive = true
end

local function DeactivateOverlay(skipPersist)
    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster
    if not minimap or not cluster then return end

    -- Restore Minimap to its container
    minimap:ClearAllPoints()
    local container = cluster.MinimapContainer
    if container then
        minimap:SetPoint("CENTER", container, "CENTER", 0, 0)
    else
        minimap:SetPoint("CENTER", cluster, "CENTER", 0, 0)
    end
    minimap:SetScale(1)
    minimap:SetAlpha(1)

    -- Restore minimap mouse interaction
    if originalMouseEnabled then
        minimap:EnableMouse(true)
    end
    minimap:EnableMouseWheel(true)
    originalMouseEnabled = nil

    -- Restore cluster visibility
    cluster:SetAlpha(1)

    -- Hide darkening overlay
    if darkeningFrame then
        darkeningFrame:ClearAllPoints()
        darkeningFrame:Hide()
    end

    -- Restore minimap shape based on user's current preference
    local db = getMinimapDB()
    if minimap then
        if db and db.mapShape == "square" then
            minimap:SetMaskTexture(SQUARE_MASK)
            if MinimapCompassTexture then MinimapCompassTexture:SetAlpha(0) end
            _G.GetMinimapShape = originalGetMinimapShape or function() return "SQUARE" end
            -- HybridMinimap: restore square mask
            if HybridMinimap then
                pcall(function()
                    HybridMinimap.MapCanvas:SetUseMaskTexture(false)
                    if HybridMinimap.CircleMask then
                        HybridMinimap.CircleMask:SetTexture(SQUARE_MASK)
                    end
                    HybridMinimap.MapCanvas:SetUseMaskTexture(true)
                end)
            end
        else
            -- Circle/default — restore compass border art
            if MinimapCompassTexture then MinimapCompassTexture:SetAlpha(1) end
            if originalGetMinimapShape then
                _G.GetMinimapShape = originalGetMinimapShape
            end
        end
    end
    originalGetMinimapShape = nil

    -- Persist state BEFORE restoring border/children (they check db.overlayActive)
    if not skipPersist then
        if db then
            db.overlayActive = false
        end
    end

    -- Restore Scoot's custom border (reads db.overlayActive, must be false first)
    if addon.SetMinimapBorderHidden then
        addon.SetMinimapBorderHidden(false)
    end

    -- Restore clock, FPS, addon buttons
    if addon.SetMinimapOverlayChildrenHidden then
        addon.SetMinimapOverlayChildrenHidden(false)
    end

    -- Restore terrain rendering (respect HybridMinimap state)
    local shouldRestoreGround = originalDrawGround
    if shouldRestoreGround == nil then shouldRestoreGround = true end
    local okHybrid, isHybrid = pcall(C_Minimap.ShouldUseHybridMinimap)
    if okHybrid and isHybrid then
        -- HybridMinimap is active — terrain should stay off
        shouldRestoreGround = false
    end
    pcall(C_Minimap.SetDrawGroundTextures, shouldRestoreGround)

    -- Restore rotation CVar
    if originalRotateCVar then
        pcall(SetCVar, "rotateMinimap", originalRotateCVar)
        originalRotateCVar = nil
    end
    originalDrawGround = nil
end

local function ToggleOverlay()
    local db = getMinimapDB()
    if not db or not db.overlayEnabled then return end

    if db.overlayActive then
        DeactivateOverlay()
    else
        ActivateOverlay(db)
    end
end

--------------------------------------------------------------------------------
-- Overlay Button (minimap toggle)
--------------------------------------------------------------------------------

local BUTTON_OFFSETS = {
    TOPLEFT     = { "TOPLEFT",     "TOPLEFT",      4,  -4 },
    TOP         = { "TOP",         "TOP",          0,  -4 },
    TOPRIGHT    = { "TOPRIGHT",    "TOPRIGHT",    -4,  -4 },
    LEFT        = { "LEFT",        "LEFT",         4,   0 },
    RIGHT       = { "RIGHT",       "RIGHT",       -4,   0 },
    BOTTOMLEFT  = { "BOTTOMLEFT",  "BOTTOMLEFT",   4,   4 },
    BOTTOM      = { "BOTTOM",      "BOTTOM",       0,   4 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -4,   4 },
}

local function UpdateOverlayButtonState(db)
    if not overlayButtonFrame then return end
    local icon = overlayButtonFrame._icon
    if not icon then return end

    if db and db.overlayActive then
        icon:SetVertexColor(0.9, 0.2, 0.2, 1)
    else
        icon:SetVertexColor(1, 1, 1, 0.8)
    end
end

local function UpdateOverlayButtonPosition(db)
    if not overlayButtonFrame then return end
    local minimap = _G.Minimap
    if not minimap then return end

    local pos = (db and db.overlayButtonPosition) or "TOPRIGHT"
    local offsets = BUTTON_OFFSETS[pos] or BUTTON_OFFSETS["TOPRIGHT"]

    overlayButtonFrame:ClearAllPoints()
    overlayButtonFrame:SetPoint(offsets[1], minimap, offsets[2], offsets[3], offsets[4])
end

local function CreateOverlayButton(db)
    if overlayButtonFrame then return overlayButtonFrame end

    local btn = CreateFrame("Button", "ScootMinimapOverlayButton", UIParent)
    btn:SetSize(36, 36)
    -- MEDIUM (core/strata.lua), not HIGH: MinimapCluster is LOW (Minimap.xml:3)
    -- and the darkening overlay is MEDIUM/100, so level 200 keeps the pin on top
    -- of both -- without floating over an open Blizzard panel.
    addon.Strata.ApplyHUD(btn, 200)

    -- Icon (map pin)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("waypoint-mappin-minimap-tracked")
    icon:SetSize(36, 36)
    icon:SetPoint("CENTER")
    icon:SetDesaturated(true)
    btn._icon = icon

    -- Click handler
    btn:SetScript("OnClick", function()
        ToggleOverlay()
        UpdateOverlayButtonState(getMinimapDB())
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Minimap Overlay", 1, 1, 1)
        GameTooltip:AddLine("Click to toggle the centered overlay.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Highlight
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    highlight:SetVertexColor(1, 1, 1, 0.15)
    highlight:SetAllPoints()

    btn:Hide()
    overlayButtonFrame = btn
    addon.RegisterPetBattleFrame(btn)
    return btn
end

--------------------------------------------------------------------------------
-- Combat Event Handling
--------------------------------------------------------------------------------

local function EnsureEventFrame()
    if overlayEventFrame then return overlayEventFrame end

    overlayEventFrame = CreateFrame("Frame", "ScootMinimapOverlayEvents", UIParent)
    overlayEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    overlayEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    overlayEventFrame:SetScript("OnEvent", function(_, event)
        local db = getMinimapDB()
        if not db or not db.overlayEnabled then return end

        if event == "PLAYER_REGEN_DISABLED" then
            -- Entering combat
            if db.overlayCombatHide and db.overlayActive then
                wasActiveBeforeCombat = true
                DeactivateOverlay(true) -- skip persist so we can restore
                UpdateOverlayButtonState(db)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Exiting combat
            if wasActiveBeforeCombat then
                wasActiveBeforeCombat = false
                C_Timer.After(0, function()
                    local dbAfter = getMinimapDB()
                    if dbAfter and dbAfter.overlayEnabled then
                        ActivateOverlay(dbAfter)
                        UpdateOverlayButtonState(dbAfter)
                    end
                end)
            end
        end
    end)

    return overlayEventFrame
end

--------------------------------------------------------------------------------
-- Edit Mode Handling
--------------------------------------------------------------------------------

local function InstallEditModeHooks()
    if editModeHooked then return end
    if not EditModeManagerFrame then return end

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if isOverlayCurrentlyActive() then
            wasActiveBeforeEditMode = true
            DeactivateOverlay(true)
            if overlayButtonFrame then overlayButtonFrame:Hide() end
        end
    end)

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        if wasActiveBeforeEditMode then
            wasActiveBeforeEditMode = false
            C_Timer.After(0, function()
                local db = getMinimapDB()
                if db and db.overlayEnabled then
                    ActivateOverlay(db)
                    UpdateOverlayButtonState(db)
                    if overlayButtonFrame then
                        UpdateOverlayButtonPosition(db)
                        overlayButtonFrame:Show()
                    end
                end
            end)
        end
    end)

    editModeHooked = true
end

--------------------------------------------------------------------------------
-- Master Apply Function
--------------------------------------------------------------------------------

local function ApplyOverlaySettings(db)
    if not db then return end

    -- Zero-touch: if overlay not enabled, clean up and exit
    if not db.overlayEnabled then
        if overlayButtonFrame then
            overlayButtonFrame:Hide()
        end
        if db.overlayActive then
            DeactivateOverlay()
        end
        if overlayEventFrame then
            overlayEventFrame:UnregisterAllEvents()
            overlayEventFrame = nil
        end
        return
    end

    -- Ensure subsystems are set up
    EnsureEventFrame()
    InstallEditModeHooks()

    -- Create and configure button
    CreateOverlayButton(db)
    UpdateOverlayButtonPosition(db)
    UpdateOverlayButtonState(db)
    overlayButtonFrame:Show()

    -- Apply or restore overlay state
    if db.overlayActive then
        ActivateOverlay(db)
    else
        -- Make sure everything is in a clean state
        DeactivateOverlay(true)
    end
end

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

addon.ApplyMinimapOverlay = ApplyOverlaySettings
addon.ToggleMinimapOverlay = ToggleOverlay

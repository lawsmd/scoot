--------------------------------------------------------------------------------
-- bars/partyframes.lua
-- Party frame health bar and text styling
--
-- Applies styling to CompactPartyFrameMember[1-5] frames.
-- Uses combat-safe overlay patterns for persistence during combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Create module namespace
addon.BarsPartyFrames = addon.BarsPartyFrames or {}
local PartyFrames = addon.BarsPartyFrames

--------------------------------------------------------------------------------
-- TAINT PREVENTION: Lookup table for party frame state
--------------------------------------------------------------------------------
-- Writing properties directly to CompactPartyFrameMember frames
-- (e.g., frame._ScootActive = true) can mark the entire frame as "addon-touched".
-- This causes ALL field accesses to return secret values in protected contexts
-- (like Edit Mode), breaking Blizzard's own code (frame.outOfRange becomes secret).
--
-- Solution: Store all Scoot state in a separate lookup table keyed by frame.
-- This avoids modifying Blizzard's frames while preserving overlay functionality.
--------------------------------------------------------------------------------
local PartyFrameState = setmetatable({}, { __mode = "k" }) -- Weak keys for GC

local function getState(frame)
    if not frame then return nil end
    return PartyFrameState[frame]
end

local function ensureState(frame)
    if not frame then return nil end
    if not PartyFrameState[frame] then
        PartyFrameState[frame] = {}
    end
    return PartyFrameState[frame]
end

-- Shared state (exported for text.lua and extras.lua)
addon.BarsPartyFrames._PartyFrameState = PartyFrameState
addon.BarsPartyFrames._getState = getState
addon.BarsPartyFrames._ensureState = ensureState

--------------------------------------------------------------------------------
-- Party Frame Detection
--------------------------------------------------------------------------------

function PartyFrames.isPartyFrame(frame)
    return Utils.isPartyFrame(frame)
end

function PartyFrames.isPartyHealthBar(frame)
    if not frame or not frame.healthBar then return false end
    return Utils.isPartyFrame(frame)
end

--------------------------------------------------------------------------------
-- Health Bar Collection
--------------------------------------------------------------------------------

local partyHealthBars = {}

function PartyFrames.collectHealthBars()
    partyHealthBars = {}
    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            table.insert(partyHealthBars, bar)
        end
    end
    return partyHealthBars
end

--------------------------------------------------------------------------------
-- Health Bar Styling
--------------------------------------------------------------------------------

function PartyFrames.applyToHealthBar(bar, cfg)
    if not bar or not cfg then return end

    local texKey = cfg.healthBarTexture or "default"
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint
    local bgTexKey = cfg.healthBarBackgroundTexture or "default"
    local bgColorMode = cfg.healthBarBackgroundColorMode or "default"
    local bgTint = cfg.healthBarBackgroundTint
    local bgOpacity = cfg.healthBarBackgroundOpacity or 50

    if addon._ApplyToStatusBar then
        addon._ApplyToStatusBar(bar, texKey, colorMode, tint, nil, "health", nil)
    end

    if addon._ApplyBackgroundToStatusBar then
        addon._ApplyBackgroundToStatusBar(bar, bgTexKey, bgColorMode, bgTint, bgOpacity, "Party", "health")
    end
end

--------------------------------------------------------------------------------
-- Health Bar Overlay (Combat-Safe Persistence)
--------------------------------------------------------------------------------

-- Update overlay dimensions based on health bar fill texture
-- Uses anchor-based sizing instead of calculating from GetValue/GetMinMaxValues.
-- This avoids secret value issues because the overlay anchors to Blizzard's fill texture directly,
-- which is sized by Blizzard's internal (untainted) code.
local function updateHealthOverlay(bar)
    if not bar then return end

    local state = getState(bar)
    local overlay = state and state.healthOverlay or nil
    if not overlay then return end
    if not state or not state.overlayActive then
        overlay:Hide()
        return
    end

    -- SECRET-SAFE: Anchor overlay to the status bar fill texture.
    -- Blizzard's fill texture is sized internally without exposing secret values.
    -- By anchoring to it, the overlay automatically matches the fill dimensions.
    local fill = bar:GetStatusBarTexture()
    if not fill then
        overlay:Hide()
        return
    end

    -- Anchor overlay to match the fill texture exactly.
    -- Don't check fill dimensions - if fill has zero width (0% health), the overlay
    -- will correctly have zero width too. This avoids reading GetWidth() which can
    -- return secret values.
    overlay:ClearAllPoints()
    overlay:SetAllPoints(fill)
    overlay:Show()
end

-- Style the overlay texture and color
local function styleHealthOverlay(bar, cfg)
    if not bar or not cfg then return end

    local state = getState(bar)
    local overlay = state and state.healthOverlay or nil
    if not overlay then return end
    local texKey = cfg.healthBarTexture or "default"
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint

    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

    if resolvedPath then
        overlay:SetTexture(resolvedPath)
    else
        local tex = bar:GetStatusBarTexture()
        local applied = false
        if tex then
            local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
            if okAtlas and atlasName and atlasName ~= "" then
                if overlay.SetAtlas then
                    pcall(overlay.SetAtlas, overlay, atlasName, true)
                    applied = true
                end
            end
            if not applied then
                local okTex, texPath = pcall(tex.GetTexture, tex)
                if okTex and texPath then
                    if type(texPath) == "string" and texPath:match("^[A-Za-z]") and not texPath:match("\\") and not texPath:match("/") then
                        if overlay.SetAtlas then
                            pcall(overlay.SetAtlas, overlay, texPath, true)
                            applied = true
                        end
                    elseif type(texPath) == "number" or (type(texPath) == "string" and (texPath:match("\\") or texPath:match("/"))) then
                        pcall(overlay.SetTexture, overlay, texPath)
                        applied = true
                    end
                end
            end
        end
        if not applied then
            overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
    end

    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "value" or colorMode == "valueDark" then
        -- "Color by Value" mode: use UnitHealthPercent with color curve
        -- FIRST: Apply fallback color so overlay is never colorless (in case applyValueBasedColor
        -- encounters secret values and returns early without applying color)
        -- Use dark gray for valueDark, green for standard value mode
        local useDark = (colorMode == "valueDark")
        if useDark then
            overlay:SetVertexColor(0.23, 0.23, 0.23, 1)  -- Dark gray fallback
        else
            overlay:SetVertexColor(0, 1, 0, 1)  -- Green fallback
        end

        local unit
        local parentFrame = bar.GetParent and bar:GetParent()
        if parentFrame then
            local okU, u = pcall(function() return parentFrame.displayedUnit or parentFrame.unit end)
            if okU and u then unit = u end
        end
        if unit and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
            -- This will override the fallback color if it can determine the actual color
            addon.BarsTextures.applyValueBasedColor(bar, unit, overlay, useDark)
        end
        return -- Color already handled (either fallback or value-based)
    elseif colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
    elseif colorMode == "class" then
        local unit
        local parentFrame = bar.GetParent and bar:GetParent()
        if parentFrame then
            local okU, u = pcall(function() return parentFrame.unit end)
            if okU and u then unit = u end
        end
        if addon.GetClassColorRGB and unit then
            local cr, cg, cb = addon.GetClassColorRGB(unit)
            r, g, b, a = cr or 1, cg or 1, cb or 1, 1
        end
    elseif colorMode == "texture" then
        r, g, b, a = 1, 1, 1, 1
    else
        -- "default" mode: Use known health default color instead of reading from
        -- Blizzard's bar (GetStatusBarColor can return uninitialized/secret values)
        if addon.GetDefaultHealthColorRGB then
            local hr, hg, hb = addon.GetDefaultHealthColorRGB()
            r, g, b = hr or 0, hg or 1, hb or 0
        else
            r, g, b = 0, 1, 0  -- Fallback green
        end
    end
    overlay:SetVertexColor(r, g, b, a)
end

-- Hide Blizzard's fill texture
local function hideBlizzardFill(bar)
    if not bar then return end
    local blizzFill = bar:GetStatusBarTexture()
    if not blizzFill then return end

    local state = ensureState(blizzFill)
    if state then state.hidden = true end
    blizzFill:SetAlpha(0)

    local barState = getState(blizzFill)
    if barState and not barState.alphaHooked and _G.hooksecurefunc then
        barState.alphaHooked = true
        _G.hooksecurefunc(blizzFill, "SetAlpha", function(self, alpha)
            local st = getState(self)
            if alpha > 0 and st and st.hidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        local st2 = getState(self)
                        if st2 and st2.hidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end
end

-- Show Blizzard's fill texture
local function showBlizzardFill(bar)
    if not bar then return end
    local blizzFill = bar:GetStatusBarTexture()
    if blizzFill then
        local state = getState(blizzFill)
        if state then state.hidden = nil end
        blizzFill:SetAlpha(1)
    end
end

-- Create or update the health overlay
function PartyFrames.ensureHealthOverlay(bar, cfg)
    if not bar then return end

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    local state = ensureState(bar)
    if state then state.overlayActive = hasCustom end

    if not hasCustom then
        if state then
            -- Clear styling state so re-enabling will apply fresh
            state.stylingApplied = nil
            state.lastAppliedFingerprint = nil
        end
        if state and state.healthOverlay then
            state.healthOverlay:Hide()
        end
        showBlizzardFill(bar)
        return
    end

    if state and not state.healthOverlay then
        -- Parent the overlay to the healthBar StatusBar (a useParentLevel="true" child).
        -- This places the overlay in the same rendering pass as DispelOverlay.
        -- Within that pass, draw layers compare normally: our BORDER sublevel 7
        -- renders before DispelOverlay's ARTWORK sublevel -5/-6, so the dispel
        -- gradient/highlight renders on top of our overlay.
        -- roleIcon, readyCheckIcon, selectionHighlight live on the parent
        -- CompactUnitFrame and render in a later pass (parent after children),
        -- so they remain visible above the overlay.
        local overlay = bar:CreateTexture(nil, "BORDER", nil, 7)
        overlay:SetVertTile(false)
        overlay:SetHorizTile(false)
        overlay:SetTexCoord(0, 1, 0, 1)
        state.healthOverlay = overlay

        local barState = ensureState(bar)
        if _G.hooksecurefunc and barState and not barState.overlayHooksInstalled then
            barState.overlayHooksInstalled = true
            _G.hooksecurefunc(bar, "SetValue", function(self)
                updateHealthOverlay(self)
                -- Also update color for "value"/"valueDark" mode to eliminate flicker.
                -- By updating color in the same hook as width, both changes happen
                -- atomically in the same frame (no timing gap = no flicker).
                local st = getState(self)
                if not st or not st.overlayActive then return end
                local db = addon and addon.db and addon.db.profile
                local groupFrames = db and rawget(db, "groupFrames") or nil
                local cfg = groupFrames and rawget(groupFrames, "party") or nil
                local colorMode = cfg and cfg.healthBarColorMode
                if colorMode == "value" or colorMode == "valueDark" then
                    local useDark = (colorMode == "valueDark")
                    local overlay = st.healthOverlay
                    local parentFrame = self.GetParent and self:GetParent()
                    local unit
                    if parentFrame then
                        local okU, u = pcall(function() return parentFrame.displayedUnit or parentFrame.unit end)
                        if okU and u then unit = u end
                    end
                    if unit and overlay and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(self, unit, overlay, useDark)
                        -- Schedule validation to catch timing edge cases (stuck colors at 100%)
                        if addon.BarsTextures.scheduleColorValidation then
                            addon.BarsTextures.scheduleColorValidation(self, unit, overlay, useDark)
                        end
                    end
                end
            end)
            _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                updateHealthOverlay(self)
            end)
            if bar.HookScript then
                bar:HookScript("OnSizeChanged", function(self, width, height)
                    updateHealthOverlay(self)
                end)
            end
            -- FIX: Hook SetStatusBarColor to intercept Blizzard's color changes.
            -- This is the key fix for blinking: when Blizzard's CompactUnitFrame_UpdateHealthColor
            -- calls SetStatusBarColor(green), the hook fires IMMEDIATELY after and re-applies
            -- the value-based color. No frame gap = no blink.
            _G.hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b)
                local st = getState(self)
                if not st or not st.overlayActive then return end
                -- Recursion guard: Check the SAME flag that applyValueBasedColor uses in addon.FrameState
                -- to prevent infinite loops when SetStatusBarColor is called from applyValueBasedColor.
                local fs = addon.FrameState and addon.FrameState.Get(self)
                if fs and fs.applyingValueBasedColor then return end
                local db = addon and addon.db and addon.db.profile
                local groupFrames = db and rawget(db, "groupFrames") or nil
                local cfg = groupFrames and rawget(groupFrames, "party") or nil
                local colorMode = cfg and cfg.healthBarColorMode
                if colorMode == "value" or colorMode == "valueDark" then
                    local useDark = (colorMode == "valueDark")
                    local overlay = st.healthOverlay
                    local parentFrame = self.GetParent and self:GetParent()
                    local unit
                    if parentFrame then
                        local okU, u = pcall(function() return parentFrame.displayedUnit or parentFrame.unit end)
                        if okU and u then unit = u end
                    end
                    if unit and overlay and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(self, unit, overlay, useDark)
                    end
                end
            end)
        end
    end

    local barState = ensureState(bar)
    if barState and not barState.textureSwapHooked and _G.hooksecurefunc then
        barState.textureSwapHooked = true
        _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            local st = getState(self)
            if st and st.overlayActive then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        hideBlizzardFill(self)
                    end)
                end
            end
        end)
    end

    -- Elevate roleIcon above Scoot overlay layers (OVERLAY 6, below name text at OVERLAY 7)
    local unitFrame = bar.GetParent and bar:GetParent()
    if unitFrame then
        local okR, roleIcon = pcall(function() return unitFrame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end

        -- Raise DispelOverlay above healthBar in the useParentLevel stacking order.
        -- Both are useParentLevel="true" siblings; rendering order among same-level
        -- siblings depends on stacking order (not draw layers across frames).
        local okD, dispelOverlay = pcall(function() return unitFrame.DispelOverlay end)
        if okD and dispelOverlay and dispelOverlay.Raise then
            pcall(dispelOverlay.Raise, dispelOverlay)
        end
    end

    -- Build a config fingerprint to detect if settings have actually changed.
    -- This prevents expensive re-styling when ApplyStyles() is called but party
    -- frame settings haven't changed (e.g., when changing Action Bar settings).
    local fingerprint = string.format("%s|%s|%s|%s|%s",
        tostring(cfg.healthBarTexture or ""),
        tostring(cfg.healthBarColorMode or ""),
        tostring(cfg.healthBarBackgroundTexture or ""),
        tostring(cfg.healthBarBackgroundColorMode or ""),
        cfg.healthBarCustomColor and string.format("%.2f,%.2f,%.2f,%.2f",
            cfg.healthBarCustomColor[1] or 0,
            cfg.healthBarCustomColor[2] or 0,
            cfg.healthBarCustomColor[3] or 0,
            cfg.healthBarCustomColor[4] or 1) or ""
    )

    -- If config hasn't changed and styling was already applied, skip re-styling.
    -- This prevents visual blinking when ApplyStyles() is called for unrelated
    -- settings (e.g., CDM, Action Bars). stylingApplied is tracked separately from
    -- overlay dimensions because GetWidth() can return <= 1 due to secret values.
    if state.lastAppliedFingerprint == fingerprint and state.stylingApplied then
        -- FIX: With sticky visibility in place (Fix 1), the overlay won't be hidden
        -- due to secret values, so an aggressive recovery loop is unnecessary.
        -- The SetValue hook will update dimensions when values become available.
        -- Only attempt a single deferred update if overlay isn't visible yet.
        local overlay = state.healthOverlay
        if overlay and not overlay:IsShown() then
            if _G.C_Timer and _G.C_Timer.After then
                C_Timer.After(0.1, function()
                    updateHealthOverlay(bar)
                    -- Don't re-style here - styling is already applied
                end)
            end
        end
        return -- Already styled with same config, skip
    end

    -- Store fingerprint for next comparison
    state.lastAppliedFingerprint = fingerprint

    styleHealthOverlay(bar, cfg)
    hideBlizzardFill(bar)
    updateHealthOverlay(bar)

    -- Mark styling as applied (separate from overlay dimensions being ready)
    state.stylingApplied = true

    -- Queue repeating updates to handle cases where bar dimensions aren't ready
    -- immediately (e.g., on UI reload at 100% health where no SetValue fires).
    -- Keep trying until the overlay is successfully shown.
    -- NOTE: This retry loop only runs on initial setup (fingerprint check above
    -- prevents re-entry on subsequent ApplyStyles calls).
    -- FIX: Reduced from 5 to 3 attempts and removed re-styling in retry loop.
    -- With anchor-based sizing, updateHealthOverlay just needs to run
    -- after the fill texture is ready. A single deferred call should suffice.
    if _G.C_Timer and _G.C_Timer.After then
        C_Timer.After(0.1, function()
            updateHealthOverlay(bar)
        end)
    end
end

function PartyFrames.disableHealthOverlay(bar)
    if not bar then return end
    local state = getState(bar)
    if state then
        state.overlayActive = false
        -- Clear styling state so re-enabling will apply fresh
        state.stylingApplied = nil
        state.lastAppliedFingerprint = nil
    end
    if state and state.healthOverlay then
        state.healthOverlay:Hide()
    end
    showBlizzardFill(bar)
    -- Restore roleIcon to stock draw layer
    local unitFrame = bar.GetParent and bar:GetParent()
    if unitFrame then
        local okR, roleIcon = pcall(function() return unitFrame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "ARTWORK", 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Health Bar Borders
--------------------------------------------------------------------------------
-- Applies Scoot bar borders to party frame health bars.
--
-- IMPORTANT: Uses explicit edge textures on the parent CompactUnitFrame (not a
-- child frame) to ensure correct draw order with Blizzard's selection highlight.
--
-- Layer order on a single frame:
-- 1. Health bar (StatusBar)
-- 2. Health overlay texture (BORDER sublevel 7)
-- 3. Scoot border textures (OVERLAY sublevel -8)
-- 4. Selection highlight (OVERLAY sublevel 0+) <- Blizzard's highlight draws on top
--
-- Note: OVERLAY layer with the lowest sublevel (-8) is used so borders appear
-- above the health bar content but below the selection highlight.
--
-- The previous SetBackdrop() approach on a child frame caused borders to draw
-- on top of the selection highlight because child frame layers draw after parent
-- frame layers (even if both are OVERLAY).
--------------------------------------------------------------------------------

-- Clear health bar border for a single bar
local function clearHealthBarBorder(bar)
    if not bar then return end
    local unitFrame = bar.GetParent and bar:GetParent()
    if not unitFrame then return end

    -- Hide edge textures if they exist (stored in PartyFrameState, not on frame)
    local ufState = getState(unitFrame)
    local edges = ufState and ufState.ScootBorderEdges
    if edges then
        for _, tex in pairs(edges) do
            if tex and tex.Hide then
                tex:Hide()
            end
        end
    end

    -- Also hide legacy anchor frame if it exists (from previous implementation)
    local state = getState(bar)
    if state and state.borderAnchor then
        state.borderAnchor:Hide()
    end
end

-- Apply health bar border to a single bar
local function applyHealthBarBorder(bar, cfg)
    if not bar then return end

    local styleKey = cfg and cfg.healthBarBorderStyle
    if not styleKey or styleKey == "none" then
        clearHealthBarBorder(bar)
        return
    end

    -- Get the parent CompactUnitFrame - borders must be created directly on this
    -- frame (not a child) so layer order is respected with selection highlight
    local unitFrame = bar.GetParent and bar:GetParent()
    if not unitFrame then return end

    -- Create edge textures on the CompactUnitFrame if they don't exist
    -- Use OVERLAY layer with lowest sublevel (-8) to appear above health bar
    -- content but below selection highlight (which uses higher sublevels)
    -- Stored in PartyFrameState (not on unitFrame) to avoid tainting the system frame.
    local ufState = ensureState(unitFrame)
    local edges = ufState.ScootBorderEdges
    if not edges then
        edges = {
            Top = unitFrame:CreateTexture(nil, "OVERLAY", nil, -8),
            Bottom = unitFrame:CreateTexture(nil, "OVERLAY", nil, -8),
            Left = unitFrame:CreateTexture(nil, "OVERLAY", nil, -8),
            Right = unitFrame:CreateTexture(nil, "OVERLAY", nil, -8),
        }
        -- Enable pixel grid snapping for crisp borders at any UI scale
        for _, tex in pairs(edges) do
            if tex.SetSnapToPixelGrid then
                tex:SetSnapToPixelGrid(true)
            end
            if tex.SetTexelSnappingBias then
                tex:SetTexelSnappingBias(0)
            end
        end
        ufState.ScootBorderEdges = edges
    end

    -- Get border settings
    local tintEnabled = cfg.healthBarBorderTintEnable
    local tintColor = cfg.healthBarBorderTintColor or {1, 1, 1, 1}
    local thickness = tonumber(cfg.healthBarBorderThickness) or 1
    local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
    local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

    -- Calculate edge size and padding based on style
    local style = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
    local edgeSize, padH, padV, texturePath

    if styleKey == "square" then
        -- Simple square border using solid color texture
        edgeSize = math.max(1, math.floor(thickness + 0.5))
        padH = 1 - insetH
        padV = 1 - insetV
        if padH < 0 then padH = 0 end
        if padV < 0 then padV = 0 end
        texturePath = "Interface\\Buttons\\WHITE8x8"
    elseif style and style.texture then
        -- Traditional border style with texture
        edgeSize = math.max(1, math.floor(thickness * 1.35 * (style.thicknessScale or 1) + 0.5))
        local paddingMult = style.paddingMultiplier or 0.5
        local basePad = math.floor(edgeSize * paddingMult + 0.5)
        padH = basePad - insetH
        padV = basePad - insetV
        if padH < 0 then padH = 0 end
        if padV < 0 then padV = 0 end
        texturePath = style.texture
    else
        -- Unknown style, hide border
        clearHealthBarBorder(bar)
        return
    end

    -- Position edges around the health bar
    -- Horizontal edges span full width including corners
    -- Vertical edges are trimmed by edge thickness to avoid corner overlap
    edges.Top:ClearAllPoints()
    edges.Top:SetPoint("TOPLEFT", bar, "TOPLEFT", -padH, padV)
    edges.Top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", padH, padV)
    edges.Top:SetHeight(edgeSize)

    edges.Bottom:ClearAllPoints()
    edges.Bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -padH, -padV)
    edges.Bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", padH, -padV)
    edges.Bottom:SetHeight(edgeSize)

    edges.Left:ClearAllPoints()
    edges.Left:SetPoint("TOPLEFT", bar, "TOPLEFT", -padH, padV - edgeSize)
    edges.Left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -padH, -padV + edgeSize)
    edges.Left:SetWidth(edgeSize)

    edges.Right:ClearAllPoints()
    edges.Right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", padH, padV - edgeSize)
    edges.Right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", padH, -padV + edgeSize)
    edges.Right:SetWidth(edgeSize)

    -- Apply texture and color to all edges
    local r, g, b, a
    if tintEnabled then
        r, g, b, a = tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] or 1
    elseif styleKey == "square" then
        -- Default square border is black
        r, g, b, a = 0, 0, 0, 1
    else
        -- Default for texture borders is white (shows texture's natural colors)
        r, g, b, a = 1, 1, 1, 1
    end

    for _, tex in pairs(edges) do
        tex:SetTexture(texturePath)
        tex:SetVertexColor(r, g, b, a)
        tex:Show()
    end
end

-- EDIT MODE GUARD: Skip processing when Edit Mode is active
local function isEditModeActiveForBorders()
    if addon and addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening then
        return addon.EditMode.IsEditModeActiveOrOpening()
    end
    local mgr = _G.EditModeManagerFrame
    return mgr and (mgr.editModeActive or (mgr.IsShown and mgr:IsShown()))
end

-- Apply health bar borders to all party frames
function addon.ApplyPartyFrameHealthBarBorders()
    if isEditModeActiveForBorders() then return end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queuePartyFrameReapply()
        return
    end

    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "party") or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not cfg then return end

    -- If no border style set or set to "none", skip - let explicit restore handle cleanup
    local styleKey = cfg.healthBarBorderStyle
    if not styleKey or styleKey == "none" then return end

    -- Apply borders to all party health bars
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.healthBar then
            C_Timer.After(0, function()
                if frame and frame.healthBar then
                    applyHealthBarBorder(frame.healthBar, cfg)
                end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Public API Functions
--------------------------------------------------------------------------------

-- Main entry point: Apply party frame health bar styling from DB settings
function addon.ApplyPartyFrameHealthBarStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "party") or nil
    if not cfg then return end

    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
    if not hasCustom then return end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queuePartyFrameReapply()
        return
    end

    PartyFrames.collectHealthBars()
    for _, bar in ipairs(partyHealthBars) do
        PartyFrames.applyToHealthBar(bar, cfg)
    end
end

-- Apply overlays to all party health bars
function addon.ApplyPartyFrameHealthOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "party") or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not cfg then return end

    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")

    -- If no custom settings, also skip - let RestorePartyFrameHealthOverlays handle cleanup
    if not hasCustom then return end

    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            if not (InCombatLockdown and InCombatLockdown()) then
                PartyFrames.ensureHealthOverlay(bar, cfg)
            else
                local state = getState(bar)
                if state and state.healthOverlay then
                    styleHealthOverlay(bar, cfg)
                    updateHealthOverlay(bar)
                end
            end
        end
    end
end

-- Restore all party health bars to stock appearance
function addon.RestorePartyFrameHealthOverlays()
    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            PartyFrames.disableHealthOverlay(bar)
        end
    end
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

-- EDIT MODE GUARD: Skip all CompactUnitFrame hooks when Edit Mode is active.
-- When Scoot triggers ApplyChanges (which bounces Edit Mode), Blizzard sets up
-- Arena/Party/Raid frames. If hooks run during this flow (even just to check
-- frame type), addon code in the execution context can cause UnitInRange() and
-- similar APIs to return secret values, breaking Blizzard's own code.
local function isEditModeActive()
    if addon and addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening then
        return addon.EditMode.IsEditModeActiveOrOpening()
    end
    local mgr = _G.EditModeManagerFrame
    return mgr and (mgr.editModeActive or (mgr.IsShown and mgr:IsShown()))
end

addon.BarsPartyFrames._isEditModeActive = isEditModeActive

function PartyFrames.installHooks()
    if addon._PartyFrameHooksInstalled then return end
    addon._PartyFrameHooksInstalled = true

    -- Raise DispelOverlay above healthBar in the useParentLevel stacking order.
    -- Both are useParentLevel="true" siblings; rendering order among same-level
    -- siblings depends on stacking order (not draw layers across frames).
    -- Show()/Hide() cycles in CompactUnitFrame_SetDispelOverlayAura can flip
    -- stacking order, so we re-Raise after every show.
    if not addon._DispelOverlayRaiseHookInstalled then
        addon._DispelOverlayRaiseHookInstalled = true
        if _G.hooksecurefunc and _G.CompactUnitFrame_SetDispelOverlayAura then
            _G.hooksecurefunc("CompactUnitFrame_SetDispelOverlayAura", function(frame, aura)
                if not frame or not frame.DispelOverlay then return end
                if aura and aura.dispelName and frame.DispelOverlay.Raise then
                    frame.DispelOverlay:Raise()
                end
            end)
        end
    end

    -- Hook CompactUnitFrame_UpdateAll
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if frame and frame.healthBar and Utils.isPartyFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.party or nil
                if cfg then
                    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                    if hasCustom then
                        local bar = frame.healthBar
                        local cfgRef = cfg
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if InCombatLockdown and InCombatLockdown() then
                                    Combat.queuePartyFrameReapply()
                                    return
                                end
                                PartyFrames.applyToHealthBar(bar, cfgRef)
                                -- Also ensure overlay exists (handles party formed mid-session)
                                PartyFrames.ensureHealthOverlay(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                            PartyFrames.applyToHealthBar(bar, cfgRef)
                            PartyFrames.ensureHealthOverlay(bar, cfgRef)
                        end
                    end
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if frame and frame.healthBar and unit and Utils.isPartyFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.party or nil
                if cfg then
                    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                    if hasCustom then
                        local bar = frame.healthBar
                        local cfgRef = cfg
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if InCombatLockdown and InCombatLockdown() then
                                    Combat.queuePartyFrameReapply()
                                    return
                                end
                                PartyFrames.applyToHealthBar(bar, cfgRef)
                                -- Also ensure overlay exists (handles party formed mid-session)
                                PartyFrames.ensureHealthOverlay(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                            PartyFrames.applyToHealthBar(bar, cfgRef)
                            PartyFrames.ensureHealthOverlay(bar, cfgRef)
                        end
                    end
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_UpdateHealthColor for "Color by Value" mode
    -- This hook fires after every health update, enabling dynamic color updates
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateHealthColor then
        _G.hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not frame or not frame.healthBar then return end
            if frame.IsForbidden and frame:IsForbidden() then return end

            -- Only process party frames (not raid frames or nameplates)
            if not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local cfg = db and db.groupFrames and db.groupFrames.party or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return end

            local useDark = (colorMode == "valueDark")

            -- Get unit token from the frame
            local unit
            local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
            if okU and u then unit = u end
            if not unit then return end

            -- FIX 1: Conditional deferral to prevent blinking during health regen.
            -- The blink occurs because:
            --   1. SetValue hook applies the custom color
            --   2. Blizzard's CompactUnitFrame_UpdateHealthColor resets to default green
            --   3. The deferred callback re-applies the custom color (1 frame later = visible flicker)
            --
            -- Solution: Only defer when overlay doesn't exist yet (initialization).
            -- When overlay is ready and shown, apply immediately (synchronously).
            local healthBar = frame.healthBar
            local state = getState(healthBar)
            local overlay = state and state.healthOverlay or nil

            if overlay and overlay:IsShown() then
                -- Overlay exists and is shown - apply immediately (no defer)
                -- This prevents the 1-frame blink where Blizzard's color shows
                if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                    addon.BarsTextures.applyValueBasedColor(healthBar, unit, overlay, useDark)
                    -- Schedule validation to catch timing edge cases (stuck colors at 100%)
                    if addon.BarsTextures.scheduleColorValidation then
                        addon.BarsTextures.scheduleColorValidation(healthBar, unit, overlay, useDark)
                    end
                end
            else
                -- Overlay not ready - defer to ensure initialization completes
                C_Timer.After(0, function()
                    local st = getState(healthBar)
                    local ov = st and st.healthOverlay or nil
                    if ov and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(healthBar, unit, ov, useDark)
                        -- Schedule validation for deferred case too
                        if addon.BarsTextures.scheduleColorValidation then
                            addon.BarsTextures.scheduleColorValidation(healthBar, unit, ov, useDark)
                        end
                    elseif addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        -- No overlay, apply to status bar texture directly
                        addon.BarsTextures.applyValueBasedColor(healthBar, unit, nil, useDark)
                    end
                end)
            end
        end)
    end

    -- Hook CompactUnitFrame_UpdateHealPrediction to reapply masks + visibility
    -- after Blizzard repositions prediction/absorb textures
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateHealPrediction then
        _G.hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
            if isEditModeActive() then return end
            if not frame or not Utils.isPartyFrame(frame) then return end

            local db = addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            if not partyCfg then return end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    -- Reapply clipping masks (defined in extras.lua, loaded after core.lua)
                    if PartyFrames.ensureHealPredictionClipping then
                        PartyFrames.ensureHealPredictionClipping(frame)
                    end
                    -- Reapply visibility if toggled
                    if partyCfg.hideHealPrediction and PartyFrames.applyHealPredictionVisibility then
                        PartyFrames.applyHealPredictionVisibility(frame, true)
                    end
                    if partyCfg.hideAbsorbBars and PartyFrames.applyAbsorbBarsVisibility then
                        PartyFrames.applyAbsorbBarsVisibility(frame, true)
                    end
                end)
            end
        end)
    end

    -- Named function for role icon customization (also used by safety net and fallbacks)
    local function applyCustomRoleIcon(frame)
        if isEditModeActive() then return end
        if not frame then return end
        if frame.IsForbidden and frame:IsForbidden() then return end

        -- Only process frames Scoot styles
        if not Utils.isPartyFrame(frame) and not Utils.isRaidFrame(frame) then return end

        -- Check if Scoot has active overlays
        local db = addon and addon.db and addon.db.profile
        local groupFrames = db and rawget(db, "groupFrames") or nil
        if not groupFrames then return end
        local cfg = Utils.isPartyFrame(frame) and rawget(groupFrames, "party")
                 or Utils.isRaidFrame(frame) and rawget(groupFrames, "raid")
                 or nil
        if not cfg then return end

        local okR, roleIcon = pcall(function() return frame.roleIcon end)
        if not okR or not roleIcon then return end

        -- Track whether we need desaturation (applied at the very end)
        local shouldDesaturate = false

        -- A) Draw layer elevation (only when Scoot overlays active)
        local hasOverlay = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default")
                        or (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
        if not hasOverlay then
            local textCfg = rawget(cfg, "textPlayerName") or nil
            hasOverlay = textCfg and Utils.hasCustomTextSettings(textCfg)
        end
        if hasOverlay and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end

        -- B) Custom positioning (independent of icon set)
        do
            local anchor = rawget(cfg, "roleIconAnchor")
            if anchor and anchor ~= "default" and roleIcon.IsShown and roleIcon:IsShown() then
                local offsetX = tonumber(rawget(cfg, "roleIconOffsetX")) or 0
                local offsetY = tonumber(rawget(cfg, "roleIconOffsetY")) or 0
                pcall(roleIcon.ClearAllPoints, roleIcon)
                pcall(roleIcon.SetPoint, roleIcon, anchor, frame, anchor, offsetX, offsetY)
            end
        end

        -- B2) Visibility filtering (no early returns — B3 and C must always run)
        do
            local vis = rawget(cfg, "roleIconVisibility")
            if vis and roleIcon.IsShown and roleIcon:IsShown() then
                if vis == "hideAll" then
                    pcall(roleIcon.SetAlpha, roleIcon, 0)
                elseif vis == "hideDPS" then
                    local unit
                    local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
                    if okU and u then unit = u end
                    if unit then
                        local okRole, role = pcall(UnitGroupRolesAssigned, unit)
                        if okRole and type(role) == "string" and role == "DAMAGER" then
                            pcall(roleIcon.SetAlpha, roleIcon, 0)
                        else
                            pcall(roleIcon.SetAlpha, roleIcon, 1)
                        end
                    else
                        -- Couldn't determine unit: ensure visible
                        pcall(roleIcon.SetAlpha, roleIcon, 1)
                    end
                elseif vis == "showAll" then
                    -- Restore from previously hidden state
                    pcall(roleIcon.SetAlpha, roleIcon, 1)
                end
            end
        end

        -- B3) Scale
        do
            local scale = tonumber(rawget(cfg, "roleIconScale"))
            if scale then
                local size = 17 * scale / 100
                pcall(roleIcon.SetSize, roleIcon, size, size)
            end
        end

        -- C) Custom icon set swap (independent of overlay state)
        local iconSet = rawget(cfg, "roleIconSet")
        local skipSwap = false
        if not iconSet or iconSet == "default" then
            skipSwap = true
        end
        if not skipSwap and (not roleIcon.IsShown or not roleIcon:IsShown()) then
            skipSwap = true
        end

        if not skipSwap then
            local unit
            local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
            if okU and u then unit = u end

            if unit then
                -- Don't override vehicle icons (set flag instead of returning)
                local isVehicle = false
                local okV, inVehicle = pcall(UnitInVehicle, unit)
                if okV and inVehicle then
                    local okVUI, hasVUI = pcall(UnitHasVehicleUI, unit)
                    if okVUI and hasVUI then isVehicle = true end
                end

                if not isVehicle then
                    local okRole, role = pcall(UnitGroupRolesAssigned, unit)
                    if okRole and type(role) == "string" and role ~= "NONE" then
                        -- Check texture-based sets first (custom TGA files)
                        local textures = Utils.ROLE_ICON_TEXTURES and Utils.ROLE_ICON_TEXTURES[iconSet]
                        if textures and textures[role] then
                            pcall(roleIcon.SetTexture, roleIcon, textures[role])
                            pcall(roleIcon.SetTexCoord, roleIcon, 0, 1, 0, 1)
                            if textures.desaturated then
                                shouldDesaturate = true
                            end
                        else
                            -- Then check atlas-based sets (built-in Blizzard atlases)
                            local atlases = Utils.ROLE_ICON_ATLASES and Utils.ROLE_ICON_ATLASES[iconSet]
                            if atlases and atlases[role] then
                                pcall(roleIcon.SetAtlas, roleIcon, atlases[role])
                            end
                        end
                    end
                end
            end
        end

        -- Final: apply desaturation state (always runs, cleans up stale state too)
        pcall(roleIcon.SetDesaturated, roleIcon, shouldDesaturate)
    end

    -- Expose for cross-file access (raidframes.lua fallback)
    addon._applyCustomRoleIcon = applyCustomRoleIcon

    -- Hook CompactUnitFrame_UpdateRoleIcon to:
    -- A) Elevate roleIcon draw layer above Scoot overlay containers
    -- B) Swap to custom icon set if configured
    if not addon._RoleIconVisibilityHookInstalled then
        addon._RoleIconVisibilityHookInstalled = true
        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateRoleIcon then
            _G.hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", applyCustomRoleIcon)
        end
    end

    -- Safety net: re-apply custom role icons on roster/role events
    -- Needed because Blizzard's CompactUnitFrame_UpdateRoleIcon may error on
    -- tainted roleIcon widgets (secret value from GetHeight), causing our
    -- post-hook to never fire. This directly applies without going through
    -- Blizzard's function.
    if not addon._RoleIconSafetyNetInstalled then
        addon._RoleIconSafetyNetInstalled = true
        local safetyNetTimer = nil
        local roleIconEventFrame = CreateFrame("Frame")
        roleIconEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        roleIconEventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
        roleIconEventFrame:SetScript("OnEvent", function()
            if isEditModeActive() then return end
            local db = addon and addon.db and addon.db.profile
            local gf = db and rawget(db, "groupFrames") or nil
            if not gf then return end
            local pCfg = rawget(gf, "party")
            local rCfg = rawget(gf, "raid")
            local hasAny = (pCfg and (rawget(pCfg, "roleIconSet") or rawget(pCfg, "roleIconAnchor") or rawget(pCfg, "roleIconVisibility")))
                        or (rCfg and (rawget(rCfg, "roleIconSet") or rawget(rCfg, "roleIconAnchor") or rawget(rCfg, "roleIconVisibility")))
            if not hasAny then return end
            if safetyNetTimer then safetyNetTimer:Cancel() end
            safetyNetTimer = C_Timer.NewTimer(0.15, function()
                safetyNetTimer = nil
                if isEditModeActive() then return end
                -- Direct apply (bypasses Blizzard's function which may error on tainted roleIcon)
                for i = 1, 5 do
                    local f = _G["CompactPartyFrameMember" .. i]
                    if f then pcall(applyCustomRoleIcon, f) end
                end
                for i = 1, 40 do
                    local f = _G["CompactRaidFrame" .. i]
                    if f then pcall(applyCustomRoleIcon, f) end
                end
                for g = 1, 8 do
                    for m = 1, 5 do
                        local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
                        if f then pcall(applyCustomRoleIcon, f) end
                    end
                end
            end)
        end)
    end

    --------------------------------------------------------------------------
    -- Group Lead Icon
    --------------------------------------------------------------------------

    local function applyGroupLeadIcon(frame)
        if isEditModeActive() then return end
        if not frame then return end
        if frame.IsForbidden and frame:IsForbidden() then return end

        local isParty = Utils.isPartyFrame(frame)
        local isRaid  = Utils.isRaidFrame(frame)
        if not isParty and not isRaid then return end

        -- DB read via rawget (no AceDB metamethods)
        local db = addon and addon.db and addon.db.profile
        local groupFrames = db and rawget(db, "groupFrames") or nil
        if not groupFrames then return end
        local cfg = isParty and rawget(groupFrames, "party")
                 or isRaid  and rawget(groupFrames, "raid")
                 or nil
        if not cfg then return end

        -- Feature disabled? Hide existing icon and bail
        local show = rawget(cfg, "groupLeadIconShow")
        local state = isParty and ensureState(frame)
                   or isRaid  and addon.BarsRaidFrames._ensureState(frame)
                   or nil

        if not show then
            if state and state.groupLeadIcon then
                pcall(state.groupLeadIcon.Hide, state.groupLeadIcon)
            end
            return
        end

        -- Unit detection (secret-safe)
        local unit
        local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
        if okU and u then unit = u end
        if not unit then
            if state and state.groupLeadIcon then
                pcall(state.groupLeadIcon.Hide, state.groupLeadIcon)
            end
            return
        end

        -- Leader check (secret-safe: guard type)
        local okL, isLeader = pcall(UnitIsGroupLeader, unit)
        if not okL or type(isLeader) ~= "boolean" or not isLeader then
            if state and state.groupLeadIcon then
                pcall(state.groupLeadIcon.Hide, state.groupLeadIcon)
            end
            return
        end

        -- Lazy creation — stored in state table, NOT on frame (taint-safe)
        if not state then return end
        if not state.groupLeadIcon then
            local okC, tex = pcall(frame.CreateTexture, frame, nil, "OVERLAY", nil, 7)
            if not okC or not tex then return end
            pcall(tex.SetAtlas, tex, "UI-HUD-UnitFrame-Player-Group-LeaderIcon")
            state.groupLeadIcon = tex
        end

        local icon = state.groupLeadIcon

        -- Icon set (desaturation)
        local iconSet = rawget(cfg, "groupLeadIconSet") or "default"
        pcall(icon.SetDesaturated, icon, iconSet == "desaturated")

        -- Scale (base 16px)
        local scale = tonumber(rawget(cfg, "groupLeadIconScale")) or 100
        local size = 16 * scale / 100
        pcall(icon.SetSize, icon, size, size)

        -- Position
        local anchor = rawget(cfg, "groupLeadIconAnchor") or "TOPLEFT"
        local offsetX = tonumber(rawget(cfg, "groupLeadIconOffsetX")) or 0
        local offsetY = tonumber(rawget(cfg, "groupLeadIconOffsetY")) or 0
        pcall(icon.ClearAllPoints, icon)
        pcall(icon.SetPoint, icon, anchor, frame, anchor, offsetX, offsetY)

        -- Show
        pcall(icon.Show, icon)
    end

    -- Expose for cross-file access
    addon._applyGroupLeadIcon = applyGroupLeadIcon

    -- Hook CompactUnitFrame_UpdateRoleIcon to also apply group lead icon.
    -- This fires during CompactUnitFrame_UpdateAll for every compact frame,
    -- providing reliable timing after unit assignment.
    if not addon._GroupLeadIconRoleIconHookInstalled then
        addon._GroupLeadIconRoleIconHookInstalled = true
        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateRoleIcon then
            _G.hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", function(frame)
                if isEditModeActive() then return end
                if not frame then return end
                local isParty = Utils.isPartyFrame(frame)
                local isRaid  = Utils.isRaidFrame(frame)
                if not isParty and not isRaid then return end
                local db = addon and addon.db and addon.db.profile
                local gf = db and rawget(db, "groupFrames") or nil
                if not gf then return end
                local cfg = isParty and rawget(gf, "party")
                         or isRaid  and rawget(gf, "raid")
                         or nil
                if not cfg or not rawget(cfg, "groupLeadIconShow") then return end
                pcall(applyGroupLeadIcon, frame)
            end)
        end
    end

    -- Event frame: PARTY_LEADER_CHANGED / GROUP_ROSTER_UPDATE
    if not addon._GroupLeadIconEventInstalled then
        addon._GroupLeadIconEventInstalled = true
        local leadIconTimer = nil
        local leadIconEventFrame = CreateFrame("Frame")
        leadIconEventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
        leadIconEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        leadIconEventFrame:SetScript("OnEvent", function()
            if isEditModeActive() then return end
            -- Early-out if feature is off in both party and raid
            local db = addon and addon.db and addon.db.profile
            local gf = db and rawget(db, "groupFrames") or nil
            if not gf then return end
            local pCfg = rawget(gf, "party")
            local rCfg = rawget(gf, "raid")
            local hasAny = (pCfg and rawget(pCfg, "groupLeadIconShow"))
                        or (rCfg and rawget(rCfg, "groupLeadIconShow"))
            if not hasAny then return end
            -- Debounce 0.15s
            if leadIconTimer then leadIconTimer:Cancel() end
            leadIconTimer = C_Timer.NewTimer(0.15, function()
                leadIconTimer = nil
                if isEditModeActive() then return end
                for i = 1, 5 do
                    local f = _G["CompactPartyFrameMember" .. i]
                    if f then pcall(applyGroupLeadIcon, f) end
                end
                for i = 1, 40 do
                    local f = _G["CompactRaidFrame" .. i]
                    if f then pcall(applyGroupLeadIcon, f) end
                end
                for g = 1, 8 do
                    for m = 1, 5 do
                        local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
                        if f then pcall(applyGroupLeadIcon, f) end
                    end
                end
            end)
        end)
    end

    -- SetUnit hook: deferred to avoid taint
    if not addon._GroupLeadSetUnitHookInstalled then
        addon._GroupLeadSetUnitHookInstalled = true
        if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
                if isEditModeActive() then return end
                if not frame then return end
                -- Only fire if feature is active for this frame type
                local isParty = Utils.isPartyFrame(frame)
                local isRaid  = Utils.isRaidFrame(frame)
                if not isParty and not isRaid then return end
                local db = addon and addon.db and addon.db.profile
                local gf = db and rawget(db, "groupFrames") or nil
                if not gf then return end
                local cfg = isParty and rawget(gf, "party")
                         or isRaid  and rawget(gf, "raid")
                         or nil
                if not cfg or not rawget(cfg, "groupLeadIconShow") then return end
                C_Timer.After(0, function()
                    pcall(applyGroupLeadIcon, frame)
                end)
            end)
        end
    end
end

-- Install hooks on load
PartyFrames.installHooks()

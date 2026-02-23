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
-- Solution: Store all ScooterMod state in a separate lookup table keyed by frame.
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
        -- Restore DispelOverlay to stock frame level (useParentLevel behavior)
        local unitFrame = bar.GetParent and bar:GetParent()
        if unitFrame then
            local parentLevel = 0
            local okL, lvl = pcall(unitFrame.GetFrameLevel, unitFrame)
            if okL and type(lvl) == "number" then parentLevel = lvl end

            local okD, dispelOverlay = pcall(function() return unitFrame.DispelOverlay end)
            if okD and dispelOverlay and dispelOverlay.SetFrameLevel then
                pcall(dispelOverlay.SetFrameLevel, dispelOverlay, parentLevel)
            end
        end
        return
    end

    if state and not state.healthOverlay then
        -- IMPORTANT: This overlay must NOT be parented to the StatusBar.
        -- WoW draws all parent frame layers first, then all child frame layers.
        -- If parented to the health bar (child), the overlay can draw *above*
        -- CompactUnitFrame parent-layer elements like roleIcon (ARTWORK) and
        -- readyCheckIcon (OVERLAY), effectively hiding them.
        --
        -- Fix: parent the overlay to the CompactUnitFrame (the health bar's parent)
        -- and draw it in BORDER sublevel 7 so it stays above heal-prediction layers
        -- but below role/ready-check indicators.
        local unitFrame = (bar.GetParent and bar:GetParent()) or nil
        local overlayParent = unitFrame or bar
        local overlay = overlayParent:CreateTexture(nil, "BORDER", nil, 7)
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

    -- Raise DispelOverlay above ScooterMod's overlay so dispel indicators remain visible.
    -- DispelOverlay uses useParentLevel="true", which means the parent's own regions
    -- (including our BORDER sublevel 7 overlay) render on top of it. SetFrameLevel
    -- is a C-side widget operation (taint-safe per Rule 4).
    -- Runs before the fingerprint check so it re-applies every call.
    local unitFrame = bar.GetParent and bar:GetParent()
    if unitFrame then
        local parentLevel = 0
        local okL, lvl = pcall(unitFrame.GetFrameLevel, unitFrame)
        if okL and type(lvl) == "number" then parentLevel = lvl end

        local okD, dispelOverlay = pcall(function() return unitFrame.DispelOverlay end)
        if okD and dispelOverlay and dispelOverlay.SetFrameLevel then
            pcall(dispelOverlay.SetFrameLevel, dispelOverlay, parentLevel + 11)
        end

        -- Elevate roleIcon above ScooterMod overlay layers (OVERLAY 6, below name text at OVERLAY 7)
        local okR, roleIcon = pcall(function() return unitFrame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
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
    -- Restore DispelOverlay to stock frame level (useParentLevel behavior)
    local unitFrame = bar.GetParent and bar:GetParent()
    if unitFrame then
        local parentLevel = 0
        local okL, lvl = pcall(unitFrame.GetFrameLevel, unitFrame)
        if okL and type(lvl) == "number" then parentLevel = lvl end

        local okD, dispelOverlay = pcall(function() return unitFrame.DispelOverlay end)
        if okD and dispelOverlay and dispelOverlay.SetFrameLevel then
            pcall(dispelOverlay.SetFrameLevel, dispelOverlay, parentLevel)
        end

        -- Restore roleIcon to stock draw layer
        local okR, roleIcon = pcall(function() return unitFrame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "ARTWORK", 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Health Bar Borders
--------------------------------------------------------------------------------
-- Applies ScooterMod bar borders to party frame health bars.
--
-- IMPORTANT: Uses explicit edge textures on the parent CompactUnitFrame (not a
-- child frame) to ensure correct draw order with Blizzard's selection highlight.
--
-- Layer order on a single frame:
-- 1. Health bar (StatusBar)
-- 2. Health overlay texture (BORDER sublevel 7)
-- 3. ScooterMod border textures (OVERLAY sublevel -8)
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
    local edges = ufState and ufState.ScooterModBorderEdges
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
    local edges = ufState.ScooterModBorderEdges
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
        ufState.ScooterModBorderEdges = edges
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
-- When ScooterMod triggers ApplyChanges (which bounces Edit Mode), Blizzard sets up
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

-- Forward declarations for functions defined later but referenced in installHooks() closures
local ensureHealPredictionClipping
local applyHealPredictionVisibility
local applyAbsorbBarsVisibility

function PartyFrames.installHooks()
    if addon._PartyFrameHooksInstalled then return end
    addon._PartyFrameHooksInstalled = true

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
                    -- Reapply clipping masks
                    ensureHealPredictionClipping(frame)
                    -- Reapply visibility if toggled
                    if partyCfg.hideHealPrediction then
                        applyHealPredictionVisibility(frame, true)
                    end
                    if partyCfg.hideAbsorbBars then
                        applyAbsorbBarsVisibility(frame, true)
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

        -- Only process frames ScooterMod styles
        if not Utils.isPartyFrame(frame) and not Utils.isRaidFrame(frame) then return end

        -- Check if ScooterMod has active overlays
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

        -- A) Draw layer elevation (only when ScooterMod overlays active)
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
    -- A) Elevate roleIcon draw layer above ScooterMod overlay containers
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
end

-- Install hooks on load
PartyFrames.installHooks()

--------------------------------------------------------------------------------
-- Apply Custom Role Icons for Party Frames
--------------------------------------------------------------------------------
-- Re-triggers Blizzard's CompactUnitFrame_UpdateRoleIcon on each party frame.
-- Blizzard sets the default atlas, then our post-hook swaps to the custom set.
-- Falls back to direct application if Blizzard's function errors (tainted widget).

function addon.ApplyPartyRoleIcons()
    local directApply = addon._applyCustomRoleIcon
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.roleIcon then
            if _G.CompactUnitFrame_UpdateRoleIcon then
                local ok = pcall(CompactUnitFrame_UpdateRoleIcon, frame)
                if not ok and directApply then
                    pcall(directApply, frame)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Event-Based Color Updates for Party Frames (Value Mode)
--------------------------------------------------------------------------------
-- The SetValue hook handles most color updates, but some edge cases require
-- explicit event handling:
-- - UNIT_MAXHEALTH: When max health changes (buffs, potions that heal to cap)
-- - UNIT_HEAL_PREDICTION: Incoming heal updates
-- - UNIT_HEALTH: Backup for any health changes the SetValue hook might miss
--
-- This fixes "stuck colors" when healing to exactly 100% where no subsequent
-- SetValue call might occur.
--------------------------------------------------------------------------------

local function isPartyUnit(unit)
    if not unit then return false end
    -- Include player since they can appear in party frames too
    return unit == "player" or unit == "party1" or unit == "party2" or unit == "party3" or unit == "party4"
end

local function getPartyHealthBarForUnit(unit)
    if not unit or not isPartyUnit(unit) then return nil, nil, nil end

    local db = addon and addon.db and addon.db.profile
    local groupFrames = db and rawget(db, "groupFrames") or nil
    local cfg = groupFrames and rawget(groupFrames, "party") or nil
    local colorMode = cfg and cfg.healthBarColorMode
    if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil, nil end

    local useDark = (colorMode == "valueDark")

    -- Party frames are dynamically assigned - check each frame's unit property
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.healthBar then
            local frameUnit
            local ok, u = pcall(function() return frame.displayedUnit or frame.unit end)
            if ok and u then frameUnit = u end
            -- Check if this frame is displaying the unit we're looking for
            if frameUnit and UnitIsUnit(frameUnit, unit) then
                return frame.healthBar, frame, useDark
            end
        end
    end
end

local partyHealthColorEventFrame = CreateFrame("Frame")
partyHealthColorEventFrame:RegisterEvent("UNIT_HEALTH")
partyHealthColorEventFrame:RegisterEvent("UNIT_MAXHEALTH")
partyHealthColorEventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
partyHealthColorEventFrame:SetScript("OnEvent", function(self, event, unit)
    if not unit or not isPartyUnit(unit) then return end

    local bar, frame, useDark = getPartyHealthBarForUnit(unit)
    if not bar then return end

    -- Use the frame's actual unit token for color calculation
    local actualUnit = unit
    if frame then
        local ok, u = pcall(function() return frame.displayedUnit or frame.unit end)
        if ok and u then actualUnit = u end
    end

    local state = getState(bar)
    local overlay = state and state.healthOverlay or nil
    if overlay and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
        addon.BarsTextures.applyValueBasedColor(bar, actualUnit, overlay, useDark)
        -- Schedule reapply loop to catch timing edge cases (stuck colors at 100%)
        if addon.BarsTextures.scheduleColorValidation then
            addon.BarsTextures.scheduleColorValidation(bar, actualUnit, overlay, useDark)
        end
    elseif addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
        addon.BarsTextures.applyValueBasedColor(bar, actualUnit, nil, useDark)
    end
end)

--------------------------------------------------------------------------------
-- Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings to party frame name text elements.
-- Target: CompactPartyFrameMember[1-5].name (FontString with parentKey="name")
--------------------------------------------------------------------------------

local function applyTextToPartyFrame(frame, cfg)
    if not frame or not cfg then return end

    local nameFS = frame.name
    if not nameFS then return end

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    local success = pcall(nameFS.SetFont, nameFS, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(nameFS.SetFont, nameFS, fallback, fontSize, fontStyle)
        end
    end

    if nameFS.SetTextColor then
        pcall(nameFS.SetTextColor, nameFS, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    -- Apply text alignment based on anchor's horizontal component
    if nameFS.SetJustifyH then
        pcall(nameFS.SetJustifyH, nameFS, Utils.getJustifyHFromAnchor(anchor))
    end

    -- Capture baseline position on first application for later restoration
    local nameState = ensureState(nameFS)
    if nameState and not nameState.originalPoint then
        local point, relativeTo, relativePoint, x, y = nameFS:GetPoint(1)
        if point then
            nameState.originalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    -- Apply anchor-based positioning with offsets relative to selected anchor
    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and nameState and nameState.originalPoint then
        -- Restore baseline (stock position) when user has reset to default
        local orig = nameState.originalPoint
        nameFS:ClearAllPoints()
        nameFS:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
        -- Also restore default text alignment
        if nameFS.SetJustifyH then
            pcall(nameFS.SetJustifyH, nameFS, "LEFT")
        end
    else
        -- Position the name FontString using the user-selected anchor, relative to the frame
        nameFS:ClearAllPoints()
        nameFS:SetPoint(anchor, frame, anchor, offsetX, offsetY)
    end

    -- Preserve Blizzard's truncation/clipping behavior: explicitly constrain the name FontString width.
    -- Blizzard normally constrains this via a dual-anchor layout (TOPLEFT + TOPRIGHT). The single-point
    -- anchor (for 9-way alignment) removes that implicit width, so SetWidth restores it.
    if nameFS.SetMaxLines then
        pcall(nameFS.SetMaxLines, nameFS, 1)
    end
    if frame.GetWidth and nameFS.SetWidth then
        local frameWidth = frame:GetWidth()
        local roleIconWidth = 0
        if frame.roleIcon and frame.roleIcon.GetWidth then
            roleIconWidth = frame.roleIcon:GetWidth() or 0
        end
        -- 3px right padding + (role icon area) + 3px left padding ~= 6px padding total, matching CUF defaults.
        local availableWidth = (frameWidth or 0) - (roleIconWidth or 0) - 6
        if availableWidth and availableWidth > 1 then
            pcall(nameFS.SetWidth, nameFS, availableWidth)
        else
            pcall(nameFS.SetWidth, nameFS, 1)
        end
    end
end

local partyFramesForText = {}
local function collectPartyFramesForText()
    if wipe then
        wipe(partyFramesForText)
    else
        partyFramesForText = {}
    end
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.name then
            local nameState = getState(frame.name)
            if not nameState or not nameState.partyTextCounted then
                local st = ensureState(frame.name)
                if st then st.partyTextCounted = true end
                table.insert(partyFramesForText, frame)
            end
        end
    end
end

function addon.ApplyPartyFrameTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPlayerName") or nil
    if not cfg then
        return
    end

    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Deprecated: Party Player Name styling is now driven by overlay FontStrings
    -- (see ApplyPartyFrameNameOverlays). Avoid touching Blizzard's `frame.name`
    -- so overlay clipping preserves stock truncation behavior.
    if addon.ApplyPartyFrameNameOverlays then
        addon.ApplyPartyFrameNameOverlays()
    end
end

local function installPartyFrameTextHooks()
    if addon._PartyFrameTextHooksInstalled then return end
    addon._PartyFrameTextHooksInstalled = true

    -- Deprecated: name styling hooks must not touch Blizzard's `frame.name`.
    -- Overlay system installs its own hooks (installPartyNameOverlayHooks()).
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on party frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because only
-- addon-owned FontStrings are manipulated.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

-- Apply styling to the overlay FontString
local function stylePartyNameOverlay(frame, cfg)
    local state = getState(frame)
    if not frame or not state or not state.overlayText or not cfg then return end

    local overlay = state.overlayText
    local container = state.overlayContainer or frame

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    -- Apply font
    local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
        end
    end

    -- Determine color based on colorMode
    local colorMode = cfg.colorMode or "default"
    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "class" then
        -- Use the party member's class color
        local unit = frame.unit
        if addon.GetClassColorRGB and unit then
            local cr, cg, cb = addon.GetClassColorRGB(unit)
            r, g, b, a = cr or 1, cg or 1, cb or 1, 1
        end
    elseif colorMode == "custom" then
        local color = cfg.color or { 1, 1, 1, 1 }
        r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    else
        -- "default" - use white
        r, g, b, a = 1, 1, 1, 1
    end

    -- Apply color
    pcall(overlay.SetTextColor, overlay, r, g, b, a)

    -- Always use LEFT justify so truncation only happens on the right side.
    -- This ensures player names always show the beginning of the name.
    pcall(overlay.SetJustifyH, overlay, "LEFT")
    if overlay.SetJustifyV then
        pcall(overlay.SetJustifyV, overlay, "MIDDLE")
    end
    if overlay.SetWordWrap then
        pcall(overlay.SetWordWrap, overlay, false)
    end
    if overlay.SetNonSpaceWrap then
        pcall(overlay.SetNonSpaceWrap, overlay, false)
    end
    if overlay.SetMaxLines then
        pcall(overlay.SetMaxLines, overlay, 1)
    end

    -- Position using dynamic text-width-based alignment.
    -- repositionNameOverlay computes exact CENTER/RIGHT offset from GetStringWidth().
    Utils.repositionNameOverlay(overlay, container, anchor, offsetX, offsetY)

    -- Store alignment params so the SetText hook can reposition after text changes.
    state.nameAnchor = anchor
    state.nameOffsetX = offsetX
    state.nameOffsetY = offsetY
end

-- Hide Blizzard's name FontString and install alpha-enforcement hook
local function hideBlizzardPartyNameText(frame)
    if not frame or not frame.name then return end
    local blizzName = frame.name

    local nameState = ensureState(blizzName)
    if nameState then nameState.hidden = true end
    if blizzName.SetAlpha then
        pcall(blizzName.SetAlpha, blizzName, 0)
    end
    if blizzName.Hide then
        pcall(blizzName.Hide, blizzName)
    end

    -- Install alpha-enforcement hook (only once)
    if nameState and not nameState.alphaHooked and _G.hooksecurefunc then
        nameState.alphaHooked = true
        _G.hooksecurefunc(blizzName, "SetAlpha", function(self, alpha)
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

    if nameState and not nameState.showHooked and _G.hooksecurefunc then
        nameState.showHooked = true
        _G.hooksecurefunc(blizzName, "Show", function(self)
            local st = getState(self)
            if not st or not st.hidden then return end
            -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    local st2 = getState(self)
                    if self and st2 and st2.hidden then
                        if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                        if self.Hide then pcall(self.Hide, self) end
                    end
                end)
            else
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                if self.Hide then pcall(self.Hide, self) end
            end
        end)
    end
end

-- Show Blizzard's name FontString (for restore/cleanup)
local function showBlizzardPartyNameText(frame)
    if not frame or not frame.name then return end
    local nameState = getState(frame.name)
    if nameState then nameState.hidden = nil end
    if frame.name.SetAlpha then
        pcall(frame.name.SetAlpha, frame.name, 1)
    end
    if frame.name.Show then
        pcall(frame.name.Show, frame.name)
    end
end

-- Create or update the party name text overlay for a specific frame
-- TAINT PREVENTION: Uses lookup table instead of writing to Blizzard frames
local function ensurePartyNameOverlay(frame, cfg)
    if not frame then return end

    local hasCustom = Utils.hasCustomTextSettings(cfg)
    local state = ensureState(frame)
    state.overlayActive = hasCustom
    state.hideRealmEnabled = cfg and cfg.hideRealm and true or false

    if not hasCustom then
        -- Disable overlay, show Blizzard's text
        if state.overlayText then
            state.overlayText:Hide()
        end
        showBlizzardPartyNameText(frame)
        return
    end

    -- Ensure an addon-owned clipping container for name text.
    -- IMPORTANT: This container must span the full available unit-frame area so 9-way alignment
    -- (e.g., BOTTOM / BOTTOMRIGHT) can genuinely reach the bottom of the frame.
    if not state.overlayContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetClipsChildren(true)

        container:ClearAllPoints()
        -- Small insets to match CUF's typical text padding and avoid touching frame edges.
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

        -- Elevate roleIcon when creating name overlay container
        local okR, roleIcon = pcall(function() return frame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end

        state.overlayContainer = container
    end

    -- Create overlay FontString if it doesn't exist
    if not state.overlayText then
        local parentForText = state.overlayContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 7) -- High sublayer to ensure visibility
        state.overlayText = overlay

        -- Install SetText hook on Blizzard's name FontString to mirror text
        -- Store hook state in the addon lookup table, not on Blizzard's frame
        if frame.name and not state.textMirrorHooked and _G.hooksecurefunc then
            state.textMirrorHooked = true
            -- Capture state reference for the closure
            local frameState = state
            _G.hooksecurefunc(frame.name, "SetText", function(self, text)
                if frameState and frameState.overlayText and frameState.overlayActive then
                    -- text may be a secret value in 12.0; branch on type
                    if type(text) == "string" then
                        local displayText = text
                        -- Strip realm suffix: split on first hyphen (WoW names never contain hyphens).
                        -- Ambiguate("none") only strips same/connected realms, not cross-realm.
                        if frameState.hideRealmEnabled and displayText ~= "" then
                            displayText = displayText:match("^([^%-]+)") or displayText
                        end
                        frameState.overlayText:SetText(displayText)
                    else
                        -- Secret or other type — SetText handles secrets natively
                        pcall(frameState.overlayText.SetText, frameState.overlayText, text)
                    end
                    -- Reposition after text change so CENTER/RIGHT alignment adapts to new text width
                    if frameState.nameAnchor then
                        Utils.repositionNameOverlay(frameState.overlayText,
                            frameState.overlayContainer or frame,
                            frameState.nameAnchor, frameState.nameOffsetX or 0, frameState.nameOffsetY or 0)
                    end
                end
            end)
        end
    end

    -- Build fingerprint to detect config changes AND unit-specific state.
    -- When colorMode is "class", include the resolved class token so the
    -- fingerprint changes when unit data becomes available (e.g., zone-in).
    local fpColorMode = cfg.colorMode or "default"
    local classKey = ""
    if fpColorMode == "class" and frame.unit then
        local ok, _, token = pcall(function() return UnitClass(frame.unit) end)
        if ok and type(token) == "string" then
            classKey = token
        end
    end

    local fingerprint = string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s",
        tostring(cfg.fontFace or ""),
        tostring(cfg.size or ""),
        tostring(cfg.style or ""),
        tostring(cfg.anchor or ""),
        tostring(cfg.hideRealm or ""),
        cfg.color and string.format("%.2f,%.2f,%.2f,%.2f",
            cfg.color[1] or 1, cfg.color[2] or 1, cfg.color[3] or 1, cfg.color[4] or 1) or "",
        cfg.offset and string.format("%.1f,%.1f", cfg.offset.x or 0, cfg.offset.y or 0) or "",
        fpColorMode,
        classKey
    )

    -- Skip re-styling if config hasn't changed and overlay is visible
    if state.lastNameFingerprint == fingerprint and state.overlayText:IsShown() then
        return
    end
    state.lastNameFingerprint = fingerprint

    -- Style the overlay and hide Blizzard's text
    stylePartyNameOverlay(frame, cfg)
    hideBlizzardPartyNameText(frame)

    -- Copy current text from Blizzard's FontString to the overlay
    -- Wrap in pcall as GetText() can return secrets in 12.0
    local textCopied = false
    if frame.name and frame.name.GetText then
        local ok, currentText = pcall(frame.name.GetText, frame.name)
        if ok and type(currentText) == "string" and currentText ~= "" then
            local displayText = currentText
            -- Apply realm stripping if enabled
            if cfg and cfg.hideRealm and displayText ~= "" then
                displayText = displayText:match("^([^%-]+)") or displayText
            end
            state.overlayText:SetText(displayText)
            textCopied = true
        end
    end

    -- Fallback: if GetText failed (secret/nil), try GetUnitName
    if not textCopied and frame.unit then
        local unitOk, unitName = pcall(GetUnitName, frame.unit, true)
        if unitOk and type(unitName) == "string" and unitName ~= "" then
            local displayText = unitName
            if cfg and cfg.hideRealm and displayText ~= "" then
                displayText = displayText:match("^([^%-]+)") or displayText
            end
            state.overlayText:SetText(displayText)
            textCopied = true
        end
    end

    -- Last resort: if both returned secrets, pass through directly
    -- SetText handles secrets natively (renders correctly, applies Text aspect)
    if not textCopied and frame.name and frame.name.GetText then
        local ok, rawText = pcall(frame.name.GetText, frame.name)
        if ok then
            pcall(state.overlayText.SetText, state.overlayText, rawText)
        end
    end

    -- Reposition after initial text copy so CENTER/RIGHT alignment uses actual text width
    if state.nameAnchor then
        Utils.repositionNameOverlay(state.overlayText, state.overlayContainer or frame,
            state.nameAnchor, state.nameOffsetX or 0, state.nameOffsetY or 0)
    end

    state.overlayText:Show()
end

-- Disable overlay and restore Blizzard's appearance for a frame
local function disablePartyNameOverlay(frame)
    if not frame then return end
    local state = getState(frame)
    if state then
        state.overlayActive = false
        if state.overlayText then
            state.overlayText:Hide()
        end
    end
    showBlizzardPartyNameText(frame)

    -- Restore roleIcon to stock draw layer
    local okR, roleIcon = pcall(function() return frame.roleIcon end)
    if okR and roleIcon and roleIcon.SetDrawLayer then
        pcall(roleIcon.SetDrawLayer, roleIcon, "ARTWORK", 0)
    end
end

-- Apply overlays to all party frames
function addon.ApplyPartyFrameNameOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    local cfg = rawget(partyCfg, "textPlayerName") or nil
    local hasCustom = Utils.hasCustomTextSettings(cfg)

    -- If no custom settings, skip - let RestorePartyFrameNameOverlays handle cleanup
    if not hasCustom then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            -- Only create overlays out of combat (initial setup)
            local state = getState(frame)
            if not (InCombatLockdown and InCombatLockdown()) then
                ensurePartyNameOverlay(frame, cfg)
            elseif state and state.overlayText then
                -- Already have overlay, just update styling (safe during combat for addon-owned FontString)
                stylePartyNameOverlay(frame, cfg)
            end
        end
    end
end

-- Restore all party frames to stock appearance
function addon.RestorePartyFrameNameOverlays()
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            disablePartyNameOverlay(frame)
        end
    end
end

-- Install hooks that trigger overlay setup/updates via CompactUnitFrame events
local function installPartyNameOverlayHooks()
    if addon._PartyNameOverlayHooksInstalled then return end
    addon._PartyNameOverlayHooksInstalled = true

    -- Hook CompactUnitFrame_UpdateAll to set up overlays
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit for unit assignment changes
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not unit or not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_UpdateName for name text updates
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
        _G.hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end

    -- Event-driven re-application for party composition changes.
    -- When entering a Follower Dungeon (or any party change), unit class data
    -- may not be ready when CompactUnitFrame hooks first fire.
    -- GROUP_ROSTER_UPDATE provides a reliable secondary trigger.
    if not addon._PartyNameRosterEventInstalled then
        addon._PartyNameRosterEventInstalled = true
        local rosterFrame = CreateFrame("Frame")
        rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        rosterFrame:SetScript("OnEvent", function()
            if isEditModeActive() then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil
            if not cfg or (cfg.colorMode or "default") ~= "class" then return end
            if not Utils.hasCustomTextSettings(cfg) then return end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0.5, function()
                    if isEditModeActive() then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queuePartyFrameReapply()
                        return
                    end
                    if addon.ApplyPartyFrameNameOverlays then
                        addon.ApplyPartyFrameNameOverlays()
                    end
                end)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Party Title)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Party Frames > Text > Player Name to the party frame title text.
-- Target: CompactPartyFrame.title (Button from CompactRaidGroupTemplate: "$parentTitle", parentKey="title").
--------------------------------------------------------------------------------

local function applyTextToFontString_PartyTitle(fs, ownerFrame, cfg)
    if not fs or not ownerFrame or not cfg then return end

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    local success = pcall(fs.SetFont, fs, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(fs.SetFont, fs, fallback, fontSize, fontStyle)
        end
    end

    if fs.SetTextColor then
        pcall(fs.SetTextColor, fs, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if fs.SetJustifyH then
        pcall(fs.SetJustifyH, fs, Utils.getJustifyHFromAnchor(anchor))
    end

    local fsState = ensureState(fs)
    if fsState and not fsState.originalPointPartyTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fsState.originalPointPartyTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fsState and fsState.originalPointPartyTitle then
        local orig = fsState.originalPointPartyTitle
        fs:ClearAllPoints()
        fs:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "LEFT")
        end
    else
        fs:ClearAllPoints()
        fs:SetPoint(anchor, ownerFrame, anchor, offsetX, offsetY)
    end
end

local function applyPartyTitle(titleButton, cfg)
    if not titleButton or not cfg then return end
    if not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    if cfg.hide == true then
        -- Hide always wins; styling is irrelevant while hidden.
        -- The hide logic is handled by hideBlizzardPartyTitleText below.
        return
    end
    applyTextToFontString_PartyTitle(fs, titleButton, cfg)
end

-- Hide Blizzard's party title FontString and install alpha-enforcement hook
local function hideBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    local fsState = ensureState(fs)
    if fsState then fsState.hidden = true end
    if fs.SetAlpha then
        pcall(fs.SetAlpha, fs, 0)
    end
    if fs.Hide then
        pcall(fs.Hide, fs)
    end

    -- Install alpha-enforcement hook (only once)
    if fsState and not fsState.alphaHooked and _G.hooksecurefunc then
        fsState.alphaHooked = true
        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
            local st = getState(self)
            if alpha > 0 and st and st.hidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        local st2 = getState(self)
                        if self and st2 and st2.hidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end

    if fsState and not fsState.showHooked and _G.hooksecurefunc then
        fsState.showHooked = true
        _G.hooksecurefunc(fs, "Show", function(self)
            local st = getState(self)
            if not st or not st.hidden then return end
            -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    local st2 = getState(self)
                    if self and st2 and st2.hidden then
                        if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                        if self.Hide then pcall(self.Hide, self) end
                    end
                end)
            else
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                if self.Hide then pcall(self.Hide, self) end
            end
        end)
    end
end

-- Show Blizzard's party title FontString (for restore/cleanup)
local function showBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    local fsState = getState(fs)
    if fsState then fsState.hidden = nil end
    if fs.SetAlpha then
        pcall(fs.SetAlpha, fs, 1)
    end
    if fs.Show then
        pcall(fs.Show, fs)
    end
end

function addon.ApplyPartyFrameTitleStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPartyTitle") or nil
    if not cfg then
        return
    end

    -- If the user has asked to hide it, do that even if other style settings are default.
    if cfg.hide ~= true and not Utils.hasCustomTextSettings(cfg) then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queuePartyFrameReapply()
        return
    end

    local partyFrame = _G.CompactPartyFrame
    local titleButton = partyFrame and partyFrame.title or _G.CompactPartyFrameTitle
    if titleButton then
        if cfg.hide == true then
            hideBlizzardPartyTitleText(titleButton)
        else
            showBlizzardPartyTitleText(titleButton)
            applyPartyTitle(titleButton, cfg)
        end
    end
end

local function installPartyTitleHooks()
    if addon._PartyFrameTitleHooksInstalled then return end
    addon._PartyFrameTitleHooksInstalled = true

    local function tryApply(groupFrame)
        if not groupFrame or not Utils.isCompactPartyFrame(groupFrame) then
            return
        end
        local db = addon and addon.db and addon.db.profile
        local cfg = db and db.groupFrames and db.groupFrames.party and db.groupFrames.party.textPartyTitle or nil
        if not cfg then
            return
        end
        if cfg.hide ~= true and not Utils.hasCustomTextSettings(cfg) then
            return
        end

        local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
        if not titleButton then return end

        local titleRef = titleButton
        local cfgRef = cfg
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queuePartyFrameReapply()
                    return
                end
                if cfgRef.hide == true then
                    hideBlizzardPartyTitleText(titleRef)
                else
                    showBlizzardPartyTitleText(titleRef)
                    applyPartyTitle(titleRef, cfgRef)
                end
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queuePartyFrameReapply()
                return
            end
            if cfgRef.hide == true then
                hideBlizzardPartyTitleText(titleRef)
            else
                showBlizzardPartyTitleText(titleRef)
                applyPartyTitle(titleRef, cfgRef)
            end
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactRaidGroup_UpdateLayout then
            _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", tryApply)
        end
        if _G.CompactRaidGroup_UpdateUnits then
            _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", tryApply)
        end
        if _G.CompactRaidGroup_UpdateBorder then
            _G.hooksecurefunc("CompactRaidGroup_UpdateBorder", tryApply)
        end
    end
end

--------------------------------------------------------------------------------
-- Over Absorb Glow Visibility
--------------------------------------------------------------------------------
-- Hides or shows the OverAbsorbGlow texture on party frames.
-- This glow appears when absorb shields exceed the health bar width.
-- Frame: CompactPartyFrameMember[1-5].overAbsorbGlow (direct child of frame, not healthBar)
--
-- Uses alpha hiding with persistent hooks (same pattern as player frame OverAbsorbGlow).
--------------------------------------------------------------------------------

local function applyOverAbsorbGlowVisibility(frame, shouldHide)
    if not frame then return end
    -- overAbsorbGlow is a direct child of CompactUnitFrame, not healthBar
    -- Frame path: CompactPartyFrameMember[1-5].overAbsorbGlow
    local glow = frame.overAbsorbGlow
    if not glow then return end

    local state = ensureState(glow)
    if not state then return end

    if shouldHide then
        state.glowHidden = true
        if glow.SetAlpha then pcall(glow.SetAlpha, glow, 0) end

        -- Install persistence hooks (only once)
        if not state.glowHooked and _G.hooksecurefunc then
            state.glowHooked = true
            _G.hooksecurefunc(glow, "SetAlpha", function(self, alpha)
                local st = getState(self)
                if alpha and alpha > 0 and st and st.glowHidden then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            local st2 = getState(self)
                            if st2 and st2.glowHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
            _G.hooksecurefunc(glow, "Show", function(self)
                local st = getState(self)
                if st and st.glowHidden and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)
        end
    else
        state.glowHidden = false
        -- Restore visibility (let Blizzard control alpha)
        if glow.SetAlpha then pcall(glow.SetAlpha, glow, 1) end
    end
end

function PartyFrames.ApplyOverAbsorbGlowVisibility()
    local db = addon.db and addon.db.profile
    local partyCfg = db and db.groupFrames and db.groupFrames.party or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    -- Only process if user has explicitly set hideOverAbsorbGlow
    local shouldHide = partyCfg.hideOverAbsorbGlow or false
    if not shouldHide then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            applyOverAbsorbGlowVisibility(frame, shouldHide)
        end
    end
end

-- Export to addon namespace
addon.ApplyPartyOverAbsorbGlowVisibility = PartyFrames.ApplyOverAbsorbGlowVisibility

--------------------------------------------------------------------------------
-- Generic Texture Visibility Helper
--------------------------------------------------------------------------------
-- Parameterized version of the OverAbsorbGlow pattern.
-- Uses SetAlpha(0) with persistent hooks on SetAlpha/Show (deferred via C_Timer.After).
-- stateKey: unique string per texture type to avoid colliding with other state flags.
--------------------------------------------------------------------------------

local function applyTextureVisibility(texture, shouldHide, stateKey)
    if not texture then return end

    local state = ensureState(texture)
    if not state then return end

    local hiddenKey = stateKey .. "Hidden"
    local hookedKey = stateKey .. "Hooked"

    if shouldHide then
        state[hiddenKey] = true
        if texture.SetAlpha then pcall(texture.SetAlpha, texture, 0) end

        -- Install persistence hooks (only once)
        if not state[hookedKey] and _G.hooksecurefunc then
            state[hookedKey] = true
            _G.hooksecurefunc(texture, "SetAlpha", function(self, alpha)
                local st = getState(self)
                if alpha and alpha > 0 and st and st[hiddenKey] then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            local st2 = getState(self)
                            if st2 and st2[hiddenKey] and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
            _G.hooksecurefunc(texture, "Show", function(self)
                local st = getState(self)
                if st and st[hiddenKey] and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)
        end
    else
        state[hiddenKey] = false
        -- Restore visibility (let Blizzard control alpha)
        if texture.SetAlpha then pcall(texture.SetAlpha, texture, 1) end
    end
end

--------------------------------------------------------------------------------
-- Heal Prediction Visibility
--------------------------------------------------------------------------------
-- Hides or shows myHealPrediction and otherHealPrediction textures on party frames.
-- Frame: CompactPartyFrameMember[1-5].myHealPrediction / .otherHealPrediction
--------------------------------------------------------------------------------

applyHealPredictionVisibility = function(frame, shouldHide)
    if not frame then return end
    applyTextureVisibility(frame.myHealPrediction, shouldHide, "healPred")
    applyTextureVisibility(frame.otherHealPrediction, shouldHide, "healPred")
end

function PartyFrames.ApplyHealPredictionVisibility()
    local db = addon.db and addon.db.profile
    local partyCfg = db and db.groupFrames and db.groupFrames.party or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    local shouldHide = partyCfg.hideHealPrediction or false
    if not shouldHide then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            applyHealPredictionVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyPartyHealPredictionVisibility = PartyFrames.ApplyHealPredictionVisibility

--------------------------------------------------------------------------------
-- Absorb Bars Visibility
--------------------------------------------------------------------------------
-- Hides or shows absorb-related textures on party frames.
-- Textures: totalAbsorb, totalAbsorbOverlay, myHealAbsorb,
--           myHealAbsorbLeftShadow, myHealAbsorbRightShadow, overHealAbsorbGlow
--------------------------------------------------------------------------------

applyAbsorbBarsVisibility = function(frame, shouldHide)
    if not frame then return end
    applyTextureVisibility(frame.totalAbsorb, shouldHide, "absorbBar")
    applyTextureVisibility(frame.totalAbsorbOverlay, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorb, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorbLeftShadow, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorbRightShadow, shouldHide, "absorbBar")
    applyTextureVisibility(frame.overHealAbsorbGlow, shouldHide, "absorbBar")
end

function PartyFrames.ApplyAbsorbBarsVisibility()
    local db = addon.db and addon.db.profile
    local partyCfg = db and db.groupFrames and db.groupFrames.party or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    local shouldHide = partyCfg.hideAbsorbBars or false
    if not shouldHide then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            applyAbsorbBarsVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyPartyAbsorbBarsVisibility = PartyFrames.ApplyAbsorbBarsVisibility

--------------------------------------------------------------------------------
-- Heal Prediction Clipping (MaskTexture)
--------------------------------------------------------------------------------
-- Clips all prediction/absorb textures to healthBar bounds using MaskTexture.
-- This prevents textures (especially otherHealPrediction) from extending past
-- the right edge of the health bar at 100% health.
--
-- Only activates when user has configured party frames (zero-touch compliant).
-- Mask is anchored to healthBar (stable frame) and persists across repositioning.
--------------------------------------------------------------------------------

local healPredictionTextureKeys = {
    "myHealPrediction",
    "otherHealPrediction",
    "totalAbsorb",
    "totalAbsorbOverlay",
    "myHealAbsorb",
    "myHealAbsorbLeftShadow",
    "myHealAbsorbRightShadow",
    "overHealAbsorbGlow",
}

ensureHealPredictionClipping = function(frame)
    if not frame then return end
    local healthBar = frame.healthBar
    if not healthBar then return end

    local state = ensureState(frame)
    if not state then return end

    -- Create mask once per frame, anchored to healthBar
    if not state.healPredClipMask then
        local ok, mask = pcall(healthBar.CreateMaskTexture, healthBar)
        if not ok or not mask then return end
        pcall(mask.SetTexture, mask, "Interface\\BUTTONS\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        pcall(mask.SetAllPoints, mask, healthBar)
        state.healPredClipMask = mask
    end

    local mask = state.healPredClipMask
    if not mask then return end

    -- Apply mask to each prediction/absorb texture
    for _, key in ipairs(healPredictionTextureKeys) do
        local tex = frame[key]
        if tex and tex.AddMaskTexture then
            pcall(tex.AddMaskTexture, tex, mask)
        end
    end
end

function PartyFrames.ApplyHealPredictionClipping()
    local db = addon.db and addon.db.profile
    local partyCfg = db and db.groupFrames and db.groupFrames.party or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            ensureHealPredictionClipping(frame)
        end
    end
end

addon.ApplyPartyHealPredictionClipping = PartyFrames.ApplyHealPredictionClipping

--------------------------------------------------------------------------------
-- Text Hook Installation
--------------------------------------------------------------------------------

function PartyFrames.installTextHooks()
    installPartyFrameTextHooks()
    installPartyNameOverlayHooks()
    installPartyTitleHooks()
end

-- Install text hooks on load
PartyFrames.installTextHooks()

return PartyFrames

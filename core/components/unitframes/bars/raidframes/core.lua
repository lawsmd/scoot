--------------------------------------------------------------------------------
-- bars/raidframes/core.lua
-- Raid frame health bar and text styling
--
-- Applies styling to CompactRaidGroup*Member* and CompactRaidFrame* frames.
-- Uses combat-safe overlay patterns for persistence during combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Create module namespace
addon.BarsRaidFrames = addon.BarsRaidFrames or {}
local RaidFrames = addon.BarsRaidFrames

--------------------------------------------------------------------------------
-- TAINT PREVENTION: Lookup table for raid frame state
--------------------------------------------------------------------------------
-- Writing properties directly to CompactRaidFrame/CompactRaidGroup
-- frames (or their children) can mark them as "addon-touched". This causes
-- Blizzard field reads (e.g., frame.unit/outOfRange) to return secret values.
-- Store all Scoot state in a separate lookup table keyed by frame.
--------------------------------------------------------------------------------
local RaidFrameState = setmetatable({}, { __mode = "k" }) -- Weak keys for GC

local function getState(frame)
    if not frame then return nil end
    return RaidFrameState[frame]
end

local function ensureState(frame)
    if not frame then return nil end
    if not RaidFrameState[frame] then
        RaidFrameState[frame] = {}
    end
    return RaidFrameState[frame]
end

-- Shared state (exported for text.lua and extras.lua)
addon.BarsRaidFrames._RaidFrameState = RaidFrameState
addon.BarsRaidFrames._getState = getState
addon.BarsRaidFrames._ensureState = ensureState

--------------------------------------------------------------------------------
-- Raid Frame Detection
--------------------------------------------------------------------------------

function RaidFrames.isRaidFrame(frame)
    return Utils.isRaidFrame(frame)
end

function RaidFrames.isRaidHealthBar(frame)
    if not frame or not frame.healthBar then return false end
    return Utils.isRaidFrame(frame)
end

--------------------------------------------------------------------------------
-- Health Bar Collection
--------------------------------------------------------------------------------

local raidHealthBars = {}

function RaidFrames.collectHealthBars()
    raidHealthBars = {}
    -- Pattern 1: Group-based naming (CompactRaidGroup1Member1HealthBar, etc.)
    for group = 1, 8 do
        for member = 1, 5 do
            local frameName = "CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"
            local bar = _G[frameName]
            if bar then
                table.insert(raidHealthBars, bar)
            end
        end
    end
    -- Pattern 2: Combined naming (CompactRaidFrame1HealthBar, etc.)
    for i = 1, 40 do
        local frameName = "CompactRaidFrame" .. i .. "HealthBar"
        local bar = _G[frameName]
        if bar then
            local state = ensureState(bar)
            if state and not state.raidBarCounted then
                state.raidBarCounted = true
                table.insert(raidHealthBars, bar)
            end
        end
    end
    return raidHealthBars
end

--------------------------------------------------------------------------------
-- Health Bar Styling
--------------------------------------------------------------------------------

function RaidFrames.applyToHealthBar(bar, cfg)
    if not bar then return end

    local texKey = cfg.healthBarTexture or "default"
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint
    local bgTexKey = cfg.healthBarBackgroundTexture or "default"
    local bgColorMode = cfg.healthBarBackgroundColorMode or "default"
    local bgTint = cfg.healthBarBackgroundTint
    local bgOpacity = cfg.healthBarBackgroundOpacity or 50

    -- Apply foreground texture and color
    if addon._ApplyToStatusBar then
        addon._ApplyToStatusBar(bar, texKey, colorMode, tint, nil, "health", nil)
    end

    -- Apply background texture and color
    if addon._ApplyBackgroundToStatusBar then
        addon._ApplyBackgroundToStatusBar(bar, bgTexKey, bgColorMode, bgTint, bgOpacity, "Raid", "health")
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
        local useDark = (colorMode == "valueDark")
        local unit
        local parentFrame = bar.GetParent and bar:GetParent()
        if parentFrame then
            local okU, u = pcall(function() return parentFrame.displayedUnit or parentFrame.unit end)
            if okU and u then unit = u end
        end
        if unit and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
            addon.BarsTextures.applyValueBasedColor(bar, unit, overlay, useDark)
            return -- Color applied by applyValueBasedColor, skip SetVertexColor below
        end
        -- Fallback: if unit not available yet, use appropriate color (will update on first health change)
        if useDark then
            r, g, b, a = 0.23, 0.23, 0.23, 1  -- Dark gray
        else
            r, g, b, a = 0, 1, 0, 1  -- Green
        end
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

    local fillState = ensureState(blizzFill)
    if fillState then fillState.hidden = true end
    blizzFill:SetAlpha(0)

    if _G.hooksecurefunc and fillState and not fillState.alphaHooked then
        fillState.alphaHooked = true
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
        local fillState = getState(blizzFill)
        if fillState then fillState.hidden = nil end
        blizzFill:SetAlpha(1)
    end
end

-- Create or update the health overlay
function RaidFrames.ensureHealthOverlay(bar, cfg)
    if not bar then return end

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    local state = ensureState(bar)
    if state then state.overlayActive = hasCustom end

    if not hasCustom then
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

        if _G.hooksecurefunc and state and not state.overlayHooksInstalled then
            state.overlayHooksInstalled = true
            _G.hooksecurefunc(bar, "SetValue", function(self)
                updateHealthOverlay(self)
                -- Also update color for "value"/"valueDark" mode to eliminate flicker.
                -- By updating color in the same hook as width, both changes happen
                -- atomically in the same frame (no timing gap = no flicker).
                local st = getState(self)
                if not st or not st.overlayActive then return end
                local db = addon and addon.db and addon.db.profile
                local groupFrames = db and rawget(db, "groupFrames") or nil
                local cfg = groupFrames and rawget(groupFrames, "raid") or nil
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
                local cfg = groupFrames and rawget(groupFrames, "raid") or nil
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

    if state and not state.textureSwapHooked and _G.hooksecurefunc then
        state.textureSwapHooked = true
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

    -- Raise DispelOverlay above Scoot's overlay so dispel indicators remain visible.
    -- DispelOverlay uses useParentLevel="true", which means the parent's own regions
    -- (including our BORDER sublevel 7 overlay) render on top of it. SetFrameLevel
    -- is a C-side widget operation (taint-safe per Rule 4).
    -- Uses parentLevel + 11 to also clear the raid border frame (at barLevel + 10).
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

        -- Elevate roleIcon above Scoot overlay layers (OVERLAY 6, below name text at OVERLAY 7)
        local okR, roleIcon = pcall(function() return unitFrame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end
    end

    -- Build a config fingerprint to detect if settings have actually changed.
    -- This prevents expensive re-styling when ApplyStyles() is called but raid
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

    -- If config hasn't changed and overlay is already visible, skip re-styling.
    -- Note: Don't check GetWidth() as it can return secret values.
    -- With anchor-based sizing, if the overlay is shown, it's sized correctly.
    if state.lastAppliedFingerprint == fingerprint then
        local overlay = state.healthOverlay
        if overlay and overlay:IsShown() then
            return -- Already styled with same config, skip
        end
    end

    -- Store fingerprint for next comparison
    state.lastAppliedFingerprint = fingerprint

    styleHealthOverlay(bar, cfg)
    hideBlizzardFill(bar)
    updateHealthOverlay(bar)

    -- Queue a single deferred update to handle cases where the fill texture
    -- isn't ready immediately (e.g., on UI reload). With anchor-based sizing,
    -- a retry loop is unnecessary - the overlay will automatically match the
    -- fill texture dimensions once anchored.
    if _G.C_Timer and _G.C_Timer.After then
        C_Timer.After(0.1, function()
            updateHealthOverlay(bar)
        end)
    end
end

function RaidFrames.disableHealthOverlay(bar)
    if not bar then return end
    local state = getState(bar)
    if state then state.overlayActive = false end
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
-- Applies Scoot bar borders to raid frame health bars.
-- Uses addon-owned anchor frames to avoid taint.
--------------------------------------------------------------------------------

-- Clear health bar border for a single bar
local function clearHealthBarBorder(bar)
    if not bar then return end
    local state = getState(bar)
    if state and state.borderAnchor then
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(state.borderAnchor)
        end
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

    local state = ensureState(bar)

    -- Create addon-owned anchor frame (avoid taint by not writing to Blizzard's bar)
    if not state.borderAnchor then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        -- Parent to bar's parent (the CompactUnitFrame) to avoid strata issues
        local unitFrame = (bar.GetParent and bar:GetParent()) or nil
        local anchorParent = unitFrame or bar:GetParent() or bar
        local anchor = CreateFrame("Frame", nil, anchorParent, template)
        state.borderAnchor = anchor

        -- Override BackdropTemplate's OnSizeChanged to guard against anchor secrecy.
        -- When bar is tainted, GetWidth() returns secrets -> arithmetic fails in
        -- SetupTextureCoordinates. Skip the update; border retains last valid coords.
        anchor:SetScript("OnSizeChanged", function(self, w, h)
            if self.backdropInfo and self.SetupTextureCoordinates then
                if type(w) == "number" and type(h) == "number"
                   and not issecretvalue(w) and not issecretvalue(h) then
                    self:SetupTextureCoordinates()
                end
            end
        end)
    end

    local anchor = state.borderAnchor

    -- ANCHOR SECRECY FIX: Get bar dimensions safely
    -- Health bars can be "anchoring secret" after SetValue(secretHealth), causing
    -- GetWidth/GetHeight to return secrets. Try pcall, fallback to defaults.
    local barWidth, barHeight = 100, 20  -- Default compact unit frame health bar size
    local okSize, w, h = pcall(function() return bar:GetWidth(), bar:GetHeight() end)
    if okSize and type(w) == "number" and type(h) == "number" and not issecretvalue(w) and not issecretvalue(h) and w > 0 and h > 0 then
        barWidth, barHeight = w, h
    end

    -- Set frame level above the health bar but below overlay elements
    local barLevel = 0
    local okL, lvl = pcall(bar.GetFrameLevel, bar)
    if okL and type(lvl) == "number" then
        barLevel = lvl
    end
    anchor:SetFrameLevel(barLevel + 10)
    anchor:Show()

    -- Apply border via BarBorders
    local tintEnabled = cfg.healthBarBorderTintEnable
    local tintColor = cfg.healthBarBorderTintColor or {1, 1, 1, 1}
    local thickness = tonumber(cfg.healthBarBorderThickness) or 1
    local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
    local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

    if addon.BarBorders then
        anchor:ClearAllPoints()

        -- Get the style definition
        local style = addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
        if style and style.texture and anchor.SetBackdrop then
            local edgeSize = math.max(1, math.floor(thickness * 1.35 * (style.thicknessScale or 1) + 0.5))
            local paddingMult = style.paddingMultiplier or 0.5
            local pad = math.floor(edgeSize * paddingMult + 0.5)
            local padAdjH = pad - insetH
            local padAdjV = pad - insetV
            if padAdjH < 0 then padAdjH = 0 end
            if padAdjV < 0 then padAdjV = 0 end

            anchor:ClearAllPoints()
            -- Set explicit size BEFORE SetBackdrop, anchor AFTER -- prevents anchor secrecy
            -- during GetWidth() inside Backdrop.lua's SetupTextureCoordinates
            anchor:SetSize(barWidth + padAdjH * 2, barHeight + padAdjV * 2)

            local insetMult = style.insetMultiplier or 0.65
            local backdropInset = math.floor(edgeSize * insetMult + 0.5)
            if backdropInset < 0 then backdropInset = 0 end

            local ok = pcall(anchor.SetBackdrop, anchor, {
                bgFile = nil,
                edgeFile = style.texture,
                tile = false,
                edgeSize = edgeSize,
                insets = { left = backdropInset, right = backdropInset, top = backdropInset, bottom = backdropInset },
            })

            -- Anchor AFTER SetBackdrop so GetWidth() inside ApplyBackdrop uses explicit size
            anchor:SetPoint("TOPLEFT", bar, "TOPLEFT", -padAdjH, padAdjV)
            anchor:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", padAdjH, -padAdjV)

            if ok then
                if anchor.SetBackdropBorderColor then
                    if tintEnabled then
                        anchor:SetBackdropBorderColor(tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] or 1)
                    else
                        anchor:SetBackdropBorderColor(1, 1, 1, 1)
                    end
                end
                if anchor.SetBackdropColor then
                    anchor:SetBackdropColor(0, 0, 0, 0)
                end
            end
        elseif styleKey == "square" and anchor.SetBackdrop then
            -- Simple square border
            local edgeSize = math.max(1, math.floor(thickness + 0.5))
            anchor:ClearAllPoints()
            anchor:SetSize(barWidth + 2, barHeight + 2)

            pcall(anchor.SetBackdrop, anchor, {
                bgFile = nil,
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                tile = false,
                edgeSize = edgeSize,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })

            -- Anchor AFTER SetBackdrop
            anchor:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
            anchor:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)

            if anchor.SetBackdropBorderColor then
                if tintEnabled then
                    anchor:SetBackdropBorderColor(tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] or 1)
                else
                    anchor:SetBackdropBorderColor(0, 0, 0, 1)
                end
            end
            if anchor.SetBackdropColor then
                anchor:SetBackdropColor(0, 0, 0, 0)
            end
        else
            -- Unknown style, hide border
            clearHealthBarBorder(bar)
        end
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

-- Apply health bar borders to all raid frames
function addon.ApplyRaidFrameHealthBarBorders()
    if isEditModeActiveForBorders() then return end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queueRaidFrameReapply()
        return
    end

    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "raid") or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not cfg then return end

    -- If no border style set or set to "none", skip - let explicit restore handle cleanup
    local styleKey = cfg.healthBarBorderStyle
    if not styleKey or styleKey == "none" then return end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.healthBar then
            C_Timer.After(0, function()
                if frame and frame.healthBar then
                    applyHealthBarBorder(frame.healthBar, cfg)
                end
            end)
        end
    end

    -- Group layout: CompactRaidGroup1..8 Member1..5
    for g = 1, 8 do
        for m = 1, 5 do
            local frame = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if frame and frame.healthBar then
                C_Timer.After(0, function()
                    if frame and frame.healthBar then
                        applyHealthBarBorder(frame.healthBar, cfg)
                    end
                end)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text)
--------------------------------------------------------------------------------

-- Styling and visibility for raid name overlays
function RaidFrames.styleNameOverlay(nameOverlay, cfg)
    if not nameOverlay or not cfg then return end

    -- Get text settings
    local textCfg = cfg.nameText or cfg
    local fontFace = textCfg.fontFace or "FRIZQT__"
    local size = textCfg.size or 12
    local style = textCfg.style or "OUTLINE"
    local color = textCfg.color or {1, 1, 1, 1}
    local anchor = textCfg.anchor or "TOPLEFT"
    local offset = textCfg.offset or {x = 0, y = 0}

    -- Resolve font path
    local fontPath = addon.Media and addon.Media.ResolveFontPath and addon.Media.ResolveFontPath(fontFace)
    if fontPath and nameOverlay.SetFont then
        pcall(nameOverlay.SetFont, nameOverlay, fontPath, size, style)
    end

    if nameOverlay.SetTextColor then
        pcall(nameOverlay.SetTextColor, nameOverlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    if nameOverlay.SetJustifyH then
        pcall(nameOverlay.SetJustifyH, nameOverlay, Utils.getJustifyHFromAnchor(anchor))
    end
end

--------------------------------------------------------------------------------
-- Public API Functions
--------------------------------------------------------------------------------

-- Main entry point: Apply raid frame health bar styling from DB settings
function addon.ApplyRaidFrameHealthBarStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "raid") or nil
    if not cfg then return end

    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
    if not hasCustom then return end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queueRaidFrameReapply()
        return
    end

    RaidFrames.collectHealthBars()
    for _, bar in ipairs(raidHealthBars) do
        RaidFrames.applyToHealthBar(bar, cfg)
    end
    for _, bar in ipairs(raidHealthBars) do
        local state = getState(bar)
        if state then state.raidBarCounted = nil end
    end
end

-- Apply overlays to all raid health bars
function addon.ApplyRaidFrameHealthOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "raid") or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not cfg then return end

    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")

    -- If no custom settings, also skip - let RestoreRaidFrameHealthOverlays handle cleanup
    if not hasCustom then return end

    -- Combined layout
    for i = 1, 40 do
        local bar = _G["CompactRaidFrame" .. i .. "HealthBar"]
        if bar then
            if not (InCombatLockdown and InCombatLockdown()) then
                RaidFrames.ensureHealthOverlay(bar, cfg)
            else
                local state = getState(bar)
                if state and state.healthOverlay then
                    styleHealthOverlay(bar, cfg)
                    updateHealthOverlay(bar)
                end
            end
        end
    end

    -- Group layout
    for group = 1, 8 do
        for member = 1, 5 do
            local bar = _G["CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"]
            if bar then
                if not (InCombatLockdown and InCombatLockdown()) then
                    RaidFrames.ensureHealthOverlay(bar, cfg)
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
end

-- Restore all raid health bars to stock appearance
function addon.RestoreRaidFrameHealthOverlays()
    -- Combined layout
    for i = 1, 40 do
        local bar = _G["CompactRaidFrame" .. i .. "HealthBar"]
        if bar then
            RaidFrames.disableHealthOverlay(bar)
        end
    end
    -- Group layout
    for group = 1, 8 do
        for member = 1, 5 do
            local bar = _G["CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"]
            if bar then
                RaidFrames.disableHealthOverlay(bar)
            end
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

addon.BarsRaidFrames._isEditModeActive = isEditModeActive

function RaidFrames.installHooks()
    if addon._RaidFrameHooksInstalled then return end
    addon._RaidFrameHooksInstalled = true

    -- Hook CompactUnitFrame_UpdateAll
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if frame and frame.healthBar and Utils.isRaidFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                if db and db.groupFrames and db.groupFrames.raid then
                    local cfg = db.groupFrames.raid
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
                                    Combat.queueRaidFrameReapply()
                                    return
                                end
                                RaidFrames.applyToHealthBar(bar, cfgRef)
                                -- Also ensure overlay exists (handles raid formed mid-session)
                                RaidFrames.ensureHealthOverlay(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queueRaidFrameReapply()
                                return
                            end
                            RaidFrames.applyToHealthBar(bar, cfgRef)
                            RaidFrames.ensureHealthOverlay(bar, cfgRef)
                        end
                    end

                    -- Apply borders if configured (independent of hasCustom texture/color check)
                    local borderStyle = cfg.healthBarBorderStyle
                    if borderStyle and borderStyle ~= "none" then
                        local barRef = frame.healthBar
                        local cfgRef2 = cfg
                        C_Timer.After(0, function()
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queueRaidFrameReapply()
                                return
                            end
                            if barRef then
                                applyHealthBarBorder(barRef, cfgRef2)
                            end
                        end)
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
            if frame and frame.healthBar and unit and Utils.isRaidFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                if db and db.groupFrames and db.groupFrames.raid then
                    local cfg = db.groupFrames.raid
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
                                    Combat.queueRaidFrameReapply()
                                    return
                                end
                                RaidFrames.applyToHealthBar(bar, cfgRef)
                                -- Also ensure overlay exists (handles raid formed mid-session)
                                RaidFrames.ensureHealthOverlay(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queueRaidFrameReapply()
                                return
                            end
                            RaidFrames.applyToHealthBar(bar, cfgRef)
                            RaidFrames.ensureHealthOverlay(bar, cfgRef)
                        end
                    end

                    -- Apply borders if configured (independent of hasCustom texture/color check)
                    local borderStyle = cfg.healthBarBorderStyle
                    if borderStyle and borderStyle ~= "none" then
                        local barRef = frame.healthBar
                        local cfgRef2 = cfg
                        C_Timer.After(0, function()
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queueRaidFrameReapply()
                                return
                            end
                            if barRef then
                                applyHealthBarBorder(barRef, cfgRef2)
                            end
                        end)
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

            -- Only process raid frames (not party frames or nameplates)
            if not Utils.isRaidFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local cfg = db and db.groupFrames and db.groupFrames.raid or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return end

            local useDark = (colorMode == "valueDark")

            -- Get unit token from the frame
            local unit
            local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
            if okU and u then unit = u end
            if not unit then return end

            -- FIX: Conditional deferral to prevent blinking during health regen.
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
            if not frame or not Utils.isRaidFrame(frame) then return end

            local db = addon.db and addon.db.profile
            local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil
            if not raidCfg then return end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    -- Reapply clipping masks (defined in extras.lua, loaded after core.lua)
                    if RaidFrames.ensureHealPredictionClipping then
                        RaidFrames.ensureHealPredictionClipping(frame)
                    end
                    -- Reapply visibility if toggled
                    if raidCfg.hideHealPrediction and RaidFrames.applyHealPredictionVisibility then
                        RaidFrames.applyHealPredictionVisibility(frame, true)
                    end
                    if raidCfg.hideAbsorbBars and RaidFrames.applyAbsorbBarsVisibility then
                        RaidFrames.applyAbsorbBarsVisibility(frame, true)
                    end
                end)
            end
        end)
    end
end

-- Install hooks on load
RaidFrames.installHooks()

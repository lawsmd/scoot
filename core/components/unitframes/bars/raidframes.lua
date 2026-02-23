--------------------------------------------------------------------------------
-- bars/raidframes.lua
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
-- Store all ScooterMod state in a separate lookup table keyed by frame.
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

    -- Raise DispelOverlay above ScooterMod's overlay so dispel indicators remain visible.
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

        -- Elevate roleIcon above ScooterMod overlay layers (OVERLAY 6, below name text at OVERLAY 7)
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
-- Applies ScooterMod bar borders to raid frame health bars.
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
        -- When bar is tainted, GetWidth() returns secrets → arithmetic fails in
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
            -- Set explicit size BEFORE SetBackdrop, anchor AFTER — prevents anchor secrecy
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
                    -- Reapply clipping masks
                    ensureHealPredictionClipping(frame)
                    -- Reapply visibility if toggled
                    if raidCfg.hideHealPrediction then
                        applyHealPredictionVisibility(frame, true)
                    end
                    if raidCfg.hideAbsorbBars then
                        applyAbsorbBarsVisibility(frame, true)
                    end
                end)
            end
        end)
    end
end

-- Install hooks on load
RaidFrames.installHooks()

--------------------------------------------------------------------------------
-- Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings to raid frame name text elements.
-- Target: CompactRaidGroup*Member*Name (the name FontString on each raid unit frame)
--------------------------------------------------------------------------------

-- Apply text settings to a raid frame's name FontString
local function applyTextToRaidFrame(frame, cfg)
    if not frame or not cfg then return end

    -- Get the name FontString (frame.name is the standard CompactUnitFrame name element)
    local nameFS = frame.name
    if not nameFS then return end

    -- Resolve font face
    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        -- Fallback to GameFontNormal's font
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    -- Get settings with defaults
    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    -- Apply font (SetFont must be called before SetText)
    local success = pcall(nameFS.SetFont, nameFS, resolvedFace, fontSize, fontStyle)
    if not success then
        -- Fallback to default font on failure
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(nameFS.SetFont, nameFS, fallback, fontSize, fontStyle)
        end
    end

    -- Apply color
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
end

-- Collect all raid frame name FontStrings
local raidNameTexts = {}

local function collectRaidNameTexts()
    if wipe then
        wipe(raidNameTexts)
    else
        raidNameTexts = {}
    end

    -- Scan CompactRaidFrame1 through CompactRaidFrame40 (combined layout)
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.name then
            local nameState = ensureState(frame.name)
            if nameState and not nameState.raidTextCounted then
                nameState.raidTextCounted = true
                table.insert(raidNameTexts, frame)
            end
        end
    end

    -- Scan CompactRaidGroup1Member1 through CompactRaidGroup8Member5 (group layout)
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.name then
                local nameState = ensureState(frame.name)
                if nameState and not nameState.raidTextCounted then
                    nameState.raidTextCounted = true
                    table.insert(raidNameTexts, frame)
                end
            end
        end
    end
end

-- Main entry point: Apply raid frame text styling from DB settings
function addon.ApplyRaidFrameTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid text styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textPlayerName") or nil
    if not cfg then
        return
    end

    -- Zero-Touch: if user hasn't actually changed anything from the defaults, do nothing.
    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Deprecated: Raid Player Name styling is now driven by overlay FontStrings
    -- (see ApplyRaidFrameNameOverlays). Moving Blizzard's `frame.name` must be avoided
    -- because the overlay clipping container copies its anchor geometry to preserve
    -- truncation. Touching `frame.name` here reintroduces leaking/incorrect clipping.
    if addon.ApplyRaidFrameNameOverlays then
        addon.ApplyRaidFrameNameOverlays()
    end
end

-- Install hooks to reapply text styling when raid frames update
local function installRaidFrameTextHooks()
    if addon._RaidFrameTextHooksInstalled then return end
    addon._RaidFrameTextHooksInstalled = true

    -- Deprecated: name styling hooks must not touch Blizzard's `frame.name`.
    -- Overlay system installs its own hooks (installRaidNameOverlayHooks()).
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on raid frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because only
-- addon-owned FontStrings are manipulated.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

-- Shared helper: create/return the clipping container that spans the full unit frame.
-- Used by both name and status text overlays for 9-way alignment.
local function ensureOverlayContainer(frame)
    if not frame then return nil end
    local frameState = ensureState(frame)
    if not frameState then return nil end

    if not frameState.nameOverlayContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetClipsChildren(true)

        -- Span the entire unit frame with small padding for visual breathing room.
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

        -- Elevate roleIcon when creating overlay container
        local okR, roleIcon = pcall(function() return frame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end

        frameState.nameOverlayContainer = container
    end

    return frameState.nameOverlayContainer
end

local function styleRaidNameOverlay(frame, cfg)
    if not frame or not cfg then return end
    local state = getState(frame)
    if not state or not state.nameOverlayText then return end

    local overlay = state.nameOverlayText
    local container = state.nameOverlayContainer or frame

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
        -- Use the raid member's class color
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
    if state then
        state.nameAnchor = anchor
        state.nameOffsetX = offsetX
        state.nameOffsetY = offsetY
    end
end

local function hideBlizzardRaidNameText(frame)
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

    if _G.hooksecurefunc and nameState and not nameState.alphaHooked then
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

    if _G.hooksecurefunc and nameState and not nameState.showHooked then
        nameState.showHooked = true
        _G.hooksecurefunc(blizzName, "Show", function(self)
            local st = getState(self)
            if not (st and st.hidden) then return end
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

local function showBlizzardRaidNameText(frame)
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

local function ensureRaidNameOverlay(frame, cfg)
    if not frame then return end

    local hasCustom = Utils.hasCustomTextSettings(cfg)
    local frameState = ensureState(frame)
    if frameState then
        frameState.nameOverlayActive = hasCustom
        frameState.hideRealmEnabled = cfg and cfg.hideRealm and true or false
    end

    if not hasCustom then
        if frameState and frameState.nameOverlayText then
            frameState.nameOverlayText:Hide()
        end
        showBlizzardRaidNameText(frame)
        return
    end

    -- Ensure an addon-owned clipping container that spans the FULL unit frame.
    -- This allows 9-way alignment to position text anywhere within the frame.
    ensureOverlayContainer(frame)

    -- Create overlay FontString if it doesn't exist (as a child of the clipping container)
    if frameState and not frameState.nameOverlayText then
        local parentForText = frameState.nameOverlayContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 7)
        frameState.nameOverlayText = overlay

        local nameState = frame.name and ensureState(frame.name) or nil
        if frame.name and _G.hooksecurefunc and nameState and not nameState.textMirrorHooked then
            nameState.textMirrorHooked = true
            local ownerState = frameState
            _G.hooksecurefunc(frame.name, "SetText", function(_, text)
                if ownerState and ownerState.nameOverlayText and ownerState.nameOverlayActive then
                    -- text may be a secret value in 12.0; branch on type
                    if type(text) == "string" then
                        local displayText = text
                        -- Strip realm suffix: "Name-Realm" → "Name"
                        -- WoW names cannot contain hyphens; hyphen always delimits realm.
                        if ownerState.hideRealmEnabled and displayText ~= "" then
                            displayText = displayText:match("^([^%-]+)") or displayText
                        end
                        ownerState.nameOverlayText:SetText(displayText)
                    else
                        -- Secret or other type — SetText handles secrets natively
                        pcall(ownerState.nameOverlayText.SetText, ownerState.nameOverlayText, text)
                    end
                    -- Reposition after text change so CENTER/RIGHT alignment adapts to new text width
                    if ownerState.nameAnchor then
                        Utils.repositionNameOverlay(ownerState.nameOverlayText,
                            ownerState.nameOverlayContainer or frame,
                            ownerState.nameAnchor, ownerState.nameOffsetX or 0, ownerState.nameOffsetY or 0)
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
    if frameState.lastNameFingerprint == fingerprint and frameState.nameOverlayText and frameState.nameOverlayText:IsShown() then
        return
    end
    frameState.lastNameFingerprint = fingerprint

    styleRaidNameOverlay(frame, cfg)
    hideBlizzardRaidNameText(frame)

    local textCopied = false
    if frameState and frameState.nameOverlayText and frame.name and frame.name.GetText then
        local ok, currentText = pcall(frame.name.GetText, frame.name)
        if ok and type(currentText) == "string" and currentText ~= "" then
            local displayText = currentText
            -- Strip realm suffix: "Name-Realm" → "Name"
            if cfg and cfg.hideRealm and displayText ~= "" then
                displayText = displayText:match("^([^%-]+)") or displayText
            end
            frameState.nameOverlayText:SetText(displayText)
            textCopied = true
        end
    end

    -- Fallback: if GetText failed (secret/nil), try GetUnitName
    if not textCopied and frameState and frameState.nameOverlayText and frame.unit then
        local unitOk, unitName = pcall(GetUnitName, frame.unit, true)
        if unitOk and type(unitName) == "string" and unitName ~= "" then
            local displayText = unitName
            -- Strip realm suffix: "Name-Realm" → "Name"
            if cfg and cfg.hideRealm and displayText ~= "" then
                displayText = displayText:match("^([^%-]+)") or displayText
            end
            frameState.nameOverlayText:SetText(displayText)
            textCopied = true
        end
    end

    -- Last resort: if both returned secrets, pass through directly
    if not textCopied and frameState and frameState.nameOverlayText and frame.name and frame.name.GetText then
        local ok, rawText = pcall(frame.name.GetText, frame.name)
        if ok then
            pcall(frameState.nameOverlayText.SetText, frameState.nameOverlayText, rawText)
        end
    end

    -- Reposition after initial text copy so CENTER/RIGHT alignment uses actual text width
    if frameState and frameState.nameAnchor and frameState.nameOverlayText then
        Utils.repositionNameOverlay(frameState.nameOverlayText,
            frameState.nameOverlayContainer or frame,
            frameState.nameAnchor, frameState.nameOffsetX or 0, frameState.nameOffsetY or 0)
    end

    if frameState and frameState.nameOverlayText then
        frameState.nameOverlayText:Show()
    end
end

local function disableRaidNameOverlay(frame)
    if not frame then return end
    local frameState = getState(frame)
    if frameState then
        frameState.nameOverlayActive = false
        if frameState.nameOverlayText then
            frameState.nameOverlayText:Hide()
        end
    end
    showBlizzardRaidNameText(frame)

    -- Restore roleIcon to stock draw layer
    local okR, roleIcon = pcall(function() return frame.roleIcon end)
    if okR and roleIcon and roleIcon.SetDrawLayer then
        pcall(roleIcon.SetDrawLayer, roleIcon, "ARTWORK", 0)
    end
end

function addon.ApplyRaidFrameNameOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local cfg = rawget(raidCfg, "textPlayerName") or nil
    local hasCustom = Utils.hasCustomTextSettings(cfg)

    -- If no custom settings, skip - let RestoreRaidFrameNameOverlays handle cleanup
    if not hasCustom then return end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.name then
            if not (InCombatLockdown and InCombatLockdown()) then
                ensureRaidNameOverlay(frame, cfg)
            else
                local state = getState(frame)
                if state and state.nameOverlayText then
                    styleRaidNameOverlay(frame, cfg)
                end
            end
        end
    end

    -- Group layout: CompactRaidGroup1Member1..CompactRaidGroup8Member5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.name then
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensureRaidNameOverlay(frame, cfg)
                else
                    local state = getState(frame)
                    if state and state.nameOverlayText then
                        styleRaidNameOverlay(frame, cfg)
                    end
                end
            end
        end
    end
end

function addon.RestoreRaidFrameNameOverlays()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            disableRaidNameOverlay(frame)
        end
    end
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                disableRaidNameOverlay(frame)
            end
        end
    end
end

local function installRaidNameOverlayHooks()
    if addon._RaidNameOverlayHooksInstalled then return end
    addon._RaidNameOverlayHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local raidCfg = gf and rawget(gf, "raid") or nil
        return raidCfg and rawget(raidCfg, "textPlayerName") or nil
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not unit then return end
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
        _G.hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end

    -- Event-driven re-application for raid composition changes.
    if not addon._RaidNameRosterEventInstalled then
        addon._RaidNameRosterEventInstalled = true
        local rosterFrame = CreateFrame("Frame")
        rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        rosterFrame:SetScript("OnEvent", function()
            if isEditModeActive() then return end

            local cfg = getCfg()
            if not cfg or (cfg.colorMode or "default") ~= "class" then return end
            if not Utils.hasCustomTextSettings(cfg) then return end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0.5, function()
                    if isEditModeActive() then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    if addon.ApplyRaidFrameNameOverlays then
                        addon.ApplyRaidFrameNameOverlays()
                    end
                end)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Overlay (Status Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on raid frames that visually replace
-- Blizzard's statusText. These overlays persist during combat because only
-- addon-owned FontStrings are manipulated. Blizzard can reset its own
-- statusText all it wants — our overlay stays styled.
--
-- Pattern: Mirror text via SetText/SetFormattedText hooks, style on setup,
-- hide Blizzard's element via SetAlpha(0).
--------------------------------------------------------------------------------

local function styleRaidStatusTextOverlay(frame, cfg)
    if not frame or not cfg then return end
    local state = getState(frame)
    if not state or not state.statusTextOverlay then return end

    local overlay = state.statusTextOverlay
    local container = state.nameOverlayContainer or frame

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

    local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
        end
    end

    -- Apply color
    local color = cfg.color or { 1, 1, 1, 1 }
    pcall(overlay.SetTextColor, overlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

    -- Justify based on anchor
    pcall(overlay.SetJustifyH, overlay, Utils.getJustifyHFromAnchor(anchor))
    if overlay.SetJustifyV then
        -- Derive vertical justify from anchor
        local justV = "MIDDLE"
        if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
            justV = "TOP"
        elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
            justV = "BOTTOM"
        end
        pcall(overlay.SetJustifyV, overlay, justV)
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

    -- Position within the clipping container
    overlay:ClearAllPoints()
    overlay:SetPoint(anchor, container, anchor, offsetX, offsetY)

    -- Store alignment params for fingerprint checks
    if state then
        state.statusTextAnchor = anchor
        state.statusTextOffsetX = offsetX
        state.statusTextOffsetY = offsetY
    end
end

local function hideBlizzardRaidStatusText(frame)
    if not frame or not frame.statusText then return end
    local blizzST = frame.statusText

    local stState = ensureState(blizzST)
    if stState then stState.hidden = true end
    if blizzST.SetAlpha then
        pcall(blizzST.SetAlpha, blizzST, 0)
    end

    if _G.hooksecurefunc and stState and not stState.alphaHooked then
        stState.alphaHooked = true
        _G.hooksecurefunc(blizzST, "SetAlpha", function(self, alpha)
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

    if _G.hooksecurefunc and stState and not stState.showHooked then
        stState.showHooked = true
        _G.hooksecurefunc(blizzST, "Show", function(self)
            local st = getState(self)
            if not (st and st.hidden) then return end
            -- Kill visibility immediately (avoid flicker), then defer Hide.
            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    local st2 = getState(self)
                    if self and st2 and st2.hidden then
                        if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                    end
                end)
            else
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            end
        end)
    end
end

local function showBlizzardRaidStatusText(frame)
    if not frame or not frame.statusText then return end
    local stState = getState(frame.statusText)
    if stState then stState.hidden = nil end
    if frame.statusText.SetAlpha then
        pcall(frame.statusText.SetAlpha, frame.statusText, 1)
    end
end

local function ensureRaidStatusTextOverlay(frame, cfg)
    if not frame then return end

    local hasCustom = Utils.hasCustomTextSettings(cfg)
    local frameState = ensureState(frame)
    if frameState then
        frameState.statusTextOverlayActive = hasCustom
    end

    if not hasCustom then
        if frameState and frameState.statusTextOverlay then
            frameState.statusTextOverlay:Hide()
        end
        showBlizzardRaidStatusText(frame)
        return
    end

    -- Ensure shared clipping container
    ensureOverlayContainer(frame)

    -- Create overlay FontString if it doesn't exist
    if frameState and not frameState.statusTextOverlay then
        local parentForText = frameState.nameOverlayContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 5)  -- Below name text (7) and role icon (6)
        frameState.statusTextOverlay = overlay

        -- Install mirroring hooks on Blizzard's statusText
        local stState = frame.statusText and ensureState(frame.statusText) or nil
        if frame.statusText and _G.hooksecurefunc and stState and not stState.textMirrorHooked then
            stState.textMirrorHooked = true
            local ownerState = frameState

            _G.hooksecurefunc(frame.statusText, "SetText", function(_, text)
                if not (ownerState and ownerState.statusTextOverlay and ownerState.statusTextOverlayActive) then return end
                -- text may be a secret value in 12.0; pcall for safety
                if type(text) == "string" then
                    ownerState.statusTextOverlay:SetText(text)
                else
                    pcall(ownerState.statusTextOverlay.SetText, ownerState.statusTextOverlay, text)
                end
                -- Mirror visibility: if Blizzard is showing status text, show our overlay
                if ownerState.statusTextOverlay.Show then
                    ownerState.statusTextOverlay:Show()
                end
            end)

            _G.hooksecurefunc(frame.statusText, "SetFormattedText", function(self, fmt, ...)
                if not (ownerState and ownerState.statusTextOverlay and ownerState.statusTextOverlayActive) then return end
                -- Forward formatted text via pcall (args may contain secrets)
                local ok, result = pcall(string.format, fmt, ...)
                if ok and type(result) == "string" then
                    ownerState.statusTextOverlay:SetText(result)
                else
                    -- Fallback: try GetText after the format has been applied
                    local okGet, currentText = pcall(self.GetText, self)
                    if okGet then
                        pcall(ownerState.statusTextOverlay.SetText, ownerState.statusTextOverlay, currentText)
                    end
                end
                if ownerState.statusTextOverlay.Show then
                    ownerState.statusTextOverlay:Show()
                end
            end)

            _G.hooksecurefunc(frame.statusText, "Show", function()
                if ownerState and ownerState.statusTextOverlay and ownerState.statusTextOverlayActive then
                    ownerState.statusTextOverlay:Show()
                end
            end)

            _G.hooksecurefunc(frame.statusText, "Hide", function()
                if ownerState and ownerState.statusTextOverlay then
                    ownerState.statusTextOverlay:Hide()
                end
            end)
        end
    end

    -- Build fingerprint to detect config changes
    local fingerprint = string.format("%s|%s|%s|%s|%s|%s",
        tostring(cfg.fontFace or ""),
        tostring(cfg.size or ""),
        tostring(cfg.style or ""),
        tostring(cfg.anchor or ""),
        cfg.color and string.format("%.2f,%.2f,%.2f,%.2f",
            cfg.color[1] or 1, cfg.color[2] or 1, cfg.color[3] or 1, cfg.color[4] or 1) or "",
        cfg.offset and string.format("%.1f,%.1f", cfg.offset.x or 0, cfg.offset.y or 0) or ""
    )

    -- Skip re-styling if config hasn't changed and overlay is visible
    if frameState.lastStatusTextFingerprint == fingerprint and frameState.statusTextOverlay and frameState.statusTextOverlay:IsShown() then
        return
    end
    frameState.lastStatusTextFingerprint = fingerprint

    styleRaidStatusTextOverlay(frame, cfg)
    hideBlizzardRaidStatusText(frame)

    -- Copy current text from Blizzard's statusText to the overlay
    if frameState and frameState.statusTextOverlay and frame.statusText then
        local blizzST = frame.statusText
        -- Check if Blizzard's statusText is currently shown
        local isVisible = false
        if blizzST.IsShown then
            local okV, vis = pcall(blizzST.IsShown, blizzST)
            -- If hidden flag is set, Blizzard might still think it's shown
            local stState = getState(blizzST)
            isVisible = okV and (vis or (stState and stState.hidden))
        end

        if blizzST.GetText then
            local ok, currentText = pcall(blizzST.GetText, blizzST)
            if ok and type(currentText) == "string" and currentText ~= "" then
                frameState.statusTextOverlay:SetText(currentText)
            elseif ok then
                -- Secret or non-string — forward directly
                pcall(frameState.statusTextOverlay.SetText, frameState.statusTextOverlay, currentText)
            end
        end

        -- Match Blizzard's visibility state
        if isVisible then
            frameState.statusTextOverlay:Show()
        else
            frameState.statusTextOverlay:Hide()
        end
    end
end

local function disableRaidStatusTextOverlay(frame)
    if not frame then return end
    local frameState = getState(frame)
    if frameState then
        frameState.statusTextOverlayActive = false
        if frameState.statusTextOverlay then
            frameState.statusTextOverlay:Hide()
        end
    end
    showBlizzardRaidStatusText(frame)
end

function addon.ApplyRaidFrameStatusTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid status text styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textStatusText") or nil
    if not cfg then
        return
    end

    -- Zero-Touch: if user hasn't actually changed anything from the defaults, do nothing.
    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.statusText then
            if not (InCombatLockdown and InCombatLockdown()) then
                ensureRaidStatusTextOverlay(frame, cfg)
            else
                -- During combat: only re-style existing overlays (no frame creation)
                local state = getState(frame)
                if state and state.statusTextOverlay then
                    styleRaidStatusTextOverlay(frame, cfg)
                end
            end
        end
    end

    -- Group layout: CompactRaidGroup1..8Member1..5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.statusText then
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensureRaidStatusTextOverlay(frame, cfg)
                else
                    local state = getState(frame)
                    if state and state.statusTextOverlay then
                        styleRaidStatusTextOverlay(frame, cfg)
                    end
                end
            end
        end
    end
end

function addon.RestoreRaidFrameStatusTextOverlays()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            disableRaidStatusTextOverlay(frame)
        end
    end
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                disableRaidStatusTextOverlay(frame)
            end
        end
    end
end

local function installRaidFrameStatusTextHooks()
    if addon._RaidFrameStatusTextHooksInstalled then return end
    addon._RaidFrameStatusTextHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local raidCfg = gf and rawget(gf, "raid") or nil
        return raidCfg and rawget(raidCfg, "textStatusText") or nil
    end

    -- Hook CompactUnitFrame_UpdateAll for overlay setup on full refresh
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            if isEditModeActive() then return end
            if not (frame and frame.statusText and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidStatusTextOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidStatusTextOverlay(frameRef, cfgRef)
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit for overlay setup on unit assignment
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            if isEditModeActive() then return end
            if not unit then return end
            if not (frame and frame.statusText and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidStatusTextOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidStatusTextOverlay(frameRef, cfgRef)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Group Numbers / Group Titles)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Player Name to raid group title text.
-- Target: CompactRaidGroup1..8Title (Button, parentKey "title").
--------------------------------------------------------------------------------

-- Get the current raid group orientation from Edit Mode settings
-- Returns "horizontal" or "vertical"
local function getGroupOrientation()
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    local EMSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
    if not (mgr and EM and EMSys and EMSetting and RGD and mgr.GetRegisteredSystemFrame) then
        return "vertical" -- Default fallback
    end
    local raidFrame = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Raid)
    if not raidFrame then return "vertical" end
    if not (addon and addon.EditMode and addon.EditMode.GetSetting) then
        return "vertical"
    end
    local displayType = addon.EditMode.GetSetting(raidFrame, EMSetting.RaidGroupDisplayType)
    if displayType == RGD.SeparateGroupsHorizontal or displayType == RGD.CombineGroupsHorizontal then
        return "horizontal"
    end
    return "vertical"
end

-- Apply number-only text and auto-centering to a group title
-- groupIndex: the group number (1-8)
local function applyNumberOnlyToGroupTitle(titleButton, groupIndex, cfg)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    -- Set text to just the number
    if fs.SetText then
        pcall(fs.SetText, fs, tostring(groupIndex or ""))
    end

    -- Determine orientation and set auto-centering
    local orientation = getGroupOrientation()

    -- Apply centering based on orientation
    if orientation == "vertical" then
        -- Vertical layout: groups stacked vertically, title centered above each column
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "CENTER")
        end
        -- Position at TOP, centered horizontally
        local offsetX = cfg and cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg and cfg.offset and tonumber(cfg.offset.y) or 0
        fs:ClearAllPoints()
        fs:SetPoint("TOP", titleButton, "TOP", offsetX, offsetY)
    else
        -- Horizontal layout: groups laid out horizontally, title beside each row
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "LEFT")
        end
        -- Position at LEFT
        local offsetX = cfg and cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg and cfg.offset and tonumber(cfg.offset.y) or 0
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", titleButton, "LEFT", offsetX, offsetY)
    end
end

local function applyTextToFontString_GroupTitle(fs, ownerFrame, cfg)
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
    if fsState and not fsState.originalPointGroupTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fsState.originalPointGroupTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fsState and fsState.originalPointGroupTitle then
        local orig = fsState.originalPointGroupTitle
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

local function applyGroupTitleToButton(titleButton, cfg, groupIndex)
    if not titleButton or not cfg then return end
    if not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    -- Check if numbers-only mode is enabled
    local db = addon and addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid
    local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

    if numbersOnly and groupIndex then
        -- Apply font styling first (font face, size, style, color)
        applyTextToFontString_GroupTitle(fs, titleButton, cfg)
        -- Then apply number-only text and auto-centering (overrides anchor/position)
        applyNumberOnlyToGroupTitle(titleButton, groupIndex, cfg)
    else
        -- Standard styling with full "Group N" text
        applyTextToFontString_GroupTitle(fs, titleButton, cfg)
    end
end

function addon.ApplyRaidFrameGroupTitlesStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid group title styling
    -- OR if numbers-only mode is enabled.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textGroupNumbers") or nil
    local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

    -- If no text config and numbers-only is not enabled, skip (Zero-Touch)
    if not cfg and not numbersOnly then
        return
    end

    -- If text config exists, check if it has custom settings
    -- Numbers-only mode alone is enough to proceed
    if cfg and not Utils.hasCustomTextSettings(cfg) and not numbersOnly then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queueRaidFrameReapply()
        return
    end

    -- Ensure cfg exists for applyGroupTitleToButton (use empty table as fallback)
    local effectiveCfg = cfg or {}

    for group = 1, 8 do
        local groupFrame = _G["CompactRaidGroup" .. group]
        local titleButton = (groupFrame and groupFrame.title) or _G["CompactRaidGroup" .. group .. "Title"]
        if titleButton then
            applyGroupTitleToButton(titleButton, effectiveCfg, group)
        end
    end
end

local function installRaidFrameGroupTitleHooks()
    if addon._RaidFrameGroupTitleHooksInstalled then return end
    addon._RaidFrameGroupTitleHooksInstalled = true

    local function tryApplyTitle(groupFrame, groupIndex)
        -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
        if isEditModeActive() then return end
        if not groupFrame or not Utils.isCompactRaidGroupFrame(groupFrame) then
            return
        end
        local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
        if not titleButton then return end

        local db = addon and addon.db and addon.db.profile
        local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil
        local cfg = raidCfg and raidCfg.textGroupNumbers or nil
        local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

        -- Zero-Touch: skip if no text config and numbers-only is not enabled
        if not cfg and not numbersOnly then
            return
        end
        if cfg and not Utils.hasCustomTextSettings(cfg) and not numbersOnly then
            return
        end

        -- Extract group index from frame name if not provided
        local effectiveGroupIndex = groupIndex
        if not effectiveGroupIndex then
            local frameName = groupFrame:GetName()
            if frameName then
                effectiveGroupIndex = tonumber(frameName:match("CompactRaidGroup(%d+)"))
            end
        end

        local titleRef = titleButton
        local cfgRef = cfg or {}
        local groupIndexRef = effectiveGroupIndex
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                applyGroupTitleToButton(titleRef, cfgRef, groupIndexRef)
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queueRaidFrameReapply()
                return
            end
            applyGroupTitleToButton(titleRef, cfgRef, groupIndexRef)
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactRaidGroup_UpdateLayout then
            _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", function(groupFrame)
                -- Extract group index from frame
                local groupIndex = groupFrame and groupFrame.GetID and groupFrame:GetID()
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
        if _G.CompactRaidGroup_InitializeForGroup then
            _G.hooksecurefunc("CompactRaidGroup_InitializeForGroup", function(groupFrame, groupIndex)
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
        if _G.CompactRaidGroup_UpdateUnits then
            _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", function(groupFrame)
                -- Extract group index from frame
                local groupIndex = groupFrame and groupFrame.GetID and groupFrame:GetID()
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Hook Installation
--------------------------------------------------------------------------------

function RaidFrames.installTextHooks()
    installRaidFrameTextHooks()
    installRaidNameOverlayHooks()
    installRaidFrameStatusTextHooks()
    installRaidFrameGroupTitleHooks()
end

-- Install text hooks on load
RaidFrames.installTextHooks()

--------------------------------------------------------------------------------
-- Over Absorb Glow Visibility
--------------------------------------------------------------------------------
-- Hides or shows the OverAbsorbGlow texture on raid frames.
-- This glow appears when absorb shields exceed the health bar width.
-- Frame paths:
--   - CompactRaidGroup[1-8]Member[1-5].overAbsorbGlow (group layout)
--   - CompactRaidFrame[1-40].overAbsorbGlow (combined layout)
--
-- Uses alpha hiding with persistent hooks (same pattern as party frames).
--------------------------------------------------------------------------------

local function applyOverAbsorbGlowVisibility(frame, shouldHide)
    if not frame then return end
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
        if glow.SetAlpha then pcall(glow.SetAlpha, glow, 1) end
    end
end

function RaidFrames.ApplyOverAbsorbGlowVisibility()
    local db = addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local shouldHide = raidCfg.hideOverAbsorbGlow or false
    if not shouldHide then return end

    -- Pattern 1: Group-based naming (CompactRaidGroup1Member1, etc.)
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                applyOverAbsorbGlowVisibility(frame, shouldHide)
            end
        end
    end

    -- Pattern 2: Combined naming (CompactRaidFrame1, etc.)
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            applyOverAbsorbGlowVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyRaidOverAbsorbGlowVisibility = RaidFrames.ApplyOverAbsorbGlowVisibility

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
-- Hides or shows myHealPrediction and otherHealPrediction textures on raid frames.
-- Frame paths:
--   - CompactRaidGroup[1-8]Member[1-5].myHealPrediction / .otherHealPrediction
--   - CompactRaidFrame[1-40].myHealPrediction / .otherHealPrediction
--------------------------------------------------------------------------------

applyHealPredictionVisibility = function(frame, shouldHide)
    if not frame then return end
    applyTextureVisibility(frame.myHealPrediction, shouldHide, "healPred")
    applyTextureVisibility(frame.otherHealPrediction, shouldHide, "healPred")
end

function RaidFrames.ApplyHealPredictionVisibility()
    local db = addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local shouldHide = raidCfg.hideHealPrediction or false
    if not shouldHide then return end

    -- Pattern 1: Group-based naming (CompactRaidGroup1Member1, etc.)
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                applyHealPredictionVisibility(frame, shouldHide)
            end
        end
    end

    -- Pattern 2: Combined naming (CompactRaidFrame1, etc.)
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            applyHealPredictionVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyRaidHealPredictionVisibility = RaidFrames.ApplyHealPredictionVisibility

--------------------------------------------------------------------------------
-- Absorb Bars Visibility
--------------------------------------------------------------------------------
-- Hides or shows absorb-related textures on raid frames.
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

function RaidFrames.ApplyAbsorbBarsVisibility()
    local db = addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local shouldHide = raidCfg.hideAbsorbBars or false
    if not shouldHide then return end

    -- Pattern 1: Group-based naming
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                applyAbsorbBarsVisibility(frame, shouldHide)
            end
        end
    end

    -- Pattern 2: Combined naming
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            applyAbsorbBarsVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyRaidAbsorbBarsVisibility = RaidFrames.ApplyAbsorbBarsVisibility

--------------------------------------------------------------------------------
-- Heal Prediction Clipping (MaskTexture)
--------------------------------------------------------------------------------
-- Clips all prediction/absorb textures to healthBar bounds using MaskTexture.
-- This prevents textures from extending past the health bar edges.
--
-- Only activates when user has configured raid frames (zero-touch compliant).
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

function RaidFrames.ApplyHealPredictionClipping()
    local db = addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    -- Pattern 1: Group-based naming
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                ensureHealPredictionClipping(frame)
            end
        end
    end

    -- Pattern 2: Combined naming
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            ensureHealPredictionClipping(frame)
        end
    end
end

addon.ApplyRaidHealPredictionClipping = RaidFrames.ApplyHealPredictionClipping

--------------------------------------------------------------------------------
-- Apply Custom Role Icons for Raid Frames
--------------------------------------------------------------------------------
-- Re-triggers Blizzard's CompactUnitFrame_UpdateRoleIcon on each raid frame.
-- Blizzard sets the default atlas, then our post-hook swaps to the custom set.

function addon.ApplyRaidRoleIcons()
    local directApply = addon._applyCustomRoleIcon
    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.roleIcon then
            if _G.CompactUnitFrame_UpdateRoleIcon then
                local ok = pcall(CompactUnitFrame_UpdateRoleIcon, frame)
                if not ok and directApply then
                    pcall(directApply, frame)
                end
            end
        end
    end

    -- Group layout: CompactRaidGroup1Member1..CompactRaidGroup8Member5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
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
end

return RaidFrames

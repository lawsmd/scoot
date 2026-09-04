--------------------------------------------------------------------------------
-- bars/raidframes/core.lua
-- Raid frame health bar and text styling
--
-- Applies styling to CompactRaidGroup*Member* and CompactRaidFrame* frames.
-- Uses combat-safe overlay patterns for persistence during combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Scratch opts for ResolveColorRGBA: per-call fields overwritten before each call
local gfColorOpts = {}

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
-- Avoids secret value issues because the overlay anchors to Blizzard's fill texture directly,
-- which is sized by Blizzard's internal (untainted) code.
local function updateHealthOverlay(bar)
    if not bar then return end

    local state = getState(bar)
    local overlay = state and state.healthOverlay or nil
    if not overlay then return end
    if not state or not state.overlayActive then
        overlay:Hide()
        state.lastAnchoredFill = nil
        return
    end

    -- SECRET-SAFE: Anchor overlay to the status bar fill texture.
    -- Blizzard's fill texture is sized internally without exposing secret values.
    -- By anchoring to it, the overlay automatically matches the fill dimensions.
    local fill = bar:GetStatusBarTexture()
    if not fill then
        overlay:Hide()
        state.lastAnchoredFill = nil
        return
    end

    -- IMPORTANT: only re-anchor when the fill texture identity has
    -- changed. Calling ClearAllPoints + SetAllPoints on every UNIT_HEALTH tick
    -- re-stamps the overlay in the bar's render queue, demoting Blizzard's
    -- (12.0.5+) dispel-highlight texture beneath the overlay. The fill pointer only
    -- changes on bar-texture swaps (handled by the SetStatusBarTexture hook),
    -- so SetValue/SetMinMaxValues/OnSizeChanged should be no-ops here.
    if state.lastAnchoredFill ~= fill then
        overlay:ClearAllPoints()
        overlay:SetAllPoints(fill)
        state.lastAnchoredFill = fill
    end
    if not overlay:IsShown() then overlay:Show() end
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
    elseif colorMode == "class" then
        local unit
        local parentFrame = bar.GetParent and bar:GetParent()
        if parentFrame then
            local okU, u = pcall(function() return parentFrame.displayedUnit or parentFrame.unit end)
            if okU and u then unit = u end
        end
        -- No unit yet: stay white until the roster pass re-styles; a class
        -- miss stays white too (no green fallback on member frames)
        if unit then
            gfColorOpts.barKind = nil
            gfColorOpts.unitForClass = unit
            r, g, b, a = addon.ResolveColorRGBA(colorMode, tint, gfColorOpts)
        end
    else
        -- custom, texture, "default", and unknown modes; custom with no
        -- stored tint keeps falling to the default green, as before
        local mode = colorMode
        if mode == "custom" and type(tint) ~= "table" then mode = "default" end
        gfColorOpts.barKind = "health"
        gfColorOpts.unitForClass = nil
        r, g, b, a = addon.ResolveColorRGBA(mode, tint, gfColorOpts)
    end
    overlay:SetVertexColor(r, g, b, a)
end

-- Hide Blizzard's fill texture: alpha 0 now, re-asserted at once and again
-- after a stack break whenever Blizzard sets the alpha (core/enforce.lua).
local FILL_HIDE_OPTS = { methods = { "SetAlpha" }, timing = "both" }

local function hideBlizzardFill(bar)
    if not bar then return end
    addon.Enforce.Set(bar:GetStatusBarTexture(), "gfFill", true, FILL_HIDE_OPTS)
end

-- Show Blizzard's fill texture
local function showBlizzardFill(bar)
    if not bar then return end
    addon.Enforce.Set(bar:GetStatusBarTexture(), "gfFill", false, FILL_HIDE_OPTS)
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
        return
    end

    if state and not state.healthOverlay then
        -- Parent the overlay to the healthBar StatusBar (a useParentLevel="true"
        -- child). Places the overlay in the same rendering pass as Blizzard's
        -- dispel highlight (rendered into the parent CompactUnitFrame's pass
        -- via PrivateAurasUI in 12.0.5+). Within that pass, BORDER 7 renders
        -- before Blizzard's ARTWORK dispel highlight, so the dispel reliably
        -- renders above it.
        local overlay = bar:CreateTexture(nil, "BORDER", nil, 7)
        overlay:SetVertTile(false)
        overlay:SetHorizTile(false)
        overlay:SetTexCoord(0, 1, 0, 1)
        state.healthOverlay = overlay

        if _G.hooksecurefunc and state and not state.overlayHooksInstalled then
            state.overlayHooksInstalled = true
            _G.hooksecurefunc(bar, "SetValue", function(self)
                updateHealthOverlay(self)
                -- Skip color updates during Edit Mode to prevent incorrect colors
                -- from being applied during frame rebuilds (Blizzard reassigns units,
                -- UnitHealthPercent may be unreliable during transitions).
                if addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening
                   and addon.EditMode.IsEditModeActiveOrOpening() then return end
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
                    end
                end
            end)
            _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                updateHealthOverlay(self)
            end)
            -- FIX: Hook SetStatusBarColor to intercept Blizzard's color changes.
            -- Key fix for blinking: when Blizzard's CompactUnitFrame_UpdateHealthColor
            -- calls SetStatusBarColor(green), the hook fires IMMEDIATELY after and re-applies
            -- the value-based color. No frame gap = no blink.
            _G.hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b)
                local st = getState(self)
                if not st or not st.overlayActive then return end
                -- Recursion guard: Check the SAME flag that applyValueBasedColor uses in addon.FrameState
                -- to prevent infinite loops when SetStatusBarColor is called from applyValueBasedColor.
                local fs = addon.FrameState and addon.FrameState.Get(self)
                if fs and fs.applyingValueBasedColor then return end
                -- Skip during Edit Mode to prevent incorrect colors from frame rebuilds
                if addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening
                   and addon.EditMode.IsEditModeActiveOrOpening() then return end
                local db = addon and addon.db and addon.db.profile
                local groupFrames = db and rawget(db, "groupFrames") or nil
                local cfg = groupFrames and rawget(groupFrames, "raid") or nil
                local colorMode = cfg and cfg.healthBarColorMode
                local overlay = st.healthOverlay
                if colorMode == "value" or colorMode == "valueDark" then
                    local useDark = (colorMode == "valueDark")
                    local parentFrame = self.GetParent and self:GetParent()
                    local unit
                    if parentFrame then
                        local okU, u = pcall(function() return parentFrame.displayedUnit or parentFrame.unit end)
                        if okU and u then unit = u end
                    end
                    if unit and overlay and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(self, unit, overlay, useDark)
                    end
                elseif overlay then
                    -- Re-enforce overlay color for non-value modes so Blizzard's
                    -- SetStatusBarColor (from UpdateHealthColor) can't bleed through
                    -- if the fill briefly becomes visible (texture swap gap).
                    local cr, cg, cb, ca = 1, 1, 1, 1
                    if colorMode == "class" then
                        local parentFrame = self.GetParent and self:GetParent()
                        local unit
                        if parentFrame then
                            local okU, u = pcall(function() return parentFrame.displayedUnit or parentFrame.unit end)
                            if okU and u then unit = u end
                        end
                        if unit then
                            gfColorOpts.barKind = nil
                            gfColorOpts.unitForClass = unit
                            cr, cg, cb, ca = addon.ResolveColorRGBA(colorMode, nil, gfColorOpts)
                        end
                    else
                        gfColorOpts.barKind = "health"
                        gfColorOpts.unitForClass = nil
                        cr, cg, cb, ca = addon.ResolveColorRGBA(colorMode, cfg and cfg.healthBarTint, gfColorOpts)
                    end
                    pcall(overlay.SetVertexColor, overlay, cr, cg, cb, ca)
                end
            end)
        end
    end

    if state and not state.textureSwapHooked and _G.hooksecurefunc then
        state.textureSwapHooked = true
        -- Closes over the bar and never reads its hook argument: a hook's self
        -- can arrive as a secret handle from a sealed caller, and keying
        -- FrameState on one marks the table secret.
        _G.hooksecurefunc(bar, "SetStatusBarTexture", function()
            local st = getState(bar)
            if st and st.overlayActive then
                -- Synchronous: hide new fill and re-anchor overlay immediately
                hideBlizzardFill(bar)
                updateHealthOverlay(bar)
                -- Deferred safety net: catch edge cases where texture isn't ready
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        hideBlizzardFill(bar)
                        updateHealthOverlay(bar)
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

    end

    -- Dispel rendering is left entirely to Blizzard (see partyframes/core.lua
    -- for the full rationale and the textures.lua ufLastTexturePath cache).

    -- Build a config fingerprint to detect whether settings changed.
    -- Prevents expensive re-styling when ApplyStyles() is called but raid
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
    if state then
        state.overlayActive = false
        -- Invalidate the anchored-fill cache so re-enabling re-anchors once.
        state.lastAnchoredFill = nil
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
-- Applies Scoot bar borders to raid frame health bars.
-- The square branch is the party implementation (see partyframes/core.lua):
-- engine-owned edges on the parent CompactUnitFrame at OVERLAY sublevel -8,
-- below Blizzard's selection highlight, with live inset sliders and whole-edge
-- hiddenEdges. Textured borders keep the addon-owned BackdropTemplate anchor
-- frame to avoid taint. Each branch hides the other's border on a style switch.
--------------------------------------------------------------------------------

-- Clear health bar border for a single bar
local function clearHealthBarBorder(bar)
    if not bar then return end
    -- Hide engine-owned square edges on the parent CompactUnitFrame
    local unitFrame = bar.GetParent and bar:GetParent()
    if unitFrame and addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(unitFrame)
    end
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

    -- Border settings
    local tintEnabled = cfg.healthBarBorderTintEnable
    local tintColor = cfg.healthBarBorderTintColor or {1, 1, 1, 1}
    local thickness = tonumber(cfg.healthBarBorderThickness) or 1
    local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
    local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
    local hiddenEdges = cfg.healthBarBorderHiddenEdges

    if styleKey == "square" then
        -- Simple square border via the shared engine: the same call as
        -- partyframes/core.lua, so raid and party render identically. Engine
        -- edges sit on the CompactUnitFrame at OVERLAY sublevel -8, below
        -- Blizzard's selection highlight, with live insets and whole-edge
        -- hiddenEdges.
        local unitFrame = bar.GetParent and bar:GetParent()
        if not unitFrame then return end

        -- Hide the BackdropTemplate anchor from a prior textured style
        local prevState = getState(bar)
        if prevState and prevState.borderAnchor then
            prevState.borderAnchor:Hide()
        end

        local r, g, b, a
        if tintEnabled then
            r, g, b, a = tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] or 1
        else
            -- Default square border is black
            r, g, b, a = 0, 0, 0, 1
        end

        addon.Borders.ApplySquare(unitFrame, {
            size = math.max(1, math.floor(thickness + 0.5)),
            color = { r, g, b, a },
            layer = "OVERLAY",
            layerSublevel = -8,
            anchorRegion = bar,
            expandX = math.max(0, 1 - insetH),
            expandY = math.max(0, 1 - insetV),
            hiddenEdges = hiddenEdges,
            skipDimensionCheck = true,
        })
        return
    end

    -- Textured border: addon-owned BackdropTemplate anchor. Hide engine-owned
    -- square edges from a prior style first.
    do
        local unitFrame = bar.GetParent and bar:GetParent()
        if unitFrame and addon.Borders and addon.Borders.HideAll then
            addon.Borders.HideAll(unitFrame)
        end
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
        else
            -- Unknown style, hide border
            clearHealthBarBorder(bar)
            return
        end

        -- Apply hidden edges to BackdropTemplate edge/corner textures
        if hiddenEdges and (hiddenEdges.top or hiddenEdges.bottom or hiddenEdges.left or hiddenEdges.right) then
            if hiddenEdges.top and anchor.TopEdge then anchor.TopEdge:Hide() end
            if hiddenEdges.bottom and anchor.BottomEdge then anchor.BottomEdge:Hide() end
            if hiddenEdges.left and anchor.LeftEdge then anchor.LeftEdge:Hide() end
            if hiddenEdges.right and anchor.RightEdge then anchor.RightEdge:Hide() end
            -- Corners: hide if either adjacent edge is hidden
            if anchor.TopLeftCorner and (hiddenEdges.top or hiddenEdges.left) then anchor.TopLeftCorner:Hide() end
            if anchor.TopRightCorner and (hiddenEdges.top or hiddenEdges.right) then anchor.TopRightCorner:Hide() end
            if anchor.BottomLeftCorner and (hiddenEdges.bottom or hiddenEdges.left) then anchor.BottomLeftCorner:Hide() end
            if anchor.BottomRightCorner and (hiddenEdges.bottom or hiddenEdges.right) then anchor.BottomRightCorner:Hide() end
        end
    end
end

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActiveForBorders = addon.EditMode.IsEditModeActiveOrOpening

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

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC).
-- Skip all CompactUnitFrame hooks when Edit Mode is active to avoid taint.
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

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
                        -- Clear fingerprint to force fresh overlay setup on frame reuse
                        local fpState = getState(bar)
                        if fpState then fpState.lastAppliedFingerprint = nil end
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
    -- Fires after every health update, enabling dynamic color updates
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
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark" and colorMode ~= "class") then return end

            -- Get unit token from the frame
            local unit
            local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
            if okU and u then unit = u end
            if not unit then return end

            -- Class color mode: apply class color to overlay
            if colorMode == "class" then
                local healthBar = frame.healthBar
                local state = getState(healthBar)
                local overlay = state and state.healthOverlay or nil
                if addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB(unit)
                    if cr then
                        if overlay and overlay:IsShown() then
                            overlay:SetVertexColor(cr, cg, cb, 1)
                        else
                            C_Timer.After(0, function()
                                local st = getState(healthBar)
                                local ov = st and st.healthOverlay or nil
                                if ov then
                                    ov:SetVertexColor(cr, cg, cb, 1)
                                end
                            end)
                        end
                    end
                end
                return
            end

            local useDark = (colorMode == "valueDark")

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
                -- Prevents the 1-frame blink where Blizzard's color shows
                if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                    addon.BarsTextures.applyValueBasedColor(healthBar, unit, overlay, useDark)
                end
            else
                -- Overlay not ready - defer to ensure initialization completes
                C_Timer.After(0, function()
                    local st = getState(healthBar)
                    local ov = st and st.healthOverlay or nil
                    if ov and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(healthBar, unit, ov, useDark)
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

    --------------------------------------------------------------------------
    -- Event-Driven Refresh + Periodic Integrity Check
    --------------------------------------------------------------------------
    -- Addresses timing gaps where Blizzard rebuilds raid frames (group join,
    -- CVar toggles like "Display Main Tank and Assist") but Scoot's deferred
    -- hooks haven't fired yet, leaving frames invisible (Blizzard fill hidden
    -- via alpha 0, overlay not yet created/shown).
    --
    -- Two-layer defense (mirrors partyframes/core.lua pattern):
    --   1. Event-driven: GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD trigger
    --      a debounced full overlay reapply after 0.5s.
    --   2. Ticker: Every 5s while in a raid, verify overlay visibility and
    --      Blizzard fill alpha for every active raid frame.
    --------------------------------------------------------------------------

    if not addon._RaidFrameIntegrityCheckInstalled then
        addon._RaidFrameIntegrityCheckInstalled = true
        local integrityTicker = nil
        local pendingRefreshTimer = nil

        -- Immediate debounced refresh: calls the brute-force Apply function
        -- that iterates all 80 possible raid frame names.
        local function scheduleFullRefresh()
            if isEditModeActive() then return end
            if pendingRefreshTimer then
                pendingRefreshTimer:Cancel()
                pendingRefreshTimer = nil
            end
            pendingRefreshTimer = C_Timer.NewTimer(0.5, function()
                pendingRefreshTimer = nil
                if isEditModeActive() then return end
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                if addon.ApplyRaidFrameHealthOverlays then
                    addon.ApplyRaidFrameHealthOverlays()
                end
                if addon.ApplyRaidFrameHealthBarBorders then
                    addon.ApplyRaidFrameHealthBarBorders()
                end
            end)
        end

        -- Per-frame integrity check (mirrors partyframes/core.lua pattern)
        local function runIntegrityCheck()
            if isEditModeActive() then
                -- Detect stuck guard: ask editmode to verify against Blizzard state
                if addon.EditMode and addon.EditMode.ForceResetIfStuck then
                    if not addon.EditMode.ForceResetIfStuck() then
                        return -- Edit Mode is genuinely active
                    end
                    -- Guard was stuck and has been reset; fall through
                else
                    return
                end
            end
            if InCombatLockdown and InCombatLockdown() then return end

            local db = addon and addon.db and addon.db.profile
            local groupFrames = db and rawget(db, "groupFrames") or nil
            local cfg = groupFrames and rawget(groupFrames, "raid") or nil
            if not cfg then return end

            local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default")
                           or (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")

            local colorMode = cfg.healthBarColorMode
            local isValueMode = (colorMode == "value" or colorMode == "valueDark")
            local useDark = (colorMode == "valueDark")

            local function checkFrame(frame)
                if not frame then return end
                local bar = frame.healthBar
                if bar and hasCustom then
                    local state = getState(bar)
                    if state and state.overlayActive then
                        local overlay = state.healthOverlay
                        if not overlay then
                            -- Overlay flag set but texture missing — force recreation
                            state.overlayActive = nil
                            state.lastAppliedFingerprint = nil
                            RaidFrames.ensureHealthOverlay(bar, cfg)
                        else
                            -- Check 1: Blizzard fill must be hidden
                            local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
                            if fill then
                                local okA, alpha = pcall(fill.GetAlpha, fill)
                                if okA and not (issecretvalue and issecretvalue(alpha))
                                   and type(alpha) == "number" and alpha > 0 then
                                    hideBlizzardFill(bar)
                                end
                            end
                            -- Check 2: Re-anchor overlay to current fill (catches orphaned anchors)
                            updateHealthOverlay(bar)
                            if not overlay:IsShown() then
                                overlay:Show()
                            end
                            -- Check 3: Revalidate overlay color for value-based modes
                            if isValueMode and overlay:IsShown() then
                                local parentFrame = bar.GetParent and bar:GetParent()
                                local unit
                                if parentFrame then
                                    local okU, u = pcall(function() return parentFrame.displayedUnit or parentFrame.unit end)
                                    if okU and u then unit = u end
                                end
                                if unit and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                                    addon.BarsTextures.applyValueBasedColor(bar, unit, overlay, useDark)
                                end
                            end
                        end
                    elseif not state or not state.overlayActive then
                        -- Overlay not yet created — force creation
                        RaidFrames.ensureHealthOverlay(bar, cfg)
                    end
                end
                -- Check 4: Role icons
                if addon._applyCustomRoleIcon then
                    pcall(addon._applyCustomRoleIcon, frame)
                end
            end

            -- Combined layout: CompactRaidFrame1..40
            for i = 1, 40 do
                checkFrame(_G["CompactRaidFrame" .. i])
            end
            -- Group layout: CompactRaidGroup1..8 Member1..5
            for g = 1, 8 do
                for m = 1, 5 do
                    checkFrame(_G["CompactRaidGroup" .. g .. "Member" .. m])
                end
            end
        end

        local function onIntegrityEvent()
            if isEditModeActive() then
                -- Guard is active — schedule a deferred check to detect stuck state.
                -- 2s delay lets Blizzard state settle after load/group-join transitions.
                if addon.EditMode and addon.EditMode.ForceResetIfStuck then
                    C_Timer.After(2.0, function()
                        if not isEditModeActive() then return end -- already cleared
                        if not addon.EditMode.ForceResetIfStuck() then return end
                        -- State was stuck; schedule the refresh that was skipped
                        local inRaid = IsInRaid and IsInRaid()
                        if inRaid then
                            scheduleFullRefresh()
                            if not integrityTicker then
                                integrityTicker = C_Timer.NewTicker(5, runIntegrityCheck)
                            end
                        end
                    end)
                end
                return
            end
            local inRaid = IsInRaid and IsInRaid()
            if inRaid then
                scheduleFullRefresh()
                if not integrityTicker then
                    integrityTicker = C_Timer.NewTicker(5, runIntegrityCheck)
                end
            else
                if integrityTicker then
                    integrityTicker:Cancel()
                    integrityTicker = nil
                end
                if pendingRefreshTimer then
                    pendingRefreshTimer:Cancel()
                    pendingRefreshTimer = nil
                end
            end
        end
        addon.Events.On("UnitFrames:RaidFrames", "GROUP_ROSTER_UPDATE", onIntegrityEvent)
        addon.Events.On("UnitFrames:RaidFrames", "PLAYER_ENTERING_WORLD", onIntegrityEvent)
    end
end

-- Install hooks on load
RaidFrames.installHooks()

--------------------------------------------------------------------------------
-- Diagnostic: /scoot debug raidframes
-- Also auto-fires 3s after PLAYER_ENTERING_WORLD if in a raid.
-- Captures the exact state of all raid frames to identify why they're invisible.
--------------------------------------------------------------------------------
function addon.DebugDumpRaidFrames()
    local lines, add = addon.DebugLines()

    add("=== Raid Frames Diagnostic ===")
    add(string.format("Time: %s", date("%Y-%m-%d %H:%M:%S")))
    add(string.format("InRaid: %s", tostring(IsInRaid and IsInRaid())))
    add(string.format("InGroup: %s", tostring(IsInGroup and IsInGroup())))
    add(string.format("InCombatLockdown: %s", tostring(InCombatLockdown and InCombatLockdown())))

    -- Edit Mode guard state
    local emGuard = "N/A"
    if addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening then
        emGuard = tostring(addon.EditMode.IsEditModeActiveOrOpening())
    end
    add(string.format("isEditModeActive(): %s", emGuard))

    -- Check the live Blizzard Edit Mode state
    local mgr = _G.EditModeManagerFrame
    if mgr then
        local ok1, active = pcall(function() return mgr.editModeActive end)
        local ok2, shown = pcall(mgr.IsShown, mgr)
        add(string.format("EditModeManagerFrame.editModeActive: %s (ok=%s)",
            tostring(active), tostring(ok1)))
        add(string.format("EditModeManagerFrame:IsShown(): %s (ok=%s)",
            tostring(shown), tostring(ok2)))
    else
        add("EditModeManagerFrame: nil")
    end
    add(string.format("_openingEditMode: %s", tostring(addon.EditMode and addon.EditMode._openingEditMode)))
    add(string.format("_exitingEditMode: %s", tostring(addon.EditMode and addon.EditMode._exitingEditMode)))

    -- DB config check
    local db = addon and addon.db and addon.db.profile
    local groupFrames = db and rawget(db, "groupFrames") or nil
    local cfg = groupFrames and rawget(groupFrames, "raid") or nil
    if cfg then
        add(string.format("\nhealthBarTexture: %s", tostring(cfg.healthBarTexture)))
        add(string.format("healthBarColorMode: %s", tostring(cfg.healthBarColorMode)))
        add(string.format("healthBarBackgroundTexture: %s", tostring(cfg.healthBarBackgroundTexture)))
        add(string.format("healthBarBackgroundColorMode: %s", tostring(cfg.healthBarBackgroundColorMode)))
        local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default")
                       or (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
        add(string.format("hasCustom (fg): %s", tostring(hasCustom)))
    else
        add("\ncfg (db.groupFrames.raid): NIL — overlays will not be applied")
    end

    -- Container state
    local container = _G.CompactRaidFrameContainer
    if container then
        local okS, shown = pcall(container.IsShown, container)
        local okV, visible = pcall(container.IsVisible, container)
        add(string.format("\nCompactRaidFrameContainer: exists, IsShown=%s, IsVisible=%s",
            tostring(shown), tostring(visible)))
    else
        add("\nCompactRaidFrameContainer: nil (does not exist)")
    end

    -- Sample frames
    add("\n--- Combined Layout (CompactRaidFrame1..40) ---")
    local combinedExists, combinedShown = 0, 0
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            combinedExists = combinedExists + 1
            local okS, shown = pcall(frame.IsShown, frame)
            if okS and shown then combinedShown = combinedShown + 1 end
        end
    end
    add(string.format("Exist: %d, Shown: %d", combinedExists, combinedShown))

    add("\n--- Group Layout (CompactRaidGroup*Member*) ---")
    local groupExists, groupShown = 0, 0
    for g = 1, 8 do
        for m = 1, 5 do
            local frame = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if frame then
                groupExists = groupExists + 1
                local okS, shown = pcall(frame.IsShown, frame)
                if okS and shown then groupShown = groupShown + 1 end
            end
        end
    end
    add(string.format("Exist: %d, Shown: %d", groupExists, groupShown))

    -- Detailed state for first 5 visible frames
    add("\n--- Detailed Frame State (first 5 shown frames) ---")
    local detailed = 0
    local function detailFrame(frameName)
        if detailed >= 5 then return end
        local frame = _G[frameName]
        if not frame then return end
        local okS, shown = pcall(frame.IsShown, frame)
        if not (okS and shown) then return end
        detailed = detailed + 1
        add(string.format("\n[%s]", frameName))
        -- Unit
        local okU, unit = pcall(function() return frame.displayedUnit or frame.unit end)
        add(string.format("  unit: %s (ok=%s)", tostring(unit), tostring(okU)))
        -- HealthBar
        local bar = frame.healthBar
        if not bar then
            add("  healthBar: nil")
            return
        end
        local okBS, barShown = pcall(bar.IsShown, bar)
        local okBV, barVisible = pcall(bar.IsVisible, bar)
        add(string.format("  healthBar: IsShown=%s, IsVisible=%s", tostring(barShown), tostring(barVisible)))
        -- Fill texture
        local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if fill then
            local okA, alpha = pcall(fill.GetAlpha, fill)
            local okT, tex = pcall(fill.GetTexture, fill)
            add(string.format("  fill: alpha=%s, tex=%s", tostring(alpha), tostring(tex)))
        else
            add("  fill: nil (no status bar texture)")
        end
        -- Overlay state
        local state = getState(bar)
        if state then
            local overlay = state.healthOverlay
            add(string.format("  overlayActive: %s", tostring(state.overlayActive)))
            add(string.format("  healthOverlay: %s", overlay and "exists" or "nil"))
            if overlay then
                local okOS, ovShown = pcall(overlay.IsShown, overlay)
                local okOV, ovVisible = pcall(overlay.IsVisible, overlay)
                local okOA, ovAlpha = pcall(overlay.GetAlpha, overlay)
                local okOT, ovTex = pcall(overlay.GetTexture, overlay)
                add(string.format("  overlay IsShown=%s, IsVisible=%s, alpha=%s, tex=%s",
                    tostring(ovShown), tostring(ovVisible), tostring(ovAlpha), tostring(ovTex)))
                -- Check if overlay has valid anchor points
                local okP, p1 = pcall(overlay.GetNumPoints, overlay)
                add(string.format("  overlay numPoints=%s", tostring(p1)))
            end
            add(string.format("  fingerprint: %s", state.lastAppliedFingerprint and "set" or "nil"))
            add(string.format("  overlayHooksInstalled: %s", tostring(state.overlayHooksInstalled)))
            add(string.format("  textureSwapHooked: %s", tostring(state.textureSwapHooked)))
            -- Frame-level topology snapshot (parent / bar / Blizzard's dispelDebuffFrames icon container).
            local okBL, barLvl = pcall(bar.GetFrameLevel, bar)
            local okPL, parLvl = pcall(frame.GetFrameLevel, frame)
            local dDF = frame.dispelDebuffFrames
            local ddfLvl, ddfParLvl
            if dDF and dDF[1] then
                local okD, v = pcall(dDF[1].GetFrameLevel, dDF[1])
                if okD then ddfLvl = v end
                local pp = dDF[1].GetParent and dDF[1]:GetParent()
                if pp then
                    local okP, v2 = pcall(pp.GetFrameLevel, pp)
                    if okP then ddfParLvl = v2 end
                end
            end
            add(string.format("  ctx: parLvl=%s bar:lvl=%s dDF[1]:lvl=%s dDF[1].parent:lvl=%s",
                tostring(parLvl), tostring(barLvl), tostring(ddfLvl), tostring(ddfParLvl)))
        else
            add("  RaidFrameState: nil (no state for this bar)")
        end
    end

    for i = 1, 40 do detailFrame("CompactRaidFrame" .. i) end
    for g = 1, 8 do
        for m = 1, 5 do detailFrame("CompactRaidGroup" .. g .. "Member" .. m) end
    end

    if detailed == 0 then
        add("\n  (No shown frames found — checking first 5 existing frames instead)")
        detailed = 0
        local function detailAnyFrame(frameName)
            if detailed >= 5 then return end
            local frame = _G[frameName]
            if not frame then return end
            detailed = detailed + 1
            add(string.format("\n[%s] (exists but not shown)", frameName))
            local okS, shown = pcall(frame.IsShown, frame)
            local okV, visible = pcall(frame.IsVisible, frame)
            add(string.format("  IsShown=%s, IsVisible=%s", tostring(shown), tostring(visible)))
            local okU, unit = pcall(function() return frame.displayedUnit or frame.unit end)
            add(string.format("  unit: %s", tostring(unit)))
            local bar = frame.healthBar
            if bar then
                local okBS, barShown = pcall(bar.IsShown, bar)
                add(string.format("  healthBar: IsShown=%s", tostring(barShown)))
            else
                add("  healthBar: nil")
            end
        end
        for i = 1, 40 do detailAnyFrame("CompactRaidFrame" .. i) end
        for g = 1, 8 do
            for m = 1, 5 do detailAnyFrame("CompactRaidGroup" .. g .. "Member" .. m) end
        end
    end

    add("\n--- Hooks ---")
    add(string.format("_RaidFrameHooksInstalled: %s", tostring(addon._RaidFrameHooksInstalled)))
    add(string.format("_RaidFrameIntegrityCheckInstalled: %s", tostring(addon._RaidFrameIntegrityCheckInstalled)))

    -- Party frames inspection
    add("\n=== Party Frames ===")
    local partyContainer = _G.CompactPartyFrame
    if partyContainer then
        local okS, shown = pcall(partyContainer.IsShown, partyContainer)
        local okV, visible = pcall(partyContainer.IsVisible, partyContainer)
        add(string.format("CompactPartyFrame: exists, IsShown=%s, IsVisible=%s",
            tostring(shown), tostring(visible)))
    else
        add("CompactPartyFrame: nil")
    end

    -- Helper: secret-safe tostring. Any value that issecretvalue() flags is
    -- replaced with "<secret>" so table.concat doesn't blow up later.
    local function safeStr(v)
        if v == nil then return "nil" end
        if _G.issecretvalue and _G.issecretvalue(v) then return "<secret>" end
        local ok, s = pcall(tostring, v)
        if not ok then return "<tostring-fail>" end
        if _G.issecretvalue and _G.issecretvalue(s) then return "<secret>" end
        return s
    end

    -- Walk Compact party member frames + their health overlay state
    local partyState = addon.BarsPartyFrames and addon.BarsPartyFrames._getState
    add("\n--- Party member frames ---")
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            local okS, shown = pcall(frame.IsShown, frame)
            local okU, unit = pcall(function() return frame.displayedUnit or frame.unit end)
            add(string.format("[%s] shown=%s unit=%s",
                "CompactPartyFrameMember" .. i, safeStr(shown), safeStr(unit)))
            local bar = frame.healthBar
            if bar and partyState then
                local st = partyState(bar)
                if st and st.healthOverlay then
                    local okHL, layer, sub = pcall(st.healthOverlay.GetDrawLayer, st.healthOverlay)
                    local okHS, hShown = pcall(st.healthOverlay.IsShown, st.healthOverlay)
                    add(string.format("  healthOverlay: layer=%s sub=%s shown=%s overlayActive=%s",
                        safeStr(layer), safeStr(sub), safeStr(hShown), safeStr(st.overlayActive)))
                else
                    add("  healthOverlay: nil")
                end
            end
        end
    end

    add("\n--- Party Hooks ---")
    add(string.format("_PartyFrameHooksInstalled: %s", tostring(addon._PartyFrameHooksInstalled)))

    if addon.DebugShowWindow then
        addon.DebugShowWindow("Group Frames Diagnostic", lines)
    end
end

addon:RegisterDebugCommand({
    name = "raidframes", aliases = { "rf" }, help = "raid frame state dump",
    handler = function() addon.DebugDumpRaidFrames() end,
})

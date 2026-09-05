--------------------------------------------------------------------------------
-- bars/groupcore.lua
-- Family factory for the party and raid frame health bar cores.
--
-- addon.BarsGroupCore.NewFamily(desc) builds the shared machinery both
-- families run: the health overlay with its per-bar hooks, the fill hide, the
-- border dispatch, the four CompactUnitFrame hooks, and the integrity check.
-- The family files (partyframes/core.lua, raidframes/core.lua) own their state
-- tables and frame iteration and pass them in through the descriptor.
--
-- desc fields:
--   module               the family's module table (method reads at call time)
--   getState, ensureState  the family's weak side-table accessors
--   isTarget             frame filter (Utils.isPartyFrame / isRaidFrame)
--   dbKey                groupFrames sub-table key ("party" / "raid")
--   bgTag                family tag passed to _ApplyBackgroundToStatusBar
--   queueReapply         the family's combat reapply queue
--   collectHealthBars    returns the family's health bar array
--   forEachUnitFrame     fn(cb) over every existing family unit frame
--   forEachHealthBar     fn(cb) over every existing family health bar
--   afterStylePass       optional fn(bars) run after the style pass
--   inGroupGate          integrity ticker gate (IsInGroup / IsInRaid)
--   hooksInstalledFlag   addon-level install latch name for the hooks
--   integrityFlag        addon-level install latch name for the integrity check
--   eventOwner           addon.Events owner for the integrity handlers
--
-- Fork flags, one per kept divergence between the two families:
--   rosterRefresh        raid: debounced full reapply plus per-frame border
--                        blocks in the UpdateAll and SetUnit hooks. Raid frames
--                        recycle through Blizzard's reservation pool, so a
--                        frame update can hand a styled frame to a new unit;
--                        party member frames are a static array and never need
--                        this.
--   texturedBorder       "edges" (party: edge textures on the CompactUnitFrame)
--                        or "backdrop" (raid: a BackdropTemplate child frame).
--
-- Resilience measures that started on one family now run on both: the
-- fingerprint skip gate only when the overlay is shown, the OnSizeChanged
-- hook, the fingerprint clear in the SetUnit hook, the integrity check's
-- unconditional re-anchor and overlay recreation, and the role icon reapply
-- in the UpdateAll hook. Color by Value paints its fallback color before
-- delegating to applyValueBasedColor, so the overlay is never colorless.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.BarsGroupCore = addon.BarsGroupCore or {}
local GC = addon.BarsGroupCore

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC).
-- Skip all CompactUnitFrame hooks when Edit Mode is active to avoid taint.
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Hide Blizzard's fill texture: alpha 0 now, re-asserted at once and again
-- after a stack break whenever Blizzard sets the alpha (core/enforce.lua).
local FILL_HIDE_OPTS = { methods = { "SetAlpha" }, timing = "both" }

local function hideBlizzardFill(bar)
    if not bar then return end
    addon.Enforce.Set(bar:GetStatusBarTexture(), "gfFill", true, FILL_HIDE_OPTS)
end

local function showBlizzardFill(bar)
    if not bar then return end
    addon.Enforce.Set(bar:GetStatusBarTexture(), "gfFill", false, FILL_HIDE_OPTS)
end

function GC.NewFamily(desc)
    local module = desc.module
    local getState = desc.getState
    local ensureState = desc.ensureState
    local isTarget = desc.isTarget
    local dbKey = desc.dbKey
    local bgTag = desc.bgTag
    local queueReapply = desc.queueReapply
    local inGroupGate = desc.inGroupGate

    local rosterRefresh = desc.rosterRefresh
    local texturedBorderMode = desc.texturedBorder

    -- Scratch opts for ResolveColorRGBA: per-call fields overwritten before each call
    local gfColorOpts = {}

    local family = {}

    -- The family's groupFrames sub-table, or nil when the profile has none.
    -- Zero-Touch: rawget, so the read materializes no default.
    local function readCfg()
        local db = addon.db and addon.db.profile
        local groupFrames = db and rawget(db, "groupFrames") or nil
        return groupFrames and rawget(groupFrames, dbKey) or nil
    end

    -- The unit a CompactUnitFrame displays, read under pcall: the field can be
    -- secret in a tainted context, and a boolean test on a secret throws.
    local function frameUnit(frame)
        if not frame then return end
        local okU, u = pcall(function() return frame.displayedUnit or frame.unit end)
        if okU and u then return u end
    end

    local function barUnit(bar)
        return frameUnit(bar.GetParent and bar:GetParent())
    end

    -- Custom foreground settings: texture or color mode off "default". The
    -- overlay exists only for these; the bar predicate adds the background.
    local function hasOverlayCustom(cfg)
        return (cfg.healthBarTexture and cfg.healthBarTexture ~= "default")
            or (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    end

    local function hasBarCustom(cfg)
        return hasOverlayCustom(cfg)
            or (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default")
            or (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
    end

    ----------------------------------------------------------------------------
    -- Health Bar Styling
    ----------------------------------------------------------------------------

    function family.applyToHealthBar(bar, cfg)
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
            addon._ApplyBackgroundToStatusBar(bar, bgTexKey, bgColorMode, bgTint, bgOpacity, bgTag, "health")
        end
    end

    ----------------------------------------------------------------------------
    -- Health Bar Overlay (Combat-Safe Persistence)
    ----------------------------------------------------------------------------

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

    family.updateHealthOverlay = updateHealthOverlay

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
            -- "Color by Value" mode: use UnitHealthPercent with color curve.
            -- FIRST: Apply fallback color so overlay is never colorless (in case
            -- applyValueBasedColor encounters secret values and returns early
            -- without applying color). Dark gray for valueDark, green for value.
            local useDark = (colorMode == "valueDark")
            if useDark then
                overlay:SetVertexColor(0.23, 0.23, 0.23, 1)
            else
                overlay:SetVertexColor(0, 1, 0, 1)
            end
            local unit = barUnit(bar)
            if unit and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                -- This overrides the fallback color when it can determine the live color
                addon.BarsTextures.applyValueBasedColor(bar, unit, overlay, useDark)
            end
            return -- Color already handled (either fallback or value-based)
        -- Kept off addon.ResolveColorRGBA: the mode compare picks the unit-aware opts; the resolver does the color.
        elseif colorMode == "class" then
            local unit = barUnit(bar)
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

    family.styleHealthOverlay = styleHealthOverlay

    -- Create or update the health overlay
    function family.ensureHealthOverlay(bar, cfg)
        if not bar then return end

        local hasCustom = cfg and hasOverlayCustom(cfg)

        local state = ensureState(bar)
        if state then state.overlayActive = hasCustom end

        if not hasCustom then
            if state then
                -- Clear the fingerprint so re-enabling styles fresh
                state.lastAppliedFingerprint = nil
            end
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
                    local cfg = readCfg()
                    local colorMode = cfg and cfg.healthBarColorMode
                    if colorMode == "value" or colorMode == "valueDark" then
                        local useDark = (colorMode == "valueDark")
                        local overlay = st.healthOverlay
                        local unit = barUnit(self)
                        if unit and overlay and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                            addon.BarsTextures.applyValueBasedColor(self, unit, overlay, useDark)
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
                    local cfg = readCfg()
                    local colorMode = cfg and cfg.healthBarColorMode
                    local overlay = st.healthOverlay
                    if colorMode == "value" or colorMode == "valueDark" then
                        local useDark = (colorMode == "valueDark")
                        local unit = barUnit(self)
                        if unit and overlay and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                            addon.BarsTextures.applyValueBasedColor(self, unit, overlay, useDark)
                        end
                    elseif overlay then
                        -- Re-enforce overlay color for non-value modes so Blizzard's
                        -- SetStatusBarColor (from UpdateHealthColor) can't bleed through
                        -- if the fill briefly becomes visible (texture swap gap).
                        local cr, cg, cb, ca = 1, 1, 1, 1
                        -- Kept off addon.ResolveColorRGBA: the mode compare picks the unit-aware opts; the resolver does the color.
                        if colorMode == "class" then
                            local unit = barUnit(self)
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
                    C_Timer.After(0, function()
                        hideBlizzardFill(bar)
                        updateHealthOverlay(bar)
                    end)
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

        -- Dispel rendering is left entirely to Blizzard. In 12.0.5+ the dispel
        -- highlight is rendered by Blizzard_PrivateAurasUI directly into the
        -- parent CompactUnitFrame's render pass at an ARTWORK draw layer that
        -- naturally sits above the BORDER 7 health overlay. As long as Scoot
        -- doesn't perturb the bar's render-queue position via redundant
        -- SetStatusBarTexture writes (see Textures.applyToBar's
        -- ufLastTexturePath cache in textures.lua), Blizzard's highlight
        -- renders correctly above the bar without addon involvement.

        -- Build a config fingerprint to detect whether settings changed.
        -- Prevents expensive re-styling when ApplyStyles() is called but group
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

        -- If config hasn't changed and the overlay is already visible, skip
        -- re-styling. Prevents visual blinking when ApplyStyles() is called for
        -- unrelated settings (e.g., CDM, Action Bars). Don't check GetWidth(),
        -- which can return a secret; with anchor-based sizing a shown overlay is
        -- sized correctly. A hidden overlay with a matching fingerprint falls
        -- through to a full re-style, whose deferred update shows it once the
        -- fill is ready.
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
        C_Timer.After(0.1, function()
            updateHealthOverlay(bar)
        end)
    end

    function family.disableHealthOverlay(bar)
        if not bar then return end
        local state = getState(bar)
        if state then
            state.overlayActive = false
            -- Clear the fingerprint so re-enabling styles fresh, and the
            -- anchored-fill cache so it re-anchors once.
            state.lastAppliedFingerprint = nil
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

    ----------------------------------------------------------------------------
    -- Health Bar Borders
    ----------------------------------------------------------------------------
    -- The square branch is shared: engine-owned edges on the parent
    -- CompactUnitFrame at OVERLAY sublevel -8, below Blizzard's selection
    -- highlight, with live inset sliders and whole-edge hiddenEdges. The
    -- textured branch forks on desc.texturedBorder: "edges" draws caller-owned
    -- edge textures on the CompactUnitFrame (same draw-order rationale as the
    -- square branch); "backdrop" keeps an addon-owned BackdropTemplate anchor
    -- frame with issecretvalue guards. Each branch hides the other's artifacts
    -- on a style switch, and clearHealthBarBorder hides all three kinds.
    ----------------------------------------------------------------------------

    -- Clear health bar border for a single bar
    local function clearHealthBarBorder(bar)
        if not bar then return end
        -- Hide engine-owned square edges on the parent CompactUnitFrame
        local unitFrame = bar.GetParent and bar:GetParent()
        if unitFrame and addon.Borders and addon.Borders.HideAll then
            addon.Borders.HideAll(unitFrame)
        end
        -- Hide caller-owned textured edge textures (stored in family state, not on frame)
        local ufState = unitFrame and getState(unitFrame)
        local edges = ufState and ufState.ScootBorderEdges
        if edges then
            for _, tex in pairs(edges) do
                if tex and tex.Hide then
                    tex:Hide()
                end
            end
        end
        -- Hide the BackdropTemplate anchor frame
        local state = getState(bar)
        if state and state.borderAnchor then
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                addon.BarBorders.ClearBarFrame(state.borderAnchor)
            end
            state.borderAnchor:Hide()
        end
    end

    family.clearHealthBarBorder = clearHealthBarBorder

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
            -- Simple square border via the shared engine: the same call for both
            -- families, so party and raid render identically. Engine edges sit on
            -- the CompactUnitFrame at OVERLAY sublevel -8, below Blizzard's
            -- selection highlight.
            local unitFrame = bar.GetParent and bar:GetParent()
            if not unitFrame then return end

            -- Hide caller-owned textured artifacts from a prior style
            local prevUfState = getState(unitFrame)
            local texturedEdges = prevUfState and prevUfState.ScootBorderEdges
            if texturedEdges then
                for _, tex in pairs(texturedEdges) do
                    if tex and tex.Hide then tex:Hide() end
                end
            end
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

        if texturedBorderMode == "edges" then
            -- Traditional border style with texture: caller-owned edge textures
            -- created directly on the parent CompactUnitFrame (not a child frame)
            -- so layer order is respected with the selection highlight.
            local unitFrame = bar.GetParent and bar:GetParent()
            if not unitFrame then return end

            local style = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
            if not (style and style.texture) then
                -- Unknown style, hide border
                clearHealthBarBorder(bar)
                return
            end

            -- Hide engine-owned square edges from a prior style first.
            if addon.Borders and addon.Borders.HideAll then
                addon.Borders.HideAll(unitFrame)
            end

            -- Create edge textures on the CompactUnitFrame if they don't exist
            -- Use OVERLAY layer with lowest sublevel (-8) to appear above health bar
            -- content but below selection highlight (which uses higher sublevels)
            -- Stored in family state (not on unitFrame) to avoid tainting the system frame.
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

            local edgeSize = math.max(1, math.floor(thickness * 1.35 * (style.thicknessScale or 1) + 0.5))
            local paddingMult = style.paddingMultiplier or 0.5
            local basePad = math.floor(edgeSize * paddingMult + 0.5)
            local padH = basePad - insetH
            local padV = basePad - insetV
            if padH < 0 then padH = 0 end
            if padV < 0 then padV = 0 end
            local texturePath = style.texture

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
            else
                -- Default for texture borders is white (shows texture's natural colors)
                r, g, b, a = 1, 1, 1, 1
            end

            for _, tex in pairs(edges) do
                tex:SetTexture(texturePath)
                tex:SetVertexColor(r, g, b, a)
                tex:Show()
            end

            -- Apply hidden edges
            if hiddenEdges then
                if hiddenEdges.top and edges.Top then edges.Top:Hide() end
                if hiddenEdges.bottom and edges.Bottom then edges.Bottom:Hide() end
                if hiddenEdges.left and edges.Left then edges.Left:Hide() end
                if hiddenEdges.right and edges.Right then edges.Right:Hide() end
            end
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

    family.applyHealthBarBorder = applyHealthBarBorder

    ----------------------------------------------------------------------------
    -- Family-Wide Appliers
    ----------------------------------------------------------------------------

    -- Apply health bar borders to all family frames
    function family.applyHealthBarBorders()
        if isEditModeActive() then return end

        if InCombatLockdown and InCombatLockdown() then
            queueReapply()
            return
        end

        -- Zero-Touch: if no family config exists, don't touch the frames at all
        local cfg = readCfg()
        if not cfg then return end

        -- If no border style set or set to "none", skip - let explicit restore handle cleanup
        local styleKey = cfg.healthBarBorderStyle
        if not styleKey or styleKey == "none" then return end

        desc.forEachUnitFrame(function(frame)
            if frame and frame.healthBar then
                C_Timer.After(0, function()
                    if frame and frame.healthBar then
                        applyHealthBarBorder(frame.healthBar, cfg)
                    end
                end)
            end
        end)
    end

    -- Main entry point: Apply health bar styling from DB settings
    function family.applyHealthBarStyle()
        local cfg = readCfg()
        if not cfg then return end
        if not hasBarCustom(cfg) then return end

        if InCombatLockdown and InCombatLockdown() then
            queueReapply()
            return
        end

        local bars = desc.collectHealthBars()
        for _, bar in ipairs(bars) do
            family.applyToHealthBar(bar, cfg)
        end
        if desc.afterStylePass then
            desc.afterStylePass(bars)
        end
    end

    -- Apply overlays to all family health bars
    function family.applyHealthOverlays()
        -- Zero-Touch: if no family config exists, don't touch the frames at all
        local cfg = readCfg()
        if not cfg then return end

        -- If no custom settings, also skip - let the explicit restore handle cleanup
        if not hasOverlayCustom(cfg) then return end

        desc.forEachHealthBar(function(bar)
            if not (InCombatLockdown and InCombatLockdown()) then
                family.ensureHealthOverlay(bar, cfg)
            else
                local state = getState(bar)
                if state and state.healthOverlay then
                    styleHealthOverlay(bar, cfg)
                    updateHealthOverlay(bar)
                end
            end
        end)
    end

    -- Restore all family health bars to stock appearance
    function family.restoreHealthOverlays()
        desc.forEachHealthBar(function(bar)
            family.disableHealthOverlay(bar)
        end)
    end

    ----------------------------------------------------------------------------
    -- Hook Installation
    ----------------------------------------------------------------------------

    function family.installHooks()
        if addon[desc.hooksInstalledFlag] then return end
        addon[desc.hooksInstalledFlag] = true

        -- Shared body of the UpdateAll and SetUnit hooks: restyle the bar and
        -- make sure its overlay exists after Blizzard's update, deferred one
        -- frame and queued past combat; with rosterRefresh, the border too.
        -- SetUnit clears the fingerprint so a recycled frame styles fresh.
        local function restyleAfterUpdate(frame, cfg, clearFingerprint)
            local bar = frame.healthBar
            if hasBarCustom(cfg) then
                if clearFingerprint then
                    local fpState = getState(bar)
                    if fpState then fpState.lastAppliedFingerprint = nil end
                end
                C_Timer.After(0, function()
                    if InCombatLockdown and InCombatLockdown() then
                        queueReapply()
                        return
                    end
                    module.applyToHealthBar(bar, cfg)
                    -- Also ensure overlay exists (handles a group formed mid-session)
                    module.ensureHealthOverlay(bar, cfg)
                end)
            end

            if rosterRefresh then
                -- Apply borders if configured (independent of the texture/color check)
                local borderStyle = cfg.healthBarBorderStyle
                if borderStyle and borderStyle ~= "none" then
                    C_Timer.After(0, function()
                        if InCombatLockdown and InCombatLockdown() then
                            queueReapply()
                            return
                        end
                        applyHealthBarBorder(bar, cfg)
                    end)
                end
            end
        end

        -- Hook CompactUnitFrame_UpdateAll
        if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
            _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
                -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
                if isEditModeActive() then return end
                if not (frame and frame.healthBar and isTarget(frame)) then return end
                local cfg = readCfg()
                if not cfg then return end
                restyleAfterUpdate(frame, cfg, false)
                -- Re-apply role icons after UpdateAll (handles follower dungeon idle resets)
                if frame.roleIcon and addon._applyCustomRoleIcon then
                    C_Timer.After(0, function()
                        pcall(addon._applyCustomRoleIcon, frame)
                    end)
                end
            end)
        end

        -- Hook CompactUnitFrame_SetUnit
        if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
                if isEditModeActive() then return end
                if not (frame and frame.healthBar and unit and isTarget(frame)) then return end
                local cfg = readCfg()
                if not cfg then return end
                restyleAfterUpdate(frame, cfg, true)
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

                -- Only process this family's frames (not other compact frames or nameplates)
                if not isTarget(frame) then return end

                local cfg = readCfg()
                local colorMode = cfg and cfg.healthBarColorMode
                if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark" and colorMode ~= "class") then return end

                -- Get unit token from the frame
                local unit = frameUnit(frame)
                if not unit then return end

                -- Class color mode: apply class color to overlay
                -- Kept off addon.ResolveColorRGBA: the mode compare routes to the class and value paths, not a resolve.
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
                if not frame or not isTarget(frame) then return end

                local cfg = readCfg()
                if not cfg then return end

                C_Timer.After(0, function()
                    -- Reapply clipping masks (defined in extras.lua, loaded after the family core)
                    if module.ensureHealPredictionClipping then
                        module.ensureHealPredictionClipping(frame)
                    end
                    -- Reapply visibility if toggled
                    if cfg.hideHealPrediction and module.applyHealPredictionVisibility then
                        module.applyHealPredictionVisibility(frame, true)
                    end
                    if cfg.hideAbsorbBars and module.applyAbsorbBarsVisibility then
                        module.applyAbsorbBarsVisibility(frame, true)
                    end
                end)
            end)
        end

        ------------------------------------------------------------------------
        -- Event-Driven Refresh + Periodic Integrity Check
        ------------------------------------------------------------------------
        -- Addresses timing gaps where Blizzard rebuilds the frames (group join,
        -- CVar toggles) but Scoot's deferred hooks haven't fired yet, leaving
        -- frames invisible (Blizzard fill hidden via alpha 0, overlay not yet
        -- created/shown). The ticker verifies overlay visibility, fill alpha,
        -- and role icons every 5 seconds while the family gate holds; with
        -- rosterRefresh, roster events also trigger a debounced full reapply.
        ------------------------------------------------------------------------

        if not addon[desc.integrityFlag] then
            addon[desc.integrityFlag] = true
            local integrityTicker = nil
            local pendingRefreshTimer = nil
            local scheduleFullRefresh = nil

            if rosterRefresh then
                -- Immediate debounced refresh: calls the brute-force appliers
                -- that iterate every possible family frame name.
                scheduleFullRefresh = function()
                    if isEditModeActive() then return end
                    if pendingRefreshTimer then
                        pendingRefreshTimer:Cancel()
                        pendingRefreshTimer = nil
                    end
                    pendingRefreshTimer = C_Timer.NewTimer(0.5, function()
                        pendingRefreshTimer = nil
                        if isEditModeActive() then return end
                        if InCombatLockdown and InCombatLockdown() then
                            queueReapply()
                            return
                        end
                        family.applyHealthOverlays()
                        family.applyHealthBarBorders()
                    end)
                end
            end

            -- Per-frame integrity check
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

                local cfg = readCfg()
                if not cfg then return end

                local hasCustom = hasOverlayCustom(cfg)

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
                                -- Overlay flag set but texture missing - force recreation
                                state.overlayActive = nil
                                state.lastAppliedFingerprint = nil
                                module.ensureHealthOverlay(bar, cfg)
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
                                -- Check 2: Overlay must be visible and anchored. Re-anchor
                                -- to the current fill (catches orphaned anchors): a no-op
                                -- while the fill identity holds, and it shows the overlay
                                -- when the fill exists.
                                updateHealthOverlay(bar)
                                -- Check 3: Revalidate overlay color for value-based modes
                                if isValueMode and overlay and overlay:IsShown() then
                                    local unit = barUnit(bar)
                                    if unit and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                                        addon.BarsTextures.applyValueBasedColor(bar, unit, overlay, useDark)
                                    end
                                end
                            end
                        else
                            -- Overlay not yet created - force creation
                            module.ensureHealthOverlay(bar, cfg)
                        end
                    end
                    -- Check 4: Role icons
                    if addon._applyCustomRoleIcon then
                        pcall(addon._applyCustomRoleIcon, frame)
                    end
                end

                desc.forEachUnitFrame(checkFrame)
            end

            local function onIntegrityEvent()
                if isEditModeActive() then
                    -- Guard is active - schedule a deferred check to detect stuck state.
                    -- 2s delay lets Blizzard state settle after load/group-join transitions.
                    if addon.EditMode and addon.EditMode.ForceResetIfStuck then
                        C_Timer.After(2.0, function()
                            if not isEditModeActive() then return end -- already cleared
                            if not addon.EditMode.ForceResetIfStuck() then return end
                            -- State was stuck; schedule the work that was skipped
                            local inGroup = inGroupGate and inGroupGate()
                            if inGroup then
                                if scheduleFullRefresh then scheduleFullRefresh() end
                                if not integrityTicker then
                                    integrityTicker = C_Timer.NewTicker(5, runIntegrityCheck)
                                end
                            end
                        end)
                    end
                    return
                end
                local inGroup = inGroupGate and inGroupGate()
                if inGroup then
                    if scheduleFullRefresh then scheduleFullRefresh() end
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
            addon.Events.On(desc.eventOwner, "GROUP_ROSTER_UPDATE", onIntegrityEvent)
            addon.Events.On(desc.eventOwner, "PLAYER_ENTERING_WORLD", onIntegrityEvent)
        end
    end

    return family
end

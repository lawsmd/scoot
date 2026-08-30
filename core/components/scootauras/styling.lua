-- scootauras/styling.lua - Apply* styling layer for tracker elements
--
-- Everything in ApplyStyling proper is Tier 1 (Scoot shell/visual only, always
-- legal). Element styling runs inside Engine.ApplyAll behind the structural
-- gate because the elements live under the engine-managed button.
local addonName, addon = ...

local SAU = addon.ScootAuras

local UnitClass = _G.UnitClass
local _, playerClassToken = UnitClass("player")
SAU._playerClassToken = playerClassToken

--------------------------------------------------------------------------------
-- Element styling (gated: called from Engine.ApplyAll only)
--------------------------------------------------------------------------------

local function ApplyIconMode(trackerId, tracker, state)
    local db = SAU.GetDB(trackerId)
    if not db then return end
    local vis = SAU.ResolveVisibility(tracker, db)

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            if not vis.showIcon then
                elem.widget:Hide()
            elseif tracker.shape == "shape" then
                -- Atlas art painted by ApplyShapeStyling below.
                elem.widget:Show()
            else
                -- The engine's SetIcon binding stamps the matched aura's real
                -- icon; this static paint is the pre-match backdrop, drawn as
                -- the Aura List and picker show the spell.
                elem.widget:SetTexture(SAU._SpellIcon(tracker.spellId))
                elem.widget:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                -- Undo any shape-mode tint from a prior binding of this element.
                elem.widget:SetVertexColor(1, 1, 1, 1)
                elem.widget:SetDesaturated(false)
                elem.widget:Show()
            end
        end
    end
end

local function ResolveShapeColor(db)
    local mode = db.shapeColorMode or "class"
    if mode == "class" then
        local classColor = RAID_CLASS_COLORS[playerClassToken]
        if classColor then return classColor.r, classColor.g, classColor.b, 1 end
        return 1, 1, 1, 1
    end
    local c = db.shapeTint or { 1, 1, 1, 1 }
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

-- Picker keys may carry a presentation prefix ("border:CircleMask",
-- "wide:bags-glow-white"); the atlas name is the part after the colon.
local function AtlasFromShapeKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    local prefix, rest = key:match("^(%w+):(.+)$")
    if prefix and rest then return rest end
    return key
end

SAU._AtlasFromShapeKey = AtlasFromShapeKey
-- The underlay's desaturated-shape variant grays this resolved tint.
SAU._ResolveShapeColor = ResolveShapeColor

local function ApplyShapeStyling(trackerId, tracker, state)
    if tracker.shape ~= "shape" then
        for _, elem in ipairs(state.elements or {}) do
            if elem.type == "texture" and elem.silhouette then
                elem.silhouette:Hide()
            end
            if elem.type == "cooldown" then
                pcall(elem.widget.SetDrawSwipe, elem.widget, false)
            end
        end
        return
    end
    local db = SAU.GetDB(trackerId)
    if not db then return end

    -- The silhouette parents to the engine button so it hides with the aura;
    -- this function only runs inside the structural gate (Engine.ApplyAll).
    local button = state.entry and state.entry.button
    local atlas = AtlasFromShapeKey(db.shapeStyle) or "SquareMask"
    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            elem.widget:SetTexCoord(0, 1, 0, 1)
            local ok = pcall(elem.widget.SetAtlas, elem.widget, atlas)
            if ok then
                elem.widget:SetVertexColor(ResolveShapeColor(db))
                elem.widget:SetDesaturated(false)
            end
            -- Same-atlas black silhouette one pixel proud behind the shape, so
            -- the art reads against any background.
            if not elem.silhouette and button then
                local sil = button:CreateTexture(nil, "ARTWORK", nil, -1)
                elem.silhouette = sil
            end
            if not elem.silhouette then
                return
            end
            local sil = elem.silhouette
            local sok = pcall(sil.SetAtlas, sil, atlas)
            if sok then
                sil:SetDesaturated(true)
                sil:SetVertexColor(0, 0, 0, 1)
                sil:ClearAllPoints()
                sil:SetPoint("TOPLEFT", elem.widget, "TOPLEFT", -1, 1)
                sil:SetPoint("BOTTOMRIGHT", elem.widget, "BOTTOMRIGHT", 1, -1)
                sil:Show()
            else
                sil:Hide()
            end
        end
    end

    -- Shaped drain swipe: the same atlas resolved to its file and texcoords,
    -- so the Cooldown's swipe is clipped to the glyph instead of a square.
    local texElem
    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then texElem = elem end
    end
    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "cooldown" then
            local cd = elem.widget
            if db.shapeShowDrain ~= false then
                if texElem then
                    pcall(cd.ClearAllPoints, cd)
                    pcall(cd.SetAllPoints, cd, texElem.widget)
                end
                pcall(cd.SetDrawSwipe, cd, true)
                pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.6)
                local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
                if info and (info.file or info.filename) then
                    pcall(cd.SetSwipeTexture, cd, info.file or info.filename)
                    pcall(cd.SetTexCoordRange, cd,
                        { x = info.leftTexCoord, y = info.topTexCoord },
                        { x = info.rightTexCoord, y = info.bottomTexCoord })
                end
            else
                pcall(cd.SetDrawSwipe, cd, false)
            end
        end
    end
end

local function ApplyTextStyling(trackerId, tracker, state)
    local db = SAU.GetDB(trackerId)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "text" then
            local source = elem.def.source
            local fontKey, fontStyle, size, color
            if source == "name" then
                fontKey = db.nameTextFont
                fontStyle = db.nameTextStyle
                size = db.nameTextSize or elem.def.baseSize or 10
                color = db.nameTextColor
            elseif source == "applications" then
                fontKey = db.stackTextFont
                fontStyle = db.stackTextStyle
                size = db.stackTextSize or elem.def.baseSize or 14
                color = db.stackTextColor
            else
                fontKey = db.textFont
                fontStyle = db.textStyle
                size = db.textSize or elem.def.baseSize or 24
                color = db.textColor
            end
            -- No local fallback: these keys register ROBOTO_SEMICOND_BLACK as
            -- their default and the component DB resolves it, so substituting
            -- FRIZQT__ here would only reintroduce the fresh-profile mismatch
            -- between what the settings panel shows and what the HUD renders.
            local fontFace = addon.ResolveFontFace(fontKey)
            addon.ApplyFontStyle(elem.widget, fontFace, size, fontStyle or "OUTLINE")

            if color and type(color) == "table" then
                elem.widget:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
            end
        end
    end
end

local function ApplyBorders(trackerId, tracker, state)
    local db = SAU.GetDB(trackerId)
    if not db then return end
    -- Borders apply to the spell-icon texture only; shape art carries its own
    -- silhouette edge.
    local wantBorder = (tracker.shape ~= "shape")

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" and elem.borderFrame then
            local style = db.borderStyle or "none"
            local bf = elem.borderFrame
            bf:ClearAllPoints()
            bf:SetAllPoints(elem.widget)

            if not wantBorder or style == "none" then
                if addon.Borders and addon.Borders.HideAll then
                    addon.Borders.HideAll(bf)
                end
                bf:Hide()
            else
                bf:Show()
                local insetH = tonumber(db.borderInsetH) or 0
                local insetV = tonumber(db.borderInsetV) or 0

                -- This dispatcher's square branch has always been outward-positive;
                -- the shared dispatcher is inward-positive, so square styles negate.
                -- Atlas styles were inward-positive here already.
                local styleDef = addon.IconBorders and addon.IconBorders.GetStyle and addon.IconBorders.GetStyle(style)
                if not styleDef or styleDef.type == "square" then
                    insetH, insetV = -insetH, -insetV
                end

                local tinted = (db.borderTintEnable and db.borderTintColor) and true or false

                addon.ApplyIconBorderStyle(bf, style, {
                    thickness = db.borderThickness,
                    insetH = insetH,
                    insetV = insetV,
                    tintEnabled = tinted,
                    color = tinted and db.borderTintColor or nil,
                    simpleTint = true,
                    styleAdjusts = true,
                    expandClamp = 12,
                })
            end
        end
    end
end

local function ApplyBarStyling(trackerId, tracker, state)
    local db = SAU.GetDB(trackerId)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "bar" then
            local w = tonumber(db.barWidth) or 120
            local h = tonumber(db.barHeight) or 12
            elem.widget:SetSize(w, h)

            local fgPath = addon.Media.ResolveBarTexturePath(db.barForegroundTexture or "bevelled")
            if fgPath then
                elem.barFill:SetStatusBarTexture(fgPath)
            else
                elem.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            end

            local fgColorMode = db.barForegroundColorMode or "class"
            local fgR, fgG, fgB, fgA = 1, 1, 1, 1
            if fgColorMode == "class" then
                local classColor = RAID_CLASS_COLORS[playerClassToken]
                if classColor then
                    fgR, fgG, fgB, fgA = classColor.r, classColor.g, classColor.b, 1
                end
            elseif fgColorMode == "custom" then
                local c = db.barForegroundTint or { 1, 1, 1, 1 }
                fgR, fgG, fgB, fgA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end
            local fillTex = elem.barFill:GetStatusBarTexture()
            if fillTex then
                fillTex:SetVertexColor(fgR, fgG, fgB, fgA)
            end
            -- Fill-mode cadence overlay: same art as the fill (BindForMode
            -- shows/hides it).
            if elem.lockOverlay then
                if fgPath then
                    elem.lockOverlay:SetTexture(fgPath)
                else
                    elem.lockOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
                end
                elem.lockOverlay:SetVertexColor(fgR, fgG, fgB, fgA)
            end

            local bgPath = addon.Media.ResolveBarTexturePath(db.barBackgroundTexture or "bevelled")
            if bgPath then
                elem.barBg:SetTexture(bgPath)
            else
                elem.barBg:SetColorTexture(0.1, 0.1, 0.1, 1)
            end
            if (db.barBackgroundColorMode or "custom") == "original" then
                elem.barBg:SetVertexColor(1, 1, 1, 1)
            else
                local c = db.barBackgroundTint or { 0, 0, 0, 1 }
                elem.barBg:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
            end
            elem.barBg:SetAlpha((db.barBackgroundOpacity or 50) / 100)

            local borderStyle = db.barBorderStyle or "none"
            local borderThickness = math.max(1, tonumber(db.barBorderThickness) or 1)
            local borderInsetH = tonumber(db.barBorderInsetH) or 0
            local borderInsetV = tonumber(db.barBorderInsetV) or 0
            local hiddenEdges = db.barBorderHiddenEdges
            if type(hiddenEdges) ~= "table" then hiddenEdges = nil end
            local borderColor = { 0, 0, 0, 1 }
            if db.barBorderTintEnable and db.barBorderTintColor then
                borderColor = db.barBorderTintColor
            end
            if borderStyle == "square" then
                if addon.BarBorders then
                    addon.BarBorders.ClearBarFrame(elem.barFill)
                end
                -- Edges live in a container parented to the widget, above it:
                -- the cadence clip frame must not own them, or the lock would
                -- clip the border too.
                addon.Borders.ApplySquare(elem.widget, {
                    size = borderThickness,
                    color = borderColor,
                    layer = "OVERLAY",
                    layerSublevel = 1,
                    levelOffset = 2,
                    containerParent = elem.widget,
                    expandX = borderInsetH,
                    expandY = borderInsetV,
                    hiddenEdges = hiddenEdges,
                    skipDimensionCheck = true,
                })

            elseif borderStyle ~= "none" and addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                addon.Borders.HideAll(elem.widget)
                addon.BarBorders.ApplyToBarFrame(elem.barFill, borderStyle, {
                    thickness = borderThickness,
                    insetH = borderInsetH,
                    insetV = borderInsetV,
                    color = borderColor,
                    hiddenEdges = hiddenEdges,
                    -- barFill lives inside the cadence clip frame; the border
                    -- holder must not, or the lock would clip the border too.
                    containerParent = elem.widget,
                    sizeProxyParent = elem.widget,
                })
            else
                addon.Borders.HideAll(elem.widget)
                if addon.BarBorders then
                    addon.BarBorders.ClearBarFrame(elem.barFill)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The combat gate
--------------------------------------------------------------------------------

-- Kinds whose "Only in Combat" verdict is applied by hiding the whole frame.
-- A missing-buff reminder is not one of them: its own gate drives a clip window
-- over the engine-sized container (missing.lua, Missing.UpdateGate), and that
-- mechanism stays its sole owner.
local SHELL_GATED_KINDS = { buff = true, debuff = true }

-- Grouped visuals live under the group frame; the shell stays hidden and
-- scale/opacity/shown apply to the visual itself. The flag is physical (set by
-- the parenting reconcile), so a membership change still waiting on the
-- structural gate keeps styling the current home.
local function StyleTarget(state)
    local entry = state.entry
    local grouped = entry and entry.grouped
    return (grouped and state.container or state.shell), grouped
end

-- Whether this tracker's frame may be shown right now. Both frames are plain
-- Scoot frames, so hiding one is legal in combat and takes the container, the
-- button and every element with it.
local function ShellShown(tracker)
    if not SHELL_GATED_KINDS[tracker.kind] then return true end
    return SAU.CombatGateOpen(tracker)
end

--------------------------------------------------------------------------------
-- Tier 1 entry
--------------------------------------------------------------------------------

-- Shell/visual state only: enabled, scale, opacity, shown. Element work runs
-- through Engine.ApplyAll, which gates and queues itself.
local function ApplyStyling(trackerId, tracker)
    local state = SAU._activeStates[trackerId]
    if not state or not state.shell then return end

    local db = SAU.GetDB(trackerId)

    local target, grouped = StyleTarget(state)

    local isEnabled = SAU.IsTrackerActive(trackerId, tracker) and SAU.IsModuleActive()
    if not isEnabled then
        SAU.Engine.SetEnabledState(trackerId, false)
        target:Hide()
        -- A tracker switched off, or gated out by its spec (or its group's),
        -- keeps no Edit Mode preview and no ticking animation record.
        SAU.Engine.HideEditModePreview(state)
        if tracker.kind == "missingbuff" and SAU.Missing then
            SAU.Missing.UpdateGate(trackerId)
        end
        -- Also stops a running blink; the Hide above already conceals it.
        if SAU.Underlay then SAU.Underlay.UpdateGate(trackerId) end
        if grouped and SAU.Groups then SAU.Groups.RequestReflow() end
        return
    end

    local scale = ((db and db.scale) or 100) / 100
    target:SetScale(math.max(scale, 0.25))

    local opacityValue
    if InCombatLockdown() then
        opacityValue = tonumber(db and db.opacityInCombat) or 100
    elseif UnitExists("target") then
        opacityValue = tonumber(db and db.opacityWithTarget) or 100
    else
        opacityValue = tonumber(db and db.opacityOutOfCombat) or 100
    end
    target:SetAlpha(opacityValue / 100)

    -- A tracker set to "Only in Combat" is hidden outright out of combat. Edit
    -- Mode forces it back: the preview and the draggable frame live under this
    -- one, and the group layout skips a member the gate hid.
    target:SetShown(ShellShown(tracker))
    if grouped then
        state.shell:Hide()
        if SAU.Groups then SAU.Groups.RequestReflow() end
    end
    SAU.Engine.SetEnabledState(trackerId, true)
    -- Missing-buff reminder: the visible set is Scoot-owned, so its styling,
    -- layout, combat gate and blink apply here, outside the structural gate;
    -- ApplyAll only carries the gate container build. Any other kind on an
    -- entry that once hosted a reminder hides it (UpdateGate is a no-op when
    -- the entry never built one).
    if SAU.Missing then
        if tracker.kind == "missingbuff" then
            SAU.Missing.Restyle(trackerId, tracker, state)
        else
            SAU.Missing.UpdateGate(trackerId)
        end
    end
    -- Missing-state underlay (underlay.lua): Scoot-owned art on the visual,
    -- so it repaints here even while ApplyAll queues behind the structural
    -- gate. Runs for every kind so a stale underlay hides on a kind flip.
    if SAU.Underlay then
        SAU.Underlay.Sync(trackerId, tracker, state)
    end
    SAU.Engine.ApplyAll(trackerId)
    -- Restyles while Edit Mode is open (late claims from reconcile, enable
    -- flips, group flushes) repaint the preview. The exit callback clears the
    -- flag before its restyle loop, so this cannot re-show on the way out.
    if SAU._isEditModeActive and SAU._isEditModeActive() then
        SAU.Engine.ShowEditModePreview(trackerId, tracker, state)
    end
end

--- Both regen edges, Edit Mode enter, and the events.lua poll: re-apply the
-- combat gate for every live tracker carrying it. Deliberately narrower than a
-- restyle. Nothing else moved at a combat edge, and a restyle would run the
-- whole element chain per tracker on every pull. The poll exists because a
-- 2026-08-29 in-combat dump caught an Only-in-Combat shell still hidden with
-- every gate input reading true: the regen edge alone does not land reliably.
-- A converged pass changes nothing, so the poll cost is a few plain reads.
function SAU.RefreshCombatGates()
    local reflow = false
    for trackerId, state in pairs(SAU._activeStates) do
        local tracker = SAU.GetTracker(trackerId)
        if tracker and SHELL_GATED_KINDS[tracker.kind] and SAU.OnlyInCombat(tracker)
            and state.shell
            and SAU.IsTrackerActive(trackerId, tracker)
            and SAU.IsModuleActive() then
            local target, grouped = StyleTarget(state)
            local shown = SAU.CombatGateOpen(tracker)
            if target and target:IsShown() ~= shown then
                target:SetShown(shown)
                if grouped then reflow = true end
                -- A hidden container runs no OnUpdate, so one re-shown at
                -- the pull has processed nothing since it was gated off.
                if shown then SAU.Engine.KickTracker(trackerId, "combat-gate") end
            end
        end
    end
    -- Reflowed now, not queued: the deferred reflow lands a frame later, which
    -- would show a returning member at the anchor it held before its group
    -- closed the gap. Group layout is plain frame math and legal in combat.
    if reflow and SAU.Groups then SAU.Groups.ReflowAll() end
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

SAU._ApplyStyling = ApplyStyling
SAU._ApplyIconMode = ApplyIconMode
SAU._ApplyShapeStyling = ApplyShapeStyling
SAU._ApplyTextStyling = ApplyTextStyling
SAU._ApplyBorders = ApplyBorders
SAU._ApplyBarStyling = ApplyBarStyling

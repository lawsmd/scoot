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
            local fontFace = addon.ResolveFontFace(fontKey or "FRIZQT__")
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
                for _, tex in pairs(bf.borderEdges) do tex:Hide() end
                bf.atlasBorder:Hide()
                bf:Hide()
            else
                bf:Show()
                local thickness = math.max(1, tonumber(db.borderThickness) or 1)
                local insetH = tonumber(db.borderInsetH) or 0
                local insetV = tonumber(db.borderInsetV) or 0
                local color = db.borderTintEnable and db.borderTintColor or { 0, 0, 0, 1 }

                local styleDef = nil
                if style ~= "square" and addon.IconBorders and addon.IconBorders.GetStyle then
                    styleDef = addon.IconBorders.GetStyle(style)
                end

                if styleDef and styleDef.type == "atlas" and styleDef.atlas then
                    for _, tex in pairs(bf.borderEdges) do tex:Hide() end
                    local atlasTex = bf.atlasBorder
                    local col = db.borderTintEnable and db.borderTintColor or styleDef.defaultColor or { 1, 1, 1, 1 }
                    atlasTex:SetAtlas(styleDef.atlas, true)
                    atlasTex:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
                    local expandX = (styleDef.expandX or 0) - insetH
                    local expandY = (styleDef.expandY or styleDef.expandX or 0) - insetV
                    atlasTex:ClearAllPoints()
                    atlasTex:SetPoint("TOPLEFT", bf, "TOPLEFT", -expandX - (styleDef.adjustLeft or 0), expandY + (styleDef.adjustTop or 0))
                    atlasTex:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", expandX + (styleDef.adjustRight or 0), -expandY - (styleDef.adjustBottom or 0))
                    atlasTex:Show()
                else
                    bf.atlasBorder:Hide()
                    local edges = bf.borderEdges
                    local r, g, b, a = color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1
                    for _, tex in pairs(edges) do tex:SetColorTexture(r, g, b, a) end

                    edges.Top:ClearAllPoints()
                    edges.Top:SetPoint("TOPLEFT", bf, "TOPLEFT", -insetH, insetV)
                    edges.Top:SetPoint("TOPRIGHT", bf, "TOPRIGHT", insetH, insetV)
                    edges.Top:SetHeight(thickness)

                    edges.Bottom:ClearAllPoints()
                    edges.Bottom:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", -insetH, -insetV)
                    edges.Bottom:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", insetH, -insetV)
                    edges.Bottom:SetHeight(thickness)

                    edges.Left:ClearAllPoints()
                    edges.Left:SetPoint("TOPLEFT", bf, "TOPLEFT", -insetH, insetV - thickness)
                    edges.Left:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", -insetH, -insetV + thickness)
                    edges.Left:SetWidth(thickness)

                    edges.Right:ClearAllPoints()
                    edges.Right:SetPoint("TOPRIGHT", bf, "TOPRIGHT", insetH, insetV - thickness)
                    edges.Right:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", insetH, -insetV + thickness)
                    edges.Right:SetWidth(thickness)

                    for _, tex in pairs(edges) do tex:Show() end
                end
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
            local bR, bG, bB, bA = borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1

            if borderStyle == "square" then
                if addon.BarBorders then
                    addon.BarBorders.ClearBarFrame(elem.barFill)
                end
                if not elem.squareBorder then
                    local bf = CreateFrame("Frame", nil, elem.widget)
                    bf:SetFrameLevel(elem.widget:GetFrameLevel() + 2)
                    bf.edges = {
                        Top = bf:CreateTexture(nil, "OVERLAY", nil, 1),
                        Bottom = bf:CreateTexture(nil, "OVERLAY", nil, 1),
                        Left = bf:CreateTexture(nil, "OVERLAY", nil, 1),
                        Right = bf:CreateTexture(nil, "OVERLAY", nil, 1),
                    }
                    elem.squareBorder = bf
                end

                local bf = elem.squareBorder
                bf:ClearAllPoints()
                bf:SetAllPoints(elem.widget)
                bf:Show()

                local edges = bf.edges
                for _, tex in pairs(edges) do tex:SetColorTexture(bR, bG, bB, bA) end

                edges.Top:ClearAllPoints()
                edges.Top:SetPoint("TOPLEFT", bf, "TOPLEFT", -borderInsetH, borderInsetV)
                edges.Top:SetPoint("TOPRIGHT", bf, "TOPRIGHT", borderInsetH, borderInsetV)
                edges.Top:SetHeight(borderThickness)

                edges.Bottom:ClearAllPoints()
                edges.Bottom:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", -borderInsetH, -borderInsetV)
                edges.Bottom:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", borderInsetH, -borderInsetV)
                edges.Bottom:SetHeight(borderThickness)

                edges.Left:ClearAllPoints()
                edges.Left:SetPoint("TOPLEFT", bf, "TOPLEFT", -borderInsetH, borderInsetV - borderThickness)
                edges.Left:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", -borderInsetH, -borderInsetV + borderThickness)
                edges.Left:SetWidth(borderThickness)

                edges.Right:ClearAllPoints()
                edges.Right:SetPoint("TOPRIGHT", bf, "TOPRIGHT", borderInsetH, borderInsetV - borderThickness)
                edges.Right:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", borderInsetH, -borderInsetV + borderThickness)
                edges.Right:SetWidth(borderThickness)

                for _, tex in pairs(edges) do tex:Show() end

                if hiddenEdges then
                    if hiddenEdges.top then edges.Top:Hide() end
                    if hiddenEdges.bottom then edges.Bottom:Hide() end
                    if hiddenEdges.left then edges.Left:Hide() end
                    if hiddenEdges.right then edges.Right:Hide() end
                end

            elseif borderStyle ~= "none" and addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                if elem.squareBorder then
                    for _, tex in pairs(elem.squareBorder.edges) do tex:Hide() end
                    elem.squareBorder:Hide()
                end
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
                if elem.squareBorder then
                    for _, tex in pairs(elem.squareBorder.edges) do tex:Hide() end
                    elem.squareBorder:Hide()
                end
                if addon.BarBorders then
                    addon.BarBorders.ClearBarFrame(elem.barFill)
                end
            end
        end
    end
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

    -- Grouped visuals live under the group frame; the shell stays hidden and
    -- scale/opacity/shown apply to the visual itself. The flag is physical
    -- (set by the parenting reconcile), so a membership change still waiting
    -- on the structural gate keeps styling the current home.
    local entry = state.entry
    local grouped = entry and entry.grouped
    local target = grouped and state.container or state.shell

    local isEnabled = tracker.enabled and SAU.IsModuleActive()
    if not isEnabled then
        SAU.Engine.SetEnabledState(trackerId, false)
        target:Hide()
        -- A disabled tracker keeps no Edit Mode preview (and no ticking
        -- animation record).
        SAU.Engine.HideEditModePreview(state)
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

    target:Show()
    if grouped then
        state.shell:Hide()
        if SAU.Groups then SAU.Groups.RequestReflow() end
    end
    SAU.Engine.SetEnabledState(trackerId, true)
    SAU.Engine.ApplyAll(trackerId)
    -- Restyles while Edit Mode is open (late claims from reconcile, enable
    -- flips, group flushes) repaint the preview. The exit callback clears the
    -- flag before its restyle loop, so this cannot re-show on the way out.
    if SAU._isEditModeActive and SAU._isEditModeActive() then
        SAU.Engine.ShowEditModePreview(trackerId, tracker, state)
    end
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

-- classauras/styling.lua - All Apply* functions: icon mode, text, shape, borders, bars, anchor linkage
local addonName, addon = ...

local CA = addon.ClassAuras

-- Local aliases (resolved at load time — core.lua and layout.lua load first)
local GetDB = CA._GetDB
local playerClassToken = CA._playerClassToken

--------------------------------------------------------------------------------
-- Styling
--------------------------------------------------------------------------------

local function ApplyIconMode(aura, state)
    local db = GetDB(aura)
    if not db then return end
    if aura.customIconHandling then return end

    -- Check if icon should be hidden by display mode
    local displayMode = db.mode or "icon"
    local showIcon = (displayMode == "icon" or displayMode == "iconbar")

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            if not showIcon or mode == "hidden" then
                elem.widget:Hide()
            elseif mode == "custom" then
                if elem.def.customPath then elem.widget:SetTexture(elem.def.customPath) end
                elem.widget:Show()
            else
                -- "default": the engine's SetIcon binding stamps the matched
                -- aura's real icon; this static paint is the pre-match backdrop.
                local ok, tex = pcall(function()
                    return C_Spell.GetSpellTexture(aura.auraSpellId)
                end)
                if ok and tex and not issecretvalue(tex) then
                    elem.widget:SetTexture(tex)
                elseif elem.def.customPath then
                    elem.widget:SetTexture(elem.def.customPath)
                end
                elem.widget:Show()
            end
        end
    end
end

local function ApplyTextStyling(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "text" then
            local isName = (elem.def.source == "name")
            local fontKey = (isName and db.nameTextFont or db.textFont) or "FRIZQT__"
            local fontFace = addon.ResolveFontFace(fontKey)
            local fontStyle = (isName and db.nameTextStyle or db.textStyle) or "OUTLINE"
            local size
            if isName then
                size = db.nameTextSize or elem.def.baseSize or 10
            else
                size = db.textSize or elem.def.baseSize or 24
            end
            addon.ApplyFontStyle(elem.widget, fontFace, size, fontStyle)

            local color = isName and db.nameTextColor or db.textColor
            if color and type(color) == "table" then
                elem.widget:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
            end
        end
    end
end

local function ApplyIconShape(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            local baseW = elem.def.defaultSize and elem.def.defaultSize[1] or 32
            local baseH = elem.def.defaultSize and elem.def.defaultSize[2] or 32
            if mode == "default" then
                local ratio = tonumber(db.iconShape) or 0
                if ratio ~= 0 and addon.IconRatio and addon.IconRatio.CalculateDimensions then
                    local w, h = addon.IconRatio.CalculateDimensions(baseW, ratio)
                    elem.widget:SetSize(w, h)
                else
                    elem.widget:SetSize(baseW, baseH)
                end
            else
                elem.widget:SetSize(baseW, baseH)
            end
        end
    end
end

local function ApplyBorders(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            local style = db.borderStyle or "none"

            -- Ensure border frame exists (parented to container, anchored to texture)
            if not elem.borderFrame then
                elem.borderFrame = CreateFrame("Frame", nil, state.container)
                elem.borderFrame:SetFrameLevel(state.container:GetFrameLevel() + 2)
                elem.borderFrame.borderEdges = {
                    Top = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Bottom = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Left = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Right = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                }
                for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                elem.borderFrame.atlasBorder = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 2)
                elem.borderFrame.atlasBorder:Hide()
            end

            -- Anchor border frame to texture widget
            elem.borderFrame:ClearAllPoints()
            elem.borderFrame:SetAllPoints(elem.widget)

            if mode ~= "default" or style == "none" then
                for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                elem.borderFrame.atlasBorder:Hide()
                elem.borderFrame:Hide()
            else
                elem.borderFrame:Show()
                local opts = {
                    style = style,
                    thickness = tonumber(db.borderThickness) or 1,
                    insetH = tonumber(db.borderInsetH) or 0,
                    insetV = tonumber(db.borderInsetV) or 0,
                    color = db.borderTintEnable and db.borderTintColor or {0, 0, 0, 1},
                    tintEnabled = db.borderTintEnable,
                    tintColor = db.borderTintColor,
                }

                local styleDef = nil
                if style ~= "square" and addon.IconBorders and addon.IconBorders.GetStyle then
                    styleDef = addon.IconBorders.GetStyle(style)
                end

                if styleDef and styleDef.type == "atlas" and styleDef.atlas then
                    -- Atlas border
                    for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                    local atlasTex = elem.borderFrame.atlasBorder
                    local col = opts.tintEnabled and opts.tintColor or styleDef.defaultColor or {1, 1, 1, 1}
                    atlasTex:SetAtlas(styleDef.atlas, true)
                    atlasTex:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
                    local expandX = (styleDef.expandX or 0) - opts.insetH
                    local expandY = (styleDef.expandY or styleDef.expandX or 0) - opts.insetV
                    atlasTex:ClearAllPoints()
                    atlasTex:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -expandX - (styleDef.adjustLeft or 0), expandY + (styleDef.adjustTop or 0))
                    atlasTex:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", expandX + (styleDef.adjustRight or 0), -expandY - (styleDef.adjustBottom or 0))
                    atlasTex:Show()
                else
                    -- Square border
                    elem.borderFrame.atlasBorder:Hide()
                    local edges = elem.borderFrame.borderEdges
                    local thickness = math.max(1, opts.thickness)
                    local col = opts.color
                    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1
                    for _, tex in pairs(edges) do tex:SetColorTexture(r, g, b, a) end

                    edges.Top:ClearAllPoints()
                    edges.Top:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -opts.insetH, opts.insetV)
                    edges.Top:SetPoint("TOPRIGHT", elem.borderFrame, "TOPRIGHT", opts.insetH, opts.insetV)
                    edges.Top:SetHeight(thickness)

                    edges.Bottom:ClearAllPoints()
                    edges.Bottom:SetPoint("BOTTOMLEFT", elem.borderFrame, "BOTTOMLEFT", -opts.insetH, -opts.insetV)
                    edges.Bottom:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", opts.insetH, -opts.insetV)
                    edges.Bottom:SetHeight(thickness)

                    edges.Left:ClearAllPoints()
                    edges.Left:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -opts.insetH, opts.insetV - thickness)
                    edges.Left:SetPoint("BOTTOMLEFT", elem.borderFrame, "BOTTOMLEFT", -opts.insetH, -opts.insetV + thickness)
                    edges.Left:SetWidth(thickness)

                    edges.Right:ClearAllPoints()
                    edges.Right:SetPoint("TOPRIGHT", elem.borderFrame, "TOPRIGHT", opts.insetH, opts.insetV - thickness)
                    edges.Right:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", opts.insetH, -opts.insetV + thickness)
                    edges.Right:SetWidth(thickness)

                    for _, tex in pairs(edges) do tex:Show() end
                end
            end
        end
    end
end

local function ApplyBarStyling(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "bar" then
            -- Dimensions
            local w = tonumber(db.barWidth) or 120
            local h = tonumber(db.barHeight) or 12
            elem.widget:SetSize(w, h)

            -- Foreground texture
            local fgTexKey = db.barForegroundTexture or "bevelled"
            local fgPath = addon.Media.ResolveBarTexturePath(fgTexKey)
            if fgPath then
                elem.barFill:SetStatusBarTexture(fgPath)
            else
                elem.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            end

            -- Foreground color
            local fgColorMode = db.barForegroundColorMode or "custom"
            local fgR, fgG, fgB, fgA = 1, 1, 1, 1
            if fgColorMode == "original" then
                fgR, fgG, fgB, fgA = 1, 1, 1, 1  -- no tint, show texture's native color
            elseif fgColorMode == "class" then
                local classColor = RAID_CLASS_COLORS[playerClassToken]
                if classColor then
                    fgR, fgG, fgB, fgA = classColor.r, classColor.g, classColor.b, 1
                end
            else -- "custom" (or any fallback)
                local c = db.barForegroundTint or aura.defaultBarColor or { 1, 1, 1, 1 }
                fgR, fgG, fgB, fgA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end
            local fillTex = elem.barFill:GetStatusBarTexture()
            if fillTex then
                fillTex:SetVertexColor(fgR, fgG, fgB, fgA)
            end

            -- Background texture
            local bgTexKey = db.barBackgroundTexture or "bevelled"
            local bgPath = addon.Media.ResolveBarTexturePath(bgTexKey)
            if bgPath then
                elem.barBg:SetTexture(bgPath)
            else
                elem.barBg:SetColorTexture(0.1, 0.1, 0.1, 1)
            end

            -- Background color
            local bgColorMode = db.barBackgroundColorMode or "custom"
            if bgColorMode == "original" then
                elem.barBg:SetVertexColor(1, 1, 1, 1)
            else -- "custom"
                local c = db.barBackgroundTint or { 0, 0, 0, 1 }
                elem.barBg:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
            end

            -- Background opacity
            elem.barBg:SetAlpha((db.barBackgroundOpacity or 50) / 100)

            -- Border
            local borderStyle = db.barBorderStyle or "none"
            local borderThickness = math.max(1, tonumber(db.barBorderThickness) or 1)
            local borderInsetH = tonumber(db.barBorderInsetH) or 0
            local borderInsetV = tonumber(db.barBorderInsetV) or 0
            local hiddenEdges = db.barBorderHiddenEdges
            local borderColor = { 0, 0, 0, 1 }
            if db.barBorderTintEnable and db.barBorderTintColor then
                borderColor = db.barBorderTintColor
            end
            local bR, bG, bB, bA = borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1

            if borderStyle == "square" then
                -- Square border: draw edge textures ourselves (BarBorders.ApplyToBarFrame
                -- treats "square" as a clear since it's not a backdrop-template style)
                if addon.BarBorders then
                    addon.BarBorders.ClearBarFrame(elem.barFill)
                end

                -- Ensure edge textures exist on the bar region
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
                    if hiddenEdges.top and edges.Top then edges.Top:Hide() end
                    if hiddenEdges.bottom and edges.Bottom then edges.Bottom:Hide() end
                    if hiddenEdges.left and edges.Left then edges.Left:Hide() end
                    if hiddenEdges.right and edges.Right then edges.Right:Hide() end
                end

            elseif borderStyle ~= "none" and addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                -- Custom asset border via BarBorders module
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
                })
            else
                -- "none": clear everything
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

local function ApplyAnchorLinkage(aura, state)
    if not aura.anchorTo then return end
    local primaryState = CA._activeAuras[aura.anchorTo]
    if not primaryState or not primaryState.container then return end
    -- Read orientation/padding from the primary aura's DB
    local primaryAura = CA._registry[aura.anchorTo]
    local primaryDb = primaryAura and GetDB(primaryAura)
    local orientation = (primaryDb and primaryDb.dotOrientation) or "horizontal"
    local padding = tonumber(primaryDb and primaryDb.dotPadding) or 4
    state.container:ClearAllPoints()
    if orientation == "vertical" then
        state.container:SetPoint("BOTTOM", primaryState.container, "TOP", 0, padding)
    else
        state.container:SetPoint("RIGHT", primaryState.container, "LEFT", -padding, 0)
    end
end

-- Everything here is Tier 1 (Scoot frame only, always legal). Content lives
-- under the engine-managed button and may only be built/styled outside
-- secrecy windows; Engine.ApplyAll gates and queues itself.
local function ApplyStyling(aura)
    local state = CA._activeAuras[aura.id]
    if not state then return end

    local db = GetDB(aura)
    if not db then return end

    -- CDM borrow: rescan on enable/disable to hide/restore CDM icon
    if aura.cdmBorrow then
        C_Timer.After(0, function() CA._RescanForCDMBorrow() end)
    end

    -- Enabled check (for linked auras, check primary's enabled state)
    local isEnabled = db.enabled
    if not isEnabled and aura.anchorTo then
        local primaryAura = CA._registry[aura.anchorTo]
        local primaryDb = primaryAura and GetDB(primaryAura)
        isEnabled = primaryDb and primaryDb.enabled
    end
    if not isEnabled then
        CA.Engine.SetEnabledState(aura, false)
        state.container:Hide()
        return
    end

    -- Scale
    local scale = (db.scale or 100) / 100
    state.container:SetScale(math.max(scale, 0.25))

    -- Opacity (priority: combat > target > out-of-combat)
    local opacityValue = 100
    if InCombatLockdown() then
        opacityValue = tonumber(db.opacityInCombat) or 100
    elseif UnitExists("target") then
        opacityValue = tonumber(db.opacityWithTarget) or 100
    else
        opacityValue = tonumber(db.opacityOutOfCombat) or 100
    end
    state.container:SetAlpha(opacityValue / 100)

    state.container:Show()
    CA.Engine.ApplyAll(aura)
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

CA._ApplyStyling = ApplyStyling
CA._ApplyIconMode = ApplyIconMode
CA._ApplyIconShape = ApplyIconShape
CA._ApplyBorders = ApplyBorders
CA._ApplyTextStyling = ApplyTextStyling
CA._ApplyBarStyling = ApplyBarStyling
CA._ApplyAnchorLinkage = ApplyAnchorLinkage

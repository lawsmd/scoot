local addonName, addon = ...

local getState = addon.ComponentsUtil._getState

local Util = addon.ComponentsUtil

local function getIconBorderContainer(frame)
    local st = getState(frame)
    return st and st.ScootIconBorderContainer or nil
end

local function setIconBorderContainer(frame, container)
    local st = getState(frame)
    if st then
        st.ScootIconBorderContainer = container
    end
end

local function ResetIconBorderTarget(target)
    if not target then return end
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(target)
    end

    local function wipeTexture(tex)
        if not tex then return end
        tex:Hide()
        if tex.SetTexture then pcall(tex.SetTexture, tex, nil) end
        if tex.SetAtlas then pcall(tex.SetAtlas, tex, nil, true) end
        if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, 1, 1, 1, 0) end
        if tex.SetAlpha then pcall(tex.SetAlpha, tex, 0) end
    end

    wipeTexture(addon.Borders.GetAtlasBorder and addon.Borders.GetAtlasBorder(target))
    wipeTexture(addon.Borders.GetTextureBorder and addon.Borders.GetTextureBorder(target))
    wipeTexture(addon.Borders.GetAtlasTintOverlay and addon.Borders.GetAtlasTintOverlay(target))
    wipeTexture(addon.Borders.GetTextureTintOverlay and addon.Borders.GetTextureTintOverlay(target))

    if target.ScootSquareBorderEdges then
        for _, edge in pairs(target.ScootSquareBorderEdges) do
            if edge then edge:Hide() end
        end
    end

    if target.ScootSquareBorder and target.ScootSquareBorder.edges then
        for _, tex in pairs(target.ScootSquareBorder.edges) do
            if tex and tex.Hide then tex:Hide() end
        end
    end
    if target.ScootSquareBorderContainer and target.ScootSquareBorderContainer.Hide then
        target.ScootSquareBorderContainer:Hide()
    end
end
Util.ResetIconBorderTarget = ResetIconBorderTarget

local function CleanupIconBorderAttachments(icon)
    if not icon then return end
    local seen = {}
    local function cleanup(target)
        if target and not seen[target] then
            seen[target] = true
            ResetIconBorderTarget(target)
        end
    end

    cleanup(icon)
    cleanup(getIconBorderContainer(icon))
    cleanup(icon.ScootAtlasBorderContainer)
    cleanup(icon.ScootTextureBorderContainer)
end
Util.CleanupIconBorderAttachments = CleanupIconBorderAttachments

function addon.ApplyIconBorderStyle(frame, styleKey, opts)
    if not frame then return "none" end

    Util.CleanupIconBorderAttachments(frame)

    local targetFrame = frame
    if frame.GetObjectType and frame:GetObjectType() == "Texture" then
        local parent = frame:GetParent() or UIParent
        local container = getIconBorderContainer(frame)
        if not container then
            container = CreateFrame("Frame", nil, parent)
            setIconBorderContainer(frame, container)
            container:EnableMouse(false)
        end
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        local strata = parent.GetFrameStrata and parent:GetFrameStrata() or "HIGH"
        container:SetFrameStrata(strata)
        local baseLevel = parent.GetFrameLevel and parent:GetFrameLevel() or 0
        container:SetFrameLevel(baseLevel + 5)
        targetFrame = container
    end

    Util.ResetIconBorderTarget(targetFrame)
    if targetFrame ~= frame then
        Util.ResetIconBorderTarget(frame)
    end

    local key = styleKey or "square"

    local styleDef = addon.IconBorders and addon.IconBorders.GetStyle(key)
    local tintEnabled = opts and opts.tintEnabled
    local requestedColor = opts and opts.color
    local dbTable = opts and opts.db
    local thicknessKey = opts and opts.thicknessKey
    local tintColorKey = opts and opts.tintColorKey
    local defaultThicknessSetting = opts and opts.defaultThickness or 1
    local thickness = tonumber(opts and opts.thickness) or defaultThicknessSetting
    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

    if not styleDef then
        if addon.Borders and addon.Borders.ApplySquare then
            addon.Borders.ApplySquare(targetFrame, {
                size = thickness,
                color = tintEnabled and requestedColor or {0, 0, 0, 1},
                layer = "OVERLAY",
                layerSublevel = 7,
            })
        end
        return "square"
    end

    if styleDef.type == "none" then
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
        return "none"
    end

    if styleDef.allowThicknessInset and dbTable and thicknessKey then
        local stored = tonumber(dbTable[thicknessKey])
        if stored then
            thickness = stored
        end
        if styleDef.defaultThickness and styleDef.defaultThickness ~= defaultThicknessSetting then
            if not stored or stored == defaultThicknessSetting then
                thickness = styleDef.defaultThickness
                dbTable[thicknessKey] = thickness
            end
        end
    elseif dbTable and thicknessKey then
        dbTable[thicknessKey] = thickness
    end

    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

    if dbTable and thicknessKey then
        dbTable[thicknessKey] = thickness
    end

    local function copyColor(color)
        if type(color) ~= "table" then
            return {1, 1, 1, 1}
        end
        return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
    end

    local defaultColor = copyColor(styleDef.defaultColor or (styleDef.type == "square" and {0, 0, 0, 1}) or {1, 1, 1, 1})
    if type(requestedColor) ~= "table" then
        if dbTable and tintColorKey and type(dbTable[tintColorKey]) == "table" then
            requestedColor = dbTable[tintColorKey]
        else
            requestedColor = defaultColor
        end
    end

    local baseColor = copyColor(defaultColor)
    local tintColor = copyColor(requestedColor)
    local baseApplyColor = copyColor(baseColor)
    if styleDef.type == "square" then
        baseApplyColor = tintEnabled and tintColor or baseColor
    end

    local function clamp(val, min, max)
        if val < min then return min end
        if val > max then return max end
        return val
    end

    local baseExpandX = styleDef.expandX or 0
    local baseExpandY = styleDef.expandY or baseExpandX
    local insetValueH = tonumber(opts and opts.insetH) or tonumber(opts and opts.inset) or 0
    local insetValueV = tonumber(opts and opts.insetV) or tonumber(opts and opts.inset) or 0
    local expandX = clamp(baseExpandX + (-insetValueH), -8, 8)
    local expandY = clamp(baseExpandY + (-insetValueV), -8, 8)

    local appliedTexture

    if styleDef.type == "atlas" then
        addon.Borders.ApplyAtlas(targetFrame, {
            atlas = styleDef.atlas,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        appliedTexture = addon.Borders.GetAtlasBorder(targetFrame)
    elseif styleDef.type == "texture" then
        addon.Borders.ApplyTexture(targetFrame, {
            texture = styleDef.texture,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
        })
        appliedTexture = addon.Borders.GetTextureBorder(targetFrame)
    else
        addon.Borders.ApplySquare(targetFrame, {
            size = thickness,
            color = baseApplyColor or {0, 0, 0, 1},
            layer = styleDef.layer or "OVERLAY",
            layerSublevel = styleDef.layerSublevel or 7,
            expandX = expandX,
            expandY = expandY,
        })
        local container = targetFrame.ScootSquareBorderContainer or targetFrame
        local edges = (container and container.ScootSquareBorderEdges) or targetFrame.ScootSquareBorderEdges
        if edges then
            for _, edge in pairs(edges) do
                if edge and edge.SetColorTexture then
                    edge:SetColorTexture(baseApplyColor[1] or 0, baseApplyColor[2] or 0, baseApplyColor[3] or 0, (baseApplyColor[4] == nil and 1) or baseApplyColor[4])
                end
            end
        end
        local atlasOverlay = addon.Borders.GetAtlasTintOverlay(targetFrame)
        local textureOverlay = addon.Borders.GetTextureTintOverlay(targetFrame)
        if atlasOverlay then atlasOverlay:Hide() end
        if textureOverlay then textureOverlay:Hide() end
    end

    if appliedTexture then
        if styleDef.type == "square" and baseApplyColor then
            appliedTexture:SetVertexColor(baseApplyColor[1] or 0, baseApplyColor[2] or 0, baseApplyColor[3] or 0, baseApplyColor[4] or 1)
        else
            appliedTexture:SetVertexColor(baseColor[1] or 1, baseColor[2] or 1, baseColor[3] or 1, baseColor[4] or 1)
        end
        appliedTexture:SetAlpha(baseColor[4] or 1)
        if appliedTexture.SetDesaturated then pcall(appliedTexture.SetDesaturated, appliedTexture, false) end
        if appliedTexture.SetBlendMode then pcall(appliedTexture.SetBlendMode, appliedTexture, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end

        local overlay
        if styleDef.type == "atlas" then
            overlay = addon.Borders.GetAtlasTintOverlay(targetFrame)
        elseif styleDef.type == "texture" then
            overlay = addon.Borders.GetTextureTintOverlay(targetFrame)
        end

        local function clampSublevel(val)
            if val == nil then return nil end
            if val > 7 then return 7 end
            if val < -8 then return -8 end
            return val
        end

        local function ensureOverlay()
            if overlay and overlay:IsObjectType("Texture") then return overlay end
            local layer, sublevel = appliedTexture:GetDrawLayer()
            layer = layer or (styleDef.layer or "OVERLAY")
            sublevel = clampSublevel((sublevel or (styleDef.layerSublevel or 7)) + 1) or clampSublevel((styleDef.layerSublevel or 7))
            local tex = targetFrame:CreateTexture(nil, layer)
            tex:SetDrawLayer(layer, sublevel or 0)
            tex:SetAllPoints(appliedTexture)
            tex:SetVertexColor(1, 1, 1, 1)
            tex:Hide()
            if styleDef.type == "atlas" then
                addon.Borders.SetAtlasTintOverlay(targetFrame, tex)
            else
                addon.Borders.SetTextureTintOverlay(targetFrame, tex)
            end
            return tex
        end

        if tintEnabled then
            overlay = ensureOverlay()
            local layer, sublevel = appliedTexture:GetDrawLayer()
            local desiredSub = clampSublevel((sublevel or 0) + 1)
            if layer then overlay:SetDrawLayer(layer, desiredSub or clampSublevel(sublevel) or 0) end
            overlay:ClearAllPoints()
            overlay:SetAllPoints(appliedTexture)
            local r = tintColor[1] or 1
            local g = tintColor[2] or 1
            local b = tintColor[3] or 1
            local a = tintColor[4] or 1
            if styleDef.type == "atlas" and styleDef.atlas then
                overlay:SetAtlas(styleDef.atlas)
            elseif styleDef.type == "texture" and styleDef.texture then
                overlay:SetTexture(styleDef.texture)
            end
            local avg = (r + g + b) / 3
            local blend = styleDef.tintBlendMode or ((avg >= 0.85) and "ADD" or "BLEND")
            if overlay.SetBlendMode then pcall(overlay.SetBlendMode, overlay, blend) end
            if overlay.SetDesaturated then pcall(overlay.SetDesaturated, overlay, (avg >= 0.85)) end
            overlay:SetVertexColor(r, g, b, a)
            overlay:SetAlpha(a)
            overlay:Show()
            appliedTexture:SetAlpha(0)
        else
            local overlays = {
                addon.Borders.GetAtlasTintOverlay(frame),
                addon.Borders.GetTextureTintOverlay(frame),
            }
            for _, ov in ipairs(overlays) do
                if ov then
                    ov:Hide()
                    if ov.SetTexture then pcall(ov.SetTexture, ov, nil) end
                    if ov.SetAtlas then pcall(ov.SetAtlas, ov, nil) end
                    if ov.SetVertexColor then pcall(ov.SetVertexColor, ov, 1, 1, 1, 0) end
                    if ov.SetBlendMode then pcall(ov.SetBlendMode, ov, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end
                end
            end

            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end

            if styleDef.type == "atlas" and styleDef.atlas then
                addon.Borders.ApplyAtlas(frame, {
                    atlas = styleDef.atlas,
                    color = baseColor,
                    tintColor = baseColor,
                    expandX = expandX,
                    expandY = expandY,
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
                appliedTexture = addon.Borders.GetAtlasBorder(frame)
            elseif styleDef.type == "texture" and styleDef.texture then
                addon.Borders.ApplyTexture(frame, {
                    texture = styleDef.texture,
                    color = baseColor,
                    tintColor = baseColor,
                    expandX = expandX,
                    expandY = expandY,
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
                appliedTexture = addon.Borders.GetTextureBorder(frame)
            else
                addon.Borders.ApplySquare(frame, {
                    size = thickness,
                    color = baseColor or {0, 0, 0, 1},
                    layer = styleDef.layer or "OVERLAY",
                    layerSublevel = styleDef.layerSublevel or 7,
                })
            end

            if appliedTexture then
                appliedTexture:SetAlpha(baseColor[4] or 1)
                if appliedTexture.SetDesaturated then pcall(appliedTexture.SetDesaturated, appliedTexture, false) end
                if appliedTexture.SetBlendMode then pcall(appliedTexture.SetBlendMode, appliedTexture, styleDef.baseBlendMode or styleDef.layerBlendMode or "BLEND") end
                appliedTexture:SetVertexColor(baseColor[1] or 1, baseColor[2] or 1, baseColor[3] or 1, baseColor[4] or 1)
            end
        end
    end

    return styleDef.type
end

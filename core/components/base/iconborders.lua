-- base/iconborders.lua - Icon border overlay creation, sizing, cleanup
local addonName, addon = ...

local getState = addon.ComponentsUtil._getState

local Util = addon.ComponentsUtil

--------------------------------------------------------------------------------
-- Sub-pixel border insets
--------------------------------------------------------------------------------
-- Textures snap to the physical pixel grid by default, which quantises fractional
-- anchor offsets straight back to whole pixels: a 0.5 inset would render identically
-- to 0 or 1. Snapping is relaxed only when the requested inset carries a
-- fractional part, so whole-number insets keep their crisp, grid-aligned edges.

local DEFAULT_TEXEL_SNAPPING_BIAS = 0.51

function addon.BorderInsetIsSubPixel(insetH, insetV)
    local h = tonumber(insetH)
    local v = tonumber(insetV)
    return (h ~= nil and h % 1 ~= 0) or (v ~= nil and v % 1 ~= 0)
end

function addon.SetBorderTexturePixelSnap(texture, subPixel)
    if not texture then return end
    if texture.SetSnapToPixelGrid then
        pcall(texture.SetSnapToPixelGrid, texture, not subPixel)
    end
    if texture.SetTexelSnappingBias then
        pcall(texture.SetTexelSnappingBias, texture, subPixel and 0 or DEFAULT_TEXEL_SNAPPING_BIAS)
    end
end

--------------------------------------------------------------------------------
-- Rounded icon masks
--------------------------------------------------------------------------------
-- Styles whose frame art has rounded corners need the icon rounded to match,
-- otherwise the icon's square corners poke out past the arc and no inset value can
-- hide them (see the note above ICON_BORDER_DEFINITIONS in core/iconborders.lua).
-- Both registries are weak-keyed so nothing is ever written onto the target frames.

local iconMasks = setmetatable({}, { __mode = "k" })      -- owner frame   -> MaskTexture
local maskedTextures = setmetatable({}, { __mode = "k" }) -- icon texture  -> MaskTexture

function addon.ClearIconMask(iconTexture)
    if not iconTexture then return end
    local existing = maskedTextures[iconTexture]
    if existing and iconTexture.RemoveMaskTexture then
        pcall(iconTexture.RemoveMaskTexture, iconTexture, existing)
    end
    maskedTextures[iconTexture] = nil
end

-- Applies (or removes) the rounded mask a border style calls for. `ownerFrame` must be
-- a Scoot-owned frame: the MaskTexture is created on it. Safe to call every restyle; the
-- mask is created once per owner and re-anchored thereafter.
function addon.ApplyIconMask(iconTexture, ownerFrame, styleKey, iconW, iconH)
    if not iconTexture or not iconTexture.AddMaskTexture then return end

    local atlas, scale
    if addon.IconBorders and addon.IconBorders.GetMaskAtlas then
        atlas, scale = addon.IconBorders.GetMaskAtlas(styleKey)
    end

    if not atlas then
        addon.ClearIconMask(iconTexture)
        return
    end

    local owner = ownerFrame or (iconTexture.GetParent and iconTexture:GetParent())
    if not owner or not owner.CreateMaskTexture then return end

    -- The mask is drawn larger than the icon (see GetMaskAtlas), so it needs real
    -- dimensions rather than edge anchors. Prefer the caller's values, then the icon,
    -- then the owner frame; bail rather than apply a wrongly-sized mask that would
    -- crop the icon.
    local w = tonumber(iconW) or (iconTexture.GetWidth and iconTexture:GetWidth()) or 0
    local h = tonumber(iconH) or (iconTexture.GetHeight and iconTexture:GetHeight()) or 0
    if w <= 0 or h <= 0 then
        w = (owner.GetWidth and owner:GetWidth()) or 0
        h = (owner.GetHeight and owner:GetHeight()) or 0
    end
    if w <= 0 or h <= 0 then
        addon.ClearIconMask(iconTexture)
        return
    end

    local mask = iconMasks[owner]
    if not mask then
        local ok, created = pcall(owner.CreateMaskTexture, owner)
        if not ok or not created then return end
        mask = created
        iconMasks[owner] = mask
    end

    if not pcall(mask.SetAtlas, mask, atlas, false) then return end

    scale = scale or 1.5
    mask:ClearAllPoints()
    mask:SetPoint("CENTER", iconTexture, "CENTER", 0, 0)
    mask:SetSize(w * scale, h * scale)
    mask:Show()

    if maskedTextures[iconTexture] ~= mask then
        addon.ClearIconMask(iconTexture)
        pcall(iconTexture.AddMaskTexture, iconTexture, mask)
        maskedTextures[iconTexture] = mask
    end
end

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

--------------------------------------------------------------------------------
-- Icon text hosts
--------------------------------------------------------------------------------
-- Border art lands on OVERLAY sublevel 7, and when ApplyIconBorderStyle is handed a
-- Texture the art lands on a container frame at parent level + 5. Frame level outranks
-- draw layer, so a stack count living on the icon's own frame cannot be lifted over the
-- border by SetDrawLayer at any sublevel. Move it onto a frame we own, one level above
-- whatever the border landed on, and hand it back when the border is switched off. Same
-- shape as the cast bar text overlay in unitframes/cast/styling.lua.

-- The frame level the border art for `target` actually ended up on.
function addon.GetIconBorderLevel(target)
    if not target then return nil end
    local frame = getIconBorderContainer(target) or target
    if not frame.GetFrameLevel then return nil end
    local ok, level = pcall(frame.GetFrameLevel, frame)
    if not ok or type(level) ~= "number" or issecretvalue(level) then return nil end
    return level
end

-- One mouse-dead host per owner frame, re-levelled on every call: the border container
-- is created lazily on the first ApplyIconBorderStyle pass, so a host built earlier has
-- nothing to measure against yet.
local function ensureIconTextHost(ownerFrame, borderTarget)
    if not ownerFrame or not ownerFrame.GetFrameLevel then return nil end
    local st = getState(ownerFrame)
    if not st then return nil end
    local host = st.ScootIconTextHost
    if not host then
        local ok, created = pcall(CreateFrame, "Frame", nil, ownerFrame)
        if not ok or not created then return nil end
        host = created
        pcall(host.EnableMouse, host, false)
        st.ScootIconTextHost = host
    end
    pcall(host.ClearAllPoints, host)
    pcall(host.SetAllPoints, host, ownerFrame)
    local borderLevel = addon.GetIconBorderLevel(borderTarget or ownerFrame)
    if borderLevel then
        pcall(host.SetFrameLevel, host, borderLevel + 1)
    end
    pcall(host.Show, host)
    return host
end
addon.EnsureIconTextHost = ensureIconTextHost

-- Reparents `fs` onto the host so it draws over the border. The original parent and draw
-- layer are recorded on the first promote so DemoteIconText can put both back.
function addon.PromoteIconText(fs, ownerFrame, borderTarget)
    if not fs or not fs.SetParent then return nil end
    local host = ensureIconTextHost(ownerFrame, borderTarget)
    if not host then return nil end
    local fsState = getState(fs)
    if fsState and fsState.ScootTextOriginalParent == nil then
        local okParent, parent = pcall(fs.GetParent, fs)
        if okParent and parent then fsState.ScootTextOriginalParent = parent end
        local okLayer, layer, sublevel = pcall(fs.GetDrawLayer, fs)
        if okLayer and type(layer) == "string" then
            fsState.ScootTextOriginalLayer = layer
            fsState.ScootTextOriginalSublevel = tonumber(sublevel) or 0
        end
    end
    pcall(fs.SetParent, fs, host)
    pcall(fs.SetDrawLayer, fs, "OVERLAY", 7)
    return host
end

-- Puts `fs` back where Blizzard had it. Safe to call when nothing was ever promoted.
function addon.DemoteIconText(fs)
    if not fs or not fs.SetParent then return end
    local fsState = getState(fs)
    local original = fsState and fsState.ScootTextOriginalParent
    if not original then return end
    pcall(fs.SetParent, fs, original)
    if fsState.ScootTextOriginalLayer then
        pcall(fs.SetDrawLayer, fs, fsState.ScootTextOriginalLayer, fsState.ScootTextOriginalSublevel or 0)
        fsState.ScootTextOriginalLayer = nil
        fsState.ScootTextOriginalSublevel = nil
    end
    fsState.ScootTextOriginalParent = nil
end

local function wipeTexture(tex)
    if not tex then return end
    tex:Hide()
    if tex.SetTexture then pcall(tex.SetTexture, tex, nil) end
    if tex.SetAtlas then pcall(tex.SetAtlas, tex, nil, true) end
    if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, 1, 1, 1, 0) end
    if tex.SetAlpha then pcall(tex.SetAlpha, tex, 0) end
end

local function ResetIconBorderTarget(target)
    if not target then return end
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(target)
    end

    wipeTexture(addon.Borders.GetAtlasBorder and addon.Borders.GetAtlasBorder(target))
    wipeTexture(addon.Borders.GetTextureBorder and addon.Borders.GetTextureBorder(target))
    wipeTexture(addon.Borders.GetAtlasTintOverlay and addon.Borders.GetAtlasTintOverlay(target))
    wipeTexture(addon.Borders.GetTextureTintOverlay and addon.Borders.GetTextureTintOverlay(target))
end
Util.ResetIconBorderTarget = ResetIconBorderTarget

local function CleanupIconBorderAttachments(icon)
    if not icon then return end
    ResetIconBorderTarget(icon)
    local container = getIconBorderContainer(icon)
    if container and container ~= icon then
        ResetIconBorderTarget(container)
    end
    local atlasC = icon.ScootAtlasBorderContainer
    if atlasC and atlasC ~= icon and atlasC ~= container then
        ResetIconBorderTarget(atlasC)
    end
    local texC = icon.ScootTextureBorderContainer
    if texC and texC ~= icon and texC ~= container and texC ~= atlasC then
        ResetIconBorderTarget(texC)
    end
end
Util.CleanupIconBorderAttachments = CleanupIconBorderAttachments

-- Scratch color tables reused across ApplyIconBorderStyle calls. Safe because all
-- consumers (SetVertexColor, Borders.Apply*) read [1..4] synchronously in the same
-- call stack. No code stores references to these tables beyond the current call.
local scratchDefaultColor = {1, 1, 1, 1}
local scratchBaseColor = {1, 1, 1, 1}
local scratchTintColor = {1, 1, 1, 1}
local scratchApplyColor = {1, 1, 1, 1}

local function fillColor(scratch, color)
    if type(color) ~= "table" then
        scratch[1], scratch[2], scratch[3], scratch[4] = 1, 1, 1, 1
    else
        scratch[1] = color[1] or 1
        scratch[2] = color[2] or 1
        scratch[3] = color[3] or 1
        scratch[4] = color[4] or 1
    end
    return scratch
end

local function clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

local function clampSublevel(val)
    if val == nil then return nil end
    if val > 7 then return 7 end
    if val < -8 then return -8 end
    return val
end

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
        local strata = parent.GetFrameStrata and parent:GetFrameStrata() or addon.Strata.HUD
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

    local defaultColor = fillColor(scratchDefaultColor, styleDef.defaultColor or (styleDef.type == "square" and {0, 0, 0, 1}) or {1, 1, 1, 1})
    if type(requestedColor) ~= "table" then
        if dbTable and tintColorKey and type(dbTable[tintColorKey]) == "table" then
            requestedColor = dbTable[tintColorKey]
        else
            requestedColor = defaultColor
        end
    end

    local baseColor = fillColor(scratchBaseColor, defaultColor)
    local tintColor = fillColor(scratchTintColor, requestedColor)
    local baseApplyColor = fillColor(scratchApplyColor, baseColor)
    if styleDef.type == "square" then
        baseApplyColor = tintEnabled and tintColor or baseColor
    end

    local baseExpandX = styleDef.expandX or 0
    local baseExpandY = styleDef.expandY or baseExpandX
    local insetValueH = tonumber(opts and opts.insetH) or tonumber(opts and opts.inset) or 0
    local insetValueV = tonumber(opts and opts.insetV) or tonumber(opts and opts.inset) or 0
    -- Dispatchers whose inset sliders never clamped expansion (CDM, custom groups,
    -- scoot auras) pass expandClamp to keep e.g. baseExpand 8 + outward inset 4 intact.
    local expandLimit = tonumber(opts and opts.expandClamp) or 8
    local expandX = clamp(baseExpandX + (-insetValueH), -expandLimit, expandLimit)
    local expandY = clamp(baseExpandY + (-insetValueV), -expandLimit, expandLimit)
    local subPixel = addon.BorderInsetIsSubPixel(insetValueH, insetValueV)

    -- Per-side style adjusts (opt-in): honors styleDef.adjustLeft/Right/Top/Bottom the
    -- way the custom-groups dispatcher established. Callers that never used adjusts
    -- keep symmetric expands and their historical geometry.
    local adjL, adjR, adjT, adjB = 0, 0, 0, 0
    if opts and opts.styleAdjusts then
        adjL = styleDef.adjustLeft or 0
        adjR = styleDef.adjustRight or 0
        adjT = styleDef.adjustTop or 0
        adjB = styleDef.adjustBottom or 0
    end
    local hasAdjusts = (adjL ~= 0) or (adjR ~= 0) or (adjT ~= 0) or (adjB ~= 0)

    -- Sub-pixel snap on square edges is likewise opt-in (opts.manageSubPixel): the
    -- dispatchers that historically relaxed snapping for fractional insets keep doing
    -- so; everyone else keeps creation-time snapping.
    local squareSubPixel = nil
    if opts and opts.manageSubPixel then
        squareSubPixel = subPixel and true or false
    end

    -- Round the icon to match rounded frame art. Only callers that own their icon
    -- texture pass maskTarget; Blizzard-owned icons (action buttons, CooldownViewer)
    -- already ship their own mask and must not be touched from addon context.
    if opts and opts.maskTarget then
        addon.ApplyIconMask(opts.maskTarget, opts.maskOwner or targetFrame, key)
    end

    local appliedTexture

    if styleDef.type == "atlas" then
        addon.Borders.ApplyAtlas(targetFrame, {
            atlas = styleDef.atlas,
            color = baseApplyColor,
            tintColor = baseApplyColor,
            expandX = expandX,
            expandY = expandY,
            offsets = hasAdjusts and {
                left = -(expandX + adjL),
                top = expandY + adjT,
                right = expandX + adjR,
                bottom = -(expandY + adjB),
            } or nil,
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
            offsets = hasAdjusts and {
                left = -(expandX + adjL),
                top = expandY + adjT,
                right = expandX + adjR,
                bottom = -(expandY + adjB),
            } or nil,
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
            subPixel = squareSubPixel,
        })
        local atlasOverlay = addon.Borders.GetAtlasTintOverlay(targetFrame)
        local textureOverlay = addon.Borders.GetTextureTintOverlay(targetFrame)
        if atlasOverlay then atlasOverlay:Hide() end
        if textureOverlay then textureOverlay:Hide() end
    end

    if appliedTexture then
        addon.SetBorderTexturePixelSnap(appliedTexture, subPixel)
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

        -- Wipes any tint overlay left from a previous full-tint apply. The base
        -- texture already carries its final color from the apply above.
        local function wipeTintOverlays()
            local overlays = {
                addon.Borders.GetAtlasTintOverlay(targetFrame),
                addon.Borders.GetTextureTintOverlay(targetFrame),
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
        end

        if tintEnabled and opts and opts.simpleTint then
            -- Simple tint: vertex-color the border art itself, with no tint overlay
            -- and no blend-mode or desaturation heuristics. The conservative path for
            -- dispatchers that have always tinted this way.
            appliedTexture:SetVertexColor(tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] or 1)
            appliedTexture:SetAlpha(1)
            wipeTintOverlays()
        elseif tintEnabled then
            overlay = ensureOverlay()
            addon.SetBorderTexturePixelSnap(overlay, subPixel)
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
            wipeTintOverlays()
        end
    end

    -- The outward reach of the applied art on each axis, for callers that need to
    -- reserve room around the icon (the settings preview sizes its clip box from these).
    return styleDef.type, expandX + math.max(adjL, adjR), expandY + math.max(adjT, adjB)
end

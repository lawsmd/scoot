local addonName, addon = ...

addon.Borders = addon.Borders or {}
local Borders = addon.Borders

-- Weak-key lookup tables to avoid writing properties to Blizzard frames
-- (which would taint them and cause secret value errors during Edit Mode operations)
local borderContainers = setmetatable({}, { __mode = "k" })   -- frame -> ScootSquareBorderContainer
local borderEdges = setmetatable({}, { __mode = "k" })        -- container/frame -> ScootSquareBorderEdges
local atlasContainers = setmetatable({}, { __mode = "k" })    -- frame -> ScooterAtlasBorderContainer
local atlasBorders = setmetatable({}, { __mode = "k" })       -- frame -> ScootAtlasBorder
local textureContainers = setmetatable({}, { __mode = "k" })  -- frame -> ScooterTextureBorderContainer
local textureBorders = setmetatable({}, { __mode = "k" })     -- frame -> ScootTextureBorder
local tintOverlays = setmetatable({}, { __mode = "k" })       -- frame -> { atlas = texture, texture = texture }

-- Secret-value safe helpers (shared module loaded before this file via TOC)
local SS = addon.SecretSafe
local safeGetter = SS.safeGetter
local safeDimension = SS.safeDimension

local function hideLegacy(frame)
    if not frame then return end
    -- Legacy direct frame property fallback (for frames that may have been styled before this fix)
    if frame.ScootSquareBorder and frame.ScootSquareBorder.edges then
        for _, tex in pairs(frame.ScootSquareBorder.edges) do tex:Hide() end
    end
    if frame.ScootSquareBorderEdges then
        for _, tex in pairs(frame.ScootSquareBorderEdges) do if tex.Hide then tex:Hide() end end
    end
    if frame.ScootSquareBorderContainer then frame.ScootSquareBorderContainer:Hide() end
    if frame.ScootAtlasBorder then frame.ScootAtlasBorder:Hide() end
    if frame.ScootTextureBorder then frame.ScootTextureBorder:Hide() end
    -- Weak-key lookup table versions
    local edges = borderEdges[frame]
    if edges then
        for _, tex in pairs(edges) do if tex.Hide then tex:Hide() end end
    end
    local container = borderContainers[frame]
    if container then container:Hide() end
    local atlasBorder = atlasBorders[frame]
    if atlasBorder then atlasBorder:Hide() end
    local textureBorder = textureBorders[frame]
    if textureBorder then textureBorder:Hide() end
    -- Also clear any tint overlays created by icon-border tinting. If these remain visible or keep their
    -- atlas/texture, they can continue to tint even after the base border is re-applied.
    -- Legacy direct frame property fallback
    if frame.ScootAtlasBorderTintOverlay then
        frame.ScootAtlasBorderTintOverlay:Hide()
        if frame.ScootAtlasBorderTintOverlay.SetTexture then pcall(frame.ScootAtlasBorderTintOverlay.SetTexture, frame.ScootAtlasBorderTintOverlay, nil) end
        if frame.ScootAtlasBorderTintOverlay.SetAtlas then pcall(frame.ScootAtlasBorderTintOverlay.SetAtlas, frame.ScootAtlasBorderTintOverlay, nil) end
    end
    if frame.ScootTextureBorderTintOverlay then
        frame.ScootTextureBorderTintOverlay:Hide()
        if frame.ScootTextureBorderTintOverlay.SetTexture then pcall(frame.ScootTextureBorderTintOverlay.SetTexture, frame.ScootTextureBorderTintOverlay, nil) end
        if frame.ScootTextureBorderTintOverlay.SetAtlas then pcall(frame.ScootTextureBorderTintOverlay.SetAtlas, frame.ScootTextureBorderTintOverlay, nil) end
    end
    -- Weak-key lookup table version for tint overlays
    local overlays = tintOverlays[frame]
    if overlays then
        if overlays.atlas then
            overlays.atlas:Hide()
            if overlays.atlas.SetTexture then pcall(overlays.atlas.SetTexture, overlays.atlas, nil) end
            if overlays.atlas.SetAtlas then pcall(overlays.atlas.SetAtlas, overlays.atlas, nil) end
        end
        if overlays.texture then
            overlays.texture:Hide()
            if overlays.texture.SetTexture then pcall(overlays.texture.SetTexture, overlays.texture, nil) end
            if overlays.texture.SetAtlas then pcall(overlays.texture.SetAtlas, overlays.texture, nil) end
        end
    end
    -- No mask textures used in the final design, so nothing else to clear here.
end

local function ensureContainer(frame, strata, levelOffset, parent, anchorRegion)
    local f = borderContainers[frame]
    if not f then
        f = CreateFrame("Frame", nil, parent or UIParent)
        borderContainers[frame] = f
    end
    local valid = { BACKGROUND=true, LOW=true, MEDIUM=true, HIGH=true, DIALOG=true, FULLSCREEN=true, FULLSCREEN_DIALOG=true, TOOLTIP=true }
    local desiredStrata = valid[strata or ""] and strata or (frame.GetFrameStrata and safeGetter(function() return frame:GetFrameStrata() end, "BACKGROUND")) or "BACKGROUND"
    local lvlOffset = tonumber(levelOffset) or 5
    local anchor = anchorRegion or frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    f:SetFrameStrata(desiredStrata)
    f:SetFrameLevel(safeDimension(function() return frame:GetFrameLevel() end) + lvlOffset)
    f:Show()
    return f
end

local function ensureSquare(frame, layer, sublevel, container)
    local parent = container or frame
    local edges = borderEdges[parent]
    if not edges then
        edges = {
            Top = parent:CreateTexture(nil, layer or "ARTWORK"),
            Bottom = parent:CreateTexture(nil, layer or "ARTWORK"),
            Left = parent:CreateTexture(nil, layer or "ARTWORK"),
            Right = parent:CreateTexture(nil, layer or "ARTWORK"),
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
        borderEdges[parent] = edges
    end
    -- Ensure desired draw layer
    local lyr = layer or "ARTWORK"
    local lvl = tonumber(sublevel) or 0
    for _, t in pairs(edges) do if t and t.SetDrawLayer then pcall(t.SetDrawLayer, t, lyr, lvl) end end
    return edges
end

local function colorEdges(edges, r, g, b, a)
    for _, t in pairs(edges) do t:SetColorTexture(r, g, b, a) end
end

function Borders.ApplySquare(frame, opts)
    if not frame or not opts then return end

    -- Sanity check: refuse to apply borders to frames larger than reasonable for a bar.
    -- This catches cases where the wrong frame is passed (e.g., a parent container instead
    -- of the actual bar). Skip the check if opts.skipDimensionCheck is set.
    if not opts.skipDimensionCheck then
        local fw = safeDimension(function() return frame:GetWidth() end)
        local fh = safeDimension(function() return frame:GetHeight() end)
        if fw > 400 or fh > 100 then
            -- Frame is too large to be a bar; clear any existing border and return.
            hideLegacy(frame)
            return
        end
    end

    hideLegacy(frame)
    local size = math.max(1, tonumber(opts.size) or 1)
    local col = opts.color or {0, 0, 0, 1}
    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1
    local layer = (type(opts.layer) == "string") and opts.layer or "ARTWORK"
    local layerSublevel = tonumber(opts.layerSublevel) or 0
    local container
    -- Create a container if either containerStrata OR levelOffset is specified.
    -- If containerStrata is nil, ensureContainer will inherit the parent frame's strata,
    -- which keeps borders below Blizzard menus while still allowing elevated frame level.
    if opts.containerStrata or opts.levelOffset then
        container = ensureContainer(frame, opts.containerStrata, opts.levelOffset, opts.containerParent, opts.containerAnchorRegion)
    end
    local e = ensureSquare(frame, layer, layerSublevel, container)
    colorEdges(e, r, g, b, a)
    local anchor = container or frame
    local target = anchor
    local expand = tonumber(opts.expand) or 0
    local ex = tonumber(opts.expandX) or expand
    local ey = tonumber(opts.expandY) or expand
    -- Optional per-side overrides (used for fine-tuning specific frames like Cast Bars)
    local exLeft  = (opts.expandLeft  ~= nil) and tonumber(opts.expandLeft)  or ex
    local exRight = (opts.expandRight ~= nil) and tonumber(opts.expandRight) or ex
    local eyTop   = (opts.expandTop   ~= nil) and tonumber(opts.expandTop)   or ey
    local eyBottom= (opts.expandBottom~= nil) and tonumber(opts.expandBottom)or ey
    -- Optional per-edge thickness overrides (e.g., thicker bottom edge for Player Power Bar Spark)
    local sizeTop    = (opts.sizeTop    ~= nil) and math.max(1, tonumber(opts.sizeTop))    or size
    local sizeBottom = (opts.sizeBottom ~= nil) and math.max(1, tonumber(opts.sizeBottom)) or size
    local sizeLeft   = (opts.sizeLeft   ~= nil) and math.max(1, tonumber(opts.sizeLeft))   or size
    local sizeRight  = (opts.sizeRight  ~= nil) and math.max(1, tonumber(opts.sizeRight))  or size
    -- Prevent corner over-darkening without leaving gaps:
    -- let horizontal edges span the full width; trim vertical edges by the thickness.
    -- This yields a single-draw corner (from the horizontal edge) at each corner.
    e.Top:ClearAllPoints();    e.Top:SetPoint("TOPLEFT", target, "TOPLEFT", -exLeft, eyTop);        e.Top:SetPoint("TOPRIGHT", target, "TOPRIGHT", exRight, eyTop);        e.Top:SetHeight(sizeTop)
    e.Bottom:ClearAllPoints(); e.Bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -exLeft, -eyBottom); e.Bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", exRight, -eyBottom); e.Bottom:SetHeight(sizeBottom)
    e.Left:ClearAllPoints();   e.Left:SetPoint("TOPLEFT", target, "TOPLEFT", -exLeft, eyTop - sizeTop);        e.Left:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -exLeft, (-eyBottom) + sizeBottom);   e.Left:SetWidth(sizeLeft)
    e.Right:ClearAllPoints();  e.Right:SetPoint("TOPRIGHT", target, "TOPRIGHT", exRight, eyTop - sizeTop);     e.Right:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", exRight, (-eyBottom) + sizeBottom); e.Right:SetWidth(sizeRight)
    -- Defer Show() for managed frames (PetFrame, etc.) to break taint chain
    if opts.deferShow then
        C_Timer.After(0, function()
            for _, t in pairs(e) do if t.Show then t:Show() end end
            if container and container.Show then container:Show() end
        end)
    else
        for _, t in pairs(e) do if t.Show then t:Show() end end
        if container and container.Show then container:Show() end
    end
end

function Borders.HideAll(frame)
    hideLegacy(frame)
    -- Also hide circular border (legacy direct property fallback)
    if frame.ScootCircleBorderContainer then
        local container = frame.ScootCircleBorderContainer
        if container.ScootCircleBorder then
            container.ScootCircleBorder:Hide()
        end
        -- Clear backdrop if set
        if container.SetBackdrop then
            pcall(container.SetBackdrop, container, nil)
        end
        container:Hide()
    end
    -- Note: Circular borders are currently disabled (ApplyCircle is commented out)
    -- so no weak-key lookup table is needed for them at this time.
end

-- Apply a circular border around a frame (for portraits)
-- DISABLED: Implementation removed (caused spritesheet rendering issues)
--[[
function Borders.ApplyCircle(frame, opts)
    if not frame or not opts then return end
    hideLegacy(frame)
    
    local thickness = math.max(1, tonumber(opts.size) or 1)
    local col = opts.color or {0, 0, 0, 1}
    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1
    -- Portrait is on BACKGROUND layer, sublevel 1
    -- We want the border to appear AROUND the portrait, not covering it
    -- SetBackdrop creates edges that don't fill the center
    -- We'll use the same frame level as the portrait's parent, and SetBackdrop will handle the visual
    local layer = (type(opts.layer) == "string") and opts.layer or "OVERLAY"
    local layerSublevel = tonumber(opts.layerSublevel) or 0
    
    -- Handle both Frame and Texture objects
    -- Portrait frames are Textures, so we need to get their parent for frame-level operations
    local frameObj = frame
    local parentFrame = frame:GetParent()
    local frameStrata = "LOW"
    local frameLevel = 0
    
    -- If frame is a Texture, use its parent for strata/level info
    if frame.GetObjectType and frame:GetObjectType() == "Texture" then
        if parentFrame and parentFrame.GetFrameStrata then
            frameStrata = parentFrame:GetFrameStrata() or "LOW"
        end
        if parentFrame and parentFrame.GetFrameLevel then
            -- Use the SAME frame level as the parent, not higher
            -- This ensures the border appears at the same level as the portrait
            frameLevel = parentFrame:GetFrameLevel() or 0
        end
    elseif frame.GetFrameStrata then
        -- It's a Frame, use it directly
        frameStrata = frame:GetFrameStrata() or "LOW"
        frameLevel = frame:GetFrameLevel() or 0
    end
    
    -- Create a container frame with BackdropTemplate for SetBackdrop support
    local container = frame.ScootCircleBorderContainer
    if not container then
        -- Use BackdropTemplate if available for proper SetBackdrop support
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        container = CreateFrame("Frame", nil, parentFrame or UIParent, template)
        frame.ScootCircleBorderContainer = container
        container:EnableMouse(false)
    end
    
    -- Get portrait dimensions
    local frameWidth = frame:GetWidth() or 60
    local frameHeight = frame:GetHeight() or 60
    
    -- Clear any existing backdrop first
    if container.SetBackdrop then
        pcall(container.SetBackdrop, container, nil)
    end
    
    -- Position container to match portrait size exactly
    -- SetBackdrop edges are drawn inward, so edges will be drawn inside the container bounds
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    container:SetFrameStrata(frameStrata)
    container:SetFrameLevel(frameLevel + 1) -- Slightly above portrait's parent so edges are visible
    container:EnableMouse(false)
    
    -- Apply backdrop with edges only (no background fill)
    -- Edges will be drawn inward from container edges, creating a border effect
    local backdrop = {
        bgFile = nil,  -- No background fill
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 0,
        edgeSize = thickness,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    }
    
    local ok = pcall(container.SetBackdrop, container, backdrop)
    
    if ok then
        -- Set border edge color
        if container.SetBackdropBorderColor then
            container:SetBackdropBorderColor(r, g, b, a)
        end
        -- Set background to fully transparent (critical!)
        if container.SetBackdropColor then
            container:SetBackdropColor(0, 0, 0, 0)
        end
        -- Hide Center piece if it exists (SetBackdrop may create it even with bgFile = nil)
        if container.Center then
            container.Center:Hide()
        end
        
        -- Create circular mask texture to make border match circular portrait
        local maskTex = container.ScootCircleBorderMask
        if not maskTex then
            maskTex = container:CreateTexture(nil, "ARTWORK", nil, 0)
            container.ScootCircleBorderMask = maskTex
            maskTex:SetAtlas("CircleMask", false)
            maskTex:SetAllPoints(container)
            maskTex:Hide() -- Hide mask texture itself (it's only used for masking, not display)
        end
        
        -- Apply circular mask to all backdrop edge textures
        -- SetBackdrop creates these textures: TopEdge, BottomEdge, LeftEdge, RightEdge, 
        -- TopLeftCorner, TopRightCorner, BottomLeftCorner, BottomRightCorner
        local edgeTextures = {
            container.TopEdge,
            container.BottomEdge,
            container.LeftEdge,
            container.RightEdge,
            container.TopLeftCorner,
            container.TopRightCorner,
            container.BottomLeftCorner,
            container.BottomRightCorner,
        }
        
        for _, edgeTex in ipairs(edgeTextures) do
            if edgeTex and edgeTex.AddMaskTexture then
                -- Clear existing masks first
                local numMasks = edgeTex:GetNumMaskTextures()
                for i = numMasks, 1, -1 do
                    local mask = edgeTex:GetMaskTexture(i)
                    if mask then
                        edgeTex:RemoveMaskTexture(mask)
                    end
                end
                -- Add circular mask
                if edgeTex:GetNumMaskTextures() < 3 then
                    pcall(edgeTex.AddMaskTexture, edgeTex, maskTex)
                end
            end
        end
        
        container:Show()
    else
        -- SetBackdrop failed - hide container
        container:Hide()
    end
end
--]]

local ATLAS_PRESETS = {
    -- Intentionally empty for now; icon atlas borders are disabled for bar borders testing
}

local function getAtlasPreset(key)
    for _, it in ipairs(ATLAS_PRESETS) do
        if it.key == key then return it end
    end
end

local function applyTextureInternal(frame, textureObject, params)
    if not frame or not textureObject then return end
    local expandX = tonumber(params.expandX) or tonumber(params.expand) or 0
    local expandY = tonumber(params.expandY) or tonumber(params.expand) or expandX
    local layer = params.layer or "OVERLAY"
    local layerSublevel = tonumber(params.layerSublevel) or 7
    if layerSublevel > 7 then
        layerSublevel = 7
    elseif layerSublevel < -8 then
        layerSublevel = -8
    end

    textureObject:SetDrawLayer(layer, layerSublevel)
    if params.setAtlas then
        textureObject:SetAtlas(params.setAtlas, true)
    elseif params.setTexture then
        textureObject:SetTexture(params.setTexture)
    end

    local tint = params.color
    local r = 1
    local g = 1
    local b = 1
    local a = 1
    if tint and type(tint) == "table" then
        r = tonumber(tint[1]) or 1
        g = tonumber(tint[2]) or 1
        b = tonumber(tint[3]) or 1
        a = tonumber(tint[4]) or 1
    end
    textureObject:SetVertexColor(r, g, b, a)

    local offsets = params.offsets
    local topLeftX, topLeftY, bottomRightX, bottomRightY
    if offsets then
        topLeftX = offsets.left or 0
        topLeftY = offsets.top or 0
        bottomRightX = offsets.right or 0
        bottomRightY = offsets.bottom or 0
    else
        topLeftX = -(expandX)
        topLeftY = expandY
        bottomRightX = expandX
        bottomRightY = -(expandY)
    end

    textureObject:ClearAllPoints()
    textureObject:SetPoint("TOPLEFT", frame, "TOPLEFT", topLeftX, topLeftY)
    textureObject:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bottomRightX, bottomRightY)
    textureObject:Show()
end

function Borders.ApplyAtlas(frame, opts)
    if not frame or not opts or type(opts.atlas) ~= "string" then return end

    -- If a Texture is passed (e.g., icon textures), wrap it in a small Frame so we
    -- have a valid CreateTexture target and stable anchor bounds.
    local originalFrame = frame  -- Keep reference for weak-key lookup
    if frame.GetObjectType and frame:GetObjectType() == "Texture" then
        local parent = frame:GetParent() or UIParent
        local container = atlasContainers[frame]
        if not container then
            container = CreateFrame("Frame", nil, parent)
            atlasContainers[frame] = container
            container:EnableMouse(false)
        end
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        local strata = parent.GetFrameStrata and parent:GetFrameStrata() or "HIGH"
        container:SetFrameStrata(strata)
        local baseLevel = parent.GetFrameLevel and parent:GetFrameLevel() or 0
        container:SetFrameLevel(baseLevel + 5)
        frame = container
    end

    hideLegacy(originalFrame)
    local border = atlasBorders[frame]
    if not border then
        border = frame:CreateTexture(nil, "OVERLAY")
        atlasBorders[frame] = border
    end

    local preset = getAtlasPreset(opts.atlas)
    local px = 0
    local py = 0
    if preset and preset.padding then
        px = tonumber(preset.padding[1]) or 0
        py = tonumber(preset.padding[2]) or 0
    end

    local extra = tonumber(opts.extraPadding)
    if extra then
        if extra < -8 then extra = -8 elseif extra > 8 then extra = 8 end
        px = px + extra
        py = py + extra
    end

    if opts.expandX ~= nil then
        px = -(tonumber(opts.expandX) or 0)
    end
    if opts.expandY ~= nil then
        py = -(tonumber(opts.expandY) or 0)
    elseif opts.expandX ~= nil then
        py = -(tonumber(opts.expandX) or 0)
    end

    local params = {
        setAtlas = opts.atlas,
        color = opts.tintColor or opts.color or opts.defaultColor,
        layer = opts.layer or "OVERLAY",
        layerSublevel = opts.layerSublevel or 7,
        offsets = opts.offsets or { left = px, top = -py, right = -px, bottom = py },
    }

    applyTextureInternal(frame, border, params)
end

function Borders.ApplyTexture(frame, opts)
    if not frame or not opts or type(opts.texture) ~= "string" then return end

    -- Same wrapper logic as ApplyAtlas: ensure we have a Frame target for borders
    -- when a raw Texture is passed in.
    local originalFrame = frame  -- Keep reference for weak-key lookup
    if frame.GetObjectType and frame:GetObjectType() == "Texture" then
        local parent = frame:GetParent() or UIParent
        local container = textureContainers[frame]
        if not container then
            container = CreateFrame("Frame", nil, parent)
            textureContainers[frame] = container
            container:EnableMouse(false)
        end
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        local strata = parent.GetFrameStrata and parent:GetFrameStrata() or "HIGH"
        container:SetFrameStrata(strata)
        local baseLevel = parent.GetFrameLevel and parent:GetFrameLevel() or 0
        container:SetFrameLevel(baseLevel + 5)
        frame = container
    end

    hideLegacy(originalFrame)
    local border = textureBorders[frame]
    if not border then
        border = frame:CreateTexture(nil, "OVERLAY")
        textureBorders[frame] = border
    end

    local params = {
        setTexture = opts.texture,
        color = opts.tintColor or opts.color or opts.defaultColor,
        expandX = opts.expandX,
        expandY = opts.expandY,
        layer = opts.layer or "OVERLAY",
        layerSublevel = opts.layerSublevel or 7,
        offsets = opts.offsets,
    }

    applyTextureInternal(frame, border, params)
end

-- Getter functions to access weak-key table entries without writing to frames
function Borders.GetAtlasBorder(frame)
    return atlasBorders[frame]
end

function Borders.GetTextureBorder(frame)
    return textureBorders[frame]
end

function Borders.GetAtlasTintOverlay(frame)
    local overlays = tintOverlays[frame]
    return overlays and overlays.atlas
end

function Borders.GetTextureTintOverlay(frame)
    local overlays = tintOverlays[frame]
    return overlays and overlays.texture
end

function Borders.SetAtlasTintOverlay(frame, texture)
    if not tintOverlays[frame] then
        tintOverlays[frame] = {}
    end
    tintOverlays[frame].atlas = texture
end

function Borders.SetTextureTintOverlay(frame, texture)
    if not tintOverlays[frame] then
        tintOverlays[frame] = {}
    end
    tintOverlays[frame].texture = texture
end

function addon.BuildBarBorderOptionsContainer()
    if addon.BarBorders and addon.BarBorders.GetDropdownEntries then
        return addon.BarBorders.GetDropdownEntries({
            previewHeight = 18,
            previewWidth = 160,
        })
    end
    local create = _G.Settings and _G.Settings.CreateControlTextContainer
    if not create then
        return { { value = "square", text = "Square" } }
    end
    local c = create()
    c:Add("square", "Square")
    return c:GetData()
end

function addon.BuildIconBorderOptionsContainer()
    if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
        return addon.IconBorders.GetDropdownEntries()
    end
    local create = Settings and Settings.CreateControlTextContainer
    if create then
        local container = create()
        container:Add("square", "Square")
        container:Add("blizzard", "Blizzard Default")
        return container:GetData()
    end
    return {
        { value = "square", text = "Square" },
        { value = "blizzard", text = "Blizzard Default" },
    }
end

-- Backwards compatibility for legacy callers
addon.BuildBorderOptionsContainer = addon.BuildBarBorderOptionsContainer

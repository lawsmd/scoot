local addonName, addon = ...

addon.BarBorders = addon.BarBorders or {}
local BarBorders = addon.BarBorders

local MEDIA_PATH_PREFIX = "Interface\\AddOns\\Scoot\\media\\barborder\\"

-- Track border state per barFrame using weak keys to avoid tainting Blizzard system frames.
-- Writing properties directly to CDM StatusBar frames causes taint that propagates to
-- Arena frames when Edit Mode iterates registered system frames.
local borderFrameState = setmetatable({}, { __mode = "k" })

local DEFAULT_REFERENCE_HEIGHT = 18
local DEFAULT_THICKNESS_MULTIPLIER = 1.35
local MAX_EDGE_SIZE = 48

local CATEGORY_LABELS = {
    traditional = "Traditional",
    clean = "Clean",
}

local STYLE_DEFINITIONS = {
    -- Traditional selections (soft gradients, Blizzard-adjacent)
    { key = "mmtBorder1", label = "Border 1", file = "mborder1.tga", category = "traditional", order = 10, thicknessScale = 1.10, paddingMultiplier = 0.55 },
    { key = "mmtBorder2", label = "Border 2", file = "mborder2.tga", category = "traditional", order = 20, thicknessScale = 1.20, paddingMultiplier = 0.55 },
    { key = "mmtYBorder", label = "Y Border", file = "yborder.tga", category = "traditional", order = 30, thicknessScale = 1.15, paddingMultiplier = 0.55 },
    { key = "mmtYBorder2", label = "Y Border 2", file = "yborder2.tga", category = "traditional", order = 40, thicknessScale = 1.20, paddingMultiplier = 0.55 },
    { key = "mmtYuluSwitch", label = "Yulu Border Switch", file = "YuluBorderSwitch.tga", category = "traditional", order = 50, thicknessScale = 1.30, paddingMultiplier = 0.55 },
    { key = "mmtYuluXI", label = "Yulu Border XI", file = "YuluBorderXI.tga", category = "traditional", order = 60, thicknessScale = 1.30, paddingMultiplier = 0.55 },

    -- Clean, geometric lines
    { key = "mmtPixel", label = "Pixel", file = "pixel.tga", category = "clean", order = 110, thicknessScale = 0.90, paddingMultiplier = 0.40, minEdgeSize = 1 },
    { key = "mmtRound", label = "Round", file = "round.tga", category = "clean", order = 120, thicknessScale = 1.25, paddingMultiplier = 0.50 },
    { key = "mmtSquares", label = "Squares", file = "squares.tga", category = "clean", order = 130, thicknessScale = 1.25, paddingMultiplier = 0.50 },
    { key = "mmtCorners", label = "Corners", file = "corners.tga", category = "clean", order = 140, thicknessScale = 1.35, paddingMultiplier = 0.55 },
    { key = "mmtPencil", label = "Pencil & Ruler", file = "pencilandlieneal.tga", category = "clean", order = 150, thicknessScale = 1.10, paddingMultiplier = 0.50 },
    { key = "mmtPencilMono", label = "Pencil & Ruler (Mono)", file = "pencilandlienealblack.tga", category = "clean", order = 160, thicknessScale = 1.10, paddingMultiplier = 0.50 },
    { key = "mmtWood", label = "Wood", file = "wood.tga", category = "clean", order = 170, thicknessScale = 1.35, paddingMultiplier = 0.55 },

}

local STYLE_MAP = {}
local STYLE_ORDER = {}

for _, def in ipairs(STYLE_DEFINITIONS) do
    def.texture = MEDIA_PATH_PREFIX .. def.file
    def.previewWidth = def.previewWidth or 180
    def.previewHeight = def.previewHeight or 18
    def.paddingMultiplier = def.paddingMultiplier or 0.5
    def.thicknessScale = def.thicknessScale or 1.0
    STYLE_MAP[def.key] = def
    STYLE_ORDER[#STYLE_ORDER + 1] = def.key
end

table.sort(STYLE_ORDER, function(a, b)
    local sa = STYLE_MAP[a]
    local sb = STYLE_MAP[b]
    local oa = (sa and sa.order) or 999
    local ob = (sb and sb.order) or 999
    if oa == ob then
        local la = sa and sa.label or ""
        local lb = sb and sb.label or ""
        return la < lb
    end
    return oa < ob
end)

local function cloneColor(color)
    if type(color) ~= "table" then
        return { 1, 1, 1, 1 }
    end
    return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
end

local function ensureBorderFrame(barFrame)
    local bfState = borderFrameState[barFrame] or {}
    borderFrameState[barFrame] = bfState
    local holder = bfState.holder
    if not holder then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local parentOverride = bfState.containerParentRef
        holder = CreateFrame("Frame", nil, parentOverride or barFrame, template)
        holder:SetClipsChildren(false)
        holder:SetIgnoreParentAlpha(false)
        holder:SetScript("OnSizeChanged", function(self, w, h)
            if self.backdropInfo and self.SetupTextureCoordinates then
                if type(w) == "number" and type(h) == "number"
                   and not issecretvalue(w) and not issecretvalue(h) then
                    self:SetupTextureCoordinates()
                end
            end
        end)
        bfState.holder = holder
    end
    local containerRef = bfState.containerParentRef or barFrame
    local strata = containerRef.GetFrameStrata and containerRef:GetFrameStrata()
    if strata then
        holder:SetFrameStrata(strata)
    end
    local parentForLevel = bfState.containerParentRef or barFrame
    local level = (parentForLevel.GetFrameLevel and parentForLevel:GetFrameLevel()) or 0
    local offset = tonumber(bfState.levelOffset) or 8
    local desiredLevel = tonumber(bfState.fixedLevel) or (level + offset)
    holder:SetFrameLevel(desiredLevel)
    return holder
end

local function computeEdgeSize(barFrame, style, thickness)
    local frameHeight = DEFAULT_REFERENCE_HEIGHT
    if barFrame and barFrame.GetHeight then
        local ok, height = pcall(barFrame.GetHeight, barFrame)
        if ok and not issecretvalue(height) and type(height) == "number" and height >= 1 then
            frameHeight = height
        end
    end
    local scale = frameHeight / DEFAULT_REFERENCE_HEIGHT
    local multiplier = (style and style.thicknessScale) or 1
    local edgeSize = thickness * DEFAULT_THICKNESS_MULTIPLIER * multiplier * scale
    if style and style.minEdgeSize then
        edgeSize = math.max(style.minEdgeSize, edgeSize)
    end
    if style and style.maxEdgeSize then
        edgeSize = math.min(style.maxEdgeSize, edgeSize)
    end
    if edgeSize > MAX_EDGE_SIZE then edgeSize = MAX_EDGE_SIZE end
    if edgeSize < 1 then edgeSize = 1 end
    return math.floor(edgeSize + 0.5)
end

local function applyBackdrop(holder, style, edgeSize)
    if not holder or not holder.SetBackdrop or not style or not style.texture then
        return false
    end
    -- Guard: when the holder inherits anchor secrecy from a StatusBar that
    -- received SetValue(secret), GetWidth()/GetHeight() return secret values.
    -- Blizzard's SetupTextureCoordinates uses these for arithmetic, causing
    -- errors reported to the global error handler even inside pcall.
    local okW, w = pcall(holder.GetWidth, holder)
    if not okW or issecretvalue(w) then
        return false
    end
    local insetMultiplier = style.insetMultiplier or 0.65
    local inset = math.floor(edgeSize * insetMultiplier + 0.5)
    if inset < 0 then inset = 0 end
    local ok = pcall(holder.SetBackdrop, holder, {
        bgFile = nil,
        edgeFile = style.texture,
        tile = false,
        edgeSize = edgeSize,
        insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    return ok
end

local function applyStyle(barFrame, style, color, thickness, skipStateUpdate, inset, insetH, insetV)
    local holder = ensureBorderFrame(barFrame)
    if not holder then return false end

    local bfState = borderFrameState[barFrame] or {}
    borderFrameState[barFrame] = bfState

    -- Edge and padding scale with the bar's height (original behavior)
    local edgeSize = computeEdgeSize(barFrame, style, thickness)
    local paddingMultiplier = style and style.paddingMultiplier or 0.5
    local pad = math.floor(edgeSize * paddingMultiplier + 0.5)
    local insetPxH = tonumber(insetH) or tonumber(bfState.insetH) or tonumber(inset) or tonumber(bfState.inset) or 0
    local insetPxV = tonumber(insetV) or tonumber(bfState.insetV) or tonumber(inset) or tonumber(bfState.inset) or 0
    -- Positive inset pulls the border inward (smaller padding); negative pushes outward
    local padAdjH = pad - insetPxH
    local padAdjV = pad - insetPxV
    if padAdjH < 0 then padAdjH = 0 end
    if padAdjV < 0 then padAdjV = 0 end

    -- Allow per-frame, per-side pad adjustments (used for fine-tuning Cast Bar borders).
    local padL, padR, padT, padB = padAdjH, padAdjH, padAdjV, padAdjV
    local perSide = bfState.padAdjust
    if type(perSide) == "table" then
        padL = padL + (tonumber(perSide.left) or 0)
        padR = padR + (tonumber(perSide.right) or 0)
        padT = padT + (tonumber(perSide.top) or 0)
        padB = padB + (tonumber(perSide.bottom) or 0)
        if padL < 0 then padL = 0 end
        if padR < 0 then padR = 0 end
        if padT < 0 then padT = 0 end
        if padB < 0 then padB = 0 end
    end

    -- Use anchorTarget if specified (e.g., clipping container for height reduction)
    local anchorFrame = (bfState and bfState.anchorTarget) or barFrame
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", -padL, padT)
    holder:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", padR, -padB)

    if not applyBackdrop(holder, style, edgeSize) then
        holder:Hide()
        return false
    end

    if holder.SetBackdropBorderColor then
        holder:SetBackdropBorderColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if holder.SetBackdropColor then
        holder:SetBackdropColor(0, 0, 0, 0)
    end

    holder:Show()

    -- Create/update gasket textures that fill the 1px gap between the
    -- fill area and the border's visible inner edge (BackdropTemplate
    -- edge textures don't extend to their mathematical boundary)
    if not bfState.gaskets then
        local g = {}
        for _, side in ipairs({"top", "bottom", "left", "right"}) do
            g[side] = holder:CreateTexture(nil, "BACKGROUND", nil, -8)
        end
        bfState.gaskets = g
    end
    local g = bfState.gaskets
    -- Top: 1px strip just outside anchor's top edge
    g.top:ClearAllPoints()
    g.top:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 0)
    g.top:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
    g.top:SetHeight(1)
    -- Bottom: 1px strip just outside anchor's bottom edge
    g.bottom:ClearAllPoints()
    g.bottom:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
    g.bottom:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    g.bottom:SetHeight(1)
    -- Left: 1px strip just outside anchor's left edge
    g.left:ClearAllPoints()
    g.left:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", 0, 0)
    g.left:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMLEFT", 0, 0)
    g.left:SetWidth(1)
    -- Right: 1px strip just outside anchor's right edge
    g.right:ClearAllPoints()
    g.right:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 0, 0)
    g.right:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    g.right:SetWidth(1)
    -- Color gaskets to match border
    for _, tex in pairs(g) do
        tex:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        tex:Show()
    end

    if not skipStateUpdate then
        bfState.state = {
            styleKey = style.key,
            thickness = thickness,
            color = cloneColor(color),
            insetH = insetPxH,
            insetV = insetPxV,
        }
    end

    return true
end

local function handleSizeChanged(frame)
    local bfState = borderFrameState[frame]
    if not frame or not bfState or not bfState.state then return end
    local state = bfState.state
    if not state.styleKey then return end
    local style = STYLE_MAP[state.styleKey]
    if not style then return end
    local color = cloneColor(state.color)
    local thickness = tonumber(state.thickness) or 1
    applyStyle(frame, style, color, thickness, true, nil, tonumber(state.insetH) or 0, tonumber(state.insetV) or 0)
end

local function ensureSizeHook(barFrame)
    if not barFrame then return end
    local bfState = borderFrameState[barFrame]
    if bfState and bfState.sizeHooked then return end

    borderFrameState[barFrame] = borderFrameState[barFrame] or {}
    borderFrameState[barFrame].sizeHooked = true

    -- Create an addon-owned proxy frame instead of HookScript on the Blizzard frame.
    -- HookScript modifies the frame's script handler table, permanently tainting it
    -- in 12.0 (taint restriction). The proxy inherits barFrame's dimensions via
    -- SetAllPoints and receives OnSizeChanged without modifying the Blizzard frame.
    -- Use sizeProxyParentRef if set (e.g., UIParent for damage meter entries to avoid taint).
    local proxyParent = borderFrameState[barFrame].sizeProxyParentRef or barFrame
    local proxy = CreateFrame("Frame", nil, proxyParent)
    proxy:SetAllPoints(barFrame)
    proxy:SetScript("OnSizeChanged", function()
        handleSizeChanged(barFrame)
    end)
    borderFrameState[barFrame].sizeProxy = proxy
end

local function formatMenuLabel(style, options)
    if not style then return "" end
    local label = style.label or style.key or "Unknown"
    if not (options and options.hideCategoryTag) then
        local cat = style.category and CATEGORY_LABELS[style.category]
        if cat then
            label = string.format("%s [%s]", label, cat)
        end
    end
    local previewHeight = (options and options.previewHeight) or style.previewHeight or 18
    local previewWidth = (options and options.previewWidth) or style.previewWidth or 180
    local preview = string.format("|T%s:%d:%d|t", style.texture, previewHeight, previewWidth)
    return string.format("%s  %s", label, preview)
end

local function buildCategoryFilter(options)
    local includeCategory = options and options.includeCategory
    local filter = {}
    if includeCategory == nil or includeCategory == true then
        for key in pairs(CATEGORY_LABELS) do
            filter[key] = true
        end
    elseif type(includeCategory) == "table" then
        for key in pairs(CATEGORY_LABELS) do
            filter[key] = not not includeCategory[key]
        end
    else
        -- Explicitly disable all categories if includeCategory is false/invalid
        for key in pairs(CATEGORY_LABELS) do
            filter[key] = false
        end
    end
    return filter
end

function BarBorders.GetStyle(key)
    return STYLE_MAP[key]
end

function BarBorders.GetDropdownEntries(options)
    options = options or {}
    local categoryFilter = buildCategoryFilter(options)

    local container
    if _G.Settings and Settings.CreateControlTextContainer then
        container = Settings.CreateControlTextContainer()
    end

    local entries = {}

    local function addEntry(value, text)
        if container then
            container:Add(value, text)
        else
            entries[#entries + 1] = { value = value, text = text }
        end
    end

    addEntry("square", "Default (Square)")

    for _, key in ipairs(STYLE_ORDER) do
        local style = STYLE_MAP[key]
        if style then
            local include = true
            if style.category and categoryFilter[style.category] ~= nil then
                include = categoryFilter[style.category]
            end
            if include then
                addEntry(style.key, formatMenuLabel(style, options))
            end
        end
    end

    if container then
        return container:GetData()
    end
    return entries
end

function BarBorders.ApplyToBarFrame(barFrame, styleKey, options)
    if not barFrame or type(barFrame.GetObjectType) ~= "function" or barFrame:GetObjectType() ~= "StatusBar" then
        return false
    end

    if not styleKey or styleKey == "square" then
        BarBorders.ClearBarFrame(barFrame)
        return false
    end

    local style = STYLE_MAP[styleKey]
    if not style then
        BarBorders.ClearBarFrame(barFrame)
        return false
    end

    -- Initialize state BEFORE ensureSizeHook so proxy can use sizeProxyParentRef
    local bfState = borderFrameState[barFrame] or {}
    borderFrameState[barFrame] = bfState

    if type(options) == "table" and options.sizeProxyParent then
        bfState.sizeProxyParentRef = options.sizeProxyParent
    end

    ensureSizeHook(barFrame)

    local thickness = tonumber(options and options.thickness) or 1
    if thickness < 1 then thickness = 1 end
    if thickness > 32 then thickness = 32 end

    local color = cloneColor(options and options.color)

    -- Re-show the size proxy if it was hidden by a previous ClearBarFrame call
    if bfState.sizeProxy then
        bfState.sizeProxy:Show()
    end

    -- Allow callers (e.g., Unit Frames) to request a specific relative level/parent so text stays above borders
    if type(options) == "table" and options.levelOffset then
        bfState.levelOffset = tonumber(options.levelOffset) or 8
    else
        bfState.levelOffset = 8
    end
    if type(options) == "table" and options.containerParent and options.containerParent.GetFrameLevel then
        bfState.containerParentRef = options.containerParent
    else
        bfState.containerParentRef = nil
    end
    bfState.insetH = tonumber(options and options.insetH) or tonumber(options and options.inset) or 0
    bfState.insetV = tonumber(options and options.insetV) or tonumber(options and options.inset) or 0
    -- Allow callers to specify an alternate frame to anchor the border to (e.g., clipping container)
    if type(options) == "table" and options.anchorTarget and options.anchorTarget.GetHeight then
        bfState.anchorTarget = options.anchorTarget
    else
        bfState.anchorTarget = nil
    end
    if type(options) == "table" and type(options.padAdjust) == "table" then
        bfState.padAdjust = options.padAdjust
    else
        bfState.padAdjust = nil
    end

    return applyStyle(barFrame, style, color, thickness, false, nil, bfState.insetH, bfState.insetV)
end

function BarBorders.ClearBarFrame(barFrame)
    if not barFrame then return end
    local bfState = borderFrameState[barFrame]
    if bfState then
        bfState.state = nil
        local holder = bfState.holder
        if holder then
            if holder.SetBackdrop then pcall(holder.SetBackdrop, holder, nil) end
            holder:Hide()
        end
        -- Hide the size proxy to suppress unnecessary OnSizeChanged events
        -- while no border is active (handleSizeChanged already early-returns
        -- when bfState.state is nil, but hiding avoids the call entirely).
        local proxy = bfState.sizeProxy
        if proxy then
            proxy:Hide()
        end
    end
end

-- Accessor for other modules to get the border holder frame without reading
-- directly from the Blizzard frame table (avoids taint)
function BarBorders.GetBorderHolder(barFrame)
    local bfState = borderFrameState[barFrame]
    return bfState and bfState.holder
end

-- Accessor for full border state (holder, state, etc.)
function BarBorders.GetBorderState(barFrame)
    return borderFrameState[barFrame]
end

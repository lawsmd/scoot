--------------------------------------------------------------------------------
-- groupauras/icons.lua
-- Icon frame pool, styling, sizing, and positioning for aura tracking icons
--
-- Depends on groupauras/core.lua (HA namespace, rainbow engine, state tables)
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local POOL_PREALLOC = 40
local BASE_SIZE_RATIO = 0.45  -- Icon base size as ratio of group frame height
local MIN_ICON_SIZE = 10
local MAX_ICON_SIZE = 64

--------------------------------------------------------------------------------
-- Anchor Maps
--------------------------------------------------------------------------------

-- Inside frame: icon anchors to matching point on the group frame. 9 values.
-- Outside-frame anchoring was removed in the 12.0.5 rework (see gfauratracking.md
-- Background > 12.0.5 architectural lockdown). Visual conflict with Blizzard's
-- native icons is now handled by the Hide Blizzard Buff Icons toggle (the
-- raidFramesDisplayBuffs game setting, 12.1), not by moving Scoot icons outside
-- the frame.
HA.INSIDE_ANCHOR_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}
table.freeze(HA.INSIDE_ANCHOR_VALUES)
HA.INSIDE_ANCHOR_ORDER = {
    "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
table.freeze(HA.INSIDE_ANCHOR_ORDER)

-- Horizontal flow direction per anchor. Right-edge anchors grow leftward (rank 2
-- sits to the left of rank 1). All other anchors grow rightward.
local ANCHOR_DIRECTION = {
    TOPLEFT     =  1,
    TOP         =  1,
    TOPRIGHT    = -1,
    LEFT        =  1,
    CENTER      =  1,
    RIGHT       = -1,
    BOTTOMLEFT  =  1,
    BOTTOM      =  1,
    BOTTOMRIGHT = -1,
}
table.freeze(ANCHOR_DIRECTION)

-- Vertical flow direction per anchor. Bottom-edge anchors grow upward (rank 4+
-- wraps to a row ABOVE the first row), keeping icons away from the bottom edge.
-- Every other anchor grows downward (row 2+ sits BELOW row 1). Mirrors Blizzard's
-- Legacy layout which is BottomRightToTopLeft for Buffs.
local ROW_GROWTH_DIR = {
    TOPLEFT     = -1,
    TOP         = -1,
    TOPRIGHT    = -1,
    LEFT        = -1,
    CENTER      = -1,
    RIGHT       = -1,
    BOTTOMLEFT  =  1,
    BOTTOM      =  1,
    BOTTOMRIGHT =  1,
}
table.freeze(ROW_GROWTH_DIR)

-- Wrap to a new row after this many icons. Matches Blizzard's Legacy /
-- BuffsRightDebuffsLeft layout (3 cols × 2 rows = up to 6 buffs).
local COLS_PER_ROW = 3

--------------------------------------------------------------------------------
-- Icon Frame Pool
--------------------------------------------------------------------------------

local iconPool = {}

local function CreateIconFrame()
    local icon = CreateFrame("Frame", nil, UIParent)
    icon:SetSize(16, 16)
    -- MEDIUM (core/strata.lua), not HIGH: Blizzard's raid frames are LOW
    -- (CompactUnitFrame.xml:3), so MEDIUM still covers them -- and unlike HIGH
    -- it lets an open Blizzard panel cover us. Level unchanged.
    addon.Strata.ApplyHUD(icon, 20)

    -- Icon texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    icon.Icon = tex

    -- Cooldown sweep
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(false)
    cd:SetHideCountdownNumbers(true)
    icon.Cooldown = cd

    -- Text overlay sits above the Cooldown drain swipe so stack numbers
    -- stay fully opaque regardless of showDuration progress.
    local textOverlay = CreateFrame("Frame", nil, icon)
    textOverlay:SetAllPoints(icon)
    textOverlay:SetFrameLevel((cd:GetFrameLevel() or icon:GetFrameLevel()) + 5)
    icon.TextOverlay = textOverlay

    -- Stack count text (parented to the text overlay, anchored to the icon)
    local count = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    count:Hide()
    icon.CountText = count

    -- Tracking fields
    icon.spellId = nil
    icon._isRainbow = false

    icon:Hide()
    return icon
end

-- Pre-allocate pool
local function PreallocatePool()
    for i = 1, POOL_PREALLOC do
        local icon = CreateIconFrame()
        table.insert(iconPool, icon)
    end
end

function HA.AcquireIcon(parent)
    local icon = table.remove(iconPool)
    if not icon then
        if InCombatLockdown() then
            -- Cannot create frames during combat; defer
            return nil
        end
        icon = CreateIconFrame()
    end
    -- Never SetParent to Blizzard frames — causes taint propagation.
    -- Icons stay parented to UIParent; anchored to group frames via SetPoint.
    return icon
end

function HA.ReleaseIcon(icon)
    if not icon then return end
    icon:Hide()
    icon:ClearAllPoints()
    icon:SetParent(UIParent)
    icon.spellId = nil

    -- Detach animation controller
    HA.DetachAnimation(icon)

    -- Remove from rainbow tracking
    if icon._isRainbow and icon.Icon then
        HA.UnregisterRainbowIcon(icon.Icon)
        icon._isRainbow = false
    end

    -- Reset cooldown and swipe state
    if icon.Cooldown then
        icon.Cooldown:Clear()
        icon.Cooldown:SetDrawSwipe(true)
        icon.Cooldown:SetReverse(true)
        icon.Cooldown:SetSwipeColor(0, 0, 0, 0.85)
        icon.Cooldown:SetDrawEdge(false)
        icon.Cooldown:SetDrawBling(false)
        pcall(function()
            icon.Cooldown:SetTexCoordRange({ x = 0, y = 0 }, { x = 1, y = 1 })
        end)
    end

    -- Reset stack text
    if icon.CountText then
        icon.CountText:Hide()
        icon.CountText:SetText("")
    end

    -- Reset icon texture and anchoring
    if icon.Icon then
        icon.Icon:SetDesaturated(false)
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon.Icon:ClearAllPoints()
        icon.Icon:SetAllPoints()
    end

    -- Reset border backing
    if icon.BorderTex then
        icon.BorderTex:Hide()
    end

    table.insert(iconPool, icon)
end

--------------------------------------------------------------------------------
-- Icon Styling
--------------------------------------------------------------------------------

local function GetSpellConfig(spellId)
    -- Resolve linked variants to their primary entry's config
    local configId = spellId
    if HA.LINKED_TO_PRIMARY and HA.LINKED_TO_PRIMARY[spellId] then
        configId = HA.LINKED_TO_PRIMARY[spellId]
    end

    local db = addon.db and addon.db.profile
    local gf = db and db.groupFrames
    local ha = gf and gf.auraTracking
    local spells = ha and ha.spells
    if not spells or not spells[configId] then
        return HA.SPELL_DEFAULTS
    end
    return setmetatable(spells[configId], { __index = HA.SPELL_DEFAULTS })
end

-- Exported for ReflowIconsForFrame to resolve per-spell anchor/rank config.
HA._GetSpellConfig = GetSpellConfig

function HA.StyleIcon(iconFrame, spellId, auraData, groupFrame, unit)
    if not iconFrame or not spellId then return end

    local config = GetSpellConfig(spellId)
    iconFrame.spellId = spellId

    -- Parse prefix variants (border:, wide:)
    local style = config.iconStyle
    local isBordered = style:sub(1, 7) == "border:"
    local isWide = style:sub(1, 5) == "wide:"
    local effectiveStyle = style
    if isBordered then
        effectiveStyle = style:sub(8)
    elseif isWide then
        effectiveStyle = style:sub(6)
    end

    -- Set icon texture
    local tex = iconFrame.Icon
    local isAnimated = effectiveStyle:sub(1, 5) == "anim:"
    if isAnimated then
        -- Animated icon: hide standard texture, use animation controller
        tex:Hide()
    elseif effectiveStyle == "spell" then
        -- Try runtime API first (most accurate), static textureId as fallback
        tex:Show()
        HA.DetachAnimation(iconFrame)
        local spellTex
        local ok = pcall(function()
            spellTex = C_Spell.GetSpellTexture(spellId)
        end)
        if ok and spellTex then
            tex:SetTexture(spellTex)
        else
            -- Fallback to static textureId (works when API fails, e.g. secrets)
            local registryEntry = HA.SPELL_REGISTRY_BY_ID and HA.SPELL_REGISTRY_BY_ID[spellId]
            local staticTex = registryEntry and registryEntry.textureId
            if staticTex then
                tex:SetTexture(staticTex)
            else
                tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
        end
    elseif effectiveStyle:sub(1, 5) == "file:" then
        -- File-based custom texture
        tex:Show()
        HA.DetachAnimation(iconFrame)
        local path = effectiveStyle:sub(6)
        tex:SetTexture(path)
    else
        -- Atlas-based icon
        tex:Show()
        HA.DetachAnimation(iconFrame)
        local atlasOk = pcall(tex.SetAtlas, tex, effectiveStyle)
        if not atlasOk then
            tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end

    -- Border variant: same-shape black backing with 1px inset
    if isBordered then
        if not iconFrame.BorderTex then
            local bt = iconFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
            bt:SetAllPoints()
            iconFrame.BorderTex = bt
        end
        -- Use the same atlas shape colored black for a matching silhouette border
        local borderAtlasOk = pcall(iconFrame.BorderTex.SetAtlas, iconFrame.BorderTex, effectiveStyle)
        if not borderAtlasOk then
            iconFrame.BorderTex:SetColorTexture(0, 0, 0, 1)
        end
        iconFrame.BorderTex:SetDesaturated(true)
        iconFrame.BorderTex:SetVertexColor(0, 0, 0, 1)
        iconFrame.BorderTex:Show()
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    else
        if iconFrame.BorderTex then
            iconFrame.BorderTex:Hide()
        end
        tex:ClearAllPoints()
        tex:SetAllPoints()
    end

    -- Apply desaturation and color
    local colorMode = config.iconColor or "original"
    -- Remove from rainbow if switching away
    if iconFrame._isRainbow then
        HA.UnregisterRainbowIcon(tex)
        iconFrame._isRainbow = false
    end

    if colorMode == "original" then
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1, 1)
    elseif colorMode == "rainbow" then
        tex:SetDesaturated(true)
        HA.RegisterRainbowIcon(tex)
        iconFrame._isRainbow = true
    elseif colorMode == "custom" then
        tex:SetDesaturated(true)
        local c = config.iconCustomColor or { 1, 1, 1, 1 }
        tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        tex:SetDesaturated(true)
        tex:SetVertexColor(1, 1, 1, 1)
    end

    -- Size based on group frame height + user scale
    -- Use OOC-cached height to avoid tainted GetHeight() reads in combat
    local frameHeight = 36
    if groupFrame then
        local state = HA._getState and HA._getState(groupFrame)
        if state and state.cachedHeight and state.cachedHeight > 0 then
            frameHeight = state.cachedHeight
        elseif not InCombatLockdown() then
            local ok, h = pcall(groupFrame.GetHeight, groupFrame)
            if ok and type(h) == "number" and h > 0 then
                frameHeight = h
                if state then
                    state.cachedHeight = h
                end
            end
        end
    end
    local baseSize = math.max(MIN_ICON_SIZE, frameHeight * BASE_SIZE_RATIO)
    local userScale = (config.iconScale or 100) / 100
    local finalSize = math.min(MAX_ICON_SIZE, math.max(MIN_ICON_SIZE, baseSize * userScale))
    -- Wide variant: 3x width
    if isWide then
        iconFrame:SetSize(finalSize * 3, finalSize)
    else
        iconFrame:SetSize(finalSize, finalSize)
    end

    -- Position the icon
    HA.PositionIcon(iconFrame, config, groupFrame)

    -- Attach animated icon controller (after sizing is finalized)
    if isAnimated then
        local animId = effectiveStyle:sub(6)
        HA.AttachAnimation(iconFrame, animId, config, finalSize)
    end

    -- Duration display configuration
    local showDuration = config.showDuration
    if showDuration == nil then showDuration = true end

    if showDuration and not isAnimated then
        -- Configure drain swipe: icon "drains" to dark as duration expires
        iconFrame.Cooldown:SetDrawSwipe(true)
        iconFrame.Cooldown:SetSwipeColor(0, 0, 0, 0.85)
        iconFrame.Cooldown:SetReverse(true)
        iconFrame.Cooldown:SetDrawEdge(false)
        iconFrame.Cooldown:SetDrawBling(false)

        -- Set swipe texture to match the icon for a shaped drain effect
        if effectiveStyle == "spell" then
            local swipeTex
            pcall(function() swipeTex = C_Spell.GetSpellTexture(spellId) end)
            if not swipeTex then
                local entry = HA.SPELL_REGISTRY_BY_ID and HA.SPELL_REGISTRY_BY_ID[spellId]
                swipeTex = entry and entry.textureId
            end
            if swipeTex then
                iconFrame.Cooldown:SetSwipeTexture(swipeTex)
            end
        elseif effectiveStyle:sub(1, 5) == "file:" then
            iconFrame.Cooldown:SetSwipeTexture(effectiveStyle:sub(6))
        else
            -- Atlas-based: resolve to file + tex coords for swipe texture
            local atlasKey = effectiveStyle
            if isBordered then atlasKey = effectiveStyle end
            local atlasInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlasKey)
            if atlasInfo and (atlasInfo.file or atlasInfo.filename) then
                iconFrame.Cooldown:SetSwipeTexture(atlasInfo.file or atlasInfo.filename)
                pcall(function()
                    iconFrame.Cooldown:SetTexCoordRange(
                        { x = atlasInfo.leftTexCoord, y = atlasInfo.topTexCoord },
                        { x = atlasInfo.rightTexCoord, y = atlasInfo.bottomTexCoord }
                    )
                end)
            end
        end
    else
        -- No drain: disable swipe (animated icons handle duration separately)
        iconFrame.Cooldown:SetDrawSwipe(false)
    end

    -- Cooldown sweep timing (DurationObject pattern — matches ScootAuras, secret-safe)
    local cdSet = false
    if auraData and auraData.auraInstanceID and unit
       and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local dOk, dObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
        if dOk and dObj then
            pcall(iconFrame.Cooldown.SetCooldownFromDurationObject, iconFrame.Cooldown, dObj)
            iconFrame.Cooldown:Show()
            cdSet = true
        end
    end
    if not cdSet then
        -- Fallback to legacy arithmetic (non-secret values only)
        if auraData and auraData.expirationTime and auraData.expirationTime > 0
           and auraData.duration and auraData.duration > 0 then
            local startTime = auraData.expirationTime - auraData.duration
            iconFrame.Cooldown:SetCooldown(startTime, auraData.duration)
            iconFrame.Cooldown:Show()
        else
            iconFrame.Cooldown:Clear()
        end
    end

    -- Wire duration data to animated icon controller
    if isAnimated then
        local AE = HA.AnimEngine
        local ctrl = AE and AE.GetActive(iconFrame)
        if ctrl and ctrl.SetDuration then
            local dObj = nil
            local fallbackStart = 0
            local fallbackTotal = 0
            if auraData and auraData.auraInstanceID and unit
               and C_UnitAuras and C_UnitAuras.GetAuraDuration then
                local dOk, d = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                if dOk and d then dObj = d end
            end
            if auraData and auraData.expirationTime and auraData.expirationTime > 0
               and auraData.duration and auraData.duration > 0 then
                fallbackStart = auraData.expirationTime - auraData.duration
                fallbackTotal = auraData.duration
            end
            -- Pass cached group frame height for descend/ascend travel distance
            ctrl:SetDuration(dObj, fallbackStart, fallbackTotal, frameHeight)
        end
    end

    -- Stack count
    if auraData and auraData.applications and auraData.applications > 1 then
        iconFrame.CountText:SetText(tostring(auraData.applications))

        -- Apply per-spell stacksText styling when configured. Defaults from
        -- HA.STACKS_TEXT_DEFAULTS preserve the historical look (white OUTLINE
        -- 12pt at BOTTOMRIGHT) when the user hasn't touched the tab.
        local st = config and rawget(config, "stacksText")
        local defaults = HA.STACKS_TEXT_DEFAULTS or {}
        local function stGet(k)
            if st and st[k] ~= nil then return st[k] end
            return defaults[k]
        end

        local fontFace = stGet("fontFace") or "FRIZQT__"
        local size     = tonumber(stGet("size")) or 12
        local style    = stGet("style") or "OUTLINE"
        local anchor   = stGet("anchor") or "BOTTOMRIGHT"
        local offsetX  = tonumber(stGet("offsetX")) or 0
        local offsetY  = tonumber(stGet("offsetY")) or 0
        local colorMode = stGet("colorMode") or "default"

        local fontPath = addon.ResolveFontFace and addon.ResolveFontFace(fontFace)
        if fontPath then
            if addon.ApplyFontStyle then
                -- Routes through Scoot's font-style helper so SHADOW / HEAVY /
                -- STROKE prefixes render correctly, matching other Scoot text.
                pcall(addon.ApplyFontStyle, iconFrame.CountText, fontPath, size, style)
            else
                pcall(iconFrame.CountText.SetFont, iconFrame.CountText, fontPath, size, style)
            end
        end

        if colorMode == "custom" then
            local c = stGet("customColor") or { 1, 1, 1, 1 }
            pcall(iconFrame.CountText.SetTextColor, iconFrame.CountText,
                c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            pcall(iconFrame.CountText.SetTextColor, iconFrame.CountText, 1, 1, 1, 1)
        end

        iconFrame.CountText:ClearAllPoints()
        iconFrame.CountText:SetPoint(anchor, iconFrame, anchor, offsetX, offsetY)

        iconFrame.CountText:Show()
    else
        iconFrame.CountText:Hide()
    end

    iconFrame:Show()
end

--------------------------------------------------------------------------------
-- Icon Positioning
--------------------------------------------------------------------------------

-- Center-anchor compensation: shift icon CENTER inward so it sits fully within
-- the frame regardless of scale. Only the first icon in an anchor group uses
-- its anchor's full compensation; subsequent icons offset along the group's
-- direction axis.
local INSIDE_CENTER_OFFSET = {
    TOPLEFT     = {  1, -1 },  -- push right and down
    TOP         = {  0, -1 },  -- push down
    TOPRIGHT    = { -1, -1 },  -- push left and down
    LEFT        = {  1,  0 },  -- push right
    CENTER      = {  0,  0 },
    RIGHT       = { -1,  0 },  -- push left
    BOTTOMLEFT  = {  1,  1 },  -- push right and up
    BOTTOM      = {  0,  1 },  -- push up
    BOTTOMRIGHT = { -1,  1 },  -- push left and up
}
table.freeze(INSIDE_CENTER_OFFSET)

local function GetGroupSpacing(anchor)
    local db = addon.db and addon.db.profile
    local at = db and db.groupFrames and db.groupFrames.auraTracking
    local map = at and at.positionGroupSpacing
    if type(map) == "table" and type(map[anchor]) == "number" then
        return map[anchor]
    end
    return 2
end

-- Place a single icon at a given horizontal + vertical offset from its anchor.
-- offsetX/offsetY are relative to the anchor point, measured along the group's
-- direction (the direction multipliers are baked in at the call site). The
-- INSIDE_CENTER_OFFSET compensation keeps the icon tucked inside the frame at
-- its anchor corner; vertical row growth is added on top.
local function PlaceIcon(iconFrame, groupFrame, anchor, offsetX, offsetY)
    offsetY = offsetY or 0
    iconFrame:ClearAllPoints()
    local halfW = iconFrame:GetWidth() * 0.5
    local halfH = iconFrame:GetHeight() * 0.5
    local comp = INSIDE_CENTER_OFFSET[anchor] or INSIDE_CENTER_OFFSET.TOPRIGHT
    iconFrame:SetPoint(
        "CENTER", groupFrame, anchor,
        offsetX + comp[1] * halfW,
        offsetY + comp[2] * halfH
    )
end

-- Reflow all active icons on a frame: group by anchor, sort by rank, offset
-- each icon from the previous by (prev_w/2 + curr_w/2 + positionGroupSpacing)
-- along the anchor's direction.
function HA.ReflowIconsForFrame(groupFrame)
    if not groupFrame then return end
    local state = HA._getState and HA._getState(groupFrame)
    if not state or not state.iconFrames then return end

    -- Bucket active icons by anchor key
    local groups = {}
    for spellId, iconFrame in pairs(state.iconFrames) do
        local cfg = HA._GetSpellConfig and HA._GetSpellConfig(spellId)
        if cfg then
            local anchor = cfg.anchor or "BOTTOMRIGHT"
            if not HA.INSIDE_ANCHOR_VALUES[anchor] then anchor = "BOTTOMRIGHT" end
            local rank = tonumber(cfg.rank) or 1
            groups[anchor] = groups[anchor] or {}
            table.insert(groups[anchor], {
                iconFrame = iconFrame,
                rank      = rank,
                spellId   = spellId,
                config    = cfg,
            })
        end
    end

    -- Sort each group by (rank asc, spellId asc) and lay out in a grid that
    -- wraps to a new row every COLS_PER_ROW icons. Direction per anchor:
    --   X  →  ANCHOR_DIRECTION  (±1 per step)
    --   Y  →  ROW_GROWTH_DIR    (±1 per row)
    for anchor, members in pairs(groups) do
        table.sort(members, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return (a.spellId or 0) < (b.spellId or 0)
        end)

        local spacing = GetGroupSpacing(anchor)
        local xDir = ANCHOR_DIRECTION[anchor] or 1
        local yDir = ROW_GROWTH_DIR[anchor] or -1

        -- Row-step height uses the first icon's height as the canonical row
        -- step for this anchor. Mixed iconScale groups all step by the same
        -- amount, which keeps rows visually aligned.
        local rowStep = 0
        if members[1] then
            rowStep = members[1].iconFrame:GetHeight() + spacing
        end

        local rowCursor = 0  -- running horizontal offset magnitude within the current row
        local prevHalfW = 0
        local lastRow = -1

        for idx, entry in ipairs(members) do
            local iconFrame = entry.iconFrame
            local halfW = iconFrame:GetWidth() * 0.5
            local col = (idx - 1) % COLS_PER_ROW
            local row = math.floor((idx - 1) / COLS_PER_ROW)

            if row ~= lastRow then
                -- First icon in this row: reset horizontal cursor.
                rowCursor = 0
                prevHalfW = halfW
                lastRow = row
            else
                rowCursor = rowCursor + prevHalfW + halfW + spacing
                prevHalfW = halfW
            end

            local offsetX = rowCursor * xDir
            local offsetY = row * rowStep * yDir

            -- Per-icon fine-tune on top of auto-placement. Raw pixels, not
            -- multiplied by xDir/yDir — +X always means right, +Y always up.
            local cfg = entry.config
            offsetX = offsetX + (tonumber(cfg and cfg.offsetX) or 0)
            offsetY = offsetY + (tonumber(cfg and cfg.offsetY) or 0)

            PlaceIcon(iconFrame, groupFrame, anchor, offsetX, offsetY)
        end
    end
end

-- Back-compat API: per-icon positioning was the old single-pass model. The new
-- rank-grouped model requires whole-frame reflow, so this wraps ReflowIcons.
-- Callers that invoke this per-icon still work, but at O(N*M) total (caller
-- iterates N icons, each call reflows all M siblings). For hot paths prefer
-- calling HA.ReflowIconsForFrame once after all sizing updates are done.
function HA.PositionIcon(iconFrame, config, groupFrame)
    HA.ReflowIconsForFrame(groupFrame)
end

--------------------------------------------------------------------------------
-- Animation Helpers
--------------------------------------------------------------------------------

function HA.AttachAnimation(iconFrame, animId, config, size)
    local AE = HA.AnimEngine
    if not AE then return end

    -- If same animation is already attached, just update size/color
    local existing = AE.GetActive(iconFrame)
    if existing and existing.animId == animId then
        existing:SetSize(size)
        HA.ApplyAnimColor(existing, config)
        return
    end

    -- Release old, acquire new
    AE.Release(iconFrame)
    local ctrl = AE.Acquire(iconFrame, iconFrame)
    if not ctrl then return end
    ctrl:Configure(animId, size)
    HA.ApplyAnimColor(ctrl, config)
    ctrl:Play()
end

function HA.DetachAnimation(iconFrame)
    local AE = HA.AnimEngine
    if AE then AE.Release(iconFrame) end
end

function HA.ApplyAnimColor(ctrl, config)
    local mode = config.iconColor or "original"
    if mode == "custom" then
        local c = config.iconCustomColor or { 1, 1, 1, 1 }
        ctrl:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        ctrl.rainbowMode = false
    elseif mode == "rainbow" then
        ctrl.rainbowMode = true
    else
        ctrl:SetColor(1, 1, 1, 1)
        ctrl.rainbowMode = false
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- Pre-allocate icon pool after PLAYER_ENTERING_WORLD
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    PreallocatePool()
    self:UnregisterAllEvents()
end)

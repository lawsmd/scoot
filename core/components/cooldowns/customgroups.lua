-- customgroups.lua - Custom CDM Groups data model, HUD frames, and component registration
local addonName, addon = ...

local Component = addon.ComponentPrototype

--------------------------------------------------------------------------------
-- Data Model
--------------------------------------------------------------------------------

addon.CustomGroups = {}
local CG = addon.CustomGroups

-- Ensure the DB structure exists for all 3 groups
local function EnsureGroupsDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.customCDMGroups then
        profile.customCDMGroups = {
            [1] = { entries = {} },
            [2] = { entries = {} },
            [3] = { entries = {} },
        }
    end
    for i = 1, 3 do
        if not profile.customCDMGroups[i] then
            profile.customCDMGroups[i] = { entries = {} }
        end
        if not profile.customCDMGroups[i].entries then
            profile.customCDMGroups[i].entries = {}
        end
    end
    return profile.customCDMGroups
end

--- Get the entries array for a group (1-3).
--- @param groupIndex number
--- @return table
function CG.GetEntries(groupIndex)
    local groups = EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return {} end
    return groups[groupIndex].entries
end

--- Add an entry to a group. Rejects duplicates (same type+id in the same group).
--- @param groupIndex number
--- @param entryType string "spell" or "item"
--- @param id number
--- @return boolean success
function CG.AddEntry(groupIndex, entryType, id)
    if not groupIndex or not entryType or not id then return false end
    local entries = CG.GetEntries(groupIndex)

    -- Duplicate check within this group
    for _, entry in ipairs(entries) do
        if entry.type == entryType and entry.id == id then
            return false
        end
    end

    table.insert(entries, { type = entryType, id = id })
    CG.FireCallback()
    return true
end

--- Remove an entry by position from a group.
--- @param groupIndex number
--- @param entryIndex number
function CG.RemoveEntry(groupIndex, entryIndex)
    local entries = CG.GetEntries(groupIndex)
    if entryIndex < 1 or entryIndex > #entries then return end
    table.remove(entries, entryIndex)
    CG.FireCallback()
end

--- Move an entry from one group to another (or same group, different position).
--- @param fromGroup number
--- @param fromIndex number
--- @param toGroup number
--- @param toIndex number
function CG.MoveEntry(fromGroup, fromIndex, toGroup, toIndex)
    local srcEntries = CG.GetEntries(fromGroup)
    if fromIndex < 1 or fromIndex > #srcEntries then return end

    local entry = table.remove(srcEntries, fromIndex)
    local dstEntries = CG.GetEntries(toGroup)

    -- Clamp target index
    toIndex = math.max(1, math.min(toIndex, #dstEntries + 1))
    table.insert(dstEntries, toIndex, entry)
    CG.FireCallback()
end

--- Reorder an entry within the same group.
--- @param groupIndex number
--- @param fromIndex number
--- @param toIndex number
function CG.ReorderEntry(groupIndex, fromIndex, toIndex)
    local entries = CG.GetEntries(groupIndex)
    if fromIndex < 1 or fromIndex > #entries then return end
    toIndex = math.max(1, math.min(toIndex, #entries))
    if fromIndex == toIndex then return end

    local entry = table.remove(entries, fromIndex)
    table.insert(entries, toIndex, entry)
    CG.FireCallback()
end

--- Optional callback for UI refresh when data changes.
CG._callbacks = {}

function CG.RegisterCallback(fn)
    table.insert(CG._callbacks, fn)
end

function CG.FireCallback()
    for _, fn in ipairs(CG._callbacks) do
        pcall(fn)
    end
end

--- Get the custom name for a group (nil if not set).
--- @param groupIndex number
--- @return string|nil
function CG.GetGroupName(groupIndex)
    local groups = EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return nil end
    return groups[groupIndex].name
end

--- Set a custom name for a group. Stores trimmed name; nil/empty clears it.
--- @param groupIndex number
--- @param name string|nil
function CG.SetGroupName(groupIndex, name)
    local groups = EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return end
    if name and type(name) == "string" then
        name = strtrim(name)
        if name == "" then name = nil end
    else
        name = nil
    end
    groups[groupIndex].name = name
    CG.FireCallback()
end

--- Get the display name for a group: custom name or fallback "Custom Group X".
--- @param groupIndex number
--- @return string
function CG.GetGroupDisplayName(groupIndex)
    local customName = CG.GetGroupName(groupIndex)
    if customName then return customName end
    return "Custom Group " .. groupIndex
end

--------------------------------------------------------------------------------
-- HUD Frame Pool + Creation Helpers
--------------------------------------------------------------------------------

addon.CustomGroupContainers = {}
local containers = addon.CustomGroupContainers

-- Per-container icon pools and active icon lists
local iconPools = { {}, {}, {} }       -- released icons per group
local activeIcons = { {}, {}, {} }     -- visible icons per group

-- GCD threshold: cooldowns shorter than this are ignored (GCD)
local MIN_CD_DURATION = 1.5

-- Item cooldown ticker handle
local itemTicker = nil
local trackedItemCount = 0

-- Cooldown end times for per-icon opacity (weak keys for GC)
local cgCooldownEndTimes = setmetatable({}, { __mode = "k" })

-- Whether HUD system has been initialized
local cgInitialized = false

local function CreateIconFrame(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(30, 30)
    icon:EnableMouse(true)

    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetAllPoints()

    icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints(icon.Icon)
    icon.Cooldown:SetDrawEdge(false)
    icon.Cooldown:SetHideCountdownNumbers(false)

    icon.CountText = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    icon.CountText:SetDrawLayer("OVERLAY", 7)
    icon.CountText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    icon.CountText:Hide()

    icon.keybindText = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    icon.keybindText:SetDrawLayer("OVERLAY", 7)
    icon.keybindText:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
    icon.keybindText:Hide()

    -- Tooltip scripts
    icon:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.entry.type == "spell" then
            GameTooltip:SetSpellByID(self.entry.id)
        elseif self.entry.type == "item" then
            GameTooltip:SetItemByID(self.entry.id)
        end
        GameTooltip:Show()
    end)

    icon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Square border edges
    icon.borderEdges = {
        Top = icon:CreateTexture(nil, "OVERLAY", nil, 1),
        Bottom = icon:CreateTexture(nil, "OVERLAY", nil, 1),
        Left = icon:CreateTexture(nil, "OVERLAY", nil, 1),
        Right = icon:CreateTexture(nil, "OVERLAY", nil, 1),
    }
    for _, tex in pairs(icon.borderEdges) do
        tex:Hide()
    end

    -- Atlas border
    icon.atlasBorder = icon:CreateTexture(nil, "OVERLAY", nil, 1)
    icon.atlasBorder:Hide()

    return icon
end

local function AcquireIcon(groupIndex, parent)
    local pool = iconPools[groupIndex]
    local icon = table.remove(pool)
    if not icon then
        icon = CreateIconFrame(parent)
    else
        icon:SetParent(parent)
    end
    icon:EnableMouse(true)
    icon:Show()
    return icon
end

local ICON_TEXCOORD_INSET = 0.07  -- crop outer ~7% to hide baked-in border art

local function ReleaseIcon(groupIndex, icon)
    icon:Hide()
    icon:EnableMouse(false)
    icon:ClearAllPoints()
    icon.Icon:SetTexture(nil)
    icon.Icon:SetDesaturated(false)
    icon.Icon:SetTexCoord(ICON_TEXCOORD_INSET, 1 - ICON_TEXCOORD_INSET,
                           ICON_TEXCOORD_INSET, 1 - ICON_TEXCOORD_INSET)
    icon.Cooldown:Clear()
    icon.CountText:SetText("")
    icon.CountText:Hide()
    if icon.keybindText then
        icon.keybindText:SetText("")
        icon.keybindText:Hide()
    end
    icon:SetAlpha(1.0)
    -- Hide borders
    for _, tex in pairs(icon.borderEdges) do
        tex:Hide()
    end
    icon.atlasBorder:Hide()
    icon.entry = nil
    icon.entryIndex = nil
    cgCooldownEndTimes[icon] = nil
    table.insert(iconPools[groupIndex], icon)
end

local function ReleaseAllIcons(groupIndex)
    local icons = activeIcons[groupIndex]
    for i = #icons, 1, -1 do
        ReleaseIcon(groupIndex, icons[i])
        icons[i] = nil
    end
end

--------------------------------------------------------------------------------
-- Icon Dimension Helpers
--------------------------------------------------------------------------------

local function GetIconDimensions(db)
    local baseSize = tonumber(db.iconSize) or 30
    local ratio = tonumber(db.tallWideRatio) or 0

    if ratio == 0 then
        return baseSize, baseSize
    end

    -- Use addon.IconRatio if available
    if addon.IconRatio and addon.IconRatio.CalculateDimensions then
        return addon.IconRatio.CalculateDimensions(baseSize, ratio)
    end

    -- Manual fallback
    if ratio > 0 then
        local widthFactor = 1 - (ratio / 100)
        return baseSize * math.max(0.33, widthFactor), baseSize
    else
        local heightFactor = 1 + (ratio / 100)
        return baseSize, baseSize * math.max(0.33, heightFactor)
    end
end

local function ApplyTexCoord(icon, iconW, iconH)
    local aspectRatio = iconW / iconH
    local inset = ICON_TEXCOORD_INSET
    local left, right, top, bottom = inset, 1 - inset, inset, 1 - inset

    if aspectRatio > 1.0 then
        local cropAmount = 1.0 - (1.0 / aspectRatio)
        local offset = cropAmount / 2.0
        top = top + offset * (1 - 2 * inset)
        bottom = bottom - offset * (1 - 2 * inset)
    elseif aspectRatio < 1.0 then
        local cropAmount = 1.0 - aspectRatio
        local offset = cropAmount / 2.0
        left = left + offset * (1 - 2 * inset)
        right = right - offset * (1 - 2 * inset)
    end

    icon.Icon:SetTexCoord(left, right, top, bottom)
end

--------------------------------------------------------------------------------
-- Border Application Helpers
--------------------------------------------------------------------------------

local function HideIconBorder(icon)
    for _, tex in pairs(icon.borderEdges) do
        tex:Hide()
    end
    icon.atlasBorder:Hide()
end

local function ApplySquareBorder(icon, opts)
    icon.atlasBorder:Hide()

    local edges = icon.borderEdges
    local thickness = math.max(1, tonumber(opts.thickness) or 1)
    local col = opts.color or {0, 0, 0, 1}
    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1
    local insetH = tonumber(opts.insetH) or tonumber(opts.inset) or 0
    local insetV = tonumber(opts.insetV) or tonumber(opts.inset) or 0

    for _, tex in pairs(edges) do
        tex:SetColorTexture(r, g, b, a)
    end

    edges.Top:ClearAllPoints()
    edges.Top:SetPoint("TOPLEFT", icon, "TOPLEFT", -insetH, insetV)
    edges.Top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", insetH, insetV)
    edges.Top:SetHeight(thickness)

    edges.Bottom:ClearAllPoints()
    edges.Bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -insetH, -insetV)
    edges.Bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", insetH, -insetV)
    edges.Bottom:SetHeight(thickness)

    edges.Left:ClearAllPoints()
    edges.Left:SetPoint("TOPLEFT", icon, "TOPLEFT", -insetH, insetV - thickness)
    edges.Left:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -insetH, -insetV + thickness)
    edges.Left:SetWidth(thickness)

    edges.Right:ClearAllPoints()
    edges.Right:SetPoint("TOPRIGHT", icon, "TOPRIGHT", insetH, insetV - thickness)
    edges.Right:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", insetH, -insetV + thickness)
    edges.Right:SetWidth(thickness)

    for _, tex in pairs(edges) do
        tex:Show()
    end
end

local function ApplyAtlasBorder(icon, opts, styleDef)
    -- Hide square borders
    for _, tex in pairs(icon.borderEdges) do
        tex:Hide()
    end

    local atlasTex = icon.atlasBorder
    local col
    if opts.tintEnabled and opts.tintColor then
        col = opts.tintColor
    else
        col = styleDef.defaultColor or {1, 1, 1, 1}
    end
    local r, g, b, a = col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1

    local atlasName = styleDef.atlas
    if not atlasName then return end

    atlasTex:SetAtlas(atlasName, true)
    atlasTex:SetVertexColor(r, g, b, a)

    local baseExpandX = styleDef.expandX or 0
    local baseExpandY = styleDef.expandY or baseExpandX
    local insetH = tonumber(opts.insetH) or tonumber(opts.inset) or 0
    local insetV = tonumber(opts.insetV) or tonumber(opts.inset) or 0
    local expandX = baseExpandX - insetH
    local expandY = baseExpandY - insetV

    local adjL = styleDef.adjustLeft or 0
    local adjR = styleDef.adjustRight or 0
    local adjT = styleDef.adjustTop or 0
    local adjB = styleDef.adjustBottom or 0

    atlasTex:ClearAllPoints()
    atlasTex:SetPoint("TOPLEFT", icon, "TOPLEFT", -expandX - adjL, expandY + adjT)
    atlasTex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", expandX + adjR, -expandY - adjB)
    atlasTex:Show()
end

local function ApplyBorderToIcon(icon, opts)
    local style = opts.style or "square"
    local styleDef = nil
    if style ~= "square" and addon.IconBorders and addon.IconBorders.GetStyle then
        styleDef = addon.IconBorders.GetStyle(style)
    end

    if styleDef and styleDef.type == "atlas" and styleDef.atlas then
        ApplyAtlasBorder(icon, opts, styleDef)
    else
        ApplySquareBorder(icon, opts)
    end
end

--------------------------------------------------------------------------------
-- Text Styling Helpers
--------------------------------------------------------------------------------

local function ApplyTextStyle(fontString, cfg, defaultSize)
    if not fontString or not cfg then return end

    local size = tonumber(cfg.size) or defaultSize or 12
    local style = cfg.style or "OUTLINE"
    local fontFace = addon.GetDefaultFontFace and addon.GetDefaultFontFace() or
                     select(1, GameFontNormal:GetFont())

    if cfg.fontFace and addon.ResolveFontFace then
        fontFace = addon.ResolveFontFace(cfg.fontFace) or fontFace
    end

    if addon.ApplyFontStyle then
        addon.ApplyFontStyle(fontString, fontFace, size, style)
    else
        fontString:SetFont(fontFace, size, style)
    end

    local color = addon.ResolveCDMColor and addon.ResolveCDMColor(cfg) or {1, 1, 1, 1}
    fontString:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

--------------------------------------------------------------------------------
-- Cooldown Tracking
--------------------------------------------------------------------------------

local function RefreshSpellCooldown(icon)
    if not icon.entry or icon.entry.type ~= "spell" then return end
    local spellID = icon.entry.id

    -- Charges (all SpellChargeInfo fields can be secret in restricted contexts)
    local chargeInfo = C_Spell.GetSpellCharges(spellID)
    if chargeInfo then
        local ok, hasMultiCharges = pcall(function()
            return chargeInfo.maxCharges > 1
        end)
        if ok then
            if hasMultiCharges then
                icon.CountText:SetText(chargeInfo.currentCharges)
                icon.CountText:Show()
                icon.Icon:SetDesaturated(chargeInfo.currentCharges == 0)
                if chargeInfo.currentCharges < chargeInfo.maxCharges and chargeInfo.cooldownStartTime > 0 then
                    icon.Cooldown:SetCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo.chargeModRate)
                    -- Only track as "on cooldown" for opacity dimming when ALL charges are spent
                    if chargeInfo.currentCharges == 0 then
                        cgCooldownEndTimes[icon] = chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration
                    else
                        cgCooldownEndTimes[icon] = nil
                    end
                else
                    icon.Cooldown:Clear()
                    cgCooldownEndTimes[icon] = nil
                end
                return
            end
            icon.CountText:Hide()
        else
            -- Secret: SetCooldown + SetText both accept secret values natively
            icon.Cooldown:SetCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo.chargeModRate)
            icon.CountText:SetText(chargeInfo.currentCharges)
            icon.CountText:Show()
            return
        end
    else
        icon.CountText:Hide()
    end

    -- Regular cooldown
    local cdInfo = C_Spell.GetSpellCooldown(spellID)
    if not cdInfo then return end

    -- isOnGCD is NeverSecret — always safe, replaces duration > MIN_CD_DURATION
    if cdInfo.isOnGCD then return end

    -- Try comparisons (work outside restricted contexts)
    local ok, isOnCD = pcall(function()
        return cdInfo.duration and cdInfo.duration > 0 and cdInfo.isEnabled
    end)

    if ok then
        if isOnCD then
            icon.Cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration, cdInfo.modRate)
            icon.Icon:SetDesaturated(true)
            cgCooldownEndTimes[icon] = cdInfo.startTime + cdInfo.duration
        else
            icon.Cooldown:Clear()
            icon.Icon:SetDesaturated(false)
            local existingEnd = cgCooldownEndTimes[icon]
            if not existingEnd or GetTime() >= existingEnd then
                cgCooldownEndTimes[icon] = nil
            end
        end
    else
        -- Secret: pass directly to SetCooldown (C++ handles secrets natively)
        icon.Cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration, cdInfo.modRate)
    end
end

local function RefreshItemCooldown(icon)
    if not icon.entry or icon.entry.type ~= "item" then return end
    local itemID = icon.entry.id

    local startTime, duration, isEnabled = C_Container.GetItemCooldown(itemID)
    local ok, isOnCD = pcall(function()
        return startTime and duration and duration > MIN_CD_DURATION and isEnabled and isEnabled ~= 0
    end)

    if ok then
        if isOnCD then
            icon.Cooldown:SetCooldown(startTime, duration)
            icon.Icon:SetDesaturated(true)
            cgCooldownEndTimes[icon] = startTime + duration
        else
            icon.Cooldown:Clear()
            icon.Icon:SetDesaturated(false)
            local existingEnd = cgCooldownEndTimes[icon]
            if not existingEnd or GetTime() >= existingEnd then
                cgCooldownEndTimes[icon] = nil
            end
        end
    elseif startTime and duration then
        -- Secret fallback: pass directly to SetCooldown
        icon.Cooldown:SetCooldown(startTime, duration)
    end

    -- Stack count
    local count = C_Item.GetItemCount(itemID, false, true)
    local countOk, showCount = pcall(function()
        return count and count > 1
    end)
    if countOk and showCount then
        icon.CountText:SetText(count)
        icon.CountText:Show()
    elseif not countOk and count then
        -- Secret: SetText accepts secret values
        icon.CountText:SetText(count)
        icon.CountText:Show()
    else
        icon.CountText:Hide()
    end
end

local function RefreshAllSpellCooldowns()
    for gi = 1, 3 do
        for _, icon in ipairs(activeIcons[gi]) do
            if icon.entry and icon.entry.type == "spell" then
                RefreshSpellCooldown(icon)
            end
        end
    end
end

local function RefreshAllItemCooldowns()
    for gi = 1, 3 do
        for _, icon in ipairs(activeIcons[gi]) do
            if icon.entry and icon.entry.type == "item" then
                RefreshItemCooldown(icon)
            end
        end
    end
end

local function RefreshAllCooldowns(groupIndex)
    local icons = activeIcons[groupIndex]
    for _, icon in ipairs(icons) do
        if icon.entry then
            if icon.entry.type == "spell" then
                RefreshSpellCooldown(icon)
            elseif icon.entry.type == "item" then
                RefreshItemCooldown(icon)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Per-Icon Cooldown Opacity
--------------------------------------------------------------------------------

local function UpdateIconCooldownOpacity(icon, opacitySetting)
    if opacitySetting >= 100 then
        icon:SetAlpha(1.0)
        return
    end

    local endTime = cgCooldownEndTimes[icon]
    local isOnCD = endTime and GetTime() < endTime
    icon:SetAlpha(isOnCD and (opacitySetting / 100) or 1.0)
end

local function UpdateGroupCooldownOpacities(groupIndex)
    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local opacitySetting = tonumber(component.db.opacityOnCooldown) or 100
    for _, icon in ipairs(activeIcons[groupIndex]) do
        UpdateIconCooldownOpacity(icon, opacitySetting)
    end
end

--------------------------------------------------------------------------------
-- Visibility Filtering + Rebuild
--------------------------------------------------------------------------------

function CG.IsEntryVisible(entry)
    if entry.type == "spell" then
        return IsPlayerSpell(entry.id) or IsSpellKnown(entry.id)
            or C_SpellBook.IsSpellInSpellBook(entry.id, Enum.SpellBookSpellBank.Player, true)
    elseif entry.type == "item" then
        return (C_Item.GetItemCount(entry.id) or 0) > 0
    end
    return false
end
local IsEntryVisible = CG.IsEntryVisible

local function GetEntryTexture(entry)
    if entry.type == "spell" then
        return C_Spell.GetSpellTexture(entry.id)
    elseif entry.type == "item" then
        return C_Item.GetItemIconByID(entry.id)
    end
    return nil
end

-- Forward declarations
local LayoutIcons, ApplyBordersToGroup, ApplyTextToGroup, ApplyKeybindTextToGroup, UpdateGroupOpacity

local function RebuildGroup(groupIndex)
    if not cgInitialized then return end

    local container = containers[groupIndex]
    if not container then return end

    ReleaseAllIcons(groupIndex)

    local entries = CG.GetEntries(groupIndex)
    local visibleEntries = {}
    trackedItemCount = 0

    for idx, entry in ipairs(entries) do
        if IsEntryVisible(entry) then
            table.insert(visibleEntries, { entry = entry, index = idx })
            if entry.type == "item" then
                trackedItemCount = trackedItemCount + 1
            end
        end
    end

    -- Recount items across all groups for ticker management
    local totalItems = 0
    for gi = 1, 3 do
        if gi == groupIndex then
            totalItems = totalItems + trackedItemCount
        else
            for _, icon in ipairs(activeIcons[gi]) do
                if icon.entry and icon.entry.type == "item" then
                    totalItems = totalItems + 1
                end
            end
        end
    end

    -- Manage item ticker
    if totalItems > 0 and not itemTicker then
        itemTicker = C_Timer.NewTicker(0.25, function()
            RefreshAllItemCooldowns()
            for i = 1, 3 do
                UpdateGroupCooldownOpacities(i)
            end
        end)
    elseif totalItems == 0 and itemTicker then
        itemTicker:Cancel()
        itemTicker = nil
    end

    -- Acquire icons for visible entries
    for _, vis in ipairs(visibleEntries) do
        local icon = AcquireIcon(groupIndex, container)
        local texture = GetEntryTexture(vis.entry)
        if texture then
            icon.Icon:SetTexture(texture)
        end
        icon.entry = vis.entry
        icon.entryIndex = vis.index
        table.insert(activeIcons[groupIndex], icon)
    end

    -- Handle items that may need data loading
    for _, icon in ipairs(activeIcons[groupIndex]) do
        if icon.entry.type == "item" and not icon.Icon:GetTexture() then
            C_Item.RequestLoadItemDataByID(icon.entry.id)
        end
    end

    if #activeIcons[groupIndex] == 0 then
        container:Hide()
    else
        container:Show()
        LayoutIcons(groupIndex)
        RefreshAllCooldowns(groupIndex)
    end
end

local function RebuildAllGroups()
    for i = 1, 3 do
        RebuildGroup(i)
        ApplyBordersToGroup(i)
        ApplyTextToGroup(i)
        ApplyKeybindTextToGroup(i)
        UpdateGroupOpacity(i)
        UpdateGroupCooldownOpacities(i)
    end
end

--------------------------------------------------------------------------------
-- Layout Engine
--------------------------------------------------------------------------------

local ANCHOR_MODE_MAP = {
    left   = "TOPLEFT",
    right  = "TOPRIGHT",
    center = "CENTER",
    top    = "TOP",
    bottom = "BOTTOM",
}

local function ReanchorContainer(container, anchorPosition)
    local targetPoint = ANCHOR_MODE_MAP[anchorPosition or "center"]
    if not targetPoint or not container then return end

    local parent = container:GetParent()
    if not parent then return end
    local scale = container:GetScale() or 1
    local left, top, right, bottom = container:GetLeft(), container:GetTop(), container:GetRight(), container:GetBottom()
    if not left or not top or not right or not bottom then return end

    left, top, right, bottom = left * scale, top * scale, right * scale, bottom * scale
    local pw, ph = parent:GetSize()

    local x = targetPoint:find("LEFT") and left
        or targetPoint:find("RIGHT") and (right - pw)
        or ((left + right) / 2 - pw / 2)
    local y = targetPoint:find("BOTTOM") and bottom
        or targetPoint:find("TOP") and (top - ph)
        or ((top + bottom) / 2 - ph / 2)

    container:ClearAllPoints()
    container:SetPoint(targetPoint, x / scale, y / scale)
end

LayoutIcons = function(groupIndex)
    local icons = activeIcons[groupIndex]
    if #icons == 0 then return end

    local container = containers[groupIndex]
    if not container then return end

    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local db = component.db
    local orientation = db.orientation or "H"
    local direction = db.direction or "right"
    local stride = tonumber(db.columns) or 12
    local padding = tonumber(db.iconPadding) or 2
    local anchorPosition = db.anchorPosition or "center"

    if stride < 1 then stride = 1 end

    local iconW, iconH = GetIconDimensions(db)

    -- Primary axis = direction icons grow along (H=horizontal, V=vertical)
    -- Secondary axis = direction rows stack along (perpendicular)
    -- primarySize/secondarySize = icon dimension along each axis
    local primarySize, secondarySize
    if orientation == "H" then
        primarySize = iconW
        secondarySize = iconH
    else
        primarySize = iconH
        secondarySize = iconW
    end

    -- Determine reference point and axis signs based on direction
    -- primarySign: +1 = icons grow in positive direction, -1 = negative
    -- secondarySign: +1 = rows stack in positive direction, -1 = negative
    local refPoint, primarySign, secondarySign
    if orientation == "H" then
        if direction == "left" then
            refPoint = "TOPRIGHT"
            primarySign = -1
            secondarySign = -1
        else -- "right"
            refPoint = "TOPLEFT"
            primarySign = 1
            secondarySign = -1
        end
    else -- "V"
        if direction == "up" then
            refPoint = "BOTTOMLEFT"
            primarySign = 1
            secondarySign = 1
        else -- "down"
            refPoint = "TOPLEFT"
            primarySign = -1
            secondarySign = 1
        end
    end

    -- Group icons into rows
    local count = #icons
    local numRows = math.ceil(count / stride)
    local row1Count = math.min(count, stride)

    -- Row 1 span (edge-to-edge, not center-to-center)
    local row1Span = (row1Count * primarySize) + ((row1Count - 1) * padding)

    -- Row 1 start position (leading edge of first icon, in primary axis units from refPoint)
    local row1Start = 0

    -- Row 1 center for aligning additional rows
    local row1Center = row1Start + row1Span / 2

    -- Position each icon using CENTER anchor
    for i, icon in ipairs(icons) do
        icon:SetSize(iconW, iconH)
        ApplyTexCoord(icon, iconW, iconH)

        local pos = i - 1
        local major = pos % stride       -- index along primary axis
        local minor = math.floor(pos / stride) -- row index

        -- Determine row start for this icon's row
        local rowStart
        if minor == 0 then
            rowStart = row1Start
        else
            local rowCount = math.min(count - (minor * stride), stride)
            local rowSpan = (rowCount * primarySize) + ((rowCount - 1) * padding)
            if anchorPosition == "left" or anchorPosition == "right" then
                rowStart = row1Start
            else
                rowStart = row1Center - rowSpan / 2
            end
        end

        -- Icon center along primary axis (from refPoint)
        local primaryPos = rowStart + (major * (primarySize + padding)) + (primarySize / 2)
        -- Icon center along secondary axis (from refPoint)
        local secondaryPos = (minor * (secondarySize + padding)) + (secondarySize / 2)

        -- Map to (x, y) using axis signs
        local x, y
        if orientation == "H" then
            x = primaryPos * primarySign
            y = secondaryPos * secondarySign
        else
            x = secondaryPos * secondarySign
            y = primaryPos * primarySign
        end

        icon:ClearAllPoints()
        icon:SetPoint("CENTER", container, refPoint, x, y)
    end

    -- Calculate container size (unchanged — icons may extend past bounds when centered)
    local majorCount = math.min(count, stride)
    local minorCount = numRows

    local totalW, totalH
    if orientation == "H" then
        totalW = (majorCount * iconW) + ((majorCount - 1) * padding)
        totalH = (minorCount * iconH) + ((minorCount - 1) * padding)
    else
        totalW = (minorCount * iconW) + ((minorCount - 1) * padding)
        totalH = (majorCount * iconH) + ((majorCount - 1) * padding)
    end

    ReanchorContainer(container, anchorPosition)
    container:SetSize(math.max(1, totalW), math.max(1, totalH))
end

--------------------------------------------------------------------------------
-- Border Application for Groups
--------------------------------------------------------------------------------

ApplyBordersToGroup = function(groupIndex)
    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local db = component.db
    local icons = activeIcons[groupIndex]

    if db.borderEnable then
        local opts = {
            style = db.borderStyle or "square",
            thickness = tonumber(db.borderThickness) or 1,
            insetH = tonumber(db.borderInsetH) or tonumber(db.borderInset) or 0,
            insetV = tonumber(db.borderInsetV) or tonumber(db.borderInset) or 0,
            color = db.borderTintEnable and db.borderTintColor or {0, 0, 0, 1},
            tintEnabled = db.borderTintEnable,
            tintColor = db.borderTintColor,
        }
        for _, icon in ipairs(icons) do
            ApplyBorderToIcon(icon, opts)
        end
    else
        for _, icon in ipairs(icons) do
            HideIconBorder(icon)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Styling for Groups
--------------------------------------------------------------------------------

ApplyTextToGroup = function(groupIndex)
    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local db = component.db
    local icons = activeIcons[groupIndex]

    for _, icon in ipairs(icons) do
        -- Cooldown text (style the Cooldown frame's internal FontString)
        if db.textCooldown and next(db.textCooldown) then
            local cdFrame = icon.Cooldown
            if cdFrame and cdFrame.GetRegions then
                for _, region in ipairs({cdFrame:GetRegions()}) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        ApplyTextStyle(region, db.textCooldown, 14)
                        local ox = (db.textCooldown.offset and db.textCooldown.offset.x) or 0
                        local oy = (db.textCooldown.offset and db.textCooldown.offset.y) or 0
                        if region.ClearAllPoints and region.SetPoint then
                            region:ClearAllPoints()
                            region:SetPoint("CENTER", cdFrame, "CENTER", ox, oy)
                        end
                        break
                    end
                end
            end
        end

        -- Charge/stack count text
        if db.textStacks and next(db.textStacks) then
            ApplyTextStyle(icon.CountText, db.textStacks, 12)
            local ox = (db.textStacks.offset and db.textStacks.offset.x) or 0
            local oy = (db.textStacks.offset and db.textStacks.offset.y) or 0
            if icon.CountText and icon.CountText.ClearAllPoints and icon.CountText.SetPoint then
                icon.CountText:ClearAllPoints()
                icon.CountText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Keybind Text for Groups
--------------------------------------------------------------------------------

ApplyKeybindTextToGroup = function(groupIndex)
    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local db = component.db
    local cfg = db.textBindings
    local icons = activeIcons[groupIndex]

    if not cfg or not cfg.enabled then
        for _, icon in ipairs(icons) do
            if icon.keybindText then
                icon.keybindText:Hide()
            end
        end
        return
    end

    local SpellBindings = addon.SpellBindings
    if not SpellBindings or not SpellBindings.GetBindingForSpellID then return end

    for _, icon in ipairs(icons) do
        if not icon.keybindText then
            -- Pooled icon from before this feature; skip until reload
        elseif icon.entry and icon.entry.type == "spell" then
            local binding = SpellBindings.GetBindingForSpellID(icon.entry.id)
            if binding then
                icon.keybindText:SetText(binding)
                ApplyTextStyle(icon.keybindText, cfg, 12)

                local anchor = cfg.anchor or "TOPLEFT"
                local ox = (cfg.offset and cfg.offset.x) or 0
                local oy = (cfg.offset and cfg.offset.y) or 0
                icon.keybindText:ClearAllPoints()
                icon.keybindText:SetPoint(anchor, icon, anchor, ox, oy)
                icon.keybindText:Show()
            else
                icon.keybindText:SetText("")
                icon.keybindText:Hide()
            end
        elseif icon.entry and icon.entry.type == "item" then
            local binding = SpellBindings.GetBindingForItemID(icon.entry.id)
            if binding then
                icon.keybindText:SetText(binding)
                ApplyTextStyle(icon.keybindText, cfg, 12)

                local anchor = cfg.anchor or "TOPLEFT"
                local ox = (cfg.offset and cfg.offset.x) or 0
                local oy = (cfg.offset and cfg.offset.y) or 0
                icon.keybindText:ClearAllPoints()
                icon.keybindText:SetPoint(anchor, icon, anchor, ox, oy)
                icon.keybindText:Show()
            else
                icon.keybindText:SetText("")
                icon.keybindText:Hide()
            end
        else
            icon.keybindText:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Container-Level Opacity
--------------------------------------------------------------------------------

UpdateGroupOpacity = function(groupIndex)
    local container = containers[groupIndex]
    if not container then return end

    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local db = component.db
    local inCombat = InCombatLockdown and InCombatLockdown()
    local hasTarget = UnitExists("target")

    local opacityValue
    if inCombat then
        opacityValue = tonumber(db.opacity) or 100
    elseif hasTarget then
        opacityValue = tonumber(db.opacityWithTarget) or 100
    else
        opacityValue = tonumber(db.opacityOutOfCombat) or 100
    end

    container:SetAlpha(math.max(0.01, math.min(1.0, opacityValue / 100)))
end

local function UpdateAllGroupOpacities()
    for i = 1, 3 do
        UpdateGroupOpacity(i)
    end
end

--------------------------------------------------------------------------------
-- LibEditMode Integration
--------------------------------------------------------------------------------

local function SaveGroupPosition(groupIndex, layoutName, point, x, y)
    local groups = EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return end

    if not groups[groupIndex].positions then
        groups[groupIndex].positions = {}
    end

    groups[groupIndex].positions[layoutName] = {
        point = point,
        x = x,
        y = y,
    }
end

local function RestoreGroupPosition(groupIndex, layoutName)
    local container = containers[groupIndex]
    if not container then return end

    local groups = EnsureGroupsDB()
    if not groups or not groups[groupIndex] then return end

    local positions = groups[groupIndex].positions
    local pos = positions and positions[layoutName]

    if pos and pos.point then
        container:ClearAllPoints()
        container:SetPoint(pos.point, pos.x or 0, pos.y or 0)
    end
end

local function UpdateEditModeNames()
    for i = 1, 3 do
        local container = containers[i]
        if container then
            container.editModeName = CG.GetGroupDisplayName(i)
        end
    end
end

local function InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    for i = 1, 3 do
        local container = containers[i]
        if container then
            container.editModeName = CG.GetGroupDisplayName(i)
            lib:AddFrame(container, function(frame, layoutName, point, x, y)
                if point and x and y then
                    frame:ClearAllPoints()
                    frame:SetPoint(point, x, y)
                end
                -- Re-anchor to match anchorPosition
                local component = addon.Components and addon.Components["customGroup" .. i]
                if component and component.db then
                    ReanchorContainer(frame, component.db.anchorPosition or "center")
                end
                -- Save the re-anchored position
                if layoutName then
                    local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
                    if savedPoint then
                        SaveGroupPosition(i, layoutName, savedPoint, savedX, savedY)
                    else
                        SaveGroupPosition(i, layoutName, point, x, y)
                    end
                end
            end, {
                point = "CENTER",
                x = 0,
                y = -100 + (i - 1) * -60,
            }, nil)
        end
    end

    lib:RegisterCallback("layout", function(layoutName, layoutIndex)
        for i = 1, 3 do
            RestoreGroupPosition(i, layoutName)
        end
    end)

    CG.RegisterCallback(UpdateEditModeNames)
end

--------------------------------------------------------------------------------
-- Container Initialization
--------------------------------------------------------------------------------

local function InitializeContainers()
    for i = 1, 3 do
        local container = CreateFrame("Frame", "ScooterModCustomGroup" .. i, UIParent)
        container:SetSize(1, 1)
        container:SetMovable(true)
        container:SetClampedToScreen(true)
        container:SetPoint("CENTER", 0, -100 + (i - 1) * -60)
        container:Hide()
        containers[i] = container
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local bagUpdatePending = false

local cgEventFrame = CreateFrame("Frame")
cgEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
cgEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
cgEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
cgEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
cgEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
cgEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
cgEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
cgEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
cgEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
cgEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
cgEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
cgEventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
cgEventFrame:RegisterEvent("BAG_UPDATE")

cgEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not cgInitialized then
            InitializeContainers()
            cgInitialized = true

            C_Timer.After(0.5, function()
                RebuildAllGroups()
                InitializeEditMode()
            end)
        else
            RebuildAllGroups()
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        RefreshAllSpellCooldowns()
        -- Check for expired cooldowns
        local now = GetTime()
        for icon, endTime in pairs(cgCooldownEndTimes) do
            if now >= endTime then
                cgCooldownEndTimes[icon] = nil
                icon:SetAlpha(1.0)
                icon.Icon:SetDesaturated(false)
            end
        end
        for i = 1, 3 do
            UpdateGroupCooldownOpacities(i)
        end

    elseif event == "BAG_UPDATE_COOLDOWN" then
        RefreshAllItemCooldowns()
        for i = 1, 3 do
            UpdateGroupCooldownOpacities(i)
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.2, RebuildAllGroups)

    elseif event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_TARGET_CHANGED" then
        UpdateAllGroupOpacities()

    elseif event == "BAG_UPDATE" then
        if not bagUpdatePending then
            bagUpdatePending = true
            C_Timer.After(0.2, function()
                bagUpdatePending = false
                RebuildAllGroups()
            end)
        end

    elseif event == "ITEM_DATA_LOAD_RESULT" then
        -- Retry textures for items that may have been loading
        for gi = 1, 3 do
            for _, icon in ipairs(activeIcons[gi]) do
                if icon.entry and icon.entry.type == "item" and not icon.Icon:GetTexture() then
                    local texture = C_Item.GetItemIconByID(icon.entry.id)
                    if texture then
                        icon.Icon:SetTexture(texture)
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Data Model Callback → HUD Updates
--------------------------------------------------------------------------------

CG.RegisterCallback(function()
    if cgInitialized then
        RebuildAllGroups()
    end
end)

-- Refresh keybind text when bindings/talents/action bars change
if addon.SpellBindings and addon.SpellBindings.RegisterRefreshCallback then
    addon.SpellBindings.RegisterRefreshCallback(function()
        if not cgInitialized then return end
        for i = 1, 3 do
            ApplyKeybindTextToGroup(i)
        end
    end)
end

--------------------------------------------------------------------------------
-- ApplyStyling Implementation
--------------------------------------------------------------------------------

local function CustomGroupApplyStyling(component)
    local groupIndex = tonumber(component.id:match("%d+"))
    if not groupIndex then return end
    if not cgInitialized then return end

    RebuildGroup(groupIndex)
    ApplyBordersToGroup(groupIndex)
    ApplyTextToGroup(groupIndex)
    ApplyKeybindTextToGroup(groupIndex)
    UpdateGroupOpacity(groupIndex)
    UpdateGroupCooldownOpacities(groupIndex)
end

--------------------------------------------------------------------------------
-- Copy From: Custom Group Settings
--------------------------------------------------------------------------------

function addon.CopyCDMCustomGroupSettings(sourceComponentId, destComponentId)
    if type(sourceComponentId) ~= "string" or type(destComponentId) ~= "string" then return end
    if sourceComponentId == destComponentId then return end

    local src = addon.Components and addon.Components[sourceComponentId]
    local dst = addon.Components and addon.Components[destComponentId]
    if not src or not dst then return end
    if not src.db or not dst.db then return end

    -- Destination must be a Custom Group
    if not destComponentId:match("^customGroup%d$") then return end

    local function deepcopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, vv in pairs(v) do out[k] = deepcopy(vv) end
        return out
    end

    -- When source is Essential/Utility, skip iconSize (% scale vs pixel size)
    local isEssentialOrUtility = (sourceComponentId == "essentialCooldowns" or sourceComponentId == "utilityCooldowns")

    -- Copy all destination-defined settings from source DB
    for key, def in pairs(dst.settings or {}) do
        if key == "supportsText" then -- skip meta flag
        elseif isEssentialOrUtility and key == "iconSize" then -- skip incompatible
        else
            local srcVal = src.db[key]
            if srcVal ~= nil then
                dst.db[key] = deepcopy(srcVal)
            end
        end
    end

    -- Apply styling to destination
    if dst.ApplyStyling then
        dst:ApplyStyling()
    end
end

--------------------------------------------------------------------------------
-- Component Registration (3 Custom Groups)
--------------------------------------------------------------------------------

-- Shared settings definition factory (all type="addon", no Edit Mode backing)
local function CreateCustomGroupSettings()
    return {
        -- Layout
        orientation = { type = "addon", default = "H" },
        direction = { type = "addon", default = "right" },
        columns = { type = "addon", default = 12 },
        iconPadding = { type = "addon", default = 2 },

        -- Anchor position
        anchorPosition = { type = "addon", default = "center" },

        -- Sizing
        iconSize = { type = "addon", default = 30 },
        tallWideRatio = { type = "addon", default = 0 },

        -- Border
        borderEnable = { type = "addon", default = false },
        borderTintEnable = { type = "addon", default = false },
        borderTintColor = { type = "addon", default = {1, 1, 1, 1} },
        borderStyle = { type = "addon", default = "square" },
        borderThickness = { type = "addon", default = 1 },
        borderInset = { type = "addon", default = 0 },
        borderInsetH = { type = "addon", default = 0 },
        borderInsetV = { type = "addon", default = 0 },

        -- Text
        textStacks = { type = "addon", default = {} },
        textCooldown = { type = "addon", default = {} },
        textBindings = { type = "addon", default = {} },
        supportsText = { type = "addon", default = true },

        -- Visibility
        opacity = { type = "addon", default = 100 },
        opacityOutOfCombat = { type = "addon", default = 100 },
        opacityWithTarget = { type = "addon", default = 100 },
        opacityOnCooldown = { type = "addon", default = 100 },
    }
end

addon:RegisterComponentInitializer(function(self)
    for i = 1, 3 do
        local comp = Component:New({
            id = "customGroup" .. i,
            name = "Custom Group " .. i,
            settings = CreateCustomGroupSettings(),
            ApplyStyling = CustomGroupApplyStyling,
        })
        self:RegisterComponent(comp)
    end
end)

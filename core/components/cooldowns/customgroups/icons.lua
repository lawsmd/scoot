-- customgroups/icons.lua - Icon pool, borders, text styling, group-level application
local addonName, addon = ...

local CG = addon.CustomGroups

--------------------------------------------------------------------------------
-- Shared State
--------------------------------------------------------------------------------

CG._iconPools = { {}, {}, {}, {}, {} }       -- released icons per group
CG._activeIcons = { {}, {}, {}, {}, {} }     -- visible icons per group
CG._MIN_CD_DURATION = 1.5            -- GCD threshold

local iconPools = CG._iconPools
local activeIcons = CG._activeIcons

local ICON_TEXCOORD_INSET = 0.07  -- crop outer ~7% to hide baked-in border art

--------------------------------------------------------------------------------
-- Icon Creation
--------------------------------------------------------------------------------

-- Border texture setup, split out so the settings-panel preview can build an icon frame that
-- CG.ApplyBorderToIcon accepts. Idempotent: safe to call on a frame that already has them.
function CG.EnsureIconBorderTextures(frame)
    if not frame then return frame end

    if not frame.borderEdges then
        frame.borderEdges = {
            Top = frame:CreateTexture(nil, "OVERLAY", nil, 1),
            Bottom = frame:CreateTexture(nil, "OVERLAY", nil, 1),
            Left = frame:CreateTexture(nil, "OVERLAY", nil, 1),
            Right = frame:CreateTexture(nil, "OVERLAY", nil, 1),
        }
        for _, tex in pairs(frame.borderEdges) do
            tex:Hide()
        end
    end

    if not frame.atlasBorder then
        frame.atlasBorder = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        frame.atlasBorder:Hide()
    end

    return frame
end

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

    icon.textFrame = CreateFrame("Frame", nil, icon)
    icon.textFrame:SetAllPoints()
    icon.textFrame:SetFrameLevel(icon.Cooldown:GetFrameLevel() + 1)

    icon.CountText = icon.textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    icon.CountText:SetDrawLayer("OVERLAY", 7)
    icon.CountText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    icon.CountText:Hide()

    icon.keybindText = icon.textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

    CG.EnsureIconBorderTextures(icon)

    return icon
end

--------------------------------------------------------------------------------
-- Icon Pool Management
--------------------------------------------------------------------------------

function CG._AcquireIcon(groupIndex, parent)
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
    if addon.ClearIconMask then
        addon.ClearIconMask(icon.Icon)
    end
    icon:SetScript("OnUpdate", nil)
    icon.entry = nil
    icon.entryIndex = nil
    icon._groupIndex = nil
    table.insert(iconPools[groupIndex], icon)
end

function CG._ReleaseAllIcons(groupIndex)
    local icons = activeIcons[groupIndex]
    for i = #icons, 1, -1 do
        ReleaseIcon(groupIndex, icons[i])
        icons[i] = nil
    end
end

--------------------------------------------------------------------------------
-- Icon Dimension Helpers
--------------------------------------------------------------------------------

function CG._GetIconDimensions(db)
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

function CG._ApplyTexCoord(icon, iconW, iconH, userZoom)
    local l, r, t, b = addon.CalculateIconTexCoords(iconW / iconH, userZoom, ICON_TEXCOORD_INSET)
    icon.Icon:SetTexCoord(l, r, t, b)
end

--------------------------------------------------------------------------------
-- Border Application Helpers
--------------------------------------------------------------------------------

local function HideIconBorder(icon)
    for _, tex in pairs(icon.borderEdges) do
        tex:Hide()
    end
    icon.atlasBorder:Hide()
    if addon.ClearIconMask then
        addon.ClearIconMask(icon.Icon)
    end
end

local function ApplySquareBorder(icon, opts)
    icon.atlasBorder:Hide()

    local edges = icon.borderEdges
    local thickness = math.max(1, tonumber(opts.thickness) or 1)
    local col = opts.color or {0, 0, 0, 1}
    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1
    local insetH = tonumber(opts.insetH) or tonumber(opts.inset) or 0
    local insetV = tonumber(opts.insetV) or tonumber(opts.inset) or 0
    local subPixel = addon.BorderInsetIsSubPixel and addon.BorderInsetIsSubPixel(insetH, insetV)

    for _, tex in pairs(edges) do
        tex:SetColorTexture(r, g, b, a)
        if addon.SetBorderTexturePixelSnap then
            addon.SetBorderTexturePixelSnap(tex, subPixel)
        end
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

    -- How far the art reaches outside the icon frame, for callers that need to reserve room.
    return insetH, insetV
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

    if addon.SetBorderTexturePixelSnap then
        addon.SetBorderTexturePixelSnap(atlasTex, addon.BorderInsetIsSubPixel(insetH, insetV))
    end

    local adjL = styleDef.adjustLeft or 0
    local adjR = styleDef.adjustRight or 0
    local adjT = styleDef.adjustTop or 0
    local adjB = styleDef.adjustBottom or 0

    atlasTex:ClearAllPoints()
    atlasTex:SetPoint("TOPLEFT", icon, "TOPLEFT", -expandX - adjL, expandY + adjT)
    atlasTex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", expandX + adjR, -expandY - adjB)
    atlasTex:Show()

    -- How far the art reaches outside the icon frame, for callers that need to reserve room.
    return expandX + math.max(adjL, adjR), expandY + math.max(adjT, adjB)
end

-- Exported so the settings-panel preview draws its border through the same code the HUD does.
-- Returns the outward reach of the applied art on each axis.
function CG.ApplyBorderToIcon(icon, opts)
    local style = opts.style or "square"
    local styleDef = nil
    if style ~= "square" and addon.IconBorders and addon.IconBorders.GetStyle then
        styleDef = addon.IconBorders.GetStyle(style)
    end

    -- Round the icon to match rounded frame art, so its square corners can't poke out
    -- past the arc. These are addon-owned textures, so masking them is always safe.
    if addon.ApplyIconMask then
        addon.ApplyIconMask(icon.Icon, icon, style)
    end

    if styleDef and styleDef.type == "atlas" and styleDef.atlas then
        return ApplyAtlasBorder(icon, opts, styleDef)
    else
        return ApplySquareBorder(icon, opts)
    end
end
local ApplyBorderToIcon = CG.ApplyBorderToIcon

--------------------------------------------------------------------------------
-- Text Styling Helper
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
-- Border Application for Groups
--------------------------------------------------------------------------------

-- Single source of truth for how a group's DB becomes border options. Exported so the
-- settings-panel preview resolves the same keys the HUD does, including the legacy
-- borderInset fallback for profiles saved before the H/V split.
function CG.BuildBorderOpts(db)
    if not db then return nil end
    return {
        style = db.borderStyle or "square",
        thickness = tonumber(db.borderThickness) or 1,
        insetH = tonumber(db.borderInsetH) or tonumber(db.borderInset) or 0,
        insetV = tonumber(db.borderInsetV) or tonumber(db.borderInset) or 0,
        color = db.borderTintEnable and db.borderTintColor or {0, 0, 0, 1},
        tintEnabled = db.borderTintEnable,
        tintColor = db.borderTintColor,
    }
end

function CG._ApplyBordersToGroup(groupIndex)
    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local db = component.db
    local icons = activeIcons[groupIndex]

    if db.borderEnable then
        local opts = CG.BuildBorderOpts(db)
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

function CG._ApplyTextToGroup(groupIndex)
    local component = addon.Components and addon.Components["customGroup" .. groupIndex]
    if not component or not component.db then return end

    local db = component.db
    local icons = activeIcons[groupIndex]

    for _, icon in ipairs(icons) do
        -- Cooldown text (style the Cooldown frame's internal FontString)
        if db.textCooldown then
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
        if db.textStacks then
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

function CG._ApplyKeybindTextToGroup(groupIndex)
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
-- Debug Access
--------------------------------------------------------------------------------

addon._debugCGActiveIcons = CG._activeIcons

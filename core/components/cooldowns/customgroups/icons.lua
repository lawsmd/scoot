-- customgroups/icons.lua - Icon pool, borders, text styling, group-level application
local addonName, addon = ...

local CG = addon.CustomGroups

--------------------------------------------------------------------------------
-- Shared State
--------------------------------------------------------------------------------

CG._activeIcons = { {}, {}, {}, {}, {} }     -- visible icons per group
CG._MIN_CD_DURATION = 1.5            -- GCD threshold

local activeIcons = CG._activeIcons

local ICON_TEXCOORD_INSET = 0.07  -- crop outer ~7% to hide baked-in border art

--------------------------------------------------------------------------------
-- Ping receiver (12.1)
--------------------------------------------------------------------------------
-- 12.1 lets a player ping an ability to call out "ready" or its remaining
-- cooldown (Enum.PingSubjectType gained ActionReady, ActionOnCooldown,
-- ActionUnavailable and ActionNotReady). Blizzard opted its own Essential and
-- Utility cooldown items in through PingableCooldownViewerItemTemplate; custom
-- group icons are addon-owned, so they have to opt themselves in.
--
-- The contract: carry the "ping-receiver" attribute so the C-side hit test in
-- C_PingSecure.GetTargetPingReceiver finds the icon, then answer the three mixin
-- methods PingManager calls on whatever it found. Scoot cannot send the ping
-- itself; C_PingSecure is SecureOnly.
--
-- Writing our own mixin here is safe in a way it is NOT on a unit frame. A unit
-- ping carries a GUID that goes secret under identity restrictions, and addon Lua
-- in that gather breaks the securecopy at the secure boundary (see the purity
-- rule in unitframesz/engine.lua). A spell or item ping carries plain numbers, so
-- there is nothing secret to fail on.
--
-- GetIsPingable returning false does NOT pass the ping through: PingManager reads
-- a found-but-unpingable frame as blocking UI and fails the ping outright. That is
-- why a pooled icon has its attribute CLEARED rather than being left to answer
-- false, which is what Blizzard does with empty action buttons.
local CG_PING = {}

function CG_PING:GetIsPingable()
    local entry = self.entry
    return entry ~= nil and (entry.type == "spell" or entry.type == "item")
end

-- Contextual pings only, matching Blizzard's cooldown item and action button.
function CG_PING:GetAllowRadialWheel()
    return false
end

function CG_PING:GetTargetInfo()
    local entry = self.entry
    if not entry then return {} end
    if entry.type == "item" then
        -- Blizzard's cooldown item prefers a spellCategoryID for health items, so
        -- its ping means "a health potion". A custom group entry is one specific
        -- item, so it pings that item.
        return { itemID = entry.id }
    end
    -- The override, not the base: _pingSpellID is stamped by the cooldown refresh
    -- from the same ResolveSpellID the swipe is driven by, so the callout matches
    -- what the icon is showing for a spell that transforms when cast.
    return { spellID = self._pingSpellID or entry.id }
end

--------------------------------------------------------------------------------
-- Icon Creation
--------------------------------------------------------------------------------

-- Border art is created lazily by addon.ApplyIconBorderStyle on first apply.
-- Kept as a stub because the settings-panel preview calls it before
-- CG.ApplyBorderToIcon.
function CG.EnsureIconBorderTextures(frame)
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

    Mixin(icon, CG_PING)
    icon:SetAttribute("ping-receiver", true)

    CG.EnsureIconBorderTextures(icon)

    return icon
end

--------------------------------------------------------------------------------
-- Icon Pool Management
--------------------------------------------------------------------------------

local function ResetIcon(icon)
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
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(icon)
    end
    if addon.ClearIconMask then
        addon.ClearIconMask(icon.Icon)
    end
    icon:SetScript("OnUpdate", nil)
    -- Cleared rather than left to answer false: an unpingable receiver BLOCKS the
    -- ping instead of passing it through.
    icon:ClearAttribute("ping-receiver")
    icon._pingSpellID = nil
    icon.entry = nil
    icon.entryIndex = nil
    icon._groupIndex = nil
end

-- One free list per group: an icon released by group 2 only ever serves
-- group 2 again.
CG._iconPools = {}
for groupIndex = 1, 5 do
    CG._iconPools[groupIndex] = addon.Pool.New(CreateIconFrame, ResetIcon)
end
local iconPools = CG._iconPools

function CG._AcquireIcon(groupIndex, parent)
    local icon, isNew = iconPools[groupIndex]:Acquire(parent)
    if not isNew then
        icon:SetParent(parent)
    end
    icon:EnableMouse(true)
    -- Back in play as a ping target. Plain frame, so the write is legal in combat.
    icon:SetAttribute("ping-receiver", true)
    icon:Show()
    return icon
end

function CG._ReleaseAllIcons(groupIndex)
    local icons = activeIcons[groupIndex]
    local pool = iconPools[groupIndex]
    for i = #icons, 1, -1 do
        pool:Release(icons[i])
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
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(icon)
    end
    if addon.ClearIconMask then
        addon.ClearIconMask(icon.Icon)
    end
end

-- Exported so the settings-panel preview draws its border through the same code the HUD does.
-- Returns the outward reach of the applied art on each axis.
function CG.ApplyBorderToIcon(icon, opts)
    local style = opts.style or "square"

    -- This dispatcher's square branch has always been outward-positive; the shared
    -- dispatcher is inward-positive, so square styles negate. Atlas styles were
    -- inward-positive here already and pass through unchanged.
    local styleDef = addon.IconBorders and addon.IconBorders.GetStyle and addon.IconBorders.GetStyle(style)
    local insetH = tonumber(opts.insetH) or tonumber(opts.inset) or 0
    local insetV = tonumber(opts.insetV) or tonumber(opts.inset) or 0
    if not styleDef or styleDef.type == "square" then
        insetH, insetV = -insetH, -insetV
    end

    local tinted = (opts.tintEnabled and opts.tintColor) and true or false

    local _, reachX, reachY = addon.ApplyIconBorderStyle(icon, style, {
        thickness = opts.thickness,
        insetH = insetH,
        insetV = insetV,
        tintEnabled = tinted,
        color = tinted and opts.tintColor or nil,
        simpleTint = true,
        manageSubPixel = true,
        styleAdjusts = true,
        expandClamp = 12,
        -- These are addon-owned textures, so masking them is always safe.
        maskTarget = icon.Icon,
        maskOwner = icon,
    })
    return reachX, reachY
end
local ApplyBorderToIcon = CG.ApplyBorderToIcon

--------------------------------------------------------------------------------
-- Text Styling Helper
--------------------------------------------------------------------------------

local cgTextFontOpts = { gameFontDefault = true }
local function ApplyTextStyle(fontString, cfg, defaultSize)
    if not fontString or not cfg then return end

    cgTextFontOpts.size = defaultSize or 12
    addon.ApplyTextFont(fontString, cfg, cgTextFontOpts)

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

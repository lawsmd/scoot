-- classauras/core.lua - Shared infrastructure for Class Auras system
local addonName, addon = ...

addon.ClassAuras = addon.ClassAuras or {}
local CA = addon.ClassAuras

local Component = addon.ComponentPrototype

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

-- Class token -> settings nav key. A map is unavoidable: "DEATHKNIGHT" cannot be
-- transformed into "classAurasDeathKnight" by string munging.
CA.NAV_KEY_BY_CLASS = {
    DEATHKNIGHT = "classAurasDeathKnight",
    DEMONHUNTER = "classAurasDemonHunter",
    DRUID       = "classAurasDruid",
    EVOKER      = "classAurasEvoker",
    HUNTER      = "classAurasHunter",
    MAGE        = "classAurasMage",
    MONK        = "classAurasMonk",
    PALADIN     = "classAurasPaladin",
    PRIEST      = "classAurasPriest",
    ROGUE       = "classAurasRogue",
    SHAMAN      = "classAurasShaman",
    WARLOCK     = "classAurasWarlock",
    WARRIOR     = "classAurasWarrior",
}

CA._registry = {}       -- [auraId] = auraDef (flat lookup)
CA._classAuras = {}     -- [classToken] = { auraDef, auraDef, ... }
CA._activeAuras = {}    -- [auraId] = { container, elements, component }

function CA.RegisterAuras(classToken, auras)
    if not classToken or not auras then return end
    CA._classAuras[classToken] = CA._classAuras[classToken] or {}
    for _, aura in ipairs(auras) do
        aura.classToken = classToken
        CA._registry[aura.id] = aura
        table.insert(CA._classAuras[classToken], aura)
    end
end

--- Returns the list of aura definitions for a class token (or empty table).
function CA.GetClassAuras(classToken)
    return CA._classAuras[classToken] or {}
end

--- Returns a fresh settings table with standard defaults.
-- @param overrides table|nil  Keys map to setting names; values replace the default.
function CA.DefaultSettings(overrides)
    overrides = overrides or {}
    local base = {
        enabled         = { type = "addon", default = false },
        scale           = { type = "addon", default = 100 },
        mode            = { type = "addon", default = "icon" },
        iconMode        = { type = "addon", default = "default" },
        textFont        = { type = "addon", default = "FRIZQT__" },
        textStyle       = { type = "addon", default = "OUTLINE" },
        textSize        = { type = "addon", default = 24 },
        textColor       = { type = "addon", default = { 1, 1, 1, 1 } },
        textPosition    = { type = "addon", default = "inside" },
        textOuterAnchor = { type = "addon", default = "RIGHT" },
        textInnerAnchor = { type = "addon", default = "CENTER" },
        hideFromCDM     = { type = "addon", default = true },
        hideText        = { type = "addon", default = false },
        textOffsetX     = { type = "addon", default = 0 },
        textOffsetY     = { type = "addon", default = 0 },
        hideNameText        = { type = "addon", default = true },
        nameTextFont        = { type = "addon", default = "FRIZQT__" },
        nameTextStyle       = { type = "addon", default = "OUTLINE" },
        nameTextSize        = { type = "addon", default = 10 },
        nameTextColor       = { type = "addon", default = { 1, 1, 1, 1 } },
        nameTextPosition    = { type = "addon", default = "inside" },
        nameTextInnerAnchor = { type = "addon", default = "LEFT" },
        nameTextOuterAnchor = { type = "addon", default = "ABOVE" },
        nameTextOffsetX     = { type = "addon", default = 0 },
        nameTextOffsetY     = { type = "addon", default = 0 },
        iconShape       = { type = "addon", default = 0 },
        borderStyle     = { type = "addon", default = "none" },
        borderThickness = { type = "addon", default = 1 },
        borderInsetH    = { type = "addon", default = 0 },
        borderInsetV    = { type = "addon", default = 0 },
        borderTintEnable = { type = "addon", default = false },
        borderTintColor  = { type = "addon", default = { 1, 1, 1, 1 } },
        barWidth                = { type = "addon", default = 120 },
        barHeight               = { type = "addon", default = 12 },
        barForegroundTexture    = { type = "addon", default = "bevelled" },
        barForegroundColorMode  = { type = "addon", default = "custom" },
        barForegroundTint       = { type = "addon", default = { 1, 1, 1, 1 } },
        barBackgroundTexture    = { type = "addon", default = "bevelled" },
        barBackgroundColorMode  = { type = "addon", default = "custom" },
        barBackgroundTint       = { type = "addon", default = { 0, 0, 0, 1 } },
        barBackgroundOpacity    = { type = "addon", default = 50 },
        barBorderStyle          = { type = "addon", default = "none" },
        barBorderThickness      = { type = "addon", default = 1 },
        barBorderInsetH         = { type = "addon", default = 0 },
        barBorderInsetV         = { type = "addon", default = 0 },
        barBorderTintEnable     = { type = "addon", default = false },
        barBorderTintColor      = { type = "addon", default = { 1, 1, 1, 1 } },
        barPosition             = { type = "addon", default = "RIGHT" },
        barOffsetX              = { type = "addon", default = 0 },
        barOffsetY              = { type = "addon", default = 0 },
        opacityInCombat         = { type = "addon", default = 100 },
        opacityWithTarget       = { type = "addon", default = 100 },
        opacityOutOfCombat      = { type = "addon", default = 100 },
    }
    for key, value in pairs(overrides) do
        if base[key] then
            base[key].default = value
        elseif type(value) == "table" and value.type then
            base[key] = value  -- inject novel settings
        end
    end
    return base
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local _, playerClassToken = UnitClass("player")

local function GetComponentId(aura)
    return "classAura_" .. aura.id
end

local function GetDB(aura)
    local comp = addon.Components and addon.Components[GetComponentId(aura)]
    return comp and comp.db
end

--------------------------------------------------------------------------------
-- Element Creation
--------------------------------------------------------------------------------

local function CreateTextElement(container, elemDef, textParent)
    local fs = (textParent or container):CreateFontString(nil, "OVERLAY")
    local fontFace = addon.ResolveFontFace("FRIZQT__")
    addon.ApplyFontStyle(fs, fontFace, elemDef.baseSize or 24, "OUTLINE")
    if elemDef.justifyH then
        fs:SetJustifyH(elemDef.justifyH)
    end
    fs:Hide()
    return { type = "text", widget = fs, def = elemDef }
end

local function CreateTextureElement(container, elemDef)
    local tex = container:CreateTexture(nil, "ARTWORK")
    if elemDef.path then
        tex:SetTexture(elemDef.path)
    elseif elemDef.customPath then
        tex:SetTexture(elemDef.customPath)
    end
    local size = elemDef.defaultSize or { 32, 32 }
    tex:SetSize(size[1], size[2])
    tex:Hide()
    return { type = "texture", widget = tex, def = elemDef }
end

local function CreateBarElement(container, elemDef)
    local barRegion = CreateFrame("Frame", nil, container)
    local size = elemDef.defaultSize or { 120, 12 }
    barRegion:SetSize(size[1], size[2])

    -- Background texture
    local barBg = barRegion:CreateTexture(nil, "BACKGROUND", nil, -1)
    barBg:SetAllPoints(barRegion)

    -- StatusBar fill
    local barFill = CreateFrame("StatusBar", nil, barRegion)
    barFill:SetAllPoints(barRegion)
    barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    barFill:SetMinMaxValues(0, elemDef.maxValue or 20)
    barFill:SetValue(0)

    barRegion:Hide()

    return {
        type = "bar",
        widget = barRegion,
        barFill = barFill,
        barBg = barBg,
        def = elemDef,
    }
end

local elementCreators = {
    text = CreateTextElement,
    texture = CreateTextureElement,
    bar = CreateBarElement,
}

--------------------------------------------------------------------------------
-- Frame Creation
--------------------------------------------------------------------------------

local function CreateAuraContainer(aura)
    local frameName = "ScootClassAura_" .. aura.id
    local container = CreateFrame("Frame", frameName, UIParent)
    -- Before the element creators below, so every child derives from this level.
    addon.Strata.ApplyHUD(container, 25)
    container:SetSize(64, 32) -- initial size, auto-resized by layout
    container:SetMovable(true)
    container:SetClampedToScreen(true)

    -- Default position
    local dp = aura.defaultPosition or { point = "CENTER", x = 0, y = -200 }
    container:SetPoint(dp.point, dp.x or 0, dp.y or 0)
    container:Hide()

    -- All visuals live under the engine-managed button (built later by
    -- CA.Engine via WireButton, which fills elements/textFrame); only the
    -- positioned Scoot frame is created here.
    CA._activeAuras[aura.id] = {
        container = container,
        elements = {},
    }

    addon.RegisterPetBattleFrame(container)

    -- Optional callback for per-class modules to initialize custom visuals
    if aura.onContainerCreated then
        aura.onContainerCreated(aura.id, CA._activeAuras[aura.id])
    end

    return container
end

local function InitializeContainers()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        if not CA._activeAuras[aura.id] then
            CreateAuraContainer(aura)
        end
    end

    -- Apply anchor linkage for secondary auras after all containers exist
    -- (late-bound: styling.lua sets CA._ApplyAnchorLinkage before runtime calls)
    for _, aura in ipairs(auras) do
        if aura.anchorTo then
            local state = CA._activeAuras[aura.id]
            if state then CA._ApplyAnchorLinkage(aura, state) end
        end
    end
end

--------------------------------------------------------------------------------
-- Rebuild
--------------------------------------------------------------------------------

local function RebuildAll()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        -- Zero-Touch: skip unconfigured components (still on proxy DB)
        local comp = addon.Components and addon.Components[GetComponentId(aura)]
        if not (comp and comp._ScootDBProxy and comp.db == comp._ScootDBProxy) then
            -- Late-bound: styling.lua sets CA._ApplyStyling before runtime calls
            CA._ApplyStyling(aura)
        end
    end
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        local auraCopy = aura -- upvalue for closure
        local comp = Component:New({
            id = GetComponentId(aura),
            name = "Class Aura: " .. aura.label,
            settings = aura.settings,
            ApplyStyling = function(component)
                -- Late-bound: styling.lua sets CA._ApplyStyling before runtime calls
                CA._ApplyStyling(auraCopy)
            end,
        })
        self:RegisterComponent(comp)
    end
end, "classAuras")

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

CA._GetDB = GetDB
CA._GetComponentId = GetComponentId
CA._playerClassToken = playerClassToken
CA._InitializeContainers = InitializeContainers
CA._RebuildAll = RebuildAll
CA._elementCreators = elementCreators

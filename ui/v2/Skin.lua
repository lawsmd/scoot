-- Skin.lua - skin registry and facade push for the settings framework.
--
-- A skin owns how the settings UI is drawn: palette roles, font roles with
-- sizes, texture paths, and chrome metrics. Controls own behavior and read
-- style only through the facades this module fills: the color and font
-- accessors on addon.UI.Theme, and Controls.Metrics() for layout numbers.
-- SetActive copies the active skin into those facades, so their table
-- identities never change and file-scope captures of the tables stay valid.
--
--   Skin.Register(name, skin)   skin = { palette, fonts, textures, metrics }
--   Skin.SetActive(name)        push the skin into the facades and notify
--   Skin.Active()               the active skin table
--   Skin.ActiveName()           its registry name
--   Skin.Metrics()              the active skin's metrics table
--   Skin.Dump()                 registry listing in the copyable debug window
--
-- Palette roles: background, backgroundSolid, textPrimary, textDim,
-- textDimLight, collapsibleBg, accentDefault; each { r, g, b, a }.
-- Font roles: label, value, desc, header, button, miniLabel, proportional,
-- proportionalMed; each { path, size }.
-- Metrics: flat layout and style numbers plus the slots, sublevels, and
-- alphas sub-tables; the full catalog is the tui skin table.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Skin = addon.UI.Skin or {}
local Skin = addon.UI.Skin

Skin._registry = {}
Skin._activeName = nil

function Skin.Register(name, skin)
    if type(name) ~= "string" or type(skin) ~= "table" then return false end
    Skin._registry[name] = skin
    return true
end

function Skin.ActiveName()
    return Skin._activeName
end

function Skin.Active()
    return Skin._activeName and Skin._registry[Skin._activeName] or nil
end

function Skin.Metrics()
    local skin = Skin.Active()
    return skin and skin.metrics
end

-- Copies the skin's values into the stable facades. A missing facade table is
-- created so load order cannot drop a push; an existing one keeps its
-- identity, so no reader learns which skin is active.
function Skin.SetActive(name)
    local skin = Skin._registry[name]
    if not skin then return false end
    Skin._activeName = name

    local Theme = addon.UI.Theme
    local p = skin.palette
    if Theme and p then
        Theme.DEFAULT_ACCENT   = p.accentDefault
        Theme.BACKGROUND       = p.background
        Theme.BACKGROUND_SOLID = p.backgroundSolid
        Theme.TEXT_PRIMARY     = p.textPrimary
        Theme.TEXT_DIM         = p.textDim
        Theme.TEXT_DIM_LIGHT   = p.textDimLight
        Theme.COLLAPSIBLE_BG   = p.collapsibleBg
    end

    local fonts = skin.fonts
    if Theme and fonts then
        Theme._fontRoles = fonts
        -- The path table behind the Theme:GetFont shim; new code reads roles
        -- through Theme:GetFontRole and Theme:ApplyFont.
        Theme.Fonts = {
            LABEL  = fonts.label and fonts.label.path,
            VALUE  = fonts.value and fonts.value.path,
            HEADER = fonts.header and fonts.header.path,
            BUTTON = fonts.button and fonts.button.path,
            PROPORTIONAL     = fonts.proportional and fonts.proportional.path,
            PROPORTIONAL_MED = fonts.proportionalMed and fonts.proportionalMed.path,
        }
    end

    if Theme and skin.textures then
        Theme.Textures = skin.textures
    end

    local m = skin.metrics
    if m then
        if Theme then
            Theme.BORDER_WIDTH = m.windowBorderWidth
        end
        addon.UI.Controls = addon.UI.Controls or {}
        local Controls = addon.UI.Controls
        Controls.SUBLEVEL_BG    = m.sublevels.bg
        Controls.SUBLEVEL_FILL  = m.sublevels.fill
        Controls.SUBLEVEL_HOVER = m.sublevels.hover
        Controls.ALPHA_HOVER    = m.alphas.hover
        Controls.ALPHA_EMPHASIS = m.alphas.emphasis
        Controls.ALPHA_SELECTED = m.alphas.selected
        Controls.BORDER_ALPHA_NORMAL = m.alphas.borderNormal
        Controls.BORDER_ALPHA_FOCUS  = m.alphas.borderFocus
    end

    -- At load there are no subscribers yet; a runtime switch retints every
    -- themed border and fill through the one shared subscription.
    if Theme and Theme.NotifySubscribers then
        Theme:NotifySubscribers()
    end
    return true
end

local function countKeys(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Skin.Dump()
    local lines, push = addon.DebugLines()
    push("active: " .. tostring(Skin._activeName))
    local names = {}
    for name in pairs(Skin._registry) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local skin = Skin._registry[name]
        push(string.format("%s: %d palette roles, %d font roles, %d textures, %d metrics",
            name, countKeys(skin.palette), countKeys(skin.fonts),
            countKeys(skin.textures), countKeys(skin.metrics)))
    end
    addon.DebugShowWindow("Skins", lines)
end

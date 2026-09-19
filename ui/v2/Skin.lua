-- Skin.lua - skin registry and facade push for the settings framework.
--
-- A skin owns how the settings UI is drawn: palette roles, font roles with
-- sizes, texture paths, and chrome metrics. Controls own behavior and read
-- style only through the facades this module fills: the color and font
-- accessors on addon.UI.Theme, and Controls.Metrics() for layout numbers.
-- SetActive copies the active skin into those facades, so their table
-- identities never change and file-scope captures of the tables stay valid.
--
--   Skin.Register(name, skin)   skin = { palette, fonts, textures, metrics,
--                               chrome, opacity, overrides }
--   Skin.SetActive(name)        push the skin into the facades, install its
--                               overrides, notify, re-render the open panel
--   Skin.Active()               the active skin table
--   Skin.ActiveName()           its registry name
--   Skin.Metrics()              the active skin's metrics table
--   Skin.Override               draw-replacement proxy; an assignment records
--                               its source and a skin switch clears the set
--   Skin.GetOverride(name)      the override the row factories dispatch on
--   Skin.Dump()                 registry listing in the copyable debug window
--
-- Palette roles: background, backgroundSolid, textPrimary, textDim,
-- textDimLight, collapsibleBg, accentDefault; each { r, g, b, a }.
-- Font roles: label, value, desc, header, button, miniLabel, proportional,
-- proportionalMed; each { path, size, style }. style is a key from
-- addon.FontStyles (core/fonts.lua) and defaults to NONE; a skin may declare
-- roles of its own beside these, for a surface whose metrics name one
-- (metrics.nav.card.labelFontRole).
-- Metrics: flat layout and style numbers plus the slots, sublevels, and
-- alphas sub-tables; the full catalog is the tui skin table.
-- Chrome: one descriptor per panel surface (window, titleBar, closeButton,
-- button, resizeGrip, scrollBar, tab, tabBody, sectionHeader, sectionBody,
-- navRow, dropdown), each a kind (flat, nineSlice, atlas, template) with the
-- names that kind draws from; ui/v2/Chrome.lua resolves them against the
-- client and supplies the flat default for a role a skin leaves out.
-- Opacity: one number per named piece of the panel's art (Chrome.PIECES), the
-- skin author's and never a player setting; a piece left out draws at 1.
--
-- An override replaces a row factory's draw body only:
-- overrides.<Control> = function(options) must return a frame satisfying the
-- stock control's public methods and the fields the framework reads (_label,
-- _description, _measureDesc), honor options.rowWidth, and set its height
-- before returning.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Skin = addon.UI.Skin or {}
local Skin = addon.UI.Skin

Skin._registry = {}
Skin._activeName = nil
Skin._overrides = {}
Skin._installSource = nil

-- Assignments through the proxy record where the override came from: the
-- skin being activated, or "manual" for a direct assignment.
Skin.Override = setmetatable({}, {
    __newindex = function(_, controlName, fn)
        if fn == nil then
            Skin._overrides[controlName] = nil
        else
            Skin._overrides[controlName] = {
                fn = fn,
                source = Skin._installSource or "manual",
            }
        end
    end,
    __index = function(_, controlName)
        local entry = Skin._overrides[controlName]
        return entry and entry.fn or nil
    end,
})

function Skin.GetOverride(controlName)
    local entry = Skin._overrides[controlName]
    return entry and entry.fn or nil
end

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

    -- The chrome table is the declaration; Chrome.Spec resolves each role
    -- against the client at draw time, so a switch only has to forget the
    -- previous resolutions.
    if Theme then
        Theme.Chrome = skin.chrome or {}
        Theme.Opacity = skin.opacity or {}
    end
    if addon.UI.Chrome and addon.UI.Chrome.Invalidate then
        addon.UI.Chrome.Invalidate()
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

    -- Replace the previous skin's override set with this skin's.
    for controlName in pairs(Skin._overrides) do
        Skin._overrides[controlName] = nil
    end
    Skin._installSource = name
    for controlName, fn in pairs(skin.overrides or {}) do
        Skin.Override[controlName] = fn
    end
    Skin._installSource = nil

    -- At load there are no subscribers yet; a runtime switch retints every
    -- themed border and fill through the one shared subscription.
    if Theme and Theme.NotifySubscribers then
        Theme:NotifySubscribers()
    end

    -- A runtime switch rebuilds the panel from the window out, so the chrome
    -- follows the skin as well as the rows, and the page that was open comes
    -- back. At load nothing is built yet, so the boot-time activations in the
    -- skin files and the product menu skip this.
    local panel = addon.UI.SettingsPanel
    if panel and panel._initialized and panel.Teardown then
        local shown = panel.frame and panel.frame.IsShown and panel.frame:IsShown()
        local key = panel._currentCategoryKey
        panel:Teardown()
        if shown then
            panel:Show()
            local Navigation = addon.UI.Navigation
            if key and key ~= "home" and Navigation and Navigation.SelectItem then
                Navigation:SelectItem(key)
            end
        end
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
        push(string.format("%s: %d palette roles, %d font roles, %d textures, %d metrics, %d chrome roles, %d overrides",
            name, countKeys(skin.palette), countKeys(skin.fonts),
            countKeys(skin.textures), countKeys(skin.metrics),
            countKeys(skin.chrome), countKeys(skin.overrides)))
    end

    local overrideNames = {}
    for controlName in pairs(Skin._overrides) do
        overrideNames[#overrideNames + 1] = controlName
    end
    table.sort(overrideNames)
    push("active overrides: " .. (#overrideNames == 0 and "none" or tostring(#overrideNames)))
    for _, controlName in ipairs(overrideNames) do
        push(string.format("  %s (from %s)", controlName, Skin._overrides[controlName].source))
    end

    local m = Skin.Metrics()
    if m then
        push("metrics:")
        local keys = {}
        for k in pairs(m) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = m[k]
            if type(v) == "table" then
                local subKeys = {}
                for sk in pairs(v) do subKeys[#subKeys + 1] = sk end
                table.sort(subKeys)
                local parts = {}
                for _, sk in ipairs(subKeys) do
                    parts[#parts + 1] = sk .. "=" .. tostring(v[sk])
                end
                push(string.format("  %s: %s", k, table.concat(parts, " ")))
            else
                push(string.format("  %s: %s", k, tostring(v)))
            end
        end
    end

    if addon.UI.Chrome and addon.UI.Chrome.Dump then
        addon.UI.Chrome.Dump(push)
    end
    addon.DebugShowWindow("Skins", lines)
end

addon:RegisterDebugCommand({
    name = "skin",
    help = "Skin registry and metrics; 'skin <name>' switches and re-renders",
    handler = function(sub)
        if sub and sub ~= "" then
            if Skin.SetActive(sub) then
                addon:Print("Skin: " .. sub)
            else
                addon:Print("Skin: no skin named '" .. tostring(sub) .. "'")
            end
            return
        end
        Skin.Dump()
    end,
})

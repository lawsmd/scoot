-- Theme.lua - Foundation for UI settings panel
-- Provides: Theme system, accent color management, font helpers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Theme = {}
local Theme = addon.UI.Theme

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Default Matrix green: #00FF41 (classic terminal green)
Theme.DEFAULT_ACCENT = { r = 0, g = 1, b = 0.255, a = 1 }

-- Accent modes. "custom" returns the color stored in db.global.accentColor;
-- "class" resolves the player's class color on every read, leaving the stored
-- custom color untouched so switching back restores the user's pick.
Theme.ACCENT_MODE_CUSTOM = "custom"
Theme.ACCENT_MODE_CLASS = "class"
Theme.DEFAULT_ACCENT_MODE = Theme.ACCENT_MODE_CUSTOM

-- The palette (DEFAULT_ACCENT, BACKGROUND, BACKGROUND_SOLID, TEXT_PRIMARY,
-- TEXT_DIM, TEXT_DIM_LIGHT, COLLAPSIBLE_BG), the Fonts and Textures tables,
-- the font roles behind GetFontRole, and BORDER_WIDTH are pushed onto this
-- table by Skin.SetActive from the active skin. This file owns the accessors;
-- the values live in the skin.

-- Glow settings (glow disabled until proper texture assets are created)
Theme.GLOW_ALPHA = 0.35  -- Reserved for future use
Theme.GLOW_WIDTH = 6     -- Reserved for future use

--------------------------------------------------------------------------------
-- Pub/Sub System for Accent Color Changes
--------------------------------------------------------------------------------

Theme._subscribers = {}

function Theme:Subscribe(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return end
    self._subscribers[key] = callback
end

function Theme:Unsubscribe(key)
    self._subscribers[key] = nil
end

function Theme:NotifySubscribers()
    local r, g, b, a = self:GetAccentColor()
    for key, callback in pairs(self._subscribers) do
        local ok, err = pcall(callback, r, g, b, a)
        if not ok then
            -- Silently log; don't break other subscribers
            if addon.Debug then
                addon.Debug("UI Theme subscriber error", key, err)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Accent Color Accessors
--------------------------------------------------------------------------------

-- The stored custom color, whichever mode is active.
function Theme:GetCustomAccentColor()
    local db = addon.db and addon.db.global
    if db and db.accentColor then
        local c = db.accentColor
        return c.r or self.DEFAULT_ACCENT.r,
               c.g or self.DEFAULT_ACCENT.g,
               c.b or self.DEFAULT_ACCENT.b,
               c.a or 1
    end
    return self.DEFAULT_ACCENT.r, self.DEFAULT_ACCENT.g, self.DEFAULT_ACCENT.b, 1
end

function Theme:GetAccentColorMode()
    local db = addon.db and addon.db.global
    if db and db.accentColorMode == self.ACCENT_MODE_CLASS then
        return self.ACCENT_MODE_CLASS
    end
    return self.ACCENT_MODE_CUSTOM
end

function Theme:SetAccentColorMode(mode)
    if not addon.db or not addon.db.global then
        return false
    end
    if mode ~= self.ACCENT_MODE_CLASS then
        mode = self.ACCENT_MODE_CUSTOM
    end
    addon.db.global.accentColorMode = mode
    self:NotifySubscribers()
    return true
end

-- Resolves the mode on every read, so all 237 call sites and both retint
-- mechanisms inherit class mode without a call-site edit.
function Theme:GetAccentColor()
    if self:GetAccentColorMode() == self.ACCENT_MODE_CLASS then
        -- Statement form, not `f and f(...)`: an and/or expression is adjusted
        -- to one value, which would drop g and b.
        local r, g, b
        if addon.GetClassColorRGB then
            r, g, b = addon.GetClassColorRGB("player")
        end
        if r and g and b then
            return r, g, b, 1
        end
        -- Class unresolved (taint, secret unit): fall through to the custom color.
    end
    return self:GetCustomAccentColor()
end

local function hexChannel(v)
    v = math.floor((v or 0) * 255 + 0.5)
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return v
end

-- 0-1 floats as "rrggbb". A plain function, not a method: the fallback path in
-- addon.GetAccentHex has no Theme instance to call it on.
function Theme.RGBToHex(r, g, b)
    return string.format("%02x%02x%02x", hexChannel(r), hexChannel(g), hexChannel(b))
end

-- The accent as "rrggbb", for the |cff escapes in chat prefixes.
function Theme:GetAccentHex()
    return Theme.RGBToHex(self:GetAccentColor())
end

function Theme:SetAccentColor(r, g, b, a)
    if not addon.db or not addon.db.global then
        return false
    end
    addon.db.global.accentColor = {
        r = r or self.DEFAULT_ACCENT.r,
        g = g or self.DEFAULT_ACCENT.g,
        b = b or self.DEFAULT_ACCENT.b,
        a = a or 1
    }
    self:NotifySubscribers()
    return true
end

-- Restores both the default color and the default mode. The mode is written
-- first so the SetAccentColor notify below carries the reset state.
function Theme:ResetAccentColor()
    if addon.db and addon.db.global then
        addon.db.global.accentColorMode = self.DEFAULT_ACCENT_MODE
    end
    return self:SetAccentColor(
        self.DEFAULT_ACCENT.r,
        self.DEFAULT_ACCENT.g,
        self.DEFAULT_ACCENT.b,
        self.DEFAULT_ACCENT.a
    )
end

-- One resolver for the callers that guard against a missing Theme, so the
-- fallback literal lives here rather than once per file. Written as statements,
-- never `theme and theme:GetAccentColor() or r, g, b`: that expression is
-- adjusted to one value and leaves g and b as the literals.
function addon.GetAccentColorRGB()
    local theme = addon.UI and addon.UI.Theme
    if theme and theme.GetAccentColor then
        return theme:GetAccentColor()
    end
    local d = Theme.DEFAULT_ACCENT
    return d.r, d.g, d.b, 1
end

-- The same resolver in "rrggbb" form, for the |cff escapes in chat prefixes.
function addon.GetAccentHex()
    local theme = addon.UI and addon.UI.Theme
    if theme and theme.GetAccentHex then
        return theme:GetAccentHex()
    end
    local d = Theme.DEFAULT_ACCENT
    return Theme.RGBToHex(d.r, d.g, d.b)
end

--------------------------------------------------------------------------------
-- Derived Color Helpers
--------------------------------------------------------------------------------

function Theme:GetGlowColor()
    local r, g, b = self:GetAccentColor()
    return r, g, b, self.GLOW_ALPHA
end

function Theme:GetBorderColor()
    local r, g, b = self:GetAccentColor()
    return r, g, b, 1
end

function Theme:GetBackgroundColor()
    return self.BACKGROUND.r, self.BACKGROUND.g, self.BACKGROUND.b, self.BACKGROUND.a
end

function Theme:GetBackgroundSolidColor()
    return self.BACKGROUND_SOLID.r, self.BACKGROUND_SOLID.g, self.BACKGROUND_SOLID.b, self.BACKGROUND_SOLID.a
end

function Theme:GetPrimaryTextColor()
    return self.TEXT_PRIMARY.r, self.TEXT_PRIMARY.g, self.TEXT_PRIMARY.b, self.TEXT_PRIMARY.a
end

function Theme:GetDimTextColor()
    return self.TEXT_DIM.r, self.TEXT_DIM.g, self.TEXT_DIM.b, self.TEXT_DIM.a
end

function Theme:GetDimTextLightColor()
    return self.TEXT_DIM_LIGHT.r, self.TEXT_DIM_LIGHT.g, self.TEXT_DIM_LIGHT.b, self.TEXT_DIM_LIGHT.a
end

function Theme:GetCollapsibleBgColor()
    return self.COLLAPSIBLE_BG.r, self.COLLAPSIBLE_BG.g, self.COLLAPSIBLE_BG.b, self.COLLAPSIBLE_BG.a
end

--------------------------------------------------------------------------------
-- Font Helper Functions
--------------------------------------------------------------------------------

-- Check if a font file exists/is loadable.
--
-- SetFont does NOT raise for a missing or not-yet-loaded file -- it returns
-- false. Testing only the pcall status therefore always answered "true", so
-- every fallback below was dead code and GetFont happily handed back a path the
-- client could not render. The boolean is the real answer.
--
-- One probe object, created lazily and reused: the old version minted a fresh
-- CreateFont global per call from a 100k-name random space.
-- Results are memoized per path: GetFont runs on nearly every panel widget, and
-- a file the client did not load at startup will not start loading mid-session
-- (that needs a full client restart), so the answer cannot change mid-session.
local probeFont
local fontExistsCache = {}
local function FontExists(path)
    if not path then return false end
    local cached = fontExistsCache[path]
    if cached ~= nil then return cached end

    -- Brand-named: both addons load this file in the retail client.
    probeFont = probeFont or CreateFont((addon.Brand or "Scoot") .. "FontProbe")
    if not probeFont then return false end
    local ok, applied = pcall(probeFont.SetFont, probeFont, path, 12, "")
    local exists = ok and applied ~= false
    fontExistsCache[path] = exists
    return exists
end

-- Get a safe font path (with fallback)
function Theme:GetFont(fontType)
    local path = self.Fonts[fontType]
    if path and FontExists(path) then
        return path
    end
    -- Fallback chain
    if self.Fonts.PROPORTIONAL and FontExists(self.Fonts.PROPORTIONAL) then
        return self.Fonts.PROPORTIONAL
    end
    -- Ultimate fallback to game default
    return "Fonts\\FRIZQT__.TTF"
end

-- The active skin supplies { path, size, style } per font role (label, value,
-- desc, header, button, miniLabel, proportional, proportionalMed, plus any
-- name a skin's own metrics point at -- nav.card.labelFontRole is one).
-- GetFontRole resolves the path through the same existence fallback as GetFont
-- and returns the role's size and style beside it.
--
-- style is a key from addon.FontStyles (core/fonts.lua), the same catalog the
-- component pages offer players: an engine flag (OUTLINE, THICKOUTLINE), a
-- shadow, a crisp SLUG variant, or DEEPSHADOW*, which draws a black copy of
-- the string behind it. A role that leaves it out reads NONE, so a skin that
-- names no styles renders exactly as it did before styles existed.
function Theme:GetFontRole(role)
    local roles = self._fontRoles
    local entry = roles and roles[role]
    local path = entry and entry.path
    if not (path and FontExists(path)) then
        local prop = roles and roles.proportional and roles.proportional.path
        if prop and FontExists(prop) then
            path = prop
        else
            path = "Fonts\\FRIZQT__.TTF"
        end
    end
    return path, (entry and entry.size) or 12, (entry and entry.style) or "NONE"
end

-- The one place a panel font face, size and style are applied together. A size
-- or style argument overrides the role's own; color stays with the caller.
--
-- addon.ApplyFontStyle does the applying, so a panel string reaches the same
-- decoder the component pages use: it walks the face fallbacks when the client
-- will not load a file, and it builds the companion string DEEPSHADOW* needs.
-- The DEEPSHADOW* keys are safe here because the panel creates every string it
-- draws and feeds each one through SetText, which is what the companion's
-- mirror hooks need (core/fontpair.lua). The one string that must not carry a
-- companion is the measurement ruler, which asks for MetricStyle instead
-- (ui/v2/controls/Fit.lua).
function Theme:ApplyFont(fontString, role, size, style)
    if not fontString or not fontString.SetFont then return end
    local path, roleSize, roleStyle = self:GetFontRole(role)
    return addon.ApplyFontStyle(fontString, path, size or roleSize, style or roleStyle)
end

-- The colored helpers are ApplyFont plus the color each is named for. They
-- read their role through the same table, so the face and size are what they
-- always were and a style the skin puts on the role now reaches them too. The
-- sizes stay literal rather than falling back to the role's: these defaults
-- predate the role sizes and callers pass a size in nearly every case.
--
-- role is the surface's own role in place of the helper's, for a surface a
-- skin wants to style by itself: the nav child row reads
-- metrics.nav.card.childLabelFontRole and the page header
-- metrics.contentHeader.fontRole, so the Camelot skin can put a style on
-- either without it reaching every other string of the same color.

-- Apply label font (accent-colored)
function Theme:ApplyLabelFont(fontString, size, role)
    if not fontString or not fontString.SetFont then return end
    self:ApplyFont(fontString, role or "label", size or 12)
    local r, g, b = self:GetAccentColor()
    if fontString.SetTextColor then
        fontString:SetTextColor(r, g, b, 1)
    end
end

-- Apply header font (accent-colored, larger; Friz ships no bold and the widget
-- API has no weight, so a skin's header role is a size, not a face)
function Theme:ApplyHeaderFont(fontString, size, role)
    if not fontString or not fontString.SetFont then return end
    self:ApplyFont(fontString, role or "header", size or 16)
    local r, g, b = self:GetAccentColor()
    if fontString.SetTextColor then
        fontString:SetTextColor(r, g, b, 1)
    end
end

-- Apply value font (white)
function Theme:ApplyValueFont(fontString, size, role)
    if not fontString or not fontString.SetFont then return end
    self:ApplyFont(fontString, role or "value", size or 12)
    if fontString.SetTextColor then
        fontString:SetTextColor(1, 1, 1, 1)
    end
end

-- Apply button font (accent-colored)
function Theme:ApplyButtonFont(fontString, size, role)
    if not fontString or not fontString.SetFont then return end
    self:ApplyFont(fontString, role or "button", size or 13)
    local r, g, b = self:GetAccentColor()
    if fontString.SetTextColor then
        fontString:SetTextColor(r, g, b, 1)
    end
end

-- Apply dim text (secondary labels; the value role, as before)
function Theme:ApplyDimFont(fontString, size, role)
    if not fontString or not fontString.SetFont then return end
    self:ApplyFont(fontString, role or "value", size or 11)
    if fontString.SetTextColor then
        fontString:SetTextColor(self.TEXT_DIM.r, self.TEXT_DIM.g, self.TEXT_DIM.b, self.TEXT_DIM.a)
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- Ensure UI namespace is properly set up when addon loads
function Theme:Initialize()
    -- Nothing special needed yet; accent color defaults are handled via AceDB
end

-- Setting patterns (reusable relationships between settings) live in
-- SettingPatterns.lua on addon.UI.SettingPatterns.

--------------------------------------------------------------------------------
-- Font style tuning
--------------------------------------------------------------------------------

-- The font roles tried on the open panel the way 'opacity' tries the art's
-- alphas: 'font <role> <STYLE>' writes the style into the active skin's fonts
-- table and rebuilds the panel from the skin, so an outline or a Deep Shadow
-- can be judged on the surface that will carry it. A reload restores the
-- skin's own styles. Role names are case-sensitive and a role the active skin
-- leaves out cannot be set. 'font styles' lists the keys.
local function DumpFontRoles()
    local lines, push = addon.DebugLines()
    local roles = Theme._fontRoles
    if not roles then
        push("no skin is active, so the panel has no font roles")
        addon.DebugShowWindow("Panel fonts", lines)
        return
    end
    -- The fonts table is keyed by name and carries no order of its own.
    local names = {}
    for name in pairs(roles) do names[#names + 1] = name end
    table.sort(names)
    push(string.format("-- skin %s", tostring(addon.UI.Skin.ActiveName())))
    push("fonts = {")
    for _, name in ipairs(names) do
        local entry = roles[name] or {}
        local path = tostring(entry.path or "?")
        push(string.format("    %-15s = { size = %s, style = %q },  -- %s",
            name, tostring(entry.size), tostring(entry.style or "NONE"),
            path:match("[^\\/]+$") or path))
    end
    push("},")
    push("")
    push("The face is a local in the skin file, so the trailing comment names")
    push("the file rather than the path to paste back.")
    addon.DebugShowWindow("Panel fonts", lines)
end

local function DumpFontStyles()
    local lines, push = addon.DebugLines()
    local Styles = addon.FontStyles
    for _, key in ipairs(Styles.orderPaired or {}) do
        push(string.format("%-24s %s", key, Styles.values[key] or ""))
    end
    if not Styles.slugSupported then
        push("")
        push("This client rejects the SLUG flag, so the crisp keys are left out:")
        push("stored on a role they render as their base style.")
    end
    addon.DebugShowWindow("Font styles", lines)
end

local fontCommand = {
    name = "font",
    help = "Panel font styles by role; 'font <role> <STYLE>' retunes the open panel",
    usage = {
        "font lists every role; role names are case-sensitive (label, value, header, navLabel)",
        "font styles lists the style keys (NONE, THICKOUTLINE, DEEPSHADOWTHICKOUTLINE)",
    },
    handler = function(sub, rest)
        local role = rest and rest[1]
        if not role or role == "" then return DumpFontRoles() end
        if sub == "styles" then return DumpFontStyles() end
        local style = rest[2] and string.upper(rest[2])
        local entry = Theme._fontRoles and Theme._fontRoles[role]
        if not entry or not style or not addon.FontStyles.values[style] then
            return addon.Commands.USAGE
        end
        entry.style = style
        local Skin = addon.UI.Skin
        Skin.SetActive(Skin.ActiveName())
    end,
}
-- The same command at the top level and under debug
addon:RegisterSlashCommand(fontCommand)
addon:RegisterDebugCommand(fontCommand)

--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/style.lua
-- The Personal Resource Display module: its switch, its settings and their
-- defaults, and what applies them to CamelotPersonalResourceDisplay. The
-- replica itself is display.lua; the page is page.lua.
--
-- First of the feature's files, and on both clients: retail loads Camelot.toc
-- for the settings panel and excludes the HUD, and the page draws its
-- controls there so a stored value can be checked across a reload while the
-- beta keeps none. Nothing here reads the frame at file scope; every apply
-- runs against it when it exists and returns when it does not.
--
-- The defaults are Forever's shipped PRD, retail's Modern preset (vanilla had
-- no PRD): both bars 15 high, the full 200 width, no spacing, full opacity,
-- always shown, bar text off. The text keys register no face, size or style:
-- nil leaves the string on the TextStatusBarText font object.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.PersonalResourceDisplay = addon.PersonalResourceDisplay or {}
local PRD = addon.PersonalResourceDisplay

-- The owner string every claim, event and Edit Mode registration carries,
-- the settings page key, and the global frames.xml declares.
PRD.OWNER = "camelotPersonalResourceDisplay"
PRD.NAV_KEY = "personalResourceDisplay"
PRD.FRAME_NAME = "CamelotPersonalResourceDisplay"

local Style = {}
PRD.Style = Style

--------------------------------------------------------------------------------
-- Module and switch
--------------------------------------------------------------------------------

DB.RegisterModule("personalResourceDisplay", true)

addon.Features.Register({
    group = "interface", groupLabel = "Interface",
    id = "personalResourceDisplay", label = "Personal Resource Display",
    path = "personalResourceDisplay.enabled",
})

-- Held for the session: the Features page changes it at the reload, and a
-- feature off at login never touches Blizzard's frame.
function PRD.IsEnabled()
    return DB.IsModuleEnabled("personalResourceDisplay")
        and DB.SessionGet("personalResourceDisplay.enabled") == true
end

--------------------------------------------------------------------------------
-- Ranges, paths and defaults
--------------------------------------------------------------------------------

-- Blizzard's Edit Mode ranges for the system (EditModeSettingDisplayInfo.lua)
-- and the Modern preset's values (EditModePresetLayouts.lua).
Style.SCALE = { min = 70, max = 150, step = 1, default = 100 }
Style.BAR_WIDTH = { min = 50, max = 150, step = 1, default = 100 }
Style.HEIGHT = { min = 10, max = 30, step = 1, default = 15 }
Style.PADDING = { min = 0, max = 10, step = 1, default = 0 }
Style.OPACITY = { min = 50, max = 100, step = 1, default = 100 }
-- Camelot's own: the background atlas draws at full alpha on Blizzard's frame.
Style.BACKGROUND_OPACITY = { min = 0, max = 100, step = 1, default = 100 }
Style.TEXT_SIZE = { min = 6, max = 36, step = 1 }
Style.THICKNESS = { min = 1, max = 8, step = 0.5, default = 1 }

-- The frame's XML width, Blizzard's defaultBarWidth; Bar Width scales it.
Style.DEFAULT_BAR_WIDTH = 200

-- The Modern preset's anchor for the system, on UIParent.
Style.DEFAULT_POSITION = { point = "BOTTOM", x = -410, y = 380 }

Style.BARS = { "health", "power" }
Style.BAR_ATLAS = "UI-HUD-CoolDownManager-Bar"
Style.BACKGROUND_ATLAS = "UI-HUD-CoolDownManager-Bar-BG"
Style.FONT_OBJECT = "TextStatusBarText"

-- The show modes of a bar's text. Blizzard's TextStatusBar had the same three
-- through the statusText CVar; the Camelot template is a plain StatusBar.
Style.SHOW_TEXT = {
    values = { always = "Always", hover = "On Hover", never = "Never" },
    order = { "always", "hover", "never" },
}

--- The dotted path of a setting: Style.Path("scale"), Style.Path("health",
--- "height"), Style.Path("power", "text", "value", "show").
function Style.Path(...)
    return "personalResourceDisplay." .. table.concat({ ... }, ".")
end

function Style.Get(...)
    return DB.Get(Style.Path(...))
end

do
    local map = {}
    map[Style.Path("enabled")] = true
    map[Style.Path("visibility")] = "always"
    map[Style.Path("scale")] = Style.SCALE.default
    map[Style.Path("barWidth")] = Style.BAR_WIDTH.default
    map[Style.Path("padding")] = Style.PADDING.default
    map[Style.Path("opacity")] = Style.OPACITY.default
    for _, bar in ipairs(Style.BARS) do
        local function set(value, ...) map[Style.Path(bar, ...)] = value end
        set(false, "hide")
        set(Style.HEIGHT.default, "height")
        set("default", "foregroundTexture")
        set("default", "foregroundColorMode")
        set({ 1, 1, 1, 1 }, "foregroundTint")
        set("default", "backgroundTexture")
        set("default", "backgroundColorMode")
        set({ 0, 0, 0, 1 }, "backgroundTint")
        set(Style.BACKGROUND_OPACITY.default, "backgroundOpacity")
        -- Off is the picker's own "none"; there is no enable key.
        set("none", "borderStyle")
        set(false, "borderTintEnabled")
        set({ 1, 1, 1, 1 }, "borderTintColor")
        set(Style.THICKNESS.default, "borderThickness")
        set(false, "hideTextureOnly")
        set(false, "hideBackground")
        -- The value text. Blizzard's Show Bar Text is off in the preset, and
        -- text is an added element. No fontFace, size or style: nil keeps
        -- the font object's own face, size and outline.
        set("never", "text", "value", "show")
        set("default", "text", "value", "colorMode")
        set({ 1, 1, 1, 1 }, "text", "value", "color")
        set("RIGHT", "text", "value", "alignment")
    end
    map[Style.Path("power", "hideManaCostPrediction")] = false
    -- The Classic unit frames' four switches, on the PRD's health bar.
    for _, field in ipairs({ "incomingHeals", "absorb", "overAbsorbGlow", "healAbsorb" }) do
        map[Style.Path("health", field)] = true
    end
    DB.RegisterDefaults(map)
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function clamp(value, range)
    local v = tonumber(value) or range.default
    if v < range.min then v = range.min elseif v > range.max then v = range.max end
    return v
end
Style.Clamp = clamp

function Style.Scale() return clamp(Style.Get("scale"), Style.SCALE) end
function Style.Opacity() return clamp(Style.Get("opacity"), Style.OPACITY) end
function Style.Padding() return clamp(Style.Get("padding"), Style.PADDING) end
function Style.BarWidthPercent() return clamp(Style.Get("barWidth"), Style.BAR_WIDTH) end

--- The bars' width in the frame's own units.
function Style.BarWidthPixels()
    return Style.DEFAULT_BAR_WIDTH * Style.BarWidthPercent() / 100
end

function Style.Height(bar)
    return clamp(Style.Get(bar, "height"), Style.HEIGHT)
end

--- "always", "combat" or "never", the Visibility catalog's keys.
function Style.Visibility()
    local v = Style.Get("visibility")
    if v == "combat" or v == "never" then return v end
    return "always"
end

--- "always", "hover" or "never" for a bar's value text.
function Style.TextShow(bar)
    local v = Style.Get(bar, "text", "value", "show")
    if v == "always" or v == "hover" then return v end
    return "never"
end

--- The frame, or nil: on retail none is built.
function Style.Frame()
    return _G[PRD.FRAME_NAME]
end

--- The bar and the plain container it fills.
function Style.Bar(frame, bar)
    if bar == "health" then return frame.HealthBarsContainer.healthBar end
    return frame.PowerBarContainer.PowerBar
end

function Style.Container(frame, bar)
    if bar == "health" then return frame.HealthBarsContainer end
    return frame.PowerBarContainer
end

--- The font object's face, size and flags, what a string draws with nothing
--- stored, and what the page shows for that state.
function Style.FontObjectFont()
    local fontObject = _G[Style.FONT_OBJECT]
    if fontObject and fontObject.GetFont then
        local face, size, flags = fontObject:GetFont()
        if face then return face, size or 10, flags or "OUTLINE" end
    end
    return nil, 10, "OUTLINE"
end

--------------------------------------------------------------------------------
-- Layout, scale, opacity
--------------------------------------------------------------------------------
-- The mixin's setters (mixins.lua) are Blizzard's own, called with the stored
-- values in place of Edit Mode's.

function Style.ApplyLayout()
    local f = Style.Frame()
    if not f then return end
    f:SetBarWidth(Style.BarWidthPercent())
    f:SetHealthBarHeight(Style.Height("health"))
    f:SetPowerBarHeight(Style.Height("power"))
    f:SetBarPadding(Style.Padding())
    f:SetHideHealth(Style.Get("health", "hide") == true)
    f:SetHidePower(Style.Get("power", "hide") == true)
end

function Style.ApplyScale()
    local f = Style.Frame()
    if not f then return end
    f:SetScale(Style.Scale() / 100)
end

-- The engine replaces alpha rather than multiplying it, so while a dynamic
-- state holds the frame's alpha is the engine's and the base stays off it.
function Style.ApplyOpacity()
    local f = Style.Frame()
    if not f then return end
    if PRD.Dynamic and PRD.Dynamic.IsDynamic() then return end
    f:SetAlpha(Style.Opacity() / 100)
end

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

local function texturePath(key)
    if key == nil or key == "" or key == "default" then return nil end
    local Media = addon.Media
    return Media and Media.ResolveBarTexturePath and Media.ResolveBarTexturePath(key) or nil
end

local function applyFill(bar, key)
    local path = texturePath(Style.Get(key, "foregroundTexture"))
    if path then
        bar:SetStatusBarTexture(path)
    else
        bar:GetStatusBarTexture():SetAtlas(Style.BAR_ATLAS)
    end
end

local function applyBackground(bar, key)
    local bg = bar.Background
    if not bg then return end
    local path = texturePath(Style.Get(key, "backgroundTexture"))
    if path then
        bg:SetTexture(path)
    else
        bg:SetAtlas(Style.BACKGROUND_ATLAS)
    end
    local r, g, b = addon.ResolveColorRGBA(Style.Get(key, "backgroundColorMode"),
        Style.Get(key, "backgroundTint"), {})
    bg:SetVertexColor(r, g, b, clamp(Style.Get(key, "backgroundOpacity"), Style.BACKGROUND_OPACITY) / 100)
end

--- The power bar's color: a custom tint, else the power color through the
--- unit frames' feed, which also paints the dead and offline greys. Called
--- again from display.lua when the feed's state changes.
function Style.ApplyPowerColor()
    local f = Style.Frame()
    if not f then return end
    local bar = Style.Bar(f, "power")
    local r, g, b, _, source = addon.ResolveColorRGBA(Style.Get("power", "foregroundColorMode"),
        Style.Get("power", "foregroundTint"), { barKind = "power", unitForPower = "player" })
    local Values = addon.UnitFrames and addon.UnitFrames.Values
    if source ~= "custom" and Values and PRD.inst then
        Values.ApplyPowerColor(PRD.inst)
    else
        bar:SetStatusBarColor(r, g, b)
    end
end

--- Textures, colors and the two hide switches of both bars.
function Style.ApplyBars()
    local f = Style.Frame()
    if not f then return end
    local inst = PRD.inst

    local health = Style.Bar(f, "health")
    applyFill(health, "health")
    local r, g, b = addon.ResolveColorRGBA(Style.Get("health", "foregroundColorMode"),
        Style.Get("health", "foregroundTint"), { barKind = "health", unitForClass = "player" })
    health:SetStatusBarColor(r, g, b)
    -- The feed restores this color on every tick (values.lua, ApplyHealth).
    if inst then inst.spec.Bars.health.color = { r, g, b } end
    applyBackground(health, "health")

    applyFill(Style.Bar(f, "power"), "power")
    Style.ApplyPowerColor()
    applyBackground(Style.Bar(f, "power"), "power")

    for _, key in ipairs(Style.BARS) do
        local bar = Style.Bar(f, key)
        local textureOnly = Style.Get(key, "hideTextureOnly") == true
        -- The texture's own alpha: the vertex alpha is what the feed rewrites.
        bar:GetStatusBarTexture():SetAlpha(textureOnly and 0 or 1)
        if bar.Background then
            bar.Background:SetAlpha((textureOnly or Style.Get(key, "hideBackground") == true) and 0 or 1)
        end
    end
end

--------------------------------------------------------------------------------
-- Borders
--------------------------------------------------------------------------------
-- The shared bar border module anchors its holder to the frame it is told;
-- a holder anchored to a bar fed a secret inherits secret anchors and hides
-- itself, so the anchor target is the bar's plain container, which the bar
-- fills on both anchors. The square style is core/borders.lua's edges on the
-- bar itself, whose reads are guarded.

local function applyBorder(f, key)
    local bar = Style.Bar(f, key)
    local BarBorders, Borders = addon.BarBorders, addon.Borders
    if BarBorders and BarBorders.ClearBarFrame then BarBorders.ClearBarFrame(bar) end
    if Borders and Borders.HideAll then Borders.HideAll(bar) end

    local styleKey = Style.Get(key, "borderStyle")
    if Style.Get(key, "hideTextureOnly") == true then styleKey = "none" end
    if styleKey == nil or styleKey == "none" then return end

    local tintEnabled = Style.Get(key, "borderTintEnabled") == true
    local tint = Style.Get(key, "borderTintColor")
    if type(tint) ~= "table" then tint = { 1, 1, 1, 1 } end
    local thickness = clamp(Style.Get(key, "borderThickness"), Style.THICKNESS)

    if styleKey == "square" then
        if Borders and Borders.ApplySquare then
            Borders.ApplySquare(bar, {
                size = thickness,
                color = tintEnabled and tint or { 0, 0, 0, 1 },
                layer = "OVERLAY", layerSublevel = 3,
                expandX = 1, expandY = (thickness <= 1) and 0 or 1,
            })
        end
        return
    end

    if BarBorders and BarBorders.ApplyToBarFrame then
        BarBorders.ApplyToBarFrame(bar, styleKey, {
            color = tintEnabled and tint or { 1, 1, 1, 1 },
            thickness = thickness,
            levelOffset = 1,
            anchorTarget = Style.Container(f, key),
        })
    end
end

function Style.ApplyBorders()
    local f = Style.Frame()
    if not f then return end
    for _, key in ipairs(Style.BARS) do applyBorder(f, key) end
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------
-- Each bar's RightText, the value. Blizzard's XML anchors it RIGHT at -5 and
-- the LeftText LEFT at 5; the alignment setting moves the one string between
-- those points.

local ALIGN = {
    LEFT = { "LEFT", 5 },
    CENTER = { "CENTER", 0 },
    RIGHT = { "RIGHT", -5 },
}

local function applyTextStyle(bar, fs, key)
    local face, size, flags = Style.FontObjectFont()
    local storedFace = Style.Get(key, "text", "value", "fontFace")
    if storedFace then face = addon.ResolveFontFace(storedFace) or face end
    size = tonumber(Style.Get(key, "text", "value", "size")) or size
    local style = Style.Get(key, "text", "value", "style")
    if face and style then
        addon.ApplyFontStyle(fs, face, size, style)
    elseif face then
        fs:SetFont(face, size, flags)
    end

    local r, g, b, a = addon.ResolveColorRGBA(Style.Get(key, "text", "value", "colorMode"),
        Style.Get(key, "text", "value", "color"), { unitForClass = "player" })
    fs:SetTextColor(r, g, b, a)

    local align = ALIGN[Style.Get(key, "text", "value", "alignment")] or ALIGN.RIGHT
    fs:SetJustifyH(align[1])
    fs:ClearAllPoints()
    fs:SetPoint(align[1], bar, align[1], align[2], 0)
end

--- The hover strings' alpha, from the frame's OnEnter and OnLeave.
function Style.ApplyHover(hovering)
    local f = Style.Frame()
    if not f then return end
    for _, key in ipairs(Style.BARS) do
        if Style.TextShow(key) == "hover" then
            Style.Bar(f, key).RightText:SetAlpha(hovering and 1 or 0)
        end
    end
end

--- Font, color, alignment and show mode of both value texts. A string set
--- to Never leaves the feed's table (values.lua feeds only the strings it
--- finds there) and is cleared, which releases the secret it held. Mouse
--- motion is on only while a string is On Hover; clicks never.
function Style.ApplyText()
    local f = Style.Frame()
    if not f then return end
    local inst = PRD.inst
    local hoverAny = false
    for _, key in ipairs(Style.BARS) do
        local bar = Style.Bar(f, key)
        local fs = bar.RightText
        applyTextStyle(bar, fs, key)
        local mode = Style.TextShow(key)
        if mode == "never" then
            fs:ClearText()
            fs:Hide()
            if inst then inst[key .. "Text"] = nil end
        else
            fs:Show()
            fs:SetAlpha((mode == "hover" and not PRD.hovering) and 0 or 1)
            if inst then inst[key .. "Text"] = fs end
            if mode == "hover" then hoverAny = true end
        end
    end
    pcall(f.SetMouseMotionEnabled, f, hoverAny)
end

--------------------------------------------------------------------------------
-- Heal prediction
--------------------------------------------------------------------------------
-- The Classic unit frames' segments on their host seam. Without the seam
-- (the file predates it, or the client has no calculator) nothing draws.

function Style.ApplyHealPrediction()
    local inst = PRD.inst
    local HP = addon.UnitFrames and addon.UnitFrames.HealPrediction
    if not (inst and HP and HP.HostSeam) then return end
    HP.Apply(inst)
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

--- Every setting, in the order the frame takes them, then the feeds and the
--- shown state, then the dynamic state back on top. The page's apply, the
--- Edit Mode dialog's and the profile engine's.
function Style.Apply()
    if not Style.Frame() then return end
    Style.ApplyLayout()
    Style.ApplyScale()
    Style.ApplyOpacity()
    Style.ApplyBars()
    Style.ApplyBorders()
    Style.ApplyText()
    Style.ApplyHealPrediction()
    if PRD.Display then
        PRD.Display.Refresh()
        PRD.Display.UpdateShownState()
    end
    if PRD.Dynamic then PRD.Dynamic.Reassert() end
end

-- After a profile switch the frame re-reads the new profile. A resync pass
-- keeps the profile it had; re-landing the base there would cut short the
-- Dynamic Layouts tween that leaving Edit Mode starts.
addon.Profiles.RegisterApplyStep("camelotPersonalResourceDisplay", function(_, ctx)
    if ctx.initial or ctx.resync then return end
    Style.Apply()
end, 30)

--------------------------------------------------------------------------------
-- Edit Mode dialog
--------------------------------------------------------------------------------
-- The three of Blizzard's fifteen a player reaches for in Edit Mode; the rest
-- are page settings. Labels only: the dialog has no room for descriptions.

local function sliderSpec(label, range, key)
    return {
        kind = "slider", label = label,
        min = range.min, max = range.max, step = range.step, precision = 0,
        get = function() return clamp(Style.Get(key), range) end,
        set = function(v)
            DB.Set(Style.Path(key), clamp(v, range))
            Style.Apply()
        end,
    }
end

--- The mirror for the branded Edit Mode dialog. Returns a function, the
--- shape the positionable's brand.mirror takes.
function Style.EditModeMirror()
    return function()
        local Visibility = addon.Catalogs.Visibility
        return {
            {
                kind = "selector", label = "Visibility",
                values = Visibility.values, order = Visibility.order,
                get = Style.Visibility,
                set = function(v)
                    DB.Set(Style.Path("visibility"), v)
                    Style.Apply()
                end,
            },
            sliderSpec("Scale", Style.SCALE, "scale"),
            sliderSpec("Opacity", Style.OPACITY, "opacity"),
        }
    end
end

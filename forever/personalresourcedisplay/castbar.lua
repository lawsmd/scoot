--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/castbar.lua
-- The cast bar on the Personal Resource Display: the player's casts as a
-- third bar in the display's own art, hanging off the frame's top or bottom
-- edge, on the cast bar engine Camelot already runs
-- (core/components/castbarz/engine.lua; the host and the painter are
-- forever/castbars/). Nothing here follows a cast. This file is one more row
-- in CBZ.BARS, a look and a painter for it, and the seams a hosted row needs.
--
-- Hosted (engine.lua, "hosted"): the bar is a child of
-- CamelotPersonalResourceDisplay and is placed here rather than by a
-- positionable, so it inherits the display's scale, opacity, shown state and
-- Dynamic Layouts state, and the display's Edit Mode box grows over it. It
-- stands in for the Player bar: while it is on, the host reports the Player
-- unit off and the engine's suppression keeps PlayerCastingBarFrame parked
-- under this row's claim. The display's Visibility therefore governs every
-- cast bar the player has: with Only in Combat, a cast out of combat draws
-- no bar.
--
-- The bar is fixed. The fill is the display's bar atlas tinted with the
-- Classic cast palette (forever/castbars/art.lua, Art.Colors), the frame its
-- background atlas, the pip Blizzard's own for this bar art. The health
-- bar's Border setting dresses it too (style.lua, ApplyBorderTo). Its two
-- strings are the page's, on the Cast Bar page's Text tabs with the bars'
-- text controls: the spell name across the bar, and the shared cast time
-- readout inside it, each starting on the TextStatusBarText font object as
-- the two bars' texts do. The row's settings function below answers the
-- engine's keys for both from castBar.spellName.* and castBar.timer.*.
-- Anything more is the Cast Bars page's, on the Player bar.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PersonalResourceDisplay
local Style = PRD.Style
local CBZ = addon.CastBarZ
local Art = addon.CastBarArt
local Util = CBZ and CBZ.PainterUtil

local CastBar = {}
PRD.CastBar = CastBar

-- Without the engine and the Classic painter (a TOC that lists this file and
-- not the cast bars) the display draws no cast bar and errors nowhere.
if not (CBZ and Art and Util and CBZ.Painters and CBZ.Painters.CLASSIC) then
    PRD.CastBar = nil
    return
end

local BAR_KEY = "ResourceDisplay"
local UNIT_KEY = "ResourceDisplay"

-- The texts' inset from the bar's ends (frames.xml, LEFT 5 and RIGHT -5),
-- and the room the readout takes from the name while it is on.
local TEXT_INSET = 5
local READOUT_RESERVE = 36

-- The background atlas past the bar, above and below (frames.xml).
local BACKGROUND_ABOVE = 3
local BACKGROUND_BELOW = 7

--------------------------------------------------------------------------------
-- The look
--------------------------------------------------------------------------------
-- The display's own art (frames.xml, CamelotPersonalResourceStatusBar): the
-- fill atlas, the background atlas on the anchors Blizzard gives it, the
-- font object of the two bars' texts. The pip is the one Blizzard draws on
-- this bar art in the Cooldown Manager (Blizzard_CooldownViewer/
-- CooldownViewer.xml:271, anchored CENTER to the fill's RIGHT at (0, -1),
-- CooldownViewer.lua:1495), at its atlas size. `width` and `height` are the
-- XML bar's; the row's config hands the painter the display's live width and
-- the Bar Height setting.

Art.Looks.RESOURCE = {
    key = "RESOURCE", recolor = false,
    width = Style.DEFAULT_BAR_WIDTH, height = Style.HEIGHT.default,

    fillAtlas = Style.BAR_ATLAS,
    background = { layer = "BACKGROUND", atlas = Style.BACKGROUND_ATLAS,
                   edges = { -2, BACKGROUND_ABOVE, 6, -BACKGROUND_BELOW } },
    spark = { layer = "OVERLAY", sublevel = 2, atlas = "UI-HUD-CoolDownManager-Bar-Pip", y = -1 },
    -- Part of the art: the Cast Bars page's Show Spark does not reach it
    -- (painter.lua, _RefreshSparkVisibility).
    sparkAlways = true,

    -- The font object is the stock face; the Spell Name tab's values reach
    -- the string through the row's settings (painter.lua, ApplyFont). The
    -- box runs the bar's width less the insets at the bar's height; layout
    -- re-anchors it and trims it while the readout is on.
    text = { layer = "OVERLAY", sublevel = 1, fontObject = Style.FONT_OBJECT,
             w = Style.DEFAULT_BAR_WIDTH - 2 * TEXT_INSET, h = Style.HEIGHT.default,
             point = "LEFT", x = TEXT_INSET, y = 0 },
}
Art.LOOK_FOR_STYLE.resource = "RESOURCE"

--------------------------------------------------------------------------------
-- The painter
--------------------------------------------------------------------------------
-- The Classic painter's cast states (the start color, the locked gray, the
-- red failure, the reset) on the display's art, inherited through __index.
-- What differs is the art itself, the fill texture, and a finish with no
-- flash: the Classic flash is a border-shaped file, and this bar has no
-- border of that shape.

local Classic = CBZ.Painters.CLASSIC
local Resource = setmetatable({}, { __index = Classic })
CBZ.Painters.RESOURCE = Resource

function Resource.build(bar, set, look)
    local bg = set.backFrame:CreateTexture(nil, look.background.layer)
    bg:SetAtlas(look.background.atlas)
    Util.AnchorEdges(bg, bar, look.background.edges)
    set.background = bg

    local art = set.artFrame
    local spark = art:CreateTexture(nil, look.spark.layer, nil, look.spark.sublevel)
    spark:SetAtlas(look.spark.atlas, true)
    Util.AnchorSpark(spark, bar.progressBar, look.spark.y)
    set.spark = spark

    set.text = Util.BuildText(art, bar, look.text)
end

-- The pip keeps its atlas size. The name's box is the bar less the insets,
-- less the readout's room at the end the readout sits at while it is on;
-- the Spell Name tab's alignment justifies the name inside that box, and
-- its color is written here, since no cast state of the Classic painter
-- touches the name's color. The font is the engine's ApplyFont, after this.
function Resource.layout(bar, set, _look, barW, barH)
    local text = set.text
    local readout = CBZ._IsCastTimeEnabled(bar.unitKey) and Style.CastBarTextAlignment("timer") or nil
    local reserve = (readout == "LEFT" or readout == "RIGHT") and READOUT_RESERVE or 0
    text:SetSize(barW - 2 * TEXT_INSET - reserve, barH)
    text:ClearAllPoints()
    if readout == "LEFT" then
        text:SetPoint("RIGHT", bar, "RIGHT", -TEXT_INSET, 0)
    else
        text:SetPoint("LEFT", bar, "LEFT", TEXT_INSET, 0)
    end
    text:SetJustifyH(Style.CastBarTextAlignment("spellName"))
    text:SetTextColor(Style.CastBarTextColor("spellName"))
end

function Resource.setFill(bar, set)
    bar.progressBar:SetStatusBarTexture(set.look.fillAtlas)
    Util.SetFill(bar, bar.startColor or Art.Colors.cast)
end

-- A finished cast goes green and fades under the engine's hold; no flash.
function Resource.queueFinish(bar)
    Util.SetFill(bar, Art.Colors.finished)
end

function Resource.stopFinish() end

-- No Frame Color: false rather than nil, or __index finds Classic's and
-- dresses a border this look does not build.
Resource.applyFrameColor = false

--------------------------------------------------------------------------------
-- The row
--------------------------------------------------------------------------------

--- The cast bar's switch, live: the display's session switch, the setting,
--- and the frame. Never the display's build: the engine's world-entry
--- reconcile runs before the display builds, and the frame exists from the
--- XML by then.
function CastBar.IsOn()
    return PRD.IsEnabled() and Style.CastBarOn() and Style.Frame() ~= nil
end

local function height()
    return Style.Clamp(Style.Get("castBar", "height"), Style.HEIGHT)
end

-- The timer's alignment is its place: the engine's three inside positions
-- (casttime.lua, CBZ.CAST_TIME_POSITIONS).
local TIMER_POSITION = { LEFT = "insideLeft", CENTER = "insideCenter", RIGHT = "insideRight" }

-- The config the engine reads as a table (painter.lua, LayoutBar;
-- casttime.lua). The width is the display's, the height the Bar Height
-- setting; no scale, since the display's reaches the bar as its child and a
-- value here would scale it twice. Writes are dropped: nothing on this row
-- is the engine's to store.
local config = setmetatable({}, {
    __index = function(_, key)
        if key == "frameStyle" then return "resource" end
        if key == "barWidth" then return Style.BarWidthPixels() end
        if key == "barHeight" then return height() end
        if key == "positionMode" then return "free" end
        if key == "castTimeSide" then return TIMER_POSITION[Style.CastBarTextAlignment("timer")] end
        return nil
    end,
    __newindex = function() end,
})

-- The font object's face as a font key, what a string with no face stored
-- draws in (ResolveFontFace lands there on nil too). Each string's face is
-- its own: the readout never follows the name's, so the Timer Text tab's
-- Font row always shows the face in use.
local STOCK_FACE = "FRIZQT__"

local function textSetting(slot, field)
    return Style.Get("castBar", slot, field)
end

-- The settings the engine reads by key: painter.lua's ApplyFont for the name
-- (fontFace, fontSize, fontStyle), casttime.lua for the readout (the
-- castTime* keys; castTimeStyle is the readout's own style, which the two
-- Cast Bars pages leave shared with the name). A size or style left unset is
-- the font object's, so the name always takes ApplyFont's styled path. The
-- gap is the texts' inset and the vertical offset nothing: the tabs carry
-- no offsets, as the bars' tabs do not.
local function settings(key)
    local _, stockSize, stockFlags = Style.FontObjectFont()
    if key == "fontFace" then return textSetting("spellName", "fontFace") or STOCK_FACE end
    if key == "fontSize" then return tonumber(textSetting("spellName", "size")) or stockSize end
    if key == "fontStyle" then return textSetting("spellName", "style") or stockFlags end
    if key == "castTime" then return Style.Get("castBar", "castTime") == true end
    if key == "castTimeReadout" then return Style.CastBarReadout() end
    if key == "castTimeFont" then return textSetting("timer", "fontFace") or STOCK_FACE end
    if key == "castTimeSize" then return tonumber(textSetting("timer", "size")) or stockSize end
    if key == "castTimeStyle" then return textSetting("timer", "style") or stockFlags end
    if key == "castTimeColor" then return { Style.CastBarTextColor("timer") } end
    if key == "castTimeGap" then return TEXT_INSET end
    if key == "castTimeOffsetY" then return 0 end
    if key == "showSpark" then return true end
    return nil
end

CBZ.BARS[#CBZ.BARS + 1] = {
    barKey = BAR_KEY, unitKey = UNIT_KEY, token = "player",
    frameName = "CamelotResourceDisplayCastBar",
    hosted = true, standsInFor = "Player",
    parent = Style.Frame,
    enabled = CastBar.IsOn,
    config = function() return config end,
    settings = settings,
}
CBZ.UNIT_LABELS[UNIT_KEY] = "Resource Display"
-- The player's own casts: never the uninterruptible gray (events.lua).
CBZ.OWN_CAST_UNITS[UNIT_KEY] = true

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------
-- Off the frame's edge rather than in its height: the health and power bars
-- never move when the cast bar is switched or flipped, and the mixin stays
-- Blizzard's transcription. The gap is the frame's own bar padding, the
-- spacing between the two bars.

local function gap(frame)
    return frame.GetBarPadding and frame:GetBarPadding() or 4
end

-- What hangs under the frame before the cast bar: the combo point row, while
-- it shows (combopoints.lua).
local function comboExtent()
    return PRD.Combo and PRD.Combo.Extent() or 0
end

--- The engine's seam for a hosted row (castbarz/editmode.lua,
--- _RestorePosition), after the painter has sized the bar. Below, it hangs
--- under the combo point row while that shows.
function CBZ._ApplyHostedPosition(bar)
    local frame = Style.Frame()
    if not frame then return end
    bar:ClearAllPoints()
    if Style.CastBarPosition() == "below" then
        bar:SetPoint("TOP", frame, "BOTTOM", 0, -(comboExtent() + gap(frame)))
    else
        bar:SetPoint("BOTTOM", frame, "TOP", 0, gap(frame))
    end
end

--- The engine's bar for this row, once built.
function CastBar.Bar()
    return CBZ._bars and CBZ._bars[BAR_KEY]
end

--- The display's selection box reach, grown over the cast bar on the side it
--- hangs: the gap, the bar, and its background's overhang past it.
function CastBar.Reach(base)
    if not CastBar.IsOn() then return base end
    local extent = gap(Style.Frame()) + height()
    local reach = { left = base.left, right = base.right, top = base.top, bottom = base.bottom }
    if Style.CastBarPosition() == "below" then
        reach.bottom = comboExtent() + extent + BACKGROUND_BELOW
    else
        reach.top = extent + BACKGROUND_ABOVE
    end
    return reach
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

--- From Style.Apply: the engine's reconcile builds the bar the first time
--- the switch is on, lays it out and places it on every pass, hides it while
--- off, and keeps Blizzard's bar parked; then the health bar's border on it,
--- anchored to the bar's own frame, a plain Frame never fed a value.
function CastBar.Apply()
    if not CBZ._Reconcile then return end
    CBZ._Reconcile()
    local bar = CastBar.Bar()
    if bar then
        Style.ApplyBorderTo(bar.progressBar, bar, "health", not CastBar.IsOn())
    end
end

--- Lines for /camelot prd.
function CastBar.Describe(push)
    local bar = CastBar.Bar()
    push("  cast bar: %s, %s the bars, height %s; built %s, shown %s, casting %s; Player bar standing down: %s",
        Style.CastBarOn() and "on" or "off", Style.CastBarPosition(),
        tostring(Style.Get("castBar", "height")),
        tostring(bar ~= nil), tostring(bar and bar:IsShown() or false), tostring(bar and bar.casting or false),
        tostring(CastBar.IsOn()))
    for _, slot in ipairs(Style.CAST_BAR_TEXTS) do
        push("    %s: face %s, size %s, style %s, color %s, %s%s",
            slot, tostring(textSetting(slot, "fontFace") or STOCK_FACE),
            tostring(settings(slot == "timer" and "castTimeSize" or "fontSize")),
            tostring(settings(slot == "timer" and "castTimeStyle" or "fontStyle")),
            tostring(textSetting(slot, "colorMode")), Style.CastBarTextAlignment(slot),
            slot == "timer" and string.format("; shown %s, readout %s",
                tostring(Style.Get("castBar", "castTime") == true), Style.CastBarReadout()) or "")
    end
end

--------------------------------------------------------------------------------
-- forever/unitframes/text.lua
-- The name and level text settings of the unit frames, one set per style of
-- each frame, and what applies them: each string's face, size and style, its
-- box and offset, its colour, and the leather backdrops behind it. The style
-- itself, and the paths every unit frame setting takes, are here too, since
-- this is the first unit frame file.
--
-- First of the unit frame files, and on both clients. Retail loads Camelot.toc
-- for the settings panel and excludes the HUD, and the page (page.lua) has to
-- draw its controls there so a stored value can be checked across a reload
-- while the beta keeps none. So nothing here reads a HUD table at file scope;
-- the apply functions run only against a built frame.
--
-- The defaults are the look of the first screenshots, 19 September: a Deep
-- Shadow thick outline on the name and the level, the bundled bold of the
-- client's own face on the level (the name went back to the regular face
-- after the first test), the class colour on a player's name, and the Legacy
-- pane's leather behind the name and inside the level ring. Vanilla's own look
-- is what a control moved to its other end draws, and each default below says
-- what that is.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local DB = addon.DB

local Text = {}
UF.Text = Text

-- Build and reconcile order. The target comes before the frame that reads its
-- target.
UF.ORDER = { "player", "target", "focus", "targettarget", "pet" }

-- unit key -> settings page key (forever/menu.lua)
Text.NAV_KEYS = {
    player = "ufPlayer",
    target = "ufTarget",
    focus = "ufFocus",
    targettarget = "ufTargetOfTarget",
    pet = "ufPet",
}

-- What each frame has for its page to draw: a level string, a leather
-- backdrop, the reaction strip, a name box with a width, the Forever surname
-- after the first name (values.lua, DisplayName), and a name shrunk to fit its
-- box (values.lua, FitName). Static rather than read off the art spec, which
-- retail does not load; the specs agree.
Text.SURFACE = {
    player       = { level = true, backdrop = true, width = true, surname = true, fit = true },
    target       = { level = true, backdrop = true, strip = true, width = true, surname = true, fit = true },
    focus        = { level = true, backdrop = true, strip = true, width = true, surname = true, fit = true },
    targettarget = { backdrop = true, width = true, surname = true, fit = true },
    pet          = {},
}

-- The font objects' own yellow, NORMAL_FONT_COLOR.
local GOLD = { 1.0, 0.82, 0, 1 }

-- The leather, as a percentage. Vanilla's black fill behind the name is 0.5;
-- this started at 0.85, went to 0.75 after the first look, and to 0.6 on 25
-- September when the leather read as an opaque black slab.
Text.BACKDROP_OPACITY = 60
-- The tint of the additive copy over each backdrop (art.lua, "Backdrops"),
-- drawn at the backdrop's own alpha. White doubles the leather; less blue and
-- green warms it toward the Legacy pane's brown.
Text.BACKDROP_LIFT = { 1, 0.85, 0.65 }
-- The target's reaction strip, drawn well under vanilla's opaque gray so the
-- black fill shows through it: at 0.75 the blue on a player target read as a
-- slab (seen 19 September).
Text.STRIP_OPACITY = 45
-- The smallest point size a long name shrinks to before the engine cuts it.
Text.FIT_MIN = 7

--------------------------------------------------------------------------------
-- Paths and defaults
--------------------------------------------------------------------------------
-- Every setting a unit frame page writes belongs to one style of the frame:
-- the Camelot style's keys sit at unitFrames.<key>.<setting>, where they
-- always were, the Classic style's at unitFrames.<key>.classic.<setting>,
-- and the Modern style's at unitFrames.<key>.modern.<setting>, so a value
-- set on one style never reaches another, and each style's defaults are its
-- own. Classic is the Camelot frame with Blizzard's values: its defaults are
-- vanilla's wherever Camelot's depart. The keys the frame keeps whatever shape it draws
-- take no prefix: the style itself, the enable switch, the scale, the attach
-- to another frame with its two offsets, which belong with the position
-- (settings.lua, "Attach"), and the target of target's hide while the target
-- is the player (settings.lua, "Hide when targeting yourself").

UF.STYLES = { camelot = "Camelot", classic = "Classic", modern = "Modern" }
UF.STYLE_ORDER = { "camelot", "classic", "modern" }

Text.STYLE_PREFIX = { camelot = "", classic = "classic.", modern = "modern." }
Text.SHARED = { style = true, enabled = true, scale = true,
                attach = true, attachX = true, attachY = true,
                hideWhenSelf = true }

--- The dotted path of one style's setting: Text.StylePath("player",
--- "modern", "name", "size").
function Text.StylePath(key, style, ...)
    local first = ...
    local prefix = Text.SHARED[first] and "" or Text.STYLE_PREFIX[style] or ""
    return "unitFrames." .. key .. "." .. prefix .. table.concat({ ... }, ".")
end

--- Which style a frame draws, from its stored setting: "camelot", "classic"
--- or "modern", anything else read as camelot.
function UF.StyleOf(key)
    local style = DB.Get(Text.StylePath(key, "camelot", "style"))
    return UF.STYLES[style] and style or "camelot"
end

--- The dotted path of a unit frame setting for the style the frame is on:
--- Text.Path("player", "name", "size"), or Text.Path("target", "stripOpacity").
function Text.Path(key, ...)
    return Text.StylePath(key, UF.StyleOf(key), ...)
end

function Text.Get(key, ...)
    return DB.Get(Text.Path(key, ...))
end

-- The Modern style's name box per frame: the box the client's own frame
-- gives the name, read off the Forever build. The specs under modern/ carry
-- the same numbers; they are here because this file registers the defaults
-- and loads where no spec does.
Text.MODERN_NAME = {
    player = { width = 116, alignment = "CENTER" },
    target = { width = 117, alignment = "CENTER" },
    focus = { width = 117, alignment = "CENTER" },
    targettarget = { width = 68, alignment = "CENTER" },
    pet = { width = 68, alignment = "CENTER" },
}

do
    local map = {}
    -- A nil face, size or style reads the font object as it is, and the page
    -- shows that number.
    local function registerString(style, key, slot, colorMode, fontFace, fontStyle)
        local p = Text.StylePath(key, style, slot) .. "."
        map[p .. "hidden"] = false
        map[p .. "fontFace"] = fontFace
        map[p .. "style"] = fontStyle
        map[p .. "colorMode"] = colorMode
        map[p .. "color"] = GOLD
        map[p .. "offsetX"] = 0
        map[p .. "offsetY"] = 0
    end
    for _, key in ipairs(UF.ORDER) do
        local function set(style, value, ...) map[Text.StylePath(key, style, ...)] = value end

        -- Camelot: the first screenshots' look (the file header). The name's
        -- face is the font object's own, vanilla's; the level takes the
        -- bold. Vanilla's style is the font object's own shadow, and vanilla
        -- colours no name: "default" is the gold. The target's level keeps
        -- vanilla's difficulty colour; the player's has no such read and
        -- wears the class colour beside the name.
        registerString("camelot", key, "name", "class", nil, "DEEPSHADOWTHICKOUTLINE")
        registerString("camelot", key, "level", key == "player" and "class" or "default",
            "FRIZQUAD_BOLD", "DEEPSHADOWTHICKOUTLINE")
        -- The name box as the XML has it: 100 wide, centred, left on the small frame.
        set("camelot", key == "targettarget" and "LEFT" or "CENTER", "name", "alignment")
        set("camelot", 100, "name", "width")
        -- Vanilla draws nothing where the leather goes, and its strip is opaque.
        set("camelot", true, "backdrop", "enabled")
        set("camelot", Text.BACKDROP_OPACITY, "backdrop", "opacity")
        set("camelot", Text.STRIP_OPACITY, "stripOpacity")

        -- Classic: the same frame as vanilla draws it. The font objects
        -- answer for the face, the size and the shadow, "default" is the gold
        -- and the target's difficulty colour, the box is the XML's, no
        -- leather, and the strip opaque.
        registerString("classic", key, "name", "default", nil, nil)
        registerString("classic", key, "level", "default", nil, nil)
        set("classic", key == "targettarget" and "LEFT" or "CENTER", "name", "alignment")
        set("classic", 100, "name", "width")
        set("classic", false, "backdrop", "enabled")
        set("classic", Text.BACKDROP_OPACITY, "backdrop", "opacity")
        set("classic", 100, "stripOpacity")

        -- Modern: the strings as the client's own frame draws them, so the
        -- font objects answer for the face, the size and the style, and
        -- "default" is each one's own colour. The name box is the client's.
        registerString("modern", key, "name", "default", nil, nil)
        registerString("modern", key, "level", "default", nil, nil)
        set("modern", Text.MODERN_NAME[key].alignment, "name", "alignment")
        set("modern", Text.MODERN_NAME[key].width, "name", "width")

        for _, style in ipairs(UF.STYLE_ORDER) do
            -- Read only where the surface has `surname`. Vanilla had no surnames.
            set(style, false, "name", "hideSurname")
            -- Read only where the surface has `fit`: Camelot's shrink, on but
            -- in the Classic style; Blizzard truncates a long name at the
            -- font's size.
            set(style, style ~= "classic", "name", "fit")
            set(style, Text.FIT_MIN, "name", "fitMin")
        end
    end
    DB.RegisterDefaults(map)

    -- Blizzard Default: each preset start draws a style of its own
    -- (settings.lua, "Style"), Classic or Modern, so no key here has a
    -- preset value. The Modern keys depart from the client on the fit alone.
    local stock = {}
    for _, key in ipairs(UF.ORDER) do
        stock[Text.StylePath(key, "modern", "name", "fit")] = false
    end
    DB.RegisterStock(stock)
end

--------------------------------------------------------------------------------
-- Colour
--------------------------------------------------------------------------------

--- The colour a string takes for its stored mode. dr, dg, db is the caller's
--- own default: the gold for a name, the difficulty colour for the target's
--- level. unit stands in for inst.unit when the Edit Mode stand-in paints,
--- which wears the player's own class on every frame.
function Text.Color(inst, slot, dr, dg, db, unit)
    local colorMode = Text.Get(inst.key, slot, "colorMode")
    -- Kept off addon.ResolveColorRGBA: class on a non-player is the gold, which classMiss cannot express.
    if colorMode == "class" then
        return UF.Values.IdentityColor(unit or inst.unit)
    end
    local r, g, b = addon.ResolveColorRGBA(colorMode, Text.Get(inst.key, slot, "color"),
        { fbR = dr, fbG = dg, fbB = db, fbA = 1 })
    return r, g, b
end

--- The colour a string's "default" mode draws: the spec's own where the slot
--- names one (the Modern level is white in its circle), else the caller's,
--- the gold for a name.
function Text.DefaultColor(inst, slot, r, g, b)
    local def = inst.spec and inst.spec.Text and inst.spec.Text[slot]
    local c = def and def.defaultColor
    if c then return c[1], c[2], c[3] end
    return r, g, b
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

-- The font object each string is built on (the art specs), which a nil
-- stored face or size falls back to. addon.ResolveFontFace turns a nil key
-- into the stock face, and GameNormalNumberFont is not that face.
local function fontObjectFont(def)
    local fontObject = _G[def.font]
    if fontObject then return fontObject:GetFont() end
end

--- The font a string is drawn in from its settings: face path, point size,
--- the font object's flags, and the style key. The size is the name fit's
--- ceiling (values.lua, FitName).
function Text.ResolveFont(inst, slot)
    local def = inst.spec.Text[slot]
    local face, size, flags = fontObjectFont(def)
    local storedFace = Text.Get(inst.key, slot, "fontFace")
    if storedFace then face = addon.ResolveFontFace(storedFace) end
    size = tonumber(Text.Get(inst.key, slot, "size")) or size
    return face, size, flags, Text.Get(inst.key, slot, "style")
end

--- Whether a frame's name is shrunk to fit its box.
function Text.FitsName(key)
    return Text.SURFACE[key].fit and Text.Get(key, "name", "fit") ~= false
end

--- The name box's width: the style's own setting, whose default is the
--- shape's box (100 on the Classic frames, the client's on the Modern ones,
--- Text.MODERN_NAME), with the spec's box behind it.
function Text.NameWidth(inst)
    return tonumber(Text.Get(inst.key, "name", "width")) or inst.spec.Text.name.w
end

--- The name's alignment the same way, with the spec's justify behind it.
function Text.NameJustify(inst)
    return Text.Get(inst.key, "name", "alignment") or inst.spec.Text.name.justifyH or "CENTER"
end

--- Draw a string in its font at a given size.
function Text.ApplyFont(fs, face, size, flags, style)
    if face and style then
        addon.ApplyFontStyle(fs, face, size, style)
    elseif face then
        fs:SetFont(face, size, flags)
    end
end

-- Geometry before the font: the Deep Shadow copy takes the string's box and
-- justify when the style is applied, and re-anchors to the string itself, so
-- a later move needs nothing. The colour is not written here; it belongs to
-- the paint, which runs after (values.lua, target.lua).
local function applyString(inst, slot, fs, def)
    local key = inst.key
    local host = inst.artFrame

    local justifyH = def.justifyH
    if def.w then
        if slot == "name" then
            fs:SetSize(Text.NameWidth(inst), def.h)
            justifyH = Text.NameJustify(inst)
        else
            fs:SetSize(Text.Get(key, slot, "width") or def.w, def.h)
            justifyH = Text.Get(key, slot, "alignment") or justifyH
        end
    end
    if justifyH then fs:SetJustifyH(justifyH) end
    if def.justifyV then fs:SetJustifyV(def.justifyV) end

    local nudge = def.nudge
    -- A string whose def names a region hangs off that region, as at build.
    local rel = def.relTo and inst.regions[def.relTo] or host
    fs:ClearAllPoints()
    fs:SetPoint(def.point, rel, def.relPoint or def.point,
        (def.x or 0) + (nudge and nudge.x or 0) + (tonumber(Text.Get(key, slot, "offsetX")) or 0),
        (def.y or 0) + (nudge and nudge.y or 0) + (tonumber(Text.Get(key, slot, "offsetY")) or 0))

    local face, size, flags, style = Text.ResolveFont(inst, slot)
    -- A fitted name keeps its fitted size until the refit the paint launches
    -- lands, so a settings change swaps the name once instead of twice.
    if slot == "name" and Text.FitsName(key) and inst.nameFitSize then
        size = inst.nameFitSize
    end
    Text.ApplyFont(fs, face, size, flags, style)

    local hidden = Text.Get(key, slot, "hidden") and true or false
    inst.textHidden[slot] = hidden
    fs:SetShown(not hidden)
end

--- Dress the name and the level from the database. The target's applyLevel
--- and the stand-in paint read inst.textHidden.level afterwards, because both
--- show or hide the level on their own.
function Text.ApplyStyle(inst)
    inst.textHidden = inst.textHidden or {}
    for _, slot in ipairs({ "name", "level" }) do
        local fs, def = inst.texts[slot], inst.spec.Text[slot]
        if fs and def then applyString(inst, slot, fs, def) end
    end
end

--------------------------------------------------------------------------------
-- Bar texts
--------------------------------------------------------------------------------
-- Each bar has a value string and a percent string, both built from the art
-- spec's healthValue or powerValue entry (frame.lua). Vanilla places them as
-- TextStatusBar does: a lone string centred on the XML's anchor, and with both
-- up (the BOTH display) the percent on the left and the value on the right, at
-- the XML's Left and Right anchors, which the spec carries as `sides`.
-- Placement reads the Show settings and not the mouse, so a string never moves
-- when the pointer arrives.

Text.BAR_TEXT_STRINGS = {
    health = { def = "healthValue", value = "healthValue", percent = "healthPercent" },
    power = { def = "powerValue", value = "powerValue", percent = "powerPercent" },
}

--- "always", "hover" or "never" for one of a bar's strings.
function Text.BarTextShow(key, bar, slot)
    local v = Text.Get(key, bar, "text", slot, "show")
    if v == "always" or v == "hover" then return v end
    return "never"
end

--- The colour a bar string takes: white by default, the class colour for a
--- player in class mode (white for anyone else), or the stored custom colour.
function Text.BarTextColor(inst, bar, slot, unit)
    local colorMode = Text.Get(inst.key, bar, "text", slot, "colorMode")
    -- Kept off addon.ResolveColorRGBA: class on a non-player is white, which classMiss cannot express.
    if colorMode == "class" then
        local ok, isPlayer = pcall(UnitIsPlayer, unit or inst.unit)
        if ok and not issecretvalue(isPlayer) and isPlayer == true then
            local r, g, b = addon.GetClassColorRGB(unit or inst.unit)
            if r then return r, g, b end
        end
        return 1, 1, 1
    end
    local r, g, b = addon.ResolveColorRGBA(colorMode, Text.Get(inst.key, bar, "text", slot, "color"),
        { fbR = 1, fbG = 1, fbB = 1, fbA = 1 })
    return r, g, b
end

local function applyBarString(inst, bar, slot, fs, anchor, def)
    local key = inst.key
    fs:ClearAllPoints()
    fs:SetPoint(anchor.point, inst.artFrame, anchor.relPoint or anchor.point,
        (anchor.x or 0) + (tonumber(Text.Get(key, bar, "text", slot, "offsetX")) or 0),
        (anchor.y or 0) + (tonumber(Text.Get(key, bar, "text", slot, "offsetY")) or 0))

    local face, size, flags = fontObjectFont(def)
    local storedFace = Text.Get(key, bar, "text", slot, "fontFace")
    if storedFace then face = addon.ResolveFontFace(storedFace) end
    size = tonumber(Text.Get(key, bar, "text", slot, "size")) or size
    Text.ApplyFont(fs, face, size, flags, Text.Get(key, bar, "text", slot, "style"))
end

--- Colour the frame's bar strings for the unit it shows. The paint calls
--- this, because a class colour changes with the target.
function Text.ApplyBarTextColors(inst)
    local unit = inst.previewStandIn and "player" or nil
    for bar, names in pairs(Text.BAR_TEXT_STRINGS) do
        for _, slot in ipairs({ "value", "percent" }) do
            local fs = inst.texts[names[slot]]
            if fs then fs:SetTextColor(Text.BarTextColor(inst, bar, slot, unit)) end
        end
    end
end

--- Place, dress and colour the frame's bar strings from the database. What
--- each one shows, and whether it is up, is values.lua's.
function Text.ApplyBarTexts(inst)
    for bar, names in pairs(Text.BAR_TEXT_STRINGS) do
        local def = inst.spec.Text[names.def]
        local valueFS, percentFS = inst.texts[names.value], inst.texts[names.percent]
        if def and valueFS and percentFS then
            local both = def.sides
                and Text.BarTextShow(inst.key, bar, "value") ~= "never"
                and Text.BarTextShow(inst.key, bar, "percent") ~= "never"
            applyBarString(inst, bar, "value", valueFS, both and def.sides.right or def, def)
            applyBarString(inst, bar, "percent", percentFS, both and def.sides.left or def, def)
        end
    end
    Text.ApplyBarTextColors(inst)
end

--- The leather behind the name and inside the level ring, where the frame
--- has either.
function Text.ApplyBackdrop(inst)
    local enabled = Text.Get(inst.key, "backdrop", "enabled") ~= false
    local alpha = (tonumber(Text.Get(inst.key, "backdrop", "opacity")) or Text.BACKDROP_OPACITY) / 100
    for _, name in ipairs({ "nameBackdrop", "levelBackdrop" }) do
        local tex = inst.regions[name]
        if tex then
            tex:SetShown(enabled)
            tex:SetVertexColor(1, 1, 1, alpha)
            if tex.lift then
                local lift = Text.BACKDROP_LIFT
                tex.lift:SetShown(enabled)
                tex.lift:SetVertexColor(lift[1], lift[2], lift[3], alpha)
            end
        end
    end
end

--- The alpha the target's reaction strip is drawn at (target.lua).
function Text.StripAlpha(inst)
    return (tonumber(Text.Get(inst.key, "stripOpacity")) or Text.STRIP_OPACITY) / 100
end

--- Re-dress one built frame, or every one, and repaint it so the colours
--- follow. The settings page's apply; a no-op where no frame is built.
function UF.RefreshText(key)
    if not UF.Frames then return end
    for k, inst in pairs(UF.Frames) do
        if key == nil or k == key then
            Text.ApplyStyle(inst)
            Text.ApplyBackdrop(inst)
            UF.Frame.PaintAll(inst)
        end
    end
end

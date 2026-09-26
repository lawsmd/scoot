--------------------------------------------------------------------------------
-- forever/unitframes/text.lua
-- The name and level text settings of the Classic unit frames, and what
-- applies them: each string's face, size and style, its box and offset, its
-- colour, and the leather backdrops behind it.
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

--- The dotted path of a unit frame text setting: Text.Path("player", "name",
--- "size"), or Text.Path("target", "stripOpacity").
function Text.Path(key, ...)
    return "unitFrames." .. key .. "." .. table.concat({ ... }, ".")
end

function Text.Get(key, ...)
    return DB.Get(Text.Path(key, ...))
end

do
    local map = {}
    local function registerString(key, slot, colorMode, fontFace)
        local p = Text.Path(key, slot) .. "."
        map[p .. "hidden"] = false
        -- Nil reads the font object's own face, which is vanilla's and the
        -- name's; the level takes the bold.
        map[p .. "fontFace"] = fontFace
        -- Vanilla's is the font object's own shadow.
        map[p .. "style"] = "DEEPSHADOWTHICKOUTLINE"
        -- No size: nil is the font object's own, and the page shows that number.
        -- Vanilla colours no name: "default" is the gold.
        map[p .. "colorMode"] = colorMode
        map[p .. "color"] = GOLD
        map[p .. "offsetX"] = 0
        map[p .. "offsetY"] = 0
    end
    for _, key in ipairs(UF.ORDER) do
        registerString(key, "name", "class", nil)
        -- The target's level keeps vanilla's difficulty colour; the player's
        -- has no such read and wears the class colour beside the name.
        registerString(key, "level", key == "player" and "class" or "default", "FRIZQUAD_BOLD")
        -- The name box as the XML has it: 100 wide, centred, left on the small frame.
        map[Text.Path(key, "name", "alignment")] = key == "targettarget" and "LEFT" or "CENTER"
        map[Text.Path(key, "name", "width")] = 100
        -- Read only where the surface has `surname`. Vanilla had no surnames.
        map[Text.Path(key, "name", "hideSurname")] = false
        -- Read only where the surface has `fit`. Vanilla truncates a long
        -- name at the font object's size.
        map[Text.Path(key, "name", "fit")] = true
        map[Text.Path(key, "name", "fitMin")] = Text.FIT_MIN
        -- Vanilla draws nothing where the leather goes.
        map[Text.Path(key, "backdrop", "enabled")] = true
        map[Text.Path(key, "backdrop", "opacity")] = Text.BACKDROP_OPACITY
        -- Vanilla's strip is opaque.
        map[Text.Path(key, "stripOpacity")] = Text.STRIP_OPACITY
    end
    DB.RegisterDefaults(map)
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

    if def.w then
        fs:SetSize(Text.Get(key, slot, "width") or def.w, def.h)
    end
    local justifyH = def.w and Text.Get(key, slot, "alignment") or def.justifyH
    if justifyH then fs:SetJustifyH(justifyH) end
    if def.justifyV then fs:SetJustifyV(def.justifyV) end

    local nudge = def.nudge
    fs:ClearAllPoints()
    fs:SetPoint(def.point, host, def.relPoint or def.point,
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

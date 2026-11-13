--------------------------------------------------------------------------------
-- forever/unitframes/values.lua
-- Feeding a bar Camelot owns from getters that return secrets.
--
-- The whole design rests on one property. StatusBar:SetMinMaxValues(min, max)
-- and StatusBar:SetValue(v) accept a secret argument: the value goes in as it
-- comes, the division happens in C, and the bar renders. Nothing in Lua ever
-- learns the number.
--
-- So the rule for everything below is: feed it, never read it back. No compare,
-- no arithmetic, no boolean test, and no GetValue afterwards. A getter whose
-- result is only ever handed to a sink needs no guard at all, which is why the
-- health and power paths carry none.
--
-- The cost is that a bar fed a secret is marked anchoring-secret, and a region
-- anchored to its fill texture inherits secret anchors. The frame art therefore
-- anchors to the frame and never to the fill. The Classic player frame has no
-- region that tracks the fill, so this costs nothing here; a spark would be the
-- first one that does.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Values = {}
addon.UnitFrames.Values = Values

local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax

-- For the reads that decide a colour: nil for a secret or a missing API, so an
-- unreadable state leaves the bar in its normal look.
local function plain(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

-- The health bar's colour from its setting (settings.lua). A caller with no
-- unit frame key (the personal resource display) sets inst.spec's colour
-- itself, and "default" is that colour too: vanilla's green on these frames.
-- Class colours a player only, as the name does; anyone else keeps the
-- default. Colour by value is the engine's curve over the health fraction
-- (core/percent.lua), evaluated at every update. unit stands in for inst.unit
-- when the Edit Mode stand-in paints.
function Values.HealthColor(inst, unit)
    unit = unit or inst.unit
    local c = inst.spec.Bars.health.color or { 0, 1, 0 }
    if not inst.key then return c[1], c[2], c[3] end
    local Settings = addon.UnitFrames.Settings
    local mode = Settings.Bar(inst.key, "health", "colorMode")
    if mode == "value" or mode == "valueDark" then
        local r, g, b = addon.Percent.HealthColor(unit, mode == "valueDark")
        if type(r) ~= "nil" then return r, g, b end
    elseif mode == "class" then
        if plain(UnitIsPlayer, unit) == true then
            local r, g, b = addon.GetClassColorRGB(unit)
            if r then return r, g, b end
        end
    elseif mode == "texture" or mode == "custom" then
        -- Kept off addon.ResolveColorRGBA for the two modes above: value is a curve and class skips non-players.
        local r, g, b = addon.ResolveColorRGBA(mode, Settings.Bar(inst.key, "health", "color"))
        return r, g, b
    end
    return c[1], c[2], c[3]
end

-- The bar's texture from its setting, and the Hide the Bar but not its Text
-- switch. On a Classic bar the texture goes onto the fill texture object
-- rather than through SetStatusBarTexture, so the heal prediction anchored
-- to that object (healprediction.lua) keeps its anchor. A Modern bar, whose
-- spec names an atlas, goes through SetStatusBarTexture for the file and
-- the atlas alike: the bar then crops within the member's rect, and it
-- keeps the one fill object, so the anchors and the mask on it stand. The
-- alpha is the texture's own: the vertex alpha is what the colour writes.
function Values.ApplyHealthStyle(inst)
    local bar = inst.healthBar
    if not (bar and inst.key) then return end
    local Settings = addon.UnitFrames.Settings
    local path
    local textureKey = Settings.Bar(inst.key, "health", "texture")
    if textureKey and textureKey ~= "default" and addon.Media and addon.Media.ResolveBarTexturePath then
        path = addon.Media.ResolveBarTexturePath(textureKey)
    end
    local spec = inst.spec.Bars.health
    local fill = bar:GetStatusBarTexture()
    if spec.atlas then
        local Art = addon.UnitFrames.Art
        local atlas = Art.ResolveAtlasName(spec.atlas)
        if path then
            bar:SetStatusBarTexture(path)
        elseif atlas then
            bar:SetStatusBarTexture(atlas)
        else
            bar:SetStatusBarTexture(spec.texture or Art.Paths.statusBar)
        end
        inst.healthFillIsAtlas = not path and atlas ~= nil or nil
    else
        fill:SetTexture(path or spec.texture)
    end
    fill:SetAlpha(Settings.Bar(inst.key, "health", "hideTextureOnly") == true and 0 or 1)
end

-- UnitFrameHealthBar_Update, with one departure. Vanilla holds a disconnected
-- unit's bar full and grey; here the bar takes the real value, since the bar
-- number beside it reads UnitHealth and a link-dead player being killed
-- showed a full bar over a falling number (the owner, 6 November 2026). The
-- grey is vanilla's 0.5, and the fill is desaturated under it: a Modern fill
-- is a green atlas drawn white, so the tint alone only darkens the green.
-- Both the colour and the desaturation go back on at every update, as
-- vanilla's colour does. Max first, then value. A bar whose range is still
-- (0, 1) when a large value arrives clamps to full for one frame, which
-- reads as a flash on login.
function Values.ApplyHealth(inst)
    local bar = inst.healthBar
    if not bar then return end
    local unit = inst.unit
    bar:SetMinMaxValues(0, UnitHealthMax(unit))
    bar:SetValue(UnitHealth(unit))
    local fill = bar:GetStatusBarTexture()
    if plain(UnitIsConnected, unit) == false then
        fill:SetDesaturated(true)
        bar:SetStatusBarColor(0.5, 0.5, 0.5)
    else
        fill:SetDesaturated(false)
        bar:SetStatusBarColor(Values.HealthColor(inst))
    end
end

-- "offline" for a disconnected unit, "dead" for the player dead or a ghost
-- and not feigning (UnitFrameManaBar_UpdateType), nil otherwise.
local function powerState(unit)
    if plain(UnitIsConnected, unit) == false then return "offline" end
    if unit == "player" and plain(UnitIsDeadOrGhost, unit) == true
        and plain(UnitIsFeignDeath, unit) ~= true then
        return "dead"
    end
    return nil
end

-- The fill's own alpha, the one writer of it: 0 under Hide the Bar but not
-- its Text, half for a dead player's atlas fill (ApplyPowerAtlas), else 1.
-- The vertex alpha belongs to the colour, as on the health bar.
local function powerFillAlpha(inst, dead)
    if inst.key and addon.UnitFrames.Settings.Bar(inst.key, "power", "hideTextureOnly") == true then
        return 0
    end
    return dead and 0.5 or 1
end

-- The stored colour mode where it replaces the power's own colour: "custom"
-- or "texture", nil for Default and for a caller with no unit frame key.
local function powerColorMode(inst)
    if not inst.key then return nil end
    local mode = addon.UnitFrames.Settings.Bar(inst.key, "power", "colorMode")
    if mode == "custom" or mode == "texture" then return mode end
    return nil
end

--- The colour of a power fill that is a plain file: the stored colour, white
--- for the texture's own, or the power's colour. The resolver returns white
--- when it cannot resolve the power, which on this frame would read as a
--- bug, so an unresolved power falls back to the XML's own mana blue. The
--- Edit Mode stand-in passes standIn and paints mana.
function Values.PowerColor(inst, standIn)
    local mode = powerColorMode(inst)
    if mode then
        local r, g, b = addon.ResolveColorRGBA(mode,
            addon.UnitFrames.Settings.Bar(inst.key, "power", "color"))
        return r, g, b
    end
    if standIn then return 0, 0, 1.0 end
    local r, g, b = addon.GetPowerColorRGB(inst.unit)
    if r == 1 and g == 1 and b == 1 then
        r, g, b = 0, 0, 1.0
    end
    return r, g, b
end

--- The power bar's texture from its setting, Hide Power Bar, and then the
--- colour. A Classic bar takes the file on its fill texture object. A Modern
--- bar, whose spec names an atlasPrefix, takes a chosen file through
--- SetStatusBarTexture, as the health bar does, and forgets which family
--- member it wore, so the colour pass puts one back when the setting returns
--- to Default. Hide Power Bar is the bar's alpha: Show and Hide belong to the
--- minus mob and the powerless pet (target.lua, pet.lua), and the cost
--- segment, a child, goes with it.
function Values.ApplyPowerStyle(inst)
    local bar = inst.powerBar
    if not (bar and inst.key) then return end
    local Settings = addon.UnitFrames.Settings
    local path
    local textureKey = Settings.Bar(inst.key, "power", "texture")
    if textureKey and textureKey ~= "default" and addon.Media and addon.Media.ResolveBarTexturePath then
        path = addon.Media.ResolveBarTexturePath(textureKey)
    end
    local spec = inst.spec.Bars.power
    if spec.atlasPrefix then
        if path then bar:SetStatusBarTexture(path) end
        inst.powerFillAtlas = nil
    else
        bar:GetStatusBarTexture():SetTexture(path or spec.texture or addon.UnitFrames.Art.Paths.statusBar)
    end
    inst.powerFillFile = path
    bar:SetAlpha(Settings.Bar(inst.key, "power", "hidden") == true and 0 or 1)
    Values.ApplyPowerColor(inst)
end

--- Whether Hide Power Bar is on for the frame; the bar strings go with it.
function Values.PowerHidden(inst)
    return inst.key ~= nil and addon.UnitFrames.Settings.Bar(inst.key, "power", "hidden") == true
end

-- The bar takes the real value whatever the state, as the health bar does
-- (ApplyHealth); vanilla holds an offline unit's full. The recolour runs on a
-- change of state alone, which is what greys the bar on UNIT_CONNECTION.
function Values.ApplyPower(inst)
    local bar = inst.powerBar
    if not bar then return end
    local unit = inst.unit
    local state = powerState(unit)
    if state ~= inst.powerState then
        inst.powerState = state
        Values.ApplyPowerColor(inst)
    end
    bar:SetMinMaxValues(0, UnitPowerMax(unit))
    bar:SetValue(UnitPower(unit))
end

--- UnitFrameManaBar_UpdateType's atlas branch, for a bar whose spec names an
--- atlasPrefix: the fill is the power's own member of the frame's family,
--- drawn white, since the colour is in the art. A power the table has no
--- member for, or a member this client lacks, falls to the family's mana
--- fill. A disconnected unit's bar is grey as the Classic one is, the member
--- desaturated under the 0.5 tint, since the tint alone would only darken
--- the art's colour; a dead player's fill is desaturated at half alpha. A
--- custom colour desaturates the member first, so the tint is the colour
--- picked and not a mix with the art's own. token stands in for the unit's
--- power when the Edit Mode stand-in paints.
function Values.ApplyPowerAtlas(inst, state, token)
    local bar = inst.powerBar
    local spec = inst.spec.Bars.power
    local Art = addon.UnitFrames.Art
    local element, whole
    if token then
        element = addon.PowerAtlasElements and addon.PowerAtlasElements[token]
    else
        element, whole = addon.GetPowerAtlasElement(inst.unit)
    end
    local name = whole or (spec.atlasPrefix .. (element or "Mana"))
    if not Art.AtlasResolves(name) then name = spec.atlasPrefix .. "Mana" end
    if inst.powerFillAtlas ~= name then
        local atlas = Art.ResolveAtlasName(name)
        if atlas then
            bar:SetStatusBarTexture(atlas)
            inst.powerFillAtlasMissing = nil
        else
            bar:SetStatusBarTexture(spec.texture or Art.Paths.statusBar)
            inst.powerFillAtlasMissing = true
        end
        inst.powerFillAtlas = name
    end
    local custom = powerColorMode(inst) == "custom"
    if state == "offline" then
        bar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
    elseif custom then
        local r, g, b = Values.PowerColor(inst)
        bar:SetStatusBarColor(r, g, b, 1)
    else
        bar:SetStatusBarColor(1, 1, 1, 1)
    end
    local fill = bar:GetStatusBarTexture()
    local dead = state == "dead"
    fill:SetDesaturated(dead or custom or state == "offline")
    fill:SetAlpha(powerFillAlpha(inst, dead))
end

-- Whether the bar's fill is a member of its spec's atlas family: a Modern
-- bar with no texture chosen (ApplyPowerStyle).
local function powerOnAtlas(inst)
    local power = inst.spec.Bars and inst.spec.Bars.power
    return power ~= nil and power.atlasPrefix ~= nil and not inst.powerFillFile
end

-- The colour of a bar whose fill is a plain file (PowerColor), or the atlas
-- branch above. The two greys are vanilla's.
function Values.ApplyPowerColor(inst)
    local bar = inst.powerBar
    if not bar then return end

    local state = powerState(inst.unit)
    inst.powerState = state
    if powerOnAtlas(inst) then
        Values.ApplyPowerAtlas(inst, state)
        return
    end
    -- A Modern bar that just left its atlas member may still carry these.
    -- A unit frame's alone: the personal resource display, which has no
    -- key, dresses its own fill.
    if inst.key then
        local fill = bar:GetStatusBarTexture()
        fill:SetDesaturated(false)
        fill:SetAlpha(powerFillAlpha(inst, false))
    end
    if state == "offline" then
        bar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        return
    elseif state == "dead" then
        bar:SetStatusBarColor(0.6, 0.6, 0.6, 0.5)
        return
    end

    local r, g, b = Values.PowerColor(inst)
    bar:SetStatusBarColor(r, g, b, 1)
end

--- The Edit Mode stand-in's power bar: mana, in the look the settings give.
--- The XML's blue on a file fill, the family's mana member on an atlas one.
function Values.ApplyPowerStandIn(inst)
    local bar = inst.powerBar
    if not bar then return end
    if powerOnAtlas(inst) then
        Values.ApplyPowerAtlas(inst, nil, "MANA")
    else
        local fill = bar:GetStatusBarTexture()
        fill:SetDesaturated(false)
        fill:SetAlpha(powerFillAlpha(inst, false))
        local r, g, b = Values.PowerColor(inst, true)
        bar:SetStatusBarColor(r, g, b, 1)
    end
    inst.powerState = nil
end

-- TargetHealthCheck's portrait tint for a dead or ghost player, or nil. A
-- secret read gives nil, which leaves the portrait untinted.
function Values.DeadTint(unit)
    if plain(UnitIsPlayer, unit) ~= true then return nil end
    if plain(UnitIsDead, unit) == true then return 0.35, 0.35, 0.35 end
    if plain(UnitIsGhost, unit) == true then return 0.2, 0.2, 0.75 end
    return nil
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

-- AbbreviateNumbers takes a secret and returns a secret string, which SetText
-- accepts. Nothing measures or reshapes the result: every other string library
-- call would throw on it, and a secret FontString can never be measured.
--
-- ClearText rather than SetText("") on the empty path. Only ClearText releases
-- the Text secret aspect once a secret has been written to the string.
--
-- format is an engine-side number formatter that takes a secret, nil for
-- AbbreviateNumbers. A Number Format of Full ("1,100"), on a unit frame or
-- the personal resource display, passes BreakUpLargeNumbers. A formatter that throws falls back to
-- AbbreviateNumbers; the returned word says which one fed the string.
local function formatText(format, value, max)
    local fn = format or AbbreviateNumbers
    local ok, text = pcall(function()
        if max == nil then return fn(value) end
        return fn(value) .. " / " .. fn(max)
    end)
    if ok and type(text) ~= "nil" then return text, format and "full" or "abbreviated" end
    if not format then return nil, "failed" end
    local text2, word = formatText(nil, value, max)
    return text2, "full failed, " .. word
end

local function feedNumber(fs, value, format)
    if not fs then return end
    local text, word = formatText(format, value)
    if text ~= nil then
        pcall(fs.SetText, fs, text)
    else
        fs:ClearText()
    end
    return word
end

-- TextStatusBar's "current / max". Concatenation is legal on a secret string,
-- and the result stays secret, so the join runs inside the pcall too.
local function feedPair(fs, value, max, format)
    if not fs then return end
    local text, word = formatText(format, value, max)
    if text ~= nil then
        pcall(fs.SetText, fs, text)
    else
        fs:ClearText()
    end
    return word
end

-- TextStatusBar's percent: the engine's fraction as a secret string, and the
-- sign joined on, which concatenation allows.
local function feedPercent(fs, text)
    if type(text) == "string" then
        local ok, joined = pcall(function() return text .. "%" end)
        if ok and pcall(fs.SetText, fs, joined) then return end
    end
    fs:ClearText()
end

-- Each bar's value string and percent string, and what feeds them. A caller
-- with no unit frame key (the personal resource display feeds its bars
-- through this file and its percents itself) has the current value at all
-- times and no percent here.
local BARS = {
    health = { value = "healthText", percent = "healthPercentText", cur = UnitHealth, max = UnitHealthMax },
    power = { value = "powerText", percent = "powerPercentText", cur = UnitPower, max = UnitPowerMax },
}

local function textShow(inst, bar, slot)
    if not inst.key then return slot == "value" and "always" or "never" end
    return addon.UnitFrames.Text.BarTextShow(inst.key, bar, slot)
end

--- Whether any of the frame's bar strings waits for the mouse, which is when
--- the hover (frame.lua, setHovered) has to repaint them.
function Values.BarTextOnHover(inst)
    if not inst.key then return false end
    for bar in pairs(BARS) do
        if textShow(inst, bar, "value") == "hover" or textShow(inst, bar, "percent") == "hover" then
            return true
        end
    end
    return false
end

local function stringUp(inst, bar, slot)
    local mode = textShow(inst, bar, slot)
    return mode == "always" or (mode == "hover" and inst.hovered == true)
end

--- Whether each bar string shows. target.lua sets inst.barTextDead, and
--- target.lua and pet.lua set inst.noPowerText where there is no power bar
--- to label; Hide Power Bar takes the power strings with the bar.
function Values.ApplyBarTextShown(inst)
    local powerHidden = Values.PowerHidden(inst)
    for bar, fields in pairs(BARS) do
        local blocked = inst.barTextDead or (bar == "power" and (inst.noPowerText or powerHidden))
        for _, slot in ipairs({ "value", "percent" }) do
            local fs = (inst.key or slot == "value") and inst[fields[slot]]
            if fs then fs:SetShown(not blocked and stringUp(inst, bar, slot)) end
        end
    end
end

-- The value reads "current" or "current / max" by its format setting; the
-- personal resource display's reads "current".
local function valueFormat(inst, bar)
    if not inst.key then return "current" end
    return addon.UnitFrames.Settings.Bar(inst.key, bar, "text", "value", "format")
end

-- The value's formatter: the instance's numberFormatter(bar) hook where it
-- sets one (the personal resource display), else a unit frame's Number
-- Format setting, else abbreviated. inst.lastNumberFormat records which
-- formatter fed each bar, for the debug windows.
local function numberFormatter(inst, bar)
    local hook = inst.numberFormatter
    if type(hook) == "function" then return hook(bar) end
    if inst.key and addon.UnitFrames.Settings.Bar(inst.key, bar, "text", "value", "numberFormat") == "full" then
        return BreakUpLargeNumbers
    end
    return nil
end

function Values.ApplyBarText(inst)
    local unit = inst.unit
    for bar, fields in pairs(BARS) do
        local valueFS = inst[fields.value]
        if valueFS then
            local word
            if not stringUp(inst, bar, "value") then
                valueFS:ClearText()
            elseif valueFormat(inst, bar) == "currentMax" then
                word = feedPair(valueFS, fields.cur(unit), fields.max(unit), numberFormatter(inst, bar))
            else
                word = feedNumber(valueFS, fields.cur(unit), numberFormatter(inst, bar))
            end
            inst.lastNumberFormat = inst.lastNumberFormat or {}
            inst.lastNumberFormat[bar] = word or "off"
        end
        local percentFS = inst.key and inst[fields.percent]
        if percentFS then
            if not stringUp(inst, bar, "percent") then
                percentFS:ClearText()
            elseif bar == "health" then
                feedPercent(percentFS, (addon.Percent.Health(unit, false)))
            else
                feedPercent(percentFS, (addon.Percent.Power(unit)))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

-- The font objects' own yellow, NORMAL_FONT_COLOR, which a string has to be
-- given back once it has worn a class colour.
local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.82, 0

-- The colour a unit's name takes: the class colour for a player whose class
-- resolves, the font's yellow for everyone else. Camelot's addition; vanilla
-- colours no name. UnitIsPlayer is decided on, so a secret answer counts as
-- no; GetClassColorRGB screens a secret itself and returns nil.
function Values.IdentityColor(unit)
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if ok and not issecretvalue(isPlayer) and isPlayer == true then
        local r, g, b = addon.GetClassColorRGB(unit)
        if r then return r, g, b end
    end
    return GOLD_R, GOLD_G, GOLD_B
end

-- The name on every frame; the level on the player frame alone, because the
-- target's level colour is the difficulty read target.lua applies after this.
-- Each string's colour mode is its setting (text.lua), with the spec's own
-- colour as the default, the gold where it names none (Text.DefaultColor),
-- and IdentityColor as the class answer. SetTextColor rather than
-- SetVertexColor: it is the call the Deep Shadow copy hooks to shade itself
-- against.
local function applyIdentityColor(inst)
    local Text = addon.UnitFrames.Text
    if inst.nameText then
        inst.nameText:SetTextColor(Text.Color(inst, "name", Text.DefaultColor(inst, "name", GOLD_R, GOLD_G, GOLD_B)))
    end
    if inst.levelText and inst.unit == "player" then
        inst.levelText:SetTextColor(Text.Color(inst, "level", Text.DefaultColor(inst, "level", GOLD_R, GOLD_G, GOLD_B)))
    end
end

-- Forever's UnitName returns the first name and the surname, where retail's
-- second return is the realm (nil for your own character). Forever's NameUtil
-- override (Blizzard_FrameXMLUtil/Camelot/NameUtil.lua) joins them with
-- CHARACTERNAME_SURNAME_SEPARATOR; with regional unique names on, the first
-- return can already hold both, and Blizzard splits it on the last separator.
-- Only a frame whose surface has `surname` asks. Concatenation is legal on a
-- secret, so a secret surname is joined without the empty test: an empty one
-- leaves a trailing separator. A secret joined first return cannot be split,
-- so hiding the surname shows both there.
local function surnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

function Values.DisplayName(unit, showSurname)
    local first, surname = UnitName(unit)
    if type(first) ~= "string" then return first end
    local sep = surnameSeparator()
    if not showSurname then
        if not issecretvalue(first) and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
            return first:match("^([^-]+)" .. sep:gsub("%p", "%%%0") .. ".*") or first
        end
        return first
    end
    if issecretvalue(surname) or (type(surname) == "string" and surname ~= "") then
        return first .. sep .. surname
    end
    return first
end

-- A long name shrinks until it fits its box on one line, through the blind
-- fit Unit Frames Z sizes its names with (core/blindfit.lua). The fit reads
-- only SetAlphaGradient, so a secret name fits as a plain one does. It lands
-- two frames later, and the name is never drawn at a size it has not decided:
-- a new subject blanks the name by alpha until then, and a hold keeps the
-- current picture up and swaps it in one step. The Deep Shadow copy follows
-- the alpha (core/fontpair.lua). The callback paints the string it measured
-- and never reads the unit again.
--
-- Floor with nothing fitting: the name draws at the floor and the engine
-- ellipsizes it. Oracle failure: the ceiling, which is the unfitted look.
function Values.FitName(inst, name, hold)
    local fs = inst.nameText
    local Text = addon.UnitFrames.Text
    local face, ceiling, flags, style = Text.ResolveFont(inst, "name")
    inst.nameFitSeq = (inst.nameFitSeq or 0) + 1
    local seq = inst.nameFitSeq
    if not hold then fs:SetAlpha(0) end

    local def = inst.spec.Text.name
    local minSize = tonumber(Text.Get(inst.key, "name", "fitMin")) or Text.FIT_MIN
    addon.RunBlindFit(name, {
        poolKey  = "camelotName:" .. inst.frameName,
        facePath = face,
        style    = style,
        width    = Text.NameWidth(inst),
        height   = def.h,
        maxLines = 1,
        minSize  = math.min(minSize, ceiling),
        maxSize  = ceiling,
        margin   = "auto",
    }, function(st)
        if seq ~= inst.nameFitSeq then return end
        local size
        if st.size then
            size = st.size
        elseif st.F and st.spaces then
            size = st.lo
        else
            size = ceiling
        end
        inst.nameFitSize, inst.lastNameFit = size, st
        Text.ApplyFont(fs, face, size, flags, style)
        fs:ClearText()
        pcall(fs.SetText, fs, name)
        fs:SetAlpha(1)
    end)
end

-- Drop a fit in flight and the size it left, for a name drawn unfitted.
local function unfitName(inst)
    inst.nameFitSeq = (inst.nameFitSeq or 0) + 1
    inst.nameText:SetAlpha(1)
    if inst.nameFitSize then
        inst.nameFitSize = nil
        local Text = addon.UnitFrames.Text
        Text.ApplyFont(inst.nameText, Text.ResolveFont(inst, "name"))
    end
end

--- Put a name string on the frame: fitted where the setting asks, direct
--- otherwise. hold keeps the current picture up while a fit runs. The nil
--- tests go through type(), which a secret name answers.
function Values.SetName(inst, name, hold)
    local present = type(name) ~= "nil"
    if present and addon.UnitFrames.Text.FitsName(inst.key) then
        Values.FitName(inst, name, hold)
        return
    end
    unfitName(inst)
    if present then
        pcall(inst.nameText.SetText, inst.nameText, name)
    else
        inst.nameText:ClearText()
    end
end

-- The player's own name and level are plain reads on retail. Both are screened
-- anyway: this frame is written to be pointed at another unit later, where they
-- are not.
function Values.ApplyIdentity(inst, hold)
    if inst.nameText then
        local Text = addon.UnitFrames.Text
        local name
        if Text.SURFACE[inst.key].surname then
            name = Values.DisplayName(inst.unit, not Text.Get(inst.key, "name", "hideSurname"))
        else
            name = UnitName(inst.unit)
        end
        Values.SetName(inst, name, hold)
    end

    if inst.levelText then
        local level = UnitLevel(inst.unit)
        if type(level) == "number" and not issecretvalue(level) then
            inst.levelText:SetText(level)
        else
            pcall(inst.levelText.SetText, inst.levelText, level)
        end
    end

    applyIdentityColor(inst)
end

-- SetPortraitTexture renders through a camera the client owns. Lua supplies no
-- zoom and no angle, and no CVar does either, so the vanilla framing is not
-- reachable from this call. It is not reachable from a PlayerModel either: a
-- model can be aimed anywhere, but the flat low-detail look the old portraits
-- had comes from the models the client loads, not from where the lens sits.
-- Measured over three builds of a scrap lab and closed.
--
-- Two arguments, so disableMasking stays false and the engine applies its own
-- circular mask. That is the vanilla call: Classic Era passes two as well.
-- A portrait def marked disableMasking passes true, which is retail's player
-- frame: its atlas mask alone shapes the face. unit stands in for inst.unit
-- when the Edit Mode stand-in paints the player's own.
function Values.ApplyPortrait(inst, unit)
    if not inst.portrait then return end
    local def = inst.spec.Regions.portrait
    if def and def.disableMasking then
        pcall(SetPortraitTexture, inst.portrait, unit or inst.unit, true)
    else
        pcall(SetPortraitTexture, inst.portrait, unit or inst.unit)
    end
    -- A new face keeps the crop the Portrait settings ask for.
    if inst.key then Values.ApplyPortraitZoom(inst) end
end

--- Portrait Zoom (settings.lua, "Portrait"): a crop of the face about its
--- centre, 100 to 200 percent. A Classic portrait's round edge is baked in
--- by SetPortraitTexture, and a crop would square it, so a zoomed one takes
--- a circle mask of its own, built on first need and taken off again at
--- 100, where the frame draws as it did before the setting. A Modern
--- portrait wears its spec's mask at every zoom.
function Values.ApplyPortraitZoom(inst)
    local portrait = inst.portrait
    if not (portrait and inst.key) then return end
    local Settings = addon.UnitFrames.Settings
    local zoom = math.max(100, math.min(200, tonumber(Settings.Portrait(inst.key, "zoom")) or 100))
    local inset = (1 - 100 / zoom) / 2
    portrait:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
    if portrait.camelotMask then return end

    local mask = inst.portraitZoomMask
    if zoom > 100 then
        if not mask then
            local Art = addon.UnitFrames.Art
            mask = Art.BuildMask(portrait:GetParent(), portrait, { file = Art.Paths.circleMask })
            inst.portraitZoomMask = mask
        end
        if mask and not inst.portraitZoomMasked then
            portrait:AddMaskTexture(mask)
            inst.portraitZoomMasked = true
        end
    elseif mask and inst.portraitZoomMasked then
        portrait:RemoveMaskTexture(mask)
        inst.portraitZoomMasked = nil
    end
end

--- The Portrait section's settings on a built frame: the zoom, and the
--- region's alpha, which nothing else writes: 0 under Hide Portrait, else
--- Portrait Opacity where the page offers it. The tints (target.lua, tot.lua)
--- are the vertex colour.
function Values.ApplyPortraitStyle(inst)
    local portrait = inst.portrait
    if not (portrait and inst.key) then return end
    Values.ApplyPortraitZoom(inst)
    local Settings = addon.UnitFrames.Settings
    local alpha = 0
    if Settings.Portrait(inst.key, "hidden") ~= true then
        local opacity = tonumber(Settings.Portrait(inst.key, "opacity")) or 100
        alpha = math.max(1, math.min(100, opacity)) / 100
    end
    portrait:SetAlpha(alpha)
end

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

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

-- Max first, then value. A bar whose range is still (0, 1) when a large value
-- arrives clamps to full for one frame, which reads as a flash on login.
function Values.ApplyHealth(inst)
    local bar = inst.healthBar
    if not bar then return end
    bar:SetMinMaxValues(0, UnitHealthMax(inst.unit))
    bar:SetValue(UnitHealth(inst.unit))
end

function Values.ApplyPower(inst)
    local bar = inst.powerBar
    if not bar then return end
    bar:SetMinMaxValues(0, UnitPowerMax(inst.unit))
    bar:SetValue(UnitPower(inst.unit))
end

-- The resolver handles the unit-to-token step and both lookup tables, and it is
-- the one place the colour tables are read. It returns white when it cannot
-- resolve, which on this frame would read as a bug, so an unresolved power
-- falls back to the XML's own mana blue instead.
function Values.ApplyPowerColor(inst)
    local bar = inst.powerBar
    if not bar then return end

    local r, g, b = addon.GetPowerColorRGB(inst.unit)
    if r == 1 and g == 1 and b == 1 then
        r, g, b = 0, 0, 1.0
    end
    bar:SetStatusBarColor(r, g, b)
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
local function feedNumber(fs, value)
    if not fs then return end
    local ok, text = pcall(AbbreviateNumbers, value)
    if ok and text ~= nil then
        pcall(fs.SetText, fs, text)
    else
        fs:ClearText()
    end
end

function Values.ApplyBarText(inst)
    feedNumber(inst.healthText, UnitHealth(inst.unit))
    feedNumber(inst.powerText, UnitPower(inst.unit))
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
-- Each string's colour mode is its setting (text.lua), with the gold as the
-- default and IdentityColor as the class answer. SetTextColor rather than
-- SetVertexColor: it is the call the Deep Shadow copy hooks to shade itself
-- against.
local function applyIdentityColor(inst)
    local Text = addon.UnitFrames.Text
    if inst.nameText then
        inst.nameText:SetTextColor(Text.Color(inst, "name", GOLD_R, GOLD_G, GOLD_B))
    end
    if inst.levelText and inst.unit == "player" then
        inst.levelText:SetTextColor(Text.Color(inst, "level", GOLD_R, GOLD_G, GOLD_B))
    end
end

-- The player's own name and level are plain reads on retail. Both are screened
-- anyway: this frame is written to be pointed at another unit later, where they
-- are not.
function Values.ApplyIdentity(inst)
    if inst.nameText then
        local name = UnitName(inst.unit)
        if name ~= nil then
            pcall(inst.nameText.SetText, inst.nameText, name)
        else
            inst.nameText:ClearText()
        end
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
function Values.ApplyPortrait(inst)
    if not inst.portrait then return end
    pcall(SetPortraitTexture, inst.portrait, inst.unit)
end

--------------------------------------------------------------------------------
-- forever/actionbars/text.lua
-- The keybind and cooldown text on a Camelot action button: their stored
-- settings per bar and the passes that draw them over Blizzard's own.
--
-- Blizzard's code owns the string. UpdateHotkeys sets its text, size and
-- anchor; Update and the range check set its colour and show or hide it.
-- The pass here runs after each of those (the overrides in mixins.lua) and
-- changes only what a setting names. With nothing stored it changes
-- nothing, so a new profile draws Blizzard's text exactly.
--
-- The cooldown text is the engine's countdown string on button.cooldown
-- (Cooldown:GetCountdownFontString). No Blizzard Lua writes it, so its pass
-- runs after each swipe the button sets (mixins.lua) and on a settings
-- change. The client draws it only while the game's cooldown numbers option
-- is on.
--
-- Loads before frames.xml: a button's load runs UpdateHotkeys, which calls
-- in here. The bar is not wired yet then (ActionBar_OnLoad writes
-- button.bar after the button's own load), so the token comes from the
-- button's name.
--------------------------------------------------------------------------------

local _, addon = ...

local DB = addon.DB
local ActionBars = addon.ActionBars

local Text = {}
ActionBars.Text = Text

-- The template's font object and its keyboard anchor
-- (Mainline/ActionButtonTemplate.xml, the hotkeyTextKeyboard KeyValues).
Text.FONT_OBJECT = "NumberFontNormalSmallGray"
local ANCHOR_X, ANCHOR_Y = -4, -5

--- The dotted path of a text setting, part "hotkey" or "cooldown":
--- Text.Path("bar2", "hotkey", "size").
function Text.Path(token, part, field)
    return "actionBars.text." .. token .. "." .. part .. "." .. field
end

local function get(token, field)
    return DB.Get(Text.Path(token, "hotkey", field))
end

local function getCooldown(token, field)
    return DB.Get(Text.Path(token, "cooldown", field))
end

-- button -> its bar token, read once from the name.
local tokens = setmetatable({}, { __mode = "k" })

local function tokenOf(button)
    local token = tokens[button]
    if token == nil then
        local n = (button:GetName() or ""):match("^CamelotActionBar(%d)Button")
        token = n and ("bar" .. n) or false
        tokens[button] = token
    end
    return token or nil
end

-- What the pass has changed on each string, so a cleared setting puts
-- Blizzard's value back; and which buttons the range check last drew red.
local fontTouched = setmetatable({}, { __mode = "k" })
local colorTouched = setmetatable({}, { __mode = "k" })
local outOfRange = setmetatable({}, { __mode = "k" })

--- The font object's face, point size and flags.
function Text.FontObjectFont()
    local fontObject = _G[Text.FONT_OBJECT]
    if fontObject then return fontObject:GetFont() end
end

--- The style key that matches the font object's outline flags.
--- The style key that matches a font's outline flags.
function Text.StyleOf(flags)
    if flags and flags:find("THICK") then return "THICKOUTLINE" end
    if flags and flags:find("OUTLINE") then return "OUTLINE" end
    return "NONE"
end

function Text.FontObjectStyle()
    local _, _, flags = Text.FontObjectFont()
    return Text.StyleOf(flags)
end

local function applyFont(button, token, hotkey)
    local fontFace, size, style = get(token, "fontFace"), tonumber(get(token, "size")), get(token, "style")
    if fontFace == nil and size == nil and style == nil then
        if fontTouched[button] then
            hotkey:SetFontObject(Text.FONT_OBJECT)
            fontTouched[button] = nil
            colorTouched[button] = true -- the font object brought its own colour
        end
        return
    end
    local face, objectSize = Text.FontObjectFont()
    if fontFace then face = addon.ResolveFontFace(fontFace) end
    addon.ApplyFontStyle(hotkey, face, size or objectSize or 12, style or Text.FontObjectStyle())
    fontTouched[button] = true
end

-- Blizzard writes the range colour as a vertex colour over the font
-- object's grey. A stored colour goes in the same channel, over white text,
-- which reads the same whether the client multiplies the two or lets the
-- vertex colour stand alone. Out-of-range red stays Blizzard's.
local function applyColor(button, token, hotkey)
    local c = get(token, "color")
    if type(c) == "table" then
        if outOfRange[button] then return end
        hotkey:SetTextColor(1, 1, 1, 1)
        hotkey:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        colorTouched[button] = true
    elseif colorTouched[button] then
        local fontObject = _G[Text.FONT_OBJECT]
        if fontObject then hotkey:SetTextColor(fontObject:GetTextColor()) end
        if outOfRange[button] then
            hotkey:SetVertexColor(RED_FONT_COLOR:GetRGB())
        else
            hotkey:SetVertexColor(ACTIONBAR_HOTKEY_FONT_COLOR:GetRGB())
        end
        colorTouched[button] = nil
    end
end

-- Blizzard's UpdateHotkeys has just anchored the string, so a stored offset
-- moves it from there, and a cleared one leaves Blizzard's anchor alone.
local function applyOffset(button, token, hotkey)
    local x, y = tonumber(get(token, "offsetX")), tonumber(get(token, "offsetY"))
    if not x and not y then return end
    hotkey:SetPoint("TOPRIGHT", button, "TOPRIGHT",
        (button.hotkeyTextKeyboardX or ANCHOR_X) + (x or 0),
        (button.hotkeyTextKeyboardY or ANCHOR_Y) + (y or 0))
end

-- Alpha, not Hide: Blizzard's Update and range check call Show on the
-- string, and the range dot of an unbound key with them.
local function applyHidden(token, hotkey)
    hotkey:SetAlpha(get(token, "hidden") and 0 or 1)
end

--- The whole pass, after Blizzard's UpdateHotkeys.
function Text.Hotkey(button)
    local token = tokenOf(button)
    local hotkey = button.HotKey
    if not token or not hotkey then return end
    applyFont(button, token, hotkey)
    applyColor(button, token, hotkey)
    applyOffset(button, token, hotkey)
    applyHidden(token, hotkey)
end

--- The colour alone, after Blizzard's Update or range check has written its
--- own. outOfRangeNow is the range check's verdict, nil from Update.
function Text.HotkeyColor(button, outOfRangeNow)
    if outOfRangeNow ~= nil then outOfRange[button] = outOfRangeNow or nil end
    local token = tokenOf(button)
    if not token or not button.HotKey then return end
    applyColor(button, token, button.HotKey)
end

--------------------------------------------------------------------------------
-- Cooldown text
--------------------------------------------------------------------------------

-- The countdown string's own font, colour and anchor, read before the pass
-- first changes it, so a cleared setting puts them back.
local cooldownOriginal = setmetatable({}, { __mode = "k" })

-- The buttons whose countdown string the pass set to alpha 0. The engine
-- owns the string and its alpha reads secret in a fight, so the pass never
-- reads it: it writes 1 back only where it wrote the 0.
local cooldownHidden = setmetatable({}, { __mode = "k" })

local COOLDOWN_FIELDS = { "fontFace", "size", "style", "color", "offsetX", "offsetY" }

local function cooldownString(button)
    local cooldown = button.cooldown
    return cooldown and cooldown.GetCountdownFontString and cooldown:GetCountdownFontString() or nil
end

--- The countdown string's face, point size and flags, from the first
--- button that has one: what the page shows while nothing is stored.
function Text.CooldownFont()
    local frame = ActionBars.Frames and ActionBars.Frames.bar1
    local button = frame and frame.actionButtons and frame.actionButtons[1]
    local fs = button and cooldownString(button)
    if not fs then return end
    local original = cooldownOriginal[button]
    if original then return original.face, original.size, original.flags end
    return fs:GetFont()
end

local function plain(...)
    for i = 1, select("#", ...) do
        if issecretvalue and issecretvalue((select(i, ...))) then return false end
    end
    return true
end

-- The string is the engine's, so a read in a fight can come back secret, and
-- a secret kept here would throw on every later pass. A read that is not
-- plain throughout leaves no record; the next pass out of combat takes it.
local function readOriginal(fs)
    local face, size, flags = fs:GetFont()
    local r, g, b, a = fs:GetTextColor()
    local point, _, relPoint, x, y = fs:GetPoint(1)
    if not plain(face, size, flags, r, g, b, a, point, relPoint, x, y) then return nil end
    return { face = face, size = size, flags = flags, color = { r, g, b, a },
        point = point, relPoint = relPoint, x = x, y = y }
end

local function captureCooldown(button, fs)
    local original = cooldownOriginal[button]
    if original then return original end
    local ok, read = pcall(readOriginal, fs)
    if ok and read then
        cooldownOriginal[button] = read
        return read
    end
end

--- The cooldown pass on one button.
function Text.Cooldown(button)
    local token = tokenOf(button)
    local fs = token and cooldownString(button)
    if not fs then return end
    local stored = false
    for _, field in ipairs(COOLDOWN_FIELDS) do
        if getCooldown(token, field) ~= nil then stored = true break end
    end
    -- Alpha, as the keybind's: written to 0 where Hide is set, and back to 1
    -- only where this pass wrote the 0.
    if getCooldown(token, "hidden") then
        fs:SetAlpha(0)
        cooldownHidden[button] = true
    elseif cooldownHidden[button] then
        fs:SetAlpha(1)
        cooldownHidden[button] = nil
    end
    local original = cooldownOriginal[button]
    if not stored then
        if original then
            if original.face then fs:SetFont(original.face, original.size, original.flags) end
            fs:SetTextColor(unpack(original.color))
            fs:ClearAllPoints()
            fs:SetPoint(original.point or "CENTER", button.cooldown, original.relPoint or "CENTER",
                original.x or 0, original.y or 0)
            cooldownOriginal[button] = nil
        end
        return
    end
    original = captureCooldown(button, fs)
    if not original then return end

    local fontFace, size, style = getCooldown(token, "fontFace"), tonumber(getCooldown(token, "size")),
        getCooldown(token, "style")
    local face = (fontFace and addon.ResolveFontFace(fontFace)) or original.face
        or addon.ResolveFontFace("FRIZQT__")
    addon.ApplyFontStyle(fs, face, size or original.size or 16, style or Text.StyleOf(original.flags))

    local c = getCooldown(token, "color")
    if type(c) == "table" then
        fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        fs:SetTextColor(unpack(original.color))
    end

    local x, y = tonumber(getCooldown(token, "offsetX")) or 0, tonumber(getCooldown(token, "offsetY")) or 0
    fs:ClearAllPoints()
    fs:SetPoint(original.point or "CENTER", button.cooldown, original.relPoint or "CENTER",
        (original.x or 0) + x, (original.y or 0) + y)
end

--- Redraw one bar's text: the keybind from Blizzard's pass up, so a cleared
--- anchor or size goes back to Blizzard's, then the cooldown text.
function Text.Refresh(token)
    local frame = ActionBars.Frames and ActionBars.Frames[token]
    if not frame or not frame.actionButtons then return end
    for _, button in ipairs(frame.actionButtons) do
        button:UpdateHotkeys(button.buttonType)
        Text.Cooldown(button)
    end
end

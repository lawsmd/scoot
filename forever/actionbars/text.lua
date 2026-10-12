--------------------------------------------------------------------------------
-- forever/actionbars/text.lua
-- The keybind text on a Camelot action button: its stored settings per bar
-- and the pass that draws them over Blizzard's own.
--
-- Blizzard's code owns the string. UpdateHotkeys sets its text, size and
-- anchor; Update and the range check set its colour and show or hide it.
-- The pass here runs after each of those (the overrides in mixins.lua) and
-- changes only what a setting names. With nothing stored it changes
-- nothing, so a new profile draws Blizzard's text exactly.
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

--- The dotted path of a keybind text setting: Text.Path("bar2", "size").
function Text.Path(token, field)
    return "actionBars.text." .. token .. ".hotkey." .. field
end

local function get(token, field)
    return DB.Get(Text.Path(token, field))
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
function Text.FontObjectStyle()
    local _, _, flags = Text.FontObjectFont()
    if flags and flags:find("THICK") then return "THICKOUTLINE" end
    if flags and flags:find("OUTLINE") then return "OUTLINE" end
    return "NONE"
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

--- Redraw one bar's keybind text from Blizzard's pass up, so a cleared
--- anchor or size goes back to Blizzard's.
function Text.Refresh(token)
    local frame = ActionBars.Frames and ActionBars.Frames[token]
    if not frame or not frame.actionButtons then return end
    for _, button in ipairs(frame.actionButtons) do
        button:UpdateHotkeys(button.buttonType)
    end
end

--------------------------------------------------------------------------------
-- forever/chat/tabs.lua
-- The chat replica's tab strip: one Camelot tab per Blizzard window on the
-- holder's Strip, named from the chat cache, in Blizzard's dock order, with
-- Blizzard's tab art and alphas, the unread flash, and Show Tabs on mouseover;
-- before them the social tab (social.lua), Blizzard's friends button as a tab.
-- Selection is Camelot's own: it shows one twin and hides the rest, and never
-- touches Blizzard's dock, whose selected-window field the send path reads.
--
-- A window whose name is secret (a whisper window in the chat messaging
-- lockdown) takes a fixed width, Blizzard's own rule for its tabs, since a
-- secret string cannot be measured. A right-click on a tab opens the menu
-- (menu.lua).
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style

local Tabs = {}
CR.Tabs = Tabs

local strip
local tabs = {}        -- source -> tab
local ordered = {}     -- entries in strip order
local selected         -- the selected entry
local mouseOver = false
local built = false

local TAB_MIN, TAB_MAX = 60, 90
local SECRET_WIDTH = 90
local TAB_GAP = 1

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function alphaConstant(name, fallback)
    local v = _G[name]
    if type(v) == "number" then return v end
    return fallback
end

-- Blizzard's tab alphas (FloatingChatFrame.lua:15-20), read at use so a
-- client that renumbers them wins.
local function alphas()
    return {
        selectedOver = alphaConstant("CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA", 1.0),
        selectedIdle = alphaConstant("CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA", 0.4),
        alertOver = alphaConstant("CHAT_FRAME_TAB_ALERTING_MOUSEOVER_ALPHA", 1.0),
        alertIdle = alphaConstant("CHAT_FRAME_TAB_ALERTING_NOMOUSE_ALPHA", 1.0),
        normalOver = alphaConstant("CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA", 0.6),
        normalIdle = alphaConstant("CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA", 0.2),
    }
end
Tabs.Alphas = alphas

--------------------------------------------------------------------------------
-- Names and order
--------------------------------------------------------------------------------

--- The window's name from the chat cache, which may be secret, and whether it
--- is.
local function windowName(entry)
    local name = Style.Cache(entry.id)
    if type(name) == "string" and (isSecret(name) or name ~= "") then
        return name, isSecret(name)
    end
    return "Window " .. tostring(entry.id), false
end

--- Blizzard's dock order, read off the dock's list, then any shown window
--- that is not docked. Every read is a plain read of a Blizzard table.
local function windowOrder()
    local Display = CR.Display
    local entries = Display and Display.Entries() or {}
    local list, seen = {}, {}
    local ok, docked = pcall(function()
        local dock = _G.GENERAL_CHAT_DOCK
        return dock and dock.DOCKED_CHAT_FRAMES
    end)
    if ok and type(docked) == "table" then
        for _, frame in ipairs(docked) do
            local entry = Display.EntryFor(frame)
            if entry and not seen[entry] and not entry.closed then
                seen[entry] = true
                list[#list + 1] = entry
            end
        end
    end
    for _, entry in ipairs(entries) do
        if not seen[entry] then
            local _, _, _, _, _, _, shown, _, docked2 = Style.Cache(entry.id)
            if not entry.closed and (entry.id == 1 or (shown == true and docked2 ~= true)) then
                seen[entry] = true
                list[#list + 1] = entry
            end
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

local function updateColors(tab, isSelected)
    -- FCFTab_UpdateColors (FloatingChatFrame.lua:1267-1290), the default color table.
    local color = _G.DEFAULT_TAB_SELECTED_COLOR_TABLE or { r = 1, g = 0.82, b = 0 }
    tab.ActiveLeft:SetShown(isSelected)
    tab.ActiveMiddle:SetShown(isSelected)
    tab.ActiveRight:SetShown(isSelected)
    local text = tab:GetFontString()
    if text then
        local normal = NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 }
        text:SetTextColor(normal.r, normal.g, normal.b)
    end
    for _, key in ipairs({ "ActiveLeft", "ActiveMiddle", "ActiveRight", "HighlightLeft", "HighlightMiddle", "HighlightRight", "glow" }) do
        local region = tab[key]
        if region then region:SetVertexColor(color.r, color.g, color.b) end
    end
end
Tabs.UpdateColors = updateColors

local function updateAlpha(tab, entry)
    local a = alphas()
    local value
    if entry == selected then
        value = mouseOver and a.selectedOver or a.selectedIdle
    elseif tab.alerting then
        value = mouseOver and a.alertOver or a.alertIdle
    else
        value = mouseOver and a.normalOver or a.normalIdle
    end
    tab:SetAlpha(value)
end

local function stopFlash(tab)
    if not tab.alerting then return end
    tab.alerting = false
    local glow = tab.glow
    if glow then
        if glow.FlashAnim and glow.FlashAnim:IsPlaying() then glow.FlashAnim:Stop() end
        glow:Hide()
    end
end

local function startFlash(tab)
    if tab.alerting then return end
    tab.alerting = true
    local glow = tab.glow
    if glow then
        glow:Show()
        if glow.FlashAnim and not glow.FlashAnim:IsPlaying() then glow.FlashAnim:Play() end
    end
end

local function label(global, fallback)
    local s = _G[global]
    if type(s) == "string" and s ~= "" then return s end
    return fallback
end

-- Blizzard's tab tooltip (FloatingChatFrame.xml, the tab's OnEnter): the
-- name as a title and the right-click hint in green.
local function onEnter(tab)
    if not GameTooltip then return end
    local name = tab.windowName
    if type(name) ~= "string" then return end
    GameTooltip:SetOwner(tab, "ANCHOR_RIGHT")
    local ok, title = pcall(string.format, label("CHAT_TAB_NAME", "%s Tab"), name)
    GameTooltip:SetText(ok and title or name)
    local green = _G.GREEN_FONT_COLOR
    GameTooltip:AddLine(label("CHAT_TAB_RIGHT_CLICK", "<Right click for Tab Settings>"),
        green and green.r or 0.1, green and green.g or 1, green and green.b or 0.1)
    GameTooltip:Show()
end

local function onLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function createTab(entry)
    local name = (addon.Brand or "Camelot") .. "ChatTab" .. tostring(entry.id)
    local tab = CreateFrame("Button", name, strip, "CamelotChatTabTemplate")
    tab:SetHeight(Style.TAB_HEIGHT)
    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tab:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if CR.Menu then CR.Menu.Open(entry) end
            return
        end
        Tabs.Select(entry)
    end)
    tab:SetScript("OnEnter", onEnter)
    tab:SetScript("OnLeave", onLeave)
    tabs[entry.source] = tab
    return tab
end

local function sizeTab(tab, secret)
    local resize = _G.PanelTemplates_TabResize
    if secret or not resize then
        -- FCF_SetTabFixedWidth: a fixed width, the text given the inside of it.
        tab.Text:SetWidth(SECRET_WIDTH - 20)
        tab:SetWidth(SECRET_WIDTH)
        return
    end
    pcall(resize, tab, 0, nil, TAB_MIN, TAB_MAX)
end

--------------------------------------------------------------------------------
-- Layout and selection
--------------------------------------------------------------------------------

--- The window tabs in a row after the social tab, when it is built.
local function layout()
    local previous = CR.Social and CR.Social.Tab()
    for _, entry in ipairs(ordered) do
        local tab = tabs[entry.source]
        tab:ClearAllPoints()
        if previous then
            tab:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", TAB_GAP, 0)
        else
            tab:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
        end
        tab:Show()
        previous = tab
    end
end

--- Rebuild the strip from the dock order and the cache: names, widths,
--- which tabs show, the selection kept where it still exists.
function Tabs.Refresh()
    if not built then return end
    ordered = windowOrder()
    local present = {}
    for _, entry in ipairs(ordered) do
        present[entry] = true
        local tab = tabs[entry.source] or createTab(entry)
        local name, secret = windowName(entry)
        tab.windowName = (not secret) and name or nil
        tab:SetText(name)
        sizeTab(tab, secret)
    end
    for source, tab in pairs(tabs) do
        local entry = CR.Display and CR.Display.EntryFor(source)
        if not (entry and present[entry]) then tab:Hide() end
    end
    layout()
    if not (selected and present[selected]) then
        Tabs.Select(ordered[1])
    else
        Tabs.UpdateState()
    end
end

--- Show one twin, hide the rest, stop its flash, tell the display.
function Tabs.Select(entry)
    if not entry then return end
    local previous = selected
    selected = entry
    local Display = CR.Display
    for _, e in ipairs(Display and Display.Entries() or {}) do
        if e == entry then e.twin:Show() else e.twin:Hide() end
    end
    local tab = tabs[entry.source]
    if tab then stopFlash(tab) end
    if Display and Display.OnSelect then Display.OnSelect(entry, previous) end
    Tabs.UpdateState()
end

function Tabs.Selected()
    return selected
end

--- The entries in strip order, the one dock the menu's Make Noninteractive
--- reaches across.
function Tabs.Ordered()
    return ordered
end

--- Colors and alphas for every shown tab, and the strip's own visibility.
function Tabs.UpdateState()
    local anyAlert = false
    for _, entry in ipairs(ordered) do
        local tab = tabs[entry.source]
        if tab then
            updateColors(tab, entry == selected)
            updateAlpha(tab, entry)
            if tab.alerting then anyAlert = true end
        end
    end
    if CR.Social then CR.Social.UpdateState(mouseOver) end
    if strip then
        local always = Style.Get("showTabs") ~= "mouseover"
        strip:SetShown(always or mouseOver or anyAlert)
    end
end

--- A line landed in a window's twin. An unselected window's tab flashes by
--- the Flash Tabs setting; `event` is the chat event the line came from.
--- Every Window flashes for a player's message (Config.IsPlayerMessage) and
--- never for a combat, loot, tradeskill or system line, so the combat log's
--- tab, which carries nothing else, stays still; Whispers Only is Blizzard's
--- own rule (ChatFrameUtil.FlashTabIfNotShown). A line with no event
--- (print) or a secret one flashes nothing.
function Tabs.OnLine(source, event)
    local entry = CR.Display and CR.Display.EntryFor(source)
    if not entry or entry == selected then return end
    local mode = Style.Get("tabFlash") or "all"
    if mode == "never" then return end
    if type(event) ~= "string" or isSecret(event) then return end
    if mode == "whispers" then
        if event ~= "CHAT_MSG_WHISPER" and event ~= "CHAT_MSG_BN_WHISPER" then return end
    elseif CR.Config and not CR.Config.IsPlayerMessage(event) then
        return
    end
    local tab = tabs[source]
    if not tab then return end
    startFlash(tab)
    Tabs.UpdateState()
end

--- The chrome ticker's mouse state, which drives the alphas and Show Tabs.
function Tabs.SetMouse(over)
    over = over and true or false
    if over == mouseOver then return end
    mouseOver = over
    Tabs.UpdateState()
end

--- Style.Apply's call: the Show Tabs setting.
function Tabs.Apply()
    Tabs.UpdateState()
end

--- Build the strip on the holder, the social tab first, then the tabs from
--- the windows the display already twinned; selects window 1.
function Tabs.Build(holder)
    if built then return end
    strip = holder.Strip
    strip:SetHeight(Style.TAB_HEIGHT)
    built = true
    if CR.Social then CR.Social.Build(strip) end
    Tabs.Refresh()
end

--- A line for /camelot chat.
function Tabs.Describe(push)
    push("  tabs: %d shown, selected %s, mouse %s, strip %s", #ordered,
        selected and tostring(selected.name) or "none", tostring(mouseOver),
        strip and (strip:IsShown() and "shown" or "hidden") or "unbuilt")
    for _, entry in ipairs(ordered) do
        local tab = tabs[entry.source]
        local name, secret = windowName(entry)
        push("    %s: %s%s, width %.0f, alerting %s", tostring(entry.name),
            secret and "<secret name>" or tostring(name), entry == selected and " (selected)" or "",
            tab and tab:GetWidth() or 0, tostring(tab and tab.alerting or false))
    end
    if CR.Social then CR.Social.Describe(push) end
end

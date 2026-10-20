--------------------------------------------------------------------------------
-- forever/chat/display.lua
-- The chat replica: CamelotChat holding one message frame per Blizzard chat
-- window, each fed by a hook on its source's AddMessage, Blizzard's windows
-- and dock parked, and /camelot chat.
--
-- Blizzard's windows keep running under the park with every event
-- registered, so the formatter, the filters, the censoring, the whisper
-- sounds and the tell targets stay Blizzard's and untainted; what they draw
-- is copied across whole. Chat payloads can be secret in the chat messaging
-- lockdown and Blizzard's formatter does string work on them in secure
-- execution, which is why no line is ever formatted here: a secret string
-- goes into the twin's AddMessage, an elevation barrier, as it came. The
-- other mutators (Clear, the predicate removals, the color and text
-- transforms, BackFillMessage, SetMaxLines) resync the twin from the source's
-- own buffer, pass-through, because a replayed Blizzard closure would run
-- under this addon's taint and compare a possibly secret line id.
--
-- Never here: a call on or a hook of FCF_* or FCFDock_*, a call to the Edit
-- Mode overrides on ChatFrame1 (SetPoint, ClearAllPoints, SetScale, Hide,
-- SetShown), a field written on a Blizzard chat frame, or a read of
-- geometry or alpha off a chat-roleset frame inside a lockdown.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style

local Display = {}
CR.Display = Display

local OWNER = CR.OWNER

local built = false
local entries = {}         -- in twin creation order: { source, twin, id, name }
local bySource = {}        -- source -> entry
local pendingResync = {}   -- source -> true
local parked = {}          -- frame -> label
local counts = { mirrored = 0, secret = 0, hidden = 0, resyncs = 0, scans = 0, hooks = 0 }
local blocked = {}
local MAX_BLOCKED = 8
local captured
local selected             -- the entry whose twin shows
local lastMouse = 0
local chromeTarget
local alertHosts           -- what ChatAlertFrame held when parked

-- Each one a full resync of the twin.
local MUTATORS = { "Clear", "RemoveMessagesByPredicate", "AdjustMessageColors", "TransformMessages", "BackFillMessage", "SetMaxLines" }

-- The UIParent children that hang off Blizzard's chat, beside the windows.
local EXTRA_PARKS = {
    "GeneralDockManager",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    "QuickJoinToastButton", "TextToSpeechButtonFrame",
    "ChatAlertFrame",
}

-- The link kinds a hover tooltip draws; the rest open on click as Blizzard's.
local TOOLTIP_LINKS = {
    item = true, spell = true, achievement = true, quest = true, talent = true, enchant = true,
    currency = true, battlepet = true, battlePetAbil = true, keystone = true, mawpower = true,
    azessence = true, conduit = true, transmogappearance = true, transmogillusion = true,
}

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function holder()
    return Style.Frame()
end

--------------------------------------------------------------------------------
-- The twins
--------------------------------------------------------------------------------

local function onHyperlinkClick(twin, link, text, button)
    if isSecret(link) or isSecret(text) then return end
    -- Camelot's own link kind, the address lines.lua wrapped: the copy box.
    if type(link) == "string" and link:sub(1, 4) == "url:" then
        if CR.Menu then CR.Menu.CopyText("Copy the address", link:sub(5)) end
        return
    end
    local setItemRef = _G.SetItemRef
    if not setItemRef then return end
    -- The parked source window, not the twin, as the frame: Blizzard's
    -- ChooseBoxForSend reads `.editBox` off it in the im chat style.
    local entry = twin.camelotEntry
    setItemRef(link, text, button, entry and entry.source or twin)
end

local function onHyperlinkEnter(twin, link)
    if type(link) ~= "string" or isSecret(link) or not GameTooltip then return end
    local kind = link:match("^([^:]+):")
    if kind == "url" then
        GameTooltip:SetOwner(twin, "ANCHOR_CURSOR")
        GameTooltip:SetText(link:sub(5), 1, 1, 1)
        GameTooltip:AddLine("Click to copy", 0.8, 0.8, 0.8)
        GameTooltip:Show()
        return
    end
    if not (kind and TOOLTIP_LINKS[kind]) then return end
    GameTooltip:SetOwner(twin, "ANCHOR_CURSOR")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if ok then GameTooltip:Show() else GameTooltip:Hide() end
end

local function onHyperlinkLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function createTwin(entry)
    local h = holder()
    local name = (addon.Brand or "Camelot") .. "ChatWindow" .. tostring(entry.id)
    local twin = CreateFrame("ScrollingMessageFrame", name, h, "CamelotChatWindowTemplate")
    twin:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    twin:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    twin:SetFontObject(ChatFontNormal)
    twin:SetIndentedWordWrap(true)
    twin:SetJustifyH("LEFT")
    twin:SetHyperlinksEnabled(true)
    -- The scroll bar as FloatingChatFrameMixin:OnLoad places it: in the
    -- gutter at the window's right, above the scroll-to-bottom button.
    twin.ScrollBar:ClearAllPoints()
    twin.ScrollBar:SetPoint("TOPLEFT", twin, "TOPRIGHT", 0, 0)
    twin.ScrollBar:SetPoint("BOTTOMLEFT", h.ScrollToBottomButton, "TOPLEFT", 0, 2)
    local noWheel = not GetCVarBool(Style.MOUSE_SCROLL_CVAR)
    pcall(ScrollUtil.InitScrollingMessageFrameWithScrollBar, twin, twin.ScrollBar, noWheel)
    twin.ScrollBar:SetAlpha(0)
    twin:SetScript("OnHyperlinkClick", onHyperlinkClick)
    twin:SetScript("OnHyperlinkEnter", onHyperlinkEnter)
    twin:SetScript("OnHyperlinkLeave", onHyperlinkLeave)
    twin.camelotEntry = entry
    twin:Hide()
    return twin
end

--------------------------------------------------------------------------------
-- The bridge
--------------------------------------------------------------------------------

--- One line into the twin, or not: the Settings page's filter asks first
--- whether the window shows the line's group or channel, on the event name
--- and the packed payload Blizzard's formatter passes (config.lua, Shows).
--- Returns the event and whether the line went in.
local function mirrorLine(entry, text, r, g, b, ...)
    local event = select(4, ...)
    if CR.Config and not CR.Config.Shows(entry, event, (select(5, ...))) then
        counts.hidden = counts.hidden + 1
        return event, false
    end
    local t, rr, gg, bb = CR.Lines.Transform(text, r, g, b, event)
    entry.twin:AddMessage(t, rr, gg, bb, ...)
    return event, true
end

--- The twin rebuilt from the source's own buffer: Blizzard's copy loop
--- without its compare. Runs one frame after the mutator, in this addon's
--- own execution, never inside Blizzard's loop.
local function resyncNow(entry)
    local source, twin = entry.source, entry.twin
    counts.resyncs = counts.resyncs + 1
    pcall(function()
        twin:Clear()
        local max = source:GetMaxLines()
        if type(max) == "number" and not isSecret(max) and max > 0 and max ~= twin:GetMaxLines() then
            twin:SetMaxLines(max)
        end
        local n = source:GetNumMessages()
        for i = 1, n do
            local args = { source:GetMessageInfo(i) }
            mirrorLine(entry, args[1], args[2], args[3], args[4], unpack(args, 5, 12))
        end
    end)
end

function Display.Resync(source)
    local entry = bySource[source]
    if not entry or pendingResync[source] then return end
    pendingResync[source] = true
    C_Timer.After(0, function()
        pendingResync[source] = nil
        if bySource[source] then resyncNow(entry) end
    end)
end

--- Every twin rebuilt, for a formatting switch that changes what a line
--- shows: the lines already on screen take it too.
function Display.ResyncAll()
    for _, entry in ipairs(entries) do Display.Resync(entry.source) end
end

local function installHooks(entry)
    local source = entry.source
    hooksecurefunc(source, "AddMessage", function(_, text, r, g, b, ...)
        counts.mirrored = counts.mirrored + 1
        if isSecret(text) then counts.secret = counts.secret + 1 end
        -- A closed pop-out's lines land in the first window, where
        -- Blizzard's close would have sent them (CloseWindow)
        local target = entry.redirect or entry
        local event, shown = mirrorLine(target, text, r, g, b, ...)
        if shown and CR.Tabs then CR.Tabs.OnLine(target.source, event) end
    end)
    counts.hooks = counts.hooks + 1
    for _, method in ipairs(MUTATORS) do
        local ok = pcall(hooksecurefunc, source, method, function() Display.Resync(source) end)
        if ok then counts.hooks = counts.hooks + 1 end
    end
end

--------------------------------------------------------------------------------
-- The windows
--------------------------------------------------------------------------------

--- Blizzard's own list of window names, a global table of strings.
local function sourceList()
    local names = _G.CHAT_FRAMES
    if type(names) ~= "table" then return {} end
    local list = {}
    for _, name in ipairs(names) do
        if type(name) == "string" then
            local frame = _G[name]
            if type(frame) == "table" and frame.GetID and frame.AddMessage and frame.GetMessageInfo then
                list[#list + 1] = frame
            end
        end
    end
    return list
end

--- Every window in CHAT_FRAMES has a twin, a hook set and a backfill. New
--- windows (a whisper pop-out, a window from the tab menu) appear here on
--- the deferred scan, after Blizzard's own copy loop has finished.
function Display.Scan(reason)
    if not built then return end
    counts.scans = counts.scans + 1
    local changed = false
    for _, source in ipairs(sourceList()) do
        if not bySource[source] then
            local entry = { source = source, id = source:GetID(), name = source:GetName() }
            entry.twin = createTwin(entry)
            bySource[source] = entry
            entries[#entries + 1] = entry
            installHooks(entry)
            resyncNow(entry)
            changed = true
        end
    end
    if changed then
        Display.Claim()
        Display.ApplyText()
    end
    if CR.Tabs then CR.Tabs.Refresh() end
    counts.lastScan = reason
end

local function deferredScan(reason)
    return function()
        if not built then return end
        C_Timer.After(0, function() Display.Scan(reason) end)
    end
end

function Display.Entries()
    return entries
end

function Display.EntryFor(source)
    return bySource[source]
end

function Display.Selected()
    return selected
end

--- The tab strip picked a window. The combat log draws only while the
--- switch ChatFrame2's own OnShow flips is on, and a parked window never
--- runs its OnShow.
function Display.OnSelect(entry, previous)
    selected = entry
    Display.ApplyChromeColor()
    local combatLog = _G.COMBATLOG
    local api = _G.C_CombatLog
    if not (combatLog and api and api.SetFilteredEventsEnabled) then return end
    if previous and previous.source == combatLog and entry.source ~= combatLog then
        pcall(api.SetFilteredEventsEnabled, false)
    end
    if entry and entry.source == combatLog then
        pcall(api.SetFilteredEventsEnabled, true)
    end
end

--- The menu closed a window: its twin and tab go. A cached window closes
--- in the chat cache too, and Blizzard's login pass finishes it (menu.lua);
--- a pop-out's later lines are sent on to the first window, since Blizzard's
--- parked frame keeps them from the first window while it stands.
function Display.CloseWindow(entry, redirect)
    if not entry or entry.closed then return end
    entry.closed = true
    entry.twin:Hide()
    if redirect then
        for _, e in ipairs(entries) do
            if e.id == 1 and e ~= entry then
                entry.redirect = e
                break
            end
        end
    end
    if CR.Tabs then CR.Tabs.Refresh() end
end

--- Make Noninteractive: a window's links take no click, the one thing
--- FCF_SetUninteractable changes on the frame; each twin follows its flag.
function Display.ApplyInteractable()
    for _, entry in ipairs(entries) do
        entry.twin:SetHyperlinksEnabled(not Style.Uninteractable(entry))
    end
end

--------------------------------------------------------------------------------
-- The park
--------------------------------------------------------------------------------
-- Every window, the dock (every docked tab is its child after the first dock
-- pass, so no tab is parked on its own), and the UIParent children that hang
-- off the chat. Never released: the Features switch lands at reload, and a
-- feature off at login never claims. The park is skipped in combat and while
-- Edit Mode is open, and paid by NativeFrame's retry.

local function park(frame, label)
    if not (frame and addon.NativeFrame) then return end
    if parked[frame] then return end
    if not addon.NativeFrame:IsSuppressed(frame) then
        addon.NativeFrame:Suppress(frame, OWNER, "park")
    end
    parked[frame] = label or true
end

local function describeAlertFrame()
    local frame = _G.ChatAlertFrame
    if not frame or alertHosts then return end
    local ok, names = pcall(function()
        local list = {}
        for _, child in ipairs({ frame:GetChildren() }) do
            list[#list + 1] = child.GetName and child:GetName() or "unnamed"
        end
        return table.concat(list, ", ")
    end)
    alertHosts = ok and (names ~= "" and names or "no children") or "unreadable"
end

function Display.Claim()
    if not CR.IsEnabled() then return end
    for _, entry in ipairs(entries) do
        park(entry.source, entry.name)
        -- An undocked window's tab leaves the dock for UIParent or the
        -- fullscreen frame; a docked one is the dock's child.
        local tab = _G[entry.name .. "Tab"]
        if tab then
            local ok, parent = pcall(tab.GetParent, tab)
            if ok and (parent == UIParent or parent == _G.FullscreenFrame) then
                park(tab, entry.name .. "Tab")
            end
        end
    end
    describeAlertFrame()
    for _, name in ipairs(EXTRA_PARKS) do
        park(_G[name], name)
    end
end

--------------------------------------------------------------------------------
-- The default position
--------------------------------------------------------------------------------
-- Where Blizzard's ChatFrame1 stood before the park, as a BOTTOMLEFT record
-- on UIParent in UIParent's scale with its size beside it, read once at the
-- first build. When the rect cannot be read, or reads secret at a reload
-- inside a lockdown, Blizzard's XML anchor and the Edit Mode preset's size.

local function plain(v)
    return type(v) == "number" and not isSecret(v)
end

function Display.CaptureDefault()
    if captured then return captured end
    local source = _G.ChatFrame1
    local ok, left, bottom, width, height, scale = pcall(function()
        return source:GetLeft(), source:GetBottom(), source:GetWidth(), source:GetHeight(), source:GetEffectiveScale()
    end)
    local uiScale = UIParent:GetEffectiveScale()
    if ok and plain(left) and plain(bottom) and plain(width) and plain(height) and plain(scale) and uiScale > 0 then
        captured = {
            point = "BOTTOMLEFT",
            x = left * scale / uiScale,
            y = bottom * scale / uiScale,
            width = width,
            height = height,
            source = "ChatFrame1's rect before the park",
        }
    else
        local anchor, size = Style.XML_ANCHOR, Style.XML_SIZE
        captured = {
            point = anchor.point, x = anchor.x, y = anchor.y,
            width = size.width, height = size.height,
            source = "Blizzard's XML anchor and the Edit Mode preset's size",
        }
    end
    return captured
end

--------------------------------------------------------------------------------
-- Size, scale, chrome, text
--------------------------------------------------------------------------------

function Display.ApplySize()
    local h = holder()
    if not h then return end
    h:SetSize(Style.Width(), Style.Height())
end

--- Scale is the holder's scale. The positionable's offsets are in the
--- holder's own scale, so a scale change re-lands the position through the
--- store, which keeps the anchor point where it was (editmode.lua).
function Display.ApplyScale()
    local h = holder()
    if not h then return end
    local scale = Style.Scale()
    if math.abs(h:GetScale() - scale) >= 0.0001 then
        h:SetScale(scale)
        if CR.EditMode then CR.EditMode.OnScaleChanged() end
    end
    if CR.EditBox then CR.EditBox.SetScale(scale) end
end

--- The tint: every texture on the chrome takes the selected window's color
--- from the chat cache, black by default, the SetVertexColor write
--- FCF_SetWindowColor makes on the Blizzard window; the files draw white
--- untinted. Blizzard's docked windows each carry their own textures, so the
--- color follows the selection as it does there.
function Display.ApplyChromeColor()
    local h = holder()
    if not h then return end
    local r, g, b = Style.BackgroundColor(selected and selected.id)
    for _, region in ipairs({ h.Chrome:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:SetVertexColor(r, g, b) end
    end
end

--- The background over the window and the scroll bar's gutter, Blizzard's
--- own anchors (FloatingChatFrame_UpdateBackgroundAnchors); the eight border
--- textures hang off it. The alpha starts at the selected window's rest; the
--- ticker owns it from there.
function Display.ApplyChrome()
    local h = holder()
    if not h then return end
    local bg = h.Chrome.Background
    local gutter = Style.SCROLL_GUTTER
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", h, "TOPLEFT", -2, 3)
    bg:SetPoint("TOPRIGHT", h, "TOPRIGHT", gutter, 3)
    bg:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", -2, -6)
    bg:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", gutter, -6)
    Display.ApplyChromeColor()
    chromeTarget = Style.BackgroundOpacity(selected and selected.id)
    h.Chrome:SetAlpha(chromeTarget)
end

function Display.ApplyText()
    local face, style = Style.FontFace(), Style.FontStyle()
    local fade, visible = Style.Get("fadeLines") == true, Style.TimeVisible()
    for _, entry in ipairs(entries) do
        local twin = entry.twin
        -- The size is the window's own from the chat cache unless the Size
        -- row overrides it (style.lua, FontSize).
        pcall(addon.ApplyFontStyle, twin, face, Style.FontSize(entry.id), style)
        twin:SetFading(fade)
        twin:SetTimeVisible(visible)
    end
end

--------------------------------------------------------------------------------
-- The chrome ticker
--------------------------------------------------------------------------------
-- Blizzard's own reveal, FCF_FadeInChatFrame and FCF_FadeOutChatFrame: the
-- textures rest at the window's alpha and rise to at least
-- DEFAULT_CHATFRAME_ALPHA under the mouse, in 0.15 s, falling back over 2 s.
-- Idle Fade takes them to nothing after the delay. The scroll bar shows under
-- the mouse, the scroll-to-bottom button while the window is scrolled up.
-- Every read is on a Camelot frame.

local FADE_IN, FADE_OUT = 0.15, 2.0
local STRIP_REACH = 35

local function fadeChrome(chrome, target)
    local fadeIn, fadeOut = _G.UIFrameFadeIn, _G.UIFrameFadeOut
    local current = chrome:GetAlpha()
    if fadeIn and fadeOut then
        if target > current then
            fadeIn(chrome, FADE_IN, current, target)
        else
            fadeOut(chrome, FADE_OUT, current, target)
        end
    else
        chrome:SetAlpha(target)
    end
end

local function tick()
    local h = holder()
    if not (h and h:IsShown()) then return end
    -- The hit rect reaches up over the strip's place (32 high, 3 above, frames.xml)
    -- so the mouse where the tabs stand shows them while they are hidden.
    local over = h:IsMouseOver(STRIP_REACH, 0, 0, 0)
    local now = GetTime()
    if over then lastMouse = now end

    if CR.Tabs then CR.Tabs.SetMouse(over) end

    local twin = selected and selected.twin
    if twin then
        twin.ScrollBar:SetAlpha(over and 1 or 0)
        local atBottom = twin:AtBottom()
        local button = h.ScrollToBottomButton
        button:SetAlpha(atBottom and 0 or 1)
        local anim = button.Flash.FlashAnim
        if not atBottom and not anim:IsPlaying() then
            button.Flash:Show()
            anim:Play()
        elseif atBottom and anim:IsPlaying() then
            anim:Stop()
            button.Flash:Hide()
        end
    end

    local rest = Style.BackgroundOpacity(selected and selected.id)
    local hover = math.max(rest, tonumber(_G.DEFAULT_CHATFRAME_ALPHA) or 0.25)
    local target = rest
    if over then
        target = hover
    elseif Style.Get("idleFade") == true and (now - lastMouse) > Style.IdleFadeDelay() then
        target = 0
    end
    if chromeTarget ~= target then
        chromeTarget = target
        fadeChrome(h.Chrome, target)
    end
end

--------------------------------------------------------------------------------
-- Scroll bindings
--------------------------------------------------------------------------------
-- CHATPAGEUP, CHATPAGEDOWN and CHATBOTTOM call the selected Blizzard window's
-- methods through ChatFrameUtil; a post-hook on each pages the selected twin
-- too. A plain table hook, never one on a chat frame's method.

local SCROLL_HOOKS = {
    ChatPageUp = "PageUp", ChatPageDown = "PageDown",
    ScrollToBottom = "ScrollToBottom", ScrollUp = "ScrollUp", ScrollDown = "ScrollDown",
}

local function hookScrollBindings()
    local util = _G.ChatFrameUtil
    if type(util) ~= "table" then return end
    for name, method in pairs(SCROLL_HOOKS) do
        if type(util[name]) == "function" then
            pcall(hooksecurefunc, util, name, function()
                local twin = selected and selected.twin
                if twin and twin[method] then twin[method](twin) end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- The bus hands a handler the event name first, then the payload.
local function onBlocked(event, addonNameBlocked, action)
    if type(action) ~= "string" then return end
    if not (action:find("ChatFrame", 1, true) or action:find("Chat", 1, true)) then return end
    table.insert(blocked, 1, string.format("%s %s %s at %.1f", event, tostring(addonNameBlocked), action, GetTime()))
    if #blocked > MAX_BLOCKED then table.remove(blocked) end
end

local function wireEvents()
    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", function()
        if built then Display.Claim() end
    end)
    addon.Events.On(OWNER, "UPDATE_CHAT_WINDOWS", deferredScan("UPDATE_CHAT_WINDOWS"))
    addon.Events.On(OWNER, "UPDATE_FLOATING_CHAT_WINDOWS", deferredScan("UPDATE_FLOATING_CHAT_WINDOWS"))
    addon.Events.On(OWNER, "CHAT_MSG_WHISPER", deferredScan("CHAT_MSG_WHISPER"))
    addon.Events.On(OWNER, "CHAT_MSG_BN_WHISPER", deferredScan("CHAT_MSG_BN_WHISPER"))
    addon.Events.On(OWNER, "ADDON_ACTION_BLOCKED", onBlocked)
    addon.Events.On(OWNER, "ADDON_ACTION_FORBIDDEN", onBlocked)
end

function Display.Build()
    if built or not CR.IsEnabled() then return end
    local h = holder()
    if not (h and _G.ChatFrame1) then return end

    -- Kept off addon.Strata.ApplyHUD: ChatFrame1 is LOW at level 5, and the
    -- edit box drops itself to LOW when it closes; a holder above LOW would
    -- sit over the closed box.
    h:SetFrameStrata("LOW")
    h:SetFrameLevel(5)
    addon.RegisterPetBattleFrame(h)

    Display.CaptureDefault()
    h.ScrollToBottomButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHAT_BOTTOM)
        local twin = selected and selected.twin
        if twin then twin:ScrollToBottom() end
    end)
    wireEvents()
    hookScrollBindings()
    built = true

    -- The twins and their hooks, then the park, so a line that lands between
    -- the two still reaches a twin; the park before the positionable, so
    -- Blizzard's own selection box is gone when Edit Mode next opens.
    Display.Scan("build")
    -- What each window listens to at login, for the Settings page's reload rule
    if CR.Config then CR.Config.Snapshot() end
    Display.Claim()
    h:Show()
    if CR.Tabs then CR.Tabs.Build(h) end
    Style.Apply()
    if CR.EditMode then CR.EditMode.Register(h) end
    if CR.Dynamic then CR.Dynamic.Register(h) end
    Display.ticker = C_Timer.NewTicker(0.1, tick)
end

function Display.IsBuilt()
    return built
end

-- One frame after world entry, so login's own UPDATE_CHAT_WINDOWS pass has
-- selected ChatFrame1 and hidden the rest before anything is parked.
addon.Events.OnWorldEntered(function()
    C_Timer.After(0, Display.Build)
end)

--------------------------------------------------------------------------------
-- /camelot chat
--------------------------------------------------------------------------------

local function frameLine(push, label, frame)
    if not frame then
        push("  %s: absent", label)
        return
    end
    local ok, text = pcall(function()
        local parent = frame:GetParent()
        local point, rel, relPoint, x, y = frame:GetPoint(1)
        return string.format("parent %s, shown %s, visible %s, alpha %.2f, scale %.2f, size %.0f x %.0f, strata %s level %d, point %s to %s %s (%.1f, %.1f)",
            parent and parent:GetName() or tostring(parent), tostring(frame:IsShown()), tostring(frame:IsVisible()),
            frame:GetAlpha(), frame:GetScale(), frame:GetWidth(), frame:GetHeight(),
            tostring(frame:GetFrameStrata()), frame:GetFrameLevel(),
            tostring(point), rel and rel.GetName and rel:GetName() or tostring(rel), tostring(relPoint), x or 0, y or 0)
    end)
    push("  %s: %s", label, ok and text or ("unreadable: " .. tostring(text)))
end

local function protectedLine(frame)
    if not frame then return "absent" end
    local ok, isProtected, explicitly = pcall(frame.IsProtected, frame)
    if not ok then return "unreadable" end
    return string.format("%s (explicit %s)", tostring(isProtected), tostring(explicitly))
end

local function secureLine(frame, key)
    if not frame then return "absent" end
    local check = _G.issecurevariable
    if not check then return "no issecurevariable" end
    local ok, secure = pcall(check, frame, key)
    if not ok then return "unreadable" end
    return tostring(secure)
end

function Display.Dump()
    local lines, push = addon.DebugLines()
    local h = holder()
    local chatInfo = _G.C_ChatInfo
    local lockdown = chatInfo and chatInfo.InChatMessagingLockdown and chatInfo.InChatMessagingLockdown()
    push("Camelot chat: enabled %s, built %s, combat lockdown %s, chat messaging lockdown %s, editing %s",
        tostring(CR.IsEnabled()), tostring(built), tostring(InCombatLockdown()), tostring(lockdown),
        tostring(addon.EditMode and addon.EditMode.IsEditing and addon.EditMode.IsEditing()))
    frameLine(push, "holder", h)
    frameLine(push, "ChatFrame1", _G.ChatFrame1)
    frameLine(push, "GeneralDockManager", _G.GeneralDockManager)
    push("  ChatFrame1 protected: %s; edit box protected: %s", protectedLine(_G.ChatFrame1), protectedLine(_G.ChatFrame1EditBox))
    push("  ChatFrame1.AddMessage secure: %s; tellTimer secure: %s", secureLine(_G.ChatFrame1, "AddMessage"), secureLine(_G.ChatFrame1, "tellTimer"))
    push("  lines mirrored %d (secret %d, hidden by the Settings page %d), resyncs %d, scans %d (last %s), hooks %d",
        counts.mirrored, counts.secret, counts.hidden, counts.resyncs, counts.scans, tostring(counts.lastScan), counts.hooks)
    local d = captured
    push("  default position: %s", d and string.format("%s (%.1f, %.1f) %.0f x %.0f from %s", d.point, d.x, d.y, d.width, d.height, d.source) or "not captured")
    push("  settings: width %d, height %d, scale %d%%, background %.2f, box %s, font %s %d %s, show tabs %s, flash %s",
        Style.Width(), Style.Height(), Style.ScalePercent(), Style.BackgroundOpacity(),
        Style.EditBoxAbove() and "above" or "below", Style.FontFace(), Style.FontSize(), tostring(Style.FontStyle()),
        tostring(Style.Get("showTabs")), tostring(Style.Get("tabFlash")))
    push("  cvars: %s %s, %s %s, chatStyle %s, whisperMode %s",
        Style.CLASS_COLOR_CVAR, tostring(GetCVar(Style.CLASS_COLOR_CVAR)),
        Style.TIMESTAMP_CVAR, tostring(GetCVar(Style.TIMESTAMP_CVAR)),
        tostring(GetCVar("chatStyle")), tostring(GetCVar("whisperMode")))
    push("  windows (%d):", #entries)
    for _, entry in ipairs(entries) do
        local ok, text = pcall(function()
            local parent = entry.source:GetParent()
            local _, size, cr, cg, cb, ca = Style.Cache(entry.id)
            return string.format("%s: parent %s, %d lines; twin %d lines, max %d, %s; cache size %s, color %s %s %s, alpha %s, links %s%s",
                entry.name, parent and parent:GetName() or tostring(parent), entry.source:GetNumMessages(),
                entry.twin:GetNumMessages(), entry.twin:GetMaxLines(), entry.twin:IsShown() and "shown" or "hidden",
                tostring(size), tostring(cr), tostring(cg), tostring(cb), tostring(ca),
                entry.twin:IsHyperlinksEnabled() and "on" or "off", entry.closed and ", closed" or "")
        end)
        push("    %s", ok and text or (tostring(entry.name) .. ": unreadable"))
    end
    push("  parked:")
    for frame, label in pairs(parked) do
        local ok, parent = pcall(frame.GetParent, frame)
        push("    %s: parent %s", tostring(label), ok and (parent and parent:GetName() or tostring(parent)) or "unreadable")
    end
    push("  ChatAlertFrame held: %s", tostring(alertHosts))
    if CR.Tabs then CR.Tabs.Describe(push) end
    if CR.Menu then CR.Menu.Describe(push) end
    if CR.Config then CR.Config.Describe(push) end
    if CR.EditBox then CR.EditBox.Describe(push) end
    if CR.Dynamic then push("  dynamic layouts: %s", CR.Dynamic.Describe()) end
    push("  blocked actions naming the chat (%d):", #blocked)
    for _, line in ipairs(blocked) do push("    %s", line) end
    addon.DebugShowWindow("Camelot chat", lines)
end

addon:RegisterSlashCommand({
    name = "chat",
    help = "show the chat replica: the holder, the twins, the parked windows, the hooks, the edit box and the blocked actions",
    handler = function() Display.Dump() end,
})

-- chat.lua - Chat frame visibility controller
local addonName, addon = ...
-- Goal: allow ScooterDeck users to fully hide the stock in-game chat UI.
-- Constraints:
--  - Lightweight (no OnUpdate polling)
--  - Persist through UI reloads and incidental Blizzard Show() calls
--  - No method overrides; only hooksecurefunc + re-apply on relevant events

addon.Chat = addon.Chat or {}
local Chat = addon.Chat

local function SafeCall(obj, method, ...)
    if not obj or not method then return end
    local fn = obj[method]
    if type(fn) ~= "function" then return end
    pcall(fn, obj, ...)
end

local function SafePCall(fn, ...)
    if type(fn) ~= "function" then return end
    pcall(fn, ...)
end

local function getProfileSetting()
    local profile = addon and addon.db and addon.db.profile
    local chat = profile and rawget(profile, "chat") or nil
    return chat and chat.hideInGameChat == true
end

local function ResolveChatFrames()
    local out = {}

    local function addFrame(name)
        local f = _G and _G[name]
        if f then
            out[name] = f
        end
    end

    -- Primary chat frames (all windows)
    local total = (type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS) or 10
    for i = 1, total do
        addFrame("ChatFrame" .. i)
        addFrame("ChatFrame" .. i .. "Tab")
        addFrame("ChatFrame" .. i .. "ButtonFrame")
    end

    -- Shared controls / container-ish frames
    addFrame("ChatFrameMenuButton")
    addFrame("ChatFrameChannelButton")
    addFrame("GeneralDockManager")
    addFrame("QuickJoinToastButton")
    addFrame("ChatFrameToggleVoiceDeafenButton")
    addFrame("ChatFrameToggleVoiceMuteButton")

    return out
end

local function CaptureBaseline(self, name, frame)
    self._baselines = self._baselines or {}
    if self._baselines[name] then
        return
    end
    local baseline = {}
    baseline.shown = frame.IsShown and frame:IsShown() or false
    baseline.alpha = frame.GetAlpha and frame:GetAlpha() or 1
    baseline.scale = frame.GetScale and frame:GetScale() or 1
    baseline.mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or false
    self._baselines[name] = baseline
end

local function ApplyHidden(self, name, frame)
    CaptureBaseline(self, name, frame)
    -- Hide as hard as possible without doing anything tainty.
    SafeCall(frame, "EnableMouse", false)
    SafeCall(frame, "SetAlpha", 0)
    SafeCall(frame, "Hide")
end

local function RestoreBaseline(self, name, frame)
    local baseline = self._baselines and self._baselines[name] or nil
    if not baseline then
        -- Zero-touch: if this frame was never hidden (no baseline captured),
        -- skip it. Never force-show chat frames.
        return
    end

    SafeCall(frame, "SetAlpha", baseline.alpha or 1)
    if baseline.scale and frame.SetScale then
        SafeCall(frame, "SetScale", baseline.scale)
    end
    if baseline.mouse ~= nil then
        SafeCall(frame, "EnableMouse", baseline.mouse and true or false)
    end
    if baseline.shown then
        SafeCall(frame, "Show")
    else
        SafeCall(frame, "Hide")
    end
end

local function HookFrame(self, name, frame)
    self._hooked = self._hooked or {}
    if self._hooked[name] then
        return
    end
    self._hooked[name] = true

    -- If Blizzard (or another addon) tries to show chat, immediately re-hide if desired.
    if frame.Show then
        hooksecurefunc(frame, "Show", function()
            if addon and addon.Chat and addon.Chat.IsHidden and addon.Chat:IsHidden() then
                ApplyHidden(addon.Chat, name, frame)
            end
        end)
    end
    if frame.SetShown then
        hooksecurefunc(frame, "SetShown", function(_, shown)
            if shown and addon and addon.Chat and addon.Chat.IsHidden and addon.Chat:IsHidden() then
                ApplyHidden(addon.Chat, name, frame)
            end
        end)
    end
end

function Chat:IsHidden()
    return getProfileSetting()
end

function Chat:ApplyFromProfile(reason)
    local shouldHide = getProfileSetting()

    -- Zero-touch: when chat hiding is disabled and nothing was hidden this session, skip.
    if not shouldHide then
        if not (self._baselines and next(self._baselines)) then
            return
        end
    end

    local frames = ResolveChatFrames()
    for name, frame in pairs(frames) do
        if shouldHide then
            HookFrame(self, name, frame)
            ApplyHidden(self, name, frame)
        else
            RestoreBaseline(self, name, frame)
        end
    end

    self._lastApplyReason = reason
end

function Chat:Initialize()
    if self._initialized then
        return
    end
    self._initialized = true

    -- Lightweight event-based re-apply for cases where the chat UI is rebuilt.
    local function onChatEvent()
        if addon and addon.Chat and addon.Chat.ApplyFromProfile then
            addon.Chat:ApplyFromProfile("ChatEvent")
        end
    end
    addon.Events.On("Chat", "PLAYER_ENTERING_WORLD", onChatEvent)
    addon.Events.On("Chat", "UPDATE_CHAT_WINDOWS", onChatEvent)
    addon.Events.On("Chat", "UPDATE_FLOATING_CHAT_WINDOWS", onChatEvent)

    self:ApplyFromProfile("Initialize")
end



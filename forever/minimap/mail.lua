--------------------------------------------------------------------------------
-- forever/minimap/mail.lua
-- The mail indicator: Blizzard's envelope in its image, a child of the holder,
-- shown while HasNewMail() is true. Placed like the tracking button: "dock"
-- is Blizzard's spot under the tracking button (or left of the plate when
-- the tracking button is not in the dock), else one of the nine points.
--
-- Blizzard's MailFrame stays parked inside IndicatorFrame and keeps its own
-- UPDATE_PENDING_MAIL handler and the notifiedOfNewMail CVar; nothing here
-- reads or writes it. The two flipbooks are replayed on Camelot's own
-- textures: the new-mail one when mail arrives during the session, the
-- reminder one when the envelope first shows at login.
--
-- In Edit Mode the envelope shows with or without mail, so the player can
-- see where it sits.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MR = addon.MinimapReplica
local Style = MR.Style

local Mail = {}
MR.Mail = Mail

-- Blizzard's frame is 20 by 15 with the envelope at its atlas size
-- (Blizzard_Minimap/Mainline/Minimap.xml, IndicatorFrame.MailFrame); the
-- flipbooks are 52 by 52 centred on it.
local BASE_W, BASE_H = 20, 15
local FLIPBOOK_SIZE = 52

-- The text's rule for a nine-point position (text.lua, placeMapText).
local INSET_X = 6
local TOP_DROP = 6

local OWNER = MR.OWNER .. ":mail"

local frame
local hadMail          -- nil until the first read, then the last HasNewMail()

local function notificationsDisabled()
    if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum.GameRule and Enum.GameRule.IngameMailNotificationDisabled) then
        return false
    end
    local ok, disabled = pcall(C_GameRules.IsGameRuleActive, Enum.GameRule.IngameMailNotificationDisabled)
    return ok and disabled == true
end

local function hasMail()
    if not HasNewMail then return false end
    local ok, value = pcall(HasNewMail)
    return ok and value == true
end

local function editing()
    return addon.EditMode and addon.EditMode.IsEditing and addon.EditMode.IsEditing() or false
end

-- Blizzard's tooltip (MinimapMailFrameUpdate).
local function onEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if hasMail() and GetLatestThreeSenders and FormatUnreadMailTooltip then
        local senders = { GetLatestThreeSenders() }
        local header = #senders >= 1 and _G.HAVE_MAIL_FROM or _G.HAVE_MAIL
        FormatUnreadMailTooltip(GameTooltip, header, senders)
    else
        GameTooltip:SetText(_G.MAIL_LABEL or "Mail", 1, 1, 1)
    end
    GameTooltip:Show()
end

-- One flipbook: an Alpha to 1 then the FlipBook, the icon hidden while it
-- plays (MinimapMailAnimMixin).
local function buildFlipbook(parent, atlas, duration, rows, columns, frames)
    local texture = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    texture:SetAtlas(atlas)
    texture:SetSize(FLIPBOOK_SIZE, FLIPBOOK_SIZE)
    texture:SetPoint("CENTER", parent.Icon)
    texture:SetAlpha(0)

    local group = parent:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetTarget(texture)
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0)
    alpha:SetOrder(0)
    local flip = group:CreateAnimation("FlipBook")
    flip:SetTarget(texture)
    flip:SetDuration(duration)
    flip:SetOrder(1)
    flip:SetFlipBookRows(rows)
    flip:SetFlipBookColumns(columns)
    flip:SetFlipBookFrames(frames)
    flip:SetFlipBookFrameWidth(0)
    flip:SetFlipBookFrameHeight(0)
    group:SetScript("OnPlay", function() parent.Icon:Hide() end)
    group:SetScript("OnFinished", function()
        texture:SetAlpha(0)
        parent.Icon:Show()
    end)
    return texture, group
end

local function stopAnims()
    if not frame then return end
    frame.NewMailAnim:Stop()
    frame.ReminderAnim:Stop()
    frame.NewMailFlipbook:SetAlpha(0)
    frame.ReminderFlipbook:SetAlpha(0)
    frame.Icon:Show()
end

--- The frame, once, from display.lua's Build.
function Mail.Build(holder)
    if frame then return end
    frame = CreateFrame("Frame", nil, holder)
    frame:SetSize(BASE_W, BASE_H)
    frame:SetFrameLevel(holder:GetFrameLevel() + 4)
    frame:EnableMouse(true)

    frame.Icon = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    frame.Icon:SetAtlas("ui-hud-minimap-mail-up")
    frame.Icon:SetAllPoints(frame)

    frame.NewMailFlipbook, frame.NewMailAnim =
        buildFlipbook(frame, "UI-HUD-Minimap-Mail-New-Flipbook", 0.5, 5, 4, 20)
    frame.ReminderFlipbook, frame.ReminderAnim =
        buildFlipbook(frame, "UI-HUD-Minimap-Mail-Reminder-Flipbook", 0.4, 3, 4, 12)

    frame:SetScript("OnEnter", onEnter)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnHide", stopAnims)
    frame:Hide()

    addon.Events.On(OWNER, "UPDATE_PENDING_MAIL", function()
        Mail.Apply()
        if frame:IsShown() and GameTooltip:IsOwned(frame) then onEnter(frame) end
    end)
    if addon.EditMode and addon.EditMode.OnEditMode then
        addon.EditMode.OnEditMode(OWNER, {
            enter = function() Mail.Apply() end,
            exit = function() Mail.Apply() end,
        })
    end
end

local function place(holder)
    local size = tonumber(Style.Get("mailSize")) or BASE_W
    local k = size / BASE_W
    frame:SetSize(BASE_W * k, BASE_H * k)
    frame.NewMailFlipbook:SetSize(FLIPBOOK_SIZE * k, FLIPBOOK_SIZE * k)
    frame.ReminderFlipbook:SetSize(FLIPBOOK_SIZE * k, FLIPBOOK_SIZE * k)

    local position = Style.Get("mailPosition") or "dock"
    frame:ClearAllPoints()
    if position == "dock" then
        -- Blizzard's IndicatorFrame: under the tracking button when it shows
        -- in the dock, else left of the plate (MiniMapIndicatorFrame_UpdatePosition).
        local tracking = MR.Tracking and MR.Tracking.Frame()
        if tracking and tracking:IsShown() and (Style.Get("trackingPosition") or "dock") == "dock" then
            frame:SetPoint("TOPRIGHT", tracking, "BOTTOMRIGHT", 2, -1)
        else
            frame:SetPoint("TOPRIGHT", holder.Header, "TOPLEFT", -1, -1)
        end
        return Style.Get("dockHide") ~= true
    end
    local x = tonumber(Style.Get("mailOffsetX")) or 0
    local y = tonumber(Style.Get("mailOffsetY")) or 0
    if position:find("LEFT") then
        x = x + INSET_X
    elseif position:find("RIGHT") then
        x = x - INSET_X
    end
    if position:find("TOP") then y = y - TOP_DROP end
    frame:SetPoint(position, holder, position, x, y)
    return true
end

function Mail.Apply()
    local holder = Style.Frame()
    if not (holder and frame) then return end

    if Style.Get("mailHide") == true or notificationsDisabled() then
        frame:Hide()
        return
    end

    local visible = place(holder)
    local mail = hasMail()
    local previewing = editing()
    if not (visible and (mail or previewing)) then
        frame:Hide()
        hadMail = mail
        return
    end

    local wasShown = frame:IsShown()
    frame:Show()
    if mail and not previewing and not wasShown then
        if hadMail == false then
            frame.NewMailAnim:Restart()
        else
            frame.ReminderAnim:Restart()
        end
    end
    hadMail = mail
end

--- Lines for /camelot map.
function Mail.Describe(push)
    push("  mail: position %s, hide %s, size %s, has mail %s, rule off %s, shown %s",
        tostring(Style.Get("mailPosition")), tostring(Style.Get("mailHide")),
        tostring(Style.Get("mailSize")), tostring(hasMail()),
        tostring(notificationsDisabled()), tostring(frame and frame:IsShown()))
end

-- invite.lua - the invite dialog: the group that invited the player, its
-- activity, the role the player is in for, and Accept or Decline; or the
-- notice that the group was joined, with OK.
--
-- Blizzard shows its own dialog on its own events whether or not the
-- window is up, and holds the next pending invite while it is shown, so
-- this dialog is a view of Blizzard's: the host parks that frame as it
-- shows and says so, this one opens from its fields, and Accept, Decline
-- and OK run Blizzard's own handlers with its frame, which hide it and
-- look for the next invite; this one closes on the hide. No sound of its
-- own: Blizzard's plays as its frame shows.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Str = GF.Str

local Invite = {}
UI.Invite = Invite

local dialog
local parts = {}

local function SetTextSafe(fs, value)
    if type(value) == "string" then
        fs:SetText(value)
    else
        fs:SetText("")
    end
end

-- A line of the stack, the holder's width, centred and on one line
local function StackLine(fs, anchor, gap)
    fs:SetPoint("TOPLEFT", anchor, anchor == parts.holder and "TOPLEFT" or "BOTTOMLEFT", 0, -gap)
    fs:SetPoint("RIGHT", parts.holder, "RIGHT", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    return fs
end

local function Build()
    local L = LAYOUT.invite
    local S = L.sizes
    dialog = addon.UI.WindowShell.Create({
        name = addon.Brand .. "GroupFinderInvite",
        width = L.width,
        height = L.height,
        role = "dialog",
        titleHeight = L.padTop,
        movable = false,
        escape = false,
        closeButton = false,
        strata = "DIALOG",
        level = LAYOUT.dialogLevel,
    })
    dialog:Hide()

    local padX = L.padX
    -- The text's holder, sized and centred by Layout
    parts.holder = CreateFrame("Frame", nil, dialog)
    parts.holder:SetWidth(L.width - 2 * padX)

    parts.label = StackLine(UI.DimText(dialog, "desc", S.label), parts.holder, 0)
    parts.name = StackLine(UI.PrimaryText(dialog, "label", S.name), parts.label, L.gap)
    parts.activity = StackLine(UI.DimText(dialog, "desc", S.activity), parts.name, L.lineGap)
    parts.roleCaption = StackLine(UI.DimText(dialog, "miniLabel", S.caption), parts.activity, L.gap)
    parts.roleCaption:SetText(Str("YOUR_ROLE", "Your role"))
    parts.role = StackLine(UI.PrimaryText(dialog, "label", S.role), parts.roleCaption, L.lineGap)

    parts.offline = UI.DimText(dialog, "desc")
    parts.offline:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", padX, L.offlineY)
    parts.offline:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -padX, L.offlineY)
    parts.offline:SetJustifyH("CENTER")
    parts.offline:SetWordWrap(true)
    parts.offline:Hide()

    parts.accept = UI.MakeButton(dialog, Str("ACCEPT", "Accept"), function() Invite:Accept() end, L.buttonWidth)
    parts.accept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -5, L.buttonY)
    parts.decline = UI.MakeButton(dialog, Str("DECLINE", "Decline"), function() Invite:Decline() end, L.buttonWidth)
    parts.decline:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 5, L.buttonY)
    parts.ok = UI.MakeButton(dialog, Str("OKAY", "OK"), function() Invite:Acknowledge() end, L.buttonWidth)
    parts.ok:SetPoint("BOTTOM", dialog, "BOTTOM", 0, L.buttonY)
end

-- From Blizzard's frame: the result it shows, the application's status
-- and role, the group's name from the result or from the frame's own
-- text when the result is gone (a joined group's notice)
function Invite:Open()
    local blizzard = LFGListInviteDialog
    local id = blizzard and GF.plainNumber(blizzard.resultID)
    if not id then return end
    if not dialog then Build() end
    self.resultID = id
    local _, status, _, _, role = GF.Application(id)
    local informational = status ~= "invited"
    self.informational = informational
    self.sawOffline = false

    if informational then
        parts.label:SetText(Str("LFG_LIST_JOINED_GROUP_NOTICE", "You have joined the group"))
    else
        parts.label:SetText(Str("LFG_LIST_INVITED_TO_GROUP", "You have been invited to a group"))
    end
    local info = GF.ResultInfo(id)
    local name = info and info.name
    if type(name) ~= "string" and blizzard.GroupName and blizzard.GroupName.GetText then
        local ok, text = pcall(blizzard.GroupName.GetText, blizzard.GroupName)
        if ok then name = text end
    end
    SetTextSafe(parts.name, name)
    SetTextSafe(parts.activity, info and GF.ActivityName(info))
    local hasRole = type(role) == "string"
    parts.role:SetText(hasRole and Str(role, role) or "")
    parts.role:SetShown(hasRole)
    parts.roleCaption:SetShown(hasRole)
    parts.accept:SetShown(not informational)
    parts.decline:SetShown(not informational)
    parts.ok:SetShown(informational)
    self:RefreshOffline()

    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:Show()
    dialog:Raise()
end

-- The offline notice while a member of the player's own group is away,
-- and the all-clear once it was shown, as Blizzard's dialog says them
function Invite:RefreshOffline()
    if not dialog then return end
    local L = LAYOUT.invite
    local offline = not self.informational and GroupHasOfflineMember
        and GroupHasOfflineMember(LE_PARTY_CATEGORY_HOME)
    if offline then self.sawOffline = true end
    if self.sawOffline then
        if offline then
            parts.offline:SetText(Str("LFG_LIST_OFFLINE_MEMBER_NOTICE", "A member of your group is offline"))
        else
            parts.offline:SetText(Str("LFG_LIST_OFFLINE_MEMBER_NOTICE_GONE", "Every member of your group is online"))
        end
        parts.offline:Show()
        dialog:SetHeight(L.tallHeight)
    else
        parts.offline:Hide()
        dialog:SetHeight(L.height)
    end
    self:Layout()
end

-- The stack's height from its sizes and gaps, never from the text, which
-- may be secret; the holder centred between the dialog's top and the
-- buttons, or the notice while it shows
function Invite:Layout()
    local L = LAYOUT.invite
    local S = L.sizes
    local height = S.label + L.gap + S.name + L.lineGap + S.activity
    if parts.role:IsShown() then
        height = height + L.gap + S.caption + L.lineGap + S.role
    end
    parts.holder:SetHeight(height)
    local bottom = L.buttonY + parts.accept:GetHeight()
    if parts.offline:IsShown() then bottom = bottom + (L.tallHeight - L.height) end
    local room = dialog:GetHeight() - L.padTop - bottom
    parts.holder:ClearAllPoints()
    parts.holder:SetPoint("TOP", dialog, "TOP", 0, -(L.padTop + math.max(0, (room - height) / 2)))
end

-- Blizzard's own handlers with its frame: they act, hide it and look for
-- the next pending invite; the hide closes this dialog
function Invite:Accept()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if LFGListInviteDialog and LFGListInviteDialog_Accept then LFGListInviteDialog_Accept(LFGListInviteDialog) end
end

function Invite:Decline()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if LFGListInviteDialog and LFGListInviteDialog_Decline then LFGListInviteDialog_Decline(LFGListInviteDialog) end
end

function Invite:Acknowledge()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if LFGListInviteDialog and LFGListInviteDialog_Acknowledge then
        LFGListInviteDialog_Acknowledge(LFGListInviteDialog)
    end
end

function Invite:Hide()
    if dialog and dialog:IsShown() then dialog:Hide() end
end

function Invite:IsShown()
    return dialog ~= nil and dialog:IsShown()
end

GF.Listen("inviteShown", function() Invite:Open() end)
GF.Listen("inviteHidden", function() Invite:Hide() end)
GF.Listen("buttons", function()
    if Invite:IsShown() then Invite:RefreshOffline() end
end)

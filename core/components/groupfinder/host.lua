--------------------------------------------------------------------------------
-- core/components/groupfinder/host.lua
-- The Blizzard frames Scoot's Group Finder window stands on.
--
-- The C side reads the search text and the sign-up note from Blizzard's own
-- edit boxes and from nowhere else, so the window shows those boxes in place
-- of drawing its own, through the shared box host (core/boxhost.lua). A box
-- renders only while every ancestor is shown, so PVEFrame stays a shown,
-- managed panel while the window is up: at alpha 0 with the mouse off,
-- scaled to a dot so none of its invisible buttons stands under the window,
-- and a shield over what is left of its rect. Every call here is a method
-- on a Blizzard frame outside the Edit Mode system set; nothing writes a
-- field on one.
--
-- Three hooks keep the two windows in step: PVEFrame's OnHide closes the
-- Scoot window, LFGListFrame_SetActivePanel ends the window's own view
-- when Blizzard moves its panel and shows the matching Scoot panel, and
-- LFGListSearchPanel_DoSearch notes every search, whichever button, key or
-- Blizzard path ran it. Two more stand on Blizzard's invite dialog,
-- which its own events show whether or not the window is up: as it shows
-- it is parked and the window's own dialog stands in for it, and as it
-- hides it is put back. One stands on Blizzard's sign-up dialog, whose
-- frame is held shown out of sight while the window hosts its note box:
-- Blizzard hides that frame as each search's results land, and the hook
-- shows it again.
--------------------------------------------------------------------------------

local addonName, addon = ...

local GF = addon.GroupFinder
local SS = addon.SecretSafe
local BoxHost = addon.BoxHost

local Host = {}
GF.Host = Host

local parked = false
local parkedStrata        -- PVEFrame's own strata, put back on unpark
local parkedLevel         -- its own frame level, put back on unpark
local parkedToplevel = false
local invitePark = false  -- Blizzard's invite dialog parked while shown

-- The parked panel's level: low, under the shield and the window. The
-- panel is toplevel in Blizzard's hands, so the client raises it to the
-- top of its strata as it shows or takes a click, above the window
-- whenever another frame of the strata stands high (an error window,
-- say); parked, it is neither toplevel nor above this level
local PANEL_LEVEL = 1

-- The parked panel's scale: a dot. Its invisible buttons, dropdowns and
-- border took the window's clicks wherever the two overlapped, and the
-- client's own account of which frame holds the mouse did not say why;
-- at this scale every child of the panel collapses to a point at its
-- corner, and nothing of Blizzard's stands under the window. A hosted box
-- ignores its parents' scale and takes its holder's effective scale as its
-- own, so it renders as before.
local PARK_SCALE = 0.01
local hooksInstalled = false
local shield

-- The buttons of Blizzard's invite dialog, whose clicks go off while it
-- is parked: its mouse off does not reach them, and the popup stack may
-- anchor the frame again after its points are cleared
local INVITE_BUTTONS = { "AcceptButton", "DeclineButton", "AcknowledgeButton" }

-- The strata the window draws in; the parked panel is lifted to it so a
-- hosted box and every ancestor share one strata, as they did in the probe
local WINDOW_STRATA = "DIALOG"
local SHIELD_LEVEL = 50

-- The take and release of a box is the shared host's (core/boxhost.lua);
-- the panels call it by these names
Host.SCROLL_BOX_ART = BoxHost.SCROLL_BOX_ART
Host.DressHolder = BoxHost.DressHolder
Host.Take = BoxHost.Take
Host.IsTaken = BoxHost.IsTaken
Host.Release = BoxHost.Release
Host.ReleaseAll = BoxHost.ReleaseAll
Host.SyncScale = BoxHost.SyncScale

local Describe = BoxHost.Describe
local DumpChain = BoxHost.DumpChain

--------------------------------------------------------------------------------
-- PVEFrame and the dialog frame
--------------------------------------------------------------------------------

local function EnsureShield()
    if shield then return shield end
    shield = CreateFrame("Frame", nil, UIParent)
    shield:EnableMouse(true)
    shield:Hide()
    return shield
end

-- Alpha 0, mouse off, and the window's strata, so a box hosted out of the
-- panel and its ancestors stay in one strata; the shield sits above the
-- panel's own buttons and below the window
function Host.Park()
    if not PVEFrame or parked then return end
    parked = true
    local ok, strata = pcall(PVEFrame.GetFrameStrata, PVEFrame)
    parkedStrata = (ok and SS.plainString(strata)) or "MEDIUM"
    PVEFrame:SetAlpha(0)
    PVEFrame:EnableMouse(false)
    PVEFrame:SetFrameStrata(WINDOW_STRATA)
    local okT, top = pcall(PVEFrame.IsToplevel, PVEFrame)
    parkedToplevel = okT and top == true
    local okL, level = pcall(PVEFrame.GetFrameLevel, PVEFrame)
    parkedLevel = (okL and SS.safeNumber(level)) or nil
    PVEFrame:SetToplevel(false)
    PVEFrame:SetFrameLevel(PANEL_LEVEL)
    PVEFrame:SetScale(PARK_SCALE)
    local s = EnsureShield()
    s:SetFrameStrata(WINDOW_STRATA)
    s:SetFrameLevel(SHIELD_LEVEL)
    s:ClearAllPoints()
    s:SetAllPoints(PVEFrame)
    s:Show()
end

function Host.Unpark()
    if not PVEFrame or not parked then return end
    parked = false
    if shield then shield:Hide() end
    PVEFrame:SetAlpha(1)
    PVEFrame:EnableMouse(true)
    PVEFrame:SetFrameStrata(parkedStrata or "MEDIUM")
    if parkedLevel then PVEFrame:SetFrameLevel(parkedLevel) end
    PVEFrame:SetToplevel(parkedToplevel)
    PVEFrame:SetScale(1)
end

-- Opens Blizzard's panel on the Premade Groups page by the call its own
-- code makes, then hides it in place
function Host.Open()
    if type(PVEFrame_ShowFrame) ~= "function" then return false end
    PVEFrame_ShowFrame("GroupFinderFrame", "LFGListPVEStub")
    if not (PVEFrame and PVEFrame:IsShown()) then return false end
    Host.Park()
    return true
end

-- hidePanel false when PVEFrame is already on its way out, which is the
-- OnHide hook's call
function Host.Close(hidePanel)
    Host.ReleaseAll()
    Host.HideDialogFrame()
    Host.Unpark()
    if hidePanel ~= false and PVEFrame and PVEFrame:IsShown() then
        HideUIPanel(PVEFrame)
    end
end

-- The sign-up dialog's frame holds the note box. Shown with no points, so it
-- has no rect and its own buttons take no click; the hosted box has points
-- of its own. The show runs every addon's OnShow hook on the frame and its
-- children as a real sign-up would, and one addon clicks the Sign Up
-- button from its OnShow to sign up on sight: Blizzard's handler would
-- then apply with a result id Blizzard never set. The button is disabled
-- before every show, since Click() does nothing on a disabled button and
-- Blizzard's own role update enables it again in between, and enabled
-- again on hide when it was enabled before the hosting began. The frame
-- stays shown while the note is hosted: Blizzard hides it as each search's
-- results land, and the hook on its OnHide shows it again a frame later,
-- while the hosting is still on.
local dialogSignUpEnabled = false
local dialogHosting = false

function Host.ShowDialogFrame()
    local dialog = LFGListApplicationDialog
    if not dialog then return false end
    local signUp = dialog.SignUpButton
    if signUp and signUp.Disable then
        if not dialogHosting then
            local ok, enabled = pcall(signUp.IsEnabled, signUp)
            dialogSignUpEnabled = ok and enabled == true
        end
        signUp:Disable()
    end
    dialogHosting = true
    dialog:ClearAllPoints()
    dialog:SetAlpha(0)
    dialog:EnableMouse(false)
    dialog:Show()
    return true
end

function Host.HideDialogFrame()
    local dialog = LFGListApplicationDialog
    if not (dialog and dialogHosting) then return end
    dialogHosting = false
    dialog:Hide()
    dialog:SetAlpha(1)
    dialog:EnableMouse(true)
    local signUp = dialog.SignUpButton
    if dialogSignUpEnabled and signUp and signUp.Enable then signUp:Enable() end
    dialogSignUpEnabled = false
end

-- Blizzard's invite dialog out of sight while shown: alpha 0, its mouse
-- off and its buttons' clicks off; its points are left to the popup
-- stack, which places every shown dialog on each show
local function SetInviteClicks(dialog, on)
    for _, key in ipairs(INVITE_BUTTONS) do
        local button = dialog[key]
        if button and button.SetMouseClickEnabled then button:SetMouseClickEnabled(on) end
    end
end

function Host.ParkInviteDialog()
    local dialog = LFGListInviteDialog
    if not dialog or invitePark then return end
    invitePark = true
    dialog:SetAlpha(0)
    dialog:EnableMouse(false)
    SetInviteClicks(dialog, false)
end

function Host.UnparkInviteDialog()
    local dialog = LFGListInviteDialog
    if not (dialog and invitePark) then return end
    invitePark = false
    dialog:SetAlpha(1)
    dialog:EnableMouse(true)
    SetInviteClicks(dialog, true)
end

--------------------------------------------------------------------------------
-- The hooks
--------------------------------------------------------------------------------

function Host.InstallHooks()
    if hooksInstalled then return end
    if not (PVEFrame and PVEFrame.HookScript) or type(_G.LFGListFrame_SetActivePanel) ~= "function" then
        return
    end
    hooksInstalled = true
    PVEFrame:HookScript("OnHide", function()
        if GF.UI and GF.UI.Close then GF.UI:Close("pveframe") end
    end)
    -- Blizzard's own switches alone reach this: the window never calls it
    hooksecurefunc("LFGListFrame_SetActivePanel", function()
        if GF.UI and GF.UI.OnPanelSwitch then GF.UI:OnPanelSwitch() end
    end)
    if type(_G.LFGListSearchPanel_DoSearch) == "function" then
        hooksecurefunc("LFGListSearchPanel_DoSearch", function() GF.NoteSearch() end)
    end
    -- The invite dialog's park, while the module is on; the window's own
    -- dialog opens and closes on the topics
    local invite = LFGListInviteDialog
    if invite and invite.HookScript then
        invite:HookScript("OnShow", function()
            if not addon:IsModuleEnabled("groupfinder") then return end
            Host.ParkInviteDialog()
            GF.Notify("inviteShown")
        end)
        invite:HookScript("OnHide", function()
            Host.UnparkInviteDialog()
            GF.Notify("inviteHidden")
        end)
    end
    -- The sign-up dialog's frame back up after Blizzard hides it under a
    -- hosted note; the window's own hide clears the flag first
    local application = LFGListApplicationDialog
    if application and application.HookScript then
        application:HookScript("OnHide", function()
            if not dialogHosting then return end
            C_Timer.After(0, function()
                if dialogHosting and not application:IsShown() then Host.ShowDialogFrame() end
            end)
        end)
    end
end


--------------------------------------------------------------------------------
-- Debug: the state of every hosted box and the frames it stands on
--------------------------------------------------------------------------------

addon:RegisterDebugCommand({
    name = "lfg",
    help = "the hosted Group Finder boxes and the frames they stand on",
    handler = function()
        local lines, push = addon.DebugLines()
        push("parked=%s hooks=%s taken=%s dialogHosting=%s", tostring(parked), tostring(hooksInstalled),
            tostring(BoxHost.AnyTaken()), tostring(dialogHosting))
        Describe(push, "PVEFrame", PVEFrame)
        Describe(push, "shield", shield)
        Describe(push, "LFGListFrame", LFGListFrame)
        if LFGListFrame then
            local active = LFGListFrame.activePanel
            push("activePanel=%s", active and active.GetDebugName and active:GetDebugName() or tostring(active))
        end
        Describe(push, "window", GF.UI and GF.UI.GetFrame and GF.UI:GetFrame())
        BoxHost.DumpTaken(push)
        if not BoxHost.AnyTaken() then
            local sp = LFGListFrame and LFGListFrame.SearchPanel
            if sp and sp.SearchBox then
                push("")
                push("search box, not hosted:")
                DumpChain(push, "box", sp.SearchBox)
            end
        end
        -- The search view and the last search, and each result's activities
        local search = GF.UI and GF.UI.GetPanel and GF.UI:GetPanel("search")
        if search then
            local state = GF.state
            push("")
            push("search view shown=%s lastSearchAt=%.1f cooldownLeft=%.1f results=%d searching=%s failed=%s",
                tostring(search:IsShown()), state.lastSearchAt or 0, GF.SearchCooldownLeft(),
                #state.results, tostring(state.searching), tostring(state.searchFailed))
            for i, id in ipairs(state.results) do
                if i > 12 then push("    ...") break end
                local info = GF.ResultInfo(id)
                local ids = info and GF.plain(info.activityIDs)
                local parts = {}
                if type(ids) == "table" then
                    for _, a in ipairs(ids) do parts[#parts + 1] = tostring(a) end
                end
                local list = type(ids) == "table" and table.concat(parts, ",") or tostring(ids)
                local _, status = GF.Application(id)
                push("    %d: activities=%s name=%s status=%s", id, list,
                    tostring(info and GF.ActivityName(info)), tostring(status))
            end
        end
        -- The saved searches and which rung of the text fill held last
        if GF.Saved then
            push("")
            push("saved searches=%d autoSearch=%s", GF.Saved.Count(), tostring(GF.Saved.autoSearch))
        end
        addon.DebugShowWindow("Group Finder host", lines)
    end,
})

--------------------------------------------------------------------------------
-- forever/groupfinder/host.lua
-- Blizzard's side of the group finder: its load-on-demand addon, whose
-- templates the window is built from, and its comment box.
--
-- A listing's comment is not an argument of CreateListing. The client reads
-- it from one edit box Blizzard registers, LFGListingComment, which refuses
-- SetText and paste from addon code, so the window shows that box and draws
-- none of its own. The box is leased: its parent is the window's holder
-- while the Listing tab's activity view is up, by one SetParent, and
-- Blizzard's activity view again when the view goes. Anchoring it under
-- Blizzard's own shown frame, as the retail window does, is not open here:
-- Blizzard's activity view shows only once its form holds a category, and
-- this file writes no field on a Blizzard frame.
--
-- Blizzard's frame is otherwise left as it is. Its event handlers keep
-- running while it is hidden: they copy a live listing's comment into the
-- box, show the two expiry popups, search the player's own listing after a
-- post and ask for the activities a new level opens.
--------------------------------------------------------------------------------

local addonName, addon = ...

local LFG = addon.ForeverGroupFinder
local BoxHost = addon.BoxHost

local Host = {}
LFG.Host = Host

local KEY = "lfgComment"

local leased = false
local homeParent          -- the box's own parent, put back on release
local holderNow           -- the holder the box is leased into
local changeHooked = false
local clickHooked = false
local viewHooked = false
local onChanged           -- the window's listener for typed text

--------------------------------------------------------------------------------
-- Blizzard's addon
--------------------------------------------------------------------------------

-- Loads Blizzard's finder when it is not in yet. True once its frames and
-- templates are there.
function Host.Ready()
    if not LFGListingComment and type(GroupFinderVanillaStyle_LoadUI) == "function" then
        pcall(GroupFinderVanillaStyle_LoadUI)
    end
    return LFGListingFrame ~= nil and LFGListingComment ~= nil
end

local function Box()
    return LFGListingComment
end

local function EditBox()
    local box = Box()
    return box and box.EditBox or nil
end

--------------------------------------------------------------------------------
-- The lease
--------------------------------------------------------------------------------

local function Place()
    local box = Box()
    if not (box and holderNow) then return end
    box:ClearAllPoints()
    box:SetAllPoints(holderNow)
    box:SetFrameLevel(holderNow:GetFrameLevel() + 1)
end

-- Typed text reaches the window's form through one hook, set once
local function HookChange()
    local editBox = EditBox()
    if changeHooked or not (editBox and editBox.HookScript) then return end
    changeHooked = true
    editBox:HookScript("OnTextChanged", function(_, userInput)
        if leased and userInput and onChanged then onChanged() end
    end)
end

-- The box is off while the account has no authenticator, and a click on it
-- then shows Blizzard's popup. Blizzard's own handler asks about its own
-- form's category, which this window never sets, so the leased box answers
-- for itself: the window turns it off for that one reason.
local function HookClick()
    local box = Box()
    if clickHooked or not (box and box.HookScript) then return end
    clickHooked = true
    box:HookScript("OnMouseDown", function()
        local editBox = EditBox()
        if leased and editBox and not editBox:IsEnabled() then
            StaticPopup_Show("GROUP_FINDER_AUTHENTICATOR_POPUP")
        end
    end)
end

-- Blizzard's activity view anchors the box and sizes it as the view shows.
-- With the box leased those points land on the holder; the lease's own go
-- back on a frame later.
local function HookView()
    local view = LFGListingFrame and LFGListingFrame.ActivityView
    if viewHooked or not (view and view.HookScript) then return end
    viewHooked = true
    view:HookScript("OnShow", function()
        if not leased then return end
        C_Timer.After(0, function()
            if leased then Place() end
        end)
    end)
end

-- holder     the window's frame the box fills
-- listener   called when the player types in the box
function Host.TakeComment(holder, listener)
    local box = Box()
    if not (box and holder) then return false end
    onChanged = listener
    HookChange()
    HookClick()
    HookView()
    if not leased then
        local ok, parent = pcall(box.GetParent, box)
        homeParent = ok and parent or nil
        -- The box's own points, strata, level and scale, kept for the
        -- release; its art and its face stay Blizzard's
        BoxHost.Take(KEY, box, holder, { editBox = box.EditBox, style = false,
            inset = { left = 0, right = 0, top = 0, bottom = 0 } })
        box:SetParent(holder)
        -- A child of the holder now, so it takes the holder's alpha and
        -- scale as any child does; the shared host's settings are for a box
        -- left under a parked parent
        box:SetIgnoreParentAlpha(false)
        if box.SetIgnoreParentScale then box:SetIgnoreParentScale(false) end
        box:SetScale(1)
        leased = true
    end
    holderNow = holder
    Place()
    box:Show()
    return true
end

function Host.ReleaseComment()
    if not leased then return end
    leased = false
    holderNow = nil
    local box = Box()
    local editBox = EditBox()
    if editBox and editBox.ClearFocus then editBox:ClearFocus() end
    if box and homeParent then box:SetParent(homeParent) end
    BoxHost.Release(KEY)
    homeParent = nil
end

function Host.IsLeased()
    return leased
end

--------------------------------------------------------------------------------
-- The box's state
--------------------------------------------------------------------------------

-- The line shown in the empty box, and whether the player may type: both
-- are Blizzard's to set as its own view shows, and the window's while the
-- box is leased
function Host.SetCommentState(instructions, enabled)
    local editBox = EditBox()
    if not editBox then return end
    if editBox.Instructions and editBox.Instructions.SetText then
        editBox.Instructions:SetText(instructions or "")
    end
    editBox:SetEnabled(enabled and true or false)
end

-- Plain text: the box's GetText is readable from addon code
function Host.CommentText()
    local editBox = EditBox()
    if not editBox then return "" end
    local ok, text = pcall(editBox.GetText, editBox)
    if not ok or type(text) ~= "string" then return "" end
    if issecretvalue and issecretvalue(text) then return "" end
    return text
end

function Host.CommentEnabled()
    local editBox = EditBox()
    return editBox ~= nil and editBox:IsEnabled() and true or false
end

function Host.FocusComment()
    local editBox = EditBox()
    if editBox and leased then addon.Keyboard.TakeFocus(editBox) end
end

function Host.ClearCommentFocus()
    local editBox = EditBox()
    if editBox then editBox:ClearFocus() end
end

-- The client empties the box and fills it from the live listing; no addon
-- call writes its text
function Host.ClearComment()
    C_LFGList.ClearCreationTextFields()
end

function Host.LoadComment()
    C_LFGList.CopyActiveEntryInfoToCreationFields()
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

function Host.Dump(push)
    push("  Blizzard's finder loaded: %s; comment box leased: %s", tostring(LFGListingFrame ~= nil), tostring(leased))
    BoxHost.Describe(push, "  LFGParentFrame", LFGParentFrame)
    BoxHost.Describe(push, "  LFGListingFrame", LFGListingFrame)
    if leased then
        BoxHost.DumpTaken(push)
    else
        BoxHost.DumpChain(push, "  comment box", Box())
    end
    push("  comment text length: %d, enabled: %s", #Host.CommentText(), tostring(Host.CommentEnabled()))
end

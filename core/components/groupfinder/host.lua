--------------------------------------------------------------------------------
-- core/components/groupfinder/host.lua
-- The box host: Blizzard's Group Finder text boxes drawn inside Scoot's
-- window, and the Blizzard frames the window stands on.
--
-- The C side reads the search text and the sign-up note from Blizzard's own
-- edit boxes and from nowhere else, so the window shows those boxes in place
-- of drawing its own. A box renders only while every ancestor is shown, so
-- PVEFrame stays a shown, managed panel while the window is up: at alpha 0
-- with the mouse off, scaled to a dot so none of its invisible buttons
-- stands under the window, a shield over what is left of its rect, and
-- each box anchored into a Scoot holder with SetIgnoreParentAlpha and
-- SetIgnoreParentScale, at the holder's effective scale, lifted to the
-- holder's strata, its template art at alpha 0 and its text in the skin's
-- face. Every call here is a method on a
-- Blizzard frame outside the Edit Mode system set; nothing writes a field on
-- one. On release the box goes back to the points it was taken from.
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

local Host = {}
GF.Host = Host

local taken = {}          -- key -> the record of a hosted box
local focusHooked = {}    -- box -> true once its focus scripts are hooked
local hoverHooked = {}    -- art child -> true once its hover scripts are hooked
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

-- The border pieces of a scrolling text box's template, put at alpha 0
-- while the box is hosted: the sign-up note and the listing's details
Host.SCROLL_BOX_ART = {
    "TopLeftTex", "TopRightTex", "TopTex", "BottomLeftTex", "BottomRightTex",
    "BottomTex", "LeftTex", "RightTex", "MiddleTex",
}

local function Theme()
    return addon.UI.Theme
end

local function Controls()
    return addon.UI.Controls
end

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
-- The holder: the single-line edit box's flat look around a hosted box
--------------------------------------------------------------------------------

function Host.DressHolder(holder)
    local C = Controls()
    holder._bg = C.AddBackground(holder, { inset = 1 })
    holder._border = C.CreateBorder(holder, {
        thickness = 1,
        alpha = 0.6,
        getAlpha = function() return holder._focused and 1 or 0.6 end,
    })
    holder._focused = false
    return holder
end

local function SetHolderFocus(holder, focused)
    if not holder then return end
    holder._focused = focused and true or false
    if holder._border and holder._border.Refresh then holder._border:Refresh() end
end

--------------------------------------------------------------------------------
-- Take and release
--------------------------------------------------------------------------------

-- The points, strata and level the box had, read under pcall; a value that
-- comes back secret is dropped and the caller's fallback points stand in
local function Capture(box)
    local rec = { points = {}, regions = {} }
    local okN, n = pcall(box.GetNumPoints, box)
    if okN and type(n) == "number" then
        for i = 1, n do
            local ok, point, rel, relPoint, x, y = pcall(box.GetPoint, box, i)
            point = ok and SS.plainString(point) or nil
            if point then
                rec.points[#rec.points + 1] = {
                    point, SS.plainFrame(rel), SS.plainString(relPoint), SS.safeOffset(x), SS.safeOffset(y),
                }
            end
        end
    end
    local okS, strata = pcall(box.GetFrameStrata, box)
    if okS then rec.strata = SS.plainString(strata) end
    local okL, level = pcall(box.GetFrameLevel, box)
    if okL then rec.level = SS.safeNumber(level) end
    local okC, scale = pcall(box.GetScale, box)
    if okC then rec.scale = SS.safeNumber(scale) end
    return rec
end

-- A hosted box ignores its parents' scale, since the parked panel is a dot;
-- on its own it would render at scale 1 while the window renders at the UI
-- scale, so it takes the holder's effective scale as its own
local function MatchScale(rec)
    local holder = rec.holder
    if not (holder and rec.box and rec.box.SetScale) then return end
    local scale = holder:GetEffectiveScale()
    if type(scale) == "number" and scale > 0 then
        rec.box:SetScale(scale)
    end
end

local function BlankRegion(rec, region)
    if not region or not region.SetAlpha then return end
    local ok, alpha = pcall(region.GetAlpha, region)
    rec.regions[#rec.regions + 1] = { region = region, alpha = (ok and SS.safeNumber(alpha)) or 1 }
    region:SetAlpha(0)
end

-- A child's own hover scripts put its art back (the clear button's icon
-- comes up at half alpha on leave), so while the box is hosted the art goes
-- back down after each
local function HookChildHover(key, child)
    if hoverHooked[child] or not child.HookScript then return end
    hoverHooked[child] = true
    local function reblank()
        local live = taken[key]
        if not live then return end
        for _, entry in ipairs(live.regions) do
            entry.region:SetAlpha(0)
        end
    end
    child:HookScript("OnEnter", reblank)
    child:HookScript("OnLeave", reblank)
end

-- The template's own art: the named regions of the box, and every texture of
-- the child frames named (the clear button)
local function BlankArt(rec, box, opts)
    for _, key in ipairs(opts.artKeys or {}) do
        BlankRegion(rec, box[key])
    end
    for _, key in ipairs(opts.artFrames or {}) do
        local child = box[key]
        if child and child.GetRegions then
            for _, region in ipairs({ child:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture") then
                    BlankRegion(rec, region)
                end
            end
            HookChildHover(rec.key, child)
        end
    end
end

-- A region's font and text color as they stand, for the release to put
-- back; a value that reads secret is dropped and that part stays
local function CaptureText(region)
    local font, color
    local okF, path, size, flags = pcall(region.GetFont, region)
    if okF and SS.plainString(path) then
        font = { path, SS.safeNumber(size), SS.plainString(flags) }
    end
    local okC, r, g, b, a = pcall(region.GetTextColor, region)
    if okC and SS.safeNumber(r) then
        color = { SS.safeNumber(r), SS.safeNumber(g) or 1, SS.safeNumber(b) or 1, SS.safeNumber(a) or 1 }
    end
    return font, color
end

local function RestoreText(region, font, color)
    if not region then return end
    if font and region.SetFont then
        pcall(region.SetFont, region, font[1], font[2] or 12, font[3] or "")
    end
    if color and region.SetTextColor then
        region:SetTextColor(color[1], color[2], color[3], color[4])
    end
end

-- The skin's value face on the text, at the caller's size when it names
-- one, primary color, and the instructions line dim. The style is named
-- so no companion string is attached to a box the player types into. The
-- box's and the instructions' own font and color are kept for the
-- release, so Blizzard's window reads as its own again.
local function Style(rec, opts)
    local theme = Theme()
    local editBox = rec.editBox
    if not editBox then return end
    rec.font, rec.textColor = CaptureText(editBox)
    theme:ApplyFont(editBox, "value", opts.fontSize, "NONE")
    local pr, pg, pb = theme:GetPrimaryTextColor()
    editBox:SetTextColor(pr, pg, pb, 1)
    if opts.textInsets then
        editBox:SetTextInsets(unpack(opts.textInsets))
    end
    local instructions = editBox.Instructions
    if instructions and instructions.SetFont then
        rec.instructionsFont, rec.instructionsColor = CaptureText(instructions)
        theme:ApplyFont(instructions, "value", opts.fontSize, "NONE")
        local dr, dg, db = theme:GetDimTextColor()
        instructions:SetTextColor(dr, dg, db, 0.7)
    end
end

local function HookFocus(rec)
    local editBox = rec.editBox
    if not editBox or focusHooked[editBox] then return end
    focusHooked[editBox] = true
    local key = rec.key
    editBox:HookScript("OnEditFocusGained", function()
        local live = taken[key]
        if live then SetHolderFocus(live.holder, true) end
    end)
    editBox:HookScript("OnEditFocusLost", function()
        local live = taken[key]
        if live then SetHolderFocus(live.holder, false) end
    end)
end

-- key        the host's name for the box ("search", "note")
-- box        the Blizzard frame moved: the EditBox itself, or the ScrollFrame
--            that holds one
-- holder     the Scoot frame it fills
-- opts.editBox      the text region to style when box is a ScrollFrame
-- opts.inset        { left, right, top, bottom } inside the holder; default 1
-- opts.artKeys      region keys on box to put at alpha 0
-- opts.artFrames    child frame keys whose textures go to alpha 0
-- opts.textInsets   { left, right, top, bottom } for SetTextInsets
-- opts.fontSize     the text's size in the value face, in place of the role's
-- opts.editBoxWidth the width for the text region inside a ScrollFrame box,
--                   which takes its width once at load and not from its
--                   frame; its own width comes back on release
-- opts.scrollBarScale  the scale of a ScrollFrame box's bar, for a holder
--                   smaller than the box's own window; 1 again on release
-- opts.fallbackPoints  the points to restore when none could be read
function Host.Take(key, box, holder, opts)
    opts = opts or {}
    if not box or not holder then return false end
    local rec = taken[key]
    if not (rec and rec.box == box) then
        if rec then Host.Release(key) end
        rec = Capture(box)
        rec.key = key
        rec.box = box
        rec.editBox = opts.editBox or box
        rec.fallbackPoints = opts.fallbackPoints
        taken[key] = rec
        BlankArt(rec, box, opts)
        Style(rec, opts)
        HookFocus(rec)
    end
    rec.holder = holder
    local inset = opts.inset or {}
    local left, right = inset.left or 1, inset.right or 1
    local top, bottom = inset.top or 1, inset.bottom or 1
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", left, -top)
    box:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -right, bottom)
    box:SetIgnoreParentAlpha(true)
    -- The parked panel is a dot; the box renders at the window's scale
    if box.SetIgnoreParentScale then box:SetIgnoreParentScale(true) end
    MatchScale(rec)
    -- The parked panel is already in the window's strata; a box whose chain
    -- is not (the dialog's) takes it here
    local okS, boxStrata = pcall(box.GetFrameStrata, box)
    if not (okS and boxStrata == holder:GetFrameStrata()) then
        box:SetFrameStrata(holder:GetFrameStrata())
    end
    box:SetFrameLevel(holder:GetFrameLevel() + 1)
    local editBox = rec.editBox
    if opts.editBoxWidth and editBox ~= box and editBox.SetWidth then
        if not rec.editBoxWidth then
            local okW, w = pcall(editBox.GetWidth, editBox)
            rec.editBoxWidth = (okW and SS.safeNumber(w)) or 0
        end
        editBox:SetWidth(math.max(1, opts.editBoxWidth))
        if editBox.Instructions and editBox.Instructions.SetWidth then
            editBox.Instructions:SetWidth(math.max(1, opts.editBoxWidth))
        end
    end
    local bar = box.ScrollBar
    if opts.scrollBarScale and bar and bar.SetScale then
        bar:SetScale(opts.scrollBarScale)
        rec.scrollBar = bar
    end
    -- An ancestor that clips its children to its own rect would clip the box
    -- out of the window; none is known, and one found is opened for the stay
    rec.unclipped = rec.unclipped or {}
    local f = box
    for _ = 1, 10 do
        local okP, parent = pcall(f.GetParent, f)
        f = okP and parent or nil
        if not f or f == UIParent then break end
        local okC, clips = pcall(f.DoesClipChildren, f)
        if okC and clips == true then
            f:SetClipsChildren(false)
            rec.unclipped[#rec.unclipped + 1] = f
        end
    end
    SetHolderFocus(holder, box.HasFocus and box:HasFocus() or (rec.editBox.HasFocus and rec.editBox:HasFocus()))
    return true
end

function Host.IsTaken(key)
    return taken[key] ~= nil
end

function Host.Release(key)
    local rec = taken[key]
    if not rec then return end
    local box = rec.box
    taken[key] = nil
    box:ClearAllPoints()
    local points = (#rec.points > 0) and rec.points or rec.fallbackPoints
    for _, p in ipairs(points or {}) do
        box:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
    end
    box:SetIgnoreParentAlpha(false)
    if box.SetScale then box:SetScale(rec.scale or 1) end
    if box.SetIgnoreParentScale then box:SetIgnoreParentScale(false) end
    if rec.strata then box:SetFrameStrata(rec.strata) end
    if rec.level then box:SetFrameLevel(rec.level) end
    for _, entry in ipairs(rec.regions) do
        entry.region:SetAlpha(entry.alpha)
    end
    RestoreText(rec.editBox, rec.font, rec.textColor)
    if rec.editBox then
        RestoreText(rec.editBox.Instructions, rec.instructionsFont, rec.instructionsColor)
    end
    if rec.editBoxWidth and rec.editBoxWidth > 0 and rec.editBox and rec.editBox.SetWidth then
        rec.editBox:SetWidth(rec.editBoxWidth)
        if rec.editBox.Instructions and rec.editBox.Instructions.SetWidth then
            rec.editBox.Instructions:SetWidth(rec.editBoxWidth)
        end
    end
    if rec.scrollBar then rec.scrollBar:SetScale(1) end
    for _, f in ipairs(rec.unclipped or {}) do
        if f.SetClipsChildren then f:SetClipsChildren(true) end
    end
    SetHolderFocus(rec.holder, false)
end

function Host.ReleaseAll()
    for key in pairs(taken) do
        Host.Release(key)
    end
end

-- Every hosted box back to its holder's scale, after the UI scale or the
-- display size changes under an open window
function Host.SyncScale()
    for _, rec in pairs(taken) do
        MatchScale(rec)
    end
end

--------------------------------------------------------------------------------
-- Debug: the state of every hosted box and the frames it stands on
--------------------------------------------------------------------------------

local function Describe(push, label, frame)
    if not frame then
        push("%s: nil", label)
        return
    end
    local function get(method, ...)
        if not frame[method] then return "-" end
        local ok, a, b, c, d = pcall(frame[method], frame, ...)
        if not ok then return "err" end
        if b ~= nil then return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) .. "," .. tostring(d) end
        return tostring(a)
    end
    push("%s: %s shown=%s visible=%s alpha=%s eff=%s ignoreParent=%s strata=%s level=%s mouse=%s clips=%s scale=%s",
        label, get("GetName"), get("IsShown"), get("IsVisible"), get("GetAlpha"), get("GetEffectiveAlpha"),
        get("IsIgnoringParentAlpha"), get("GetFrameStrata"), get("GetFrameLevel"), get("IsMouseEnabled"),
        get("DoesClipChildren"), get("GetEffectiveScale"))
    push("    rect left=%s bottom=%s w=%s h=%s points=%s",
        get("GetLeft"), get("GetBottom"), get("GetWidth"), get("GetHeight"), get("GetNumPoints"))
end

local function DumpChain(push, label, frame)
    local depth = 0
    local f = frame
    while f and depth < 10 do
        Describe(push, string.format("%s[%d]", label, depth), f)
        local ok, parent = pcall(f.GetParent, f)
        f = ok and parent or nil
        depth = depth + 1
    end
end

addon:RegisterDebugCommand({
    name = "lfg",
    help = "the hosted Group Finder boxes and the frames they stand on",
    handler = function()
        local lines, push = addon.DebugLines()
        push("parked=%s hooks=%s taken=%s dialogHosting=%s", tostring(parked), tostring(hooksInstalled),
            tostring(next(taken) ~= nil), tostring(dialogHosting))
        Describe(push, "PVEFrame", PVEFrame)
        Describe(push, "shield", shield)
        Describe(push, "LFGListFrame", LFGListFrame)
        if LFGListFrame then
            local active = LFGListFrame.activePanel
            push("activePanel=%s", active and active.GetDebugName and active:GetDebugName() or tostring(active))
        end
        Describe(push, "window", GF.UI and GF.UI.GetFrame and GF.UI:GetFrame())
        for key, rec in pairs(taken) do
            push("")
            push("hosted %s: points captured=%d regions blanked=%d font=%s",
                key, #rec.points, #rec.regions, rec.font and (tostring(rec.font[1]) .. " " .. tostring(rec.font[2])) or "-")
            Describe(push, "holder", rec.holder)
            DumpChain(push, "box", rec.box)
            if rec.editBox and rec.editBox ~= rec.box then
                Describe(push, "editBox", rec.editBox)
            end
            local eb = rec.editBox
            if eb then
                local okF, path, size, flags = pcall(eb.GetFont, eb)
                push("    editBox font=%s %s %s focus=%s insets=%s",
                    okF and tostring(path) or "err", tostring(size), tostring(flags),
                    eb.HasFocus and tostring(eb:HasFocus()) or "-",
                    eb.GetTextInsets and table.concat({ eb:GetTextInsets() }, ",") or "-")
                if eb.Instructions then
                    Describe(push, "    instructions", eb.Instructions)
                    local okT, text = pcall(eb.Instructions.GetText, eb.Instructions)
                    push("    instructions text=%s", okT and tostring(text) or "err")
                end
                local okText, boxText = pcall(eb.GetText, eb)
                push("    editBox text=%s textColor=%s", okText and tostring(boxText) or "err",
                    eb.GetTextColor and table.concat({ eb:GetTextColor() }, ",") or "-")
            end
        end
        if not next(taken) then
            local sp = LFGListFrame and LFGListFrame.SearchPanel
            if sp and sp.SearchBox then
                push("")
                push("search box, not hosted:")
                DumpChain(push, "box", sp.SearchBox)
            end
        end
        addon.DebugShowWindow("Group Finder host", lines)
    end,
})

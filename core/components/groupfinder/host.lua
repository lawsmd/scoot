--------------------------------------------------------------------------------
-- core/components/groupfinder/host.lua
-- The box host: Blizzard's Group Finder text boxes drawn inside Scoot's
-- window, and the Blizzard frames the window stands on.
--
-- The C side reads the search text and the sign-up note from Blizzard's own
-- edit boxes and from nowhere else, so the window shows those boxes in place
-- of drawing its own. A box renders only while every ancestor is shown, so
-- PVEFrame stays a shown, managed panel at alpha 0 with the mouse off while
-- the window is up, a shield over its rect takes the clicks its invisible
-- buttons would, and each box is anchored into a Scoot holder with
-- SetIgnoreParentAlpha, lifted to the holder's strata, its template art at
-- alpha 0 and its text in the skin's face. Every call here is a method on a
-- Blizzard frame outside the Edit Mode system set; nothing writes a field on
-- one. On release the box goes back to the points it was taken from.
--
-- Two hooks keep the two windows in step: PVEFrame's OnHide closes the Scoot
-- window, and LFGListFrame_SetActivePanel shows the matching Scoot panel.
--------------------------------------------------------------------------------

local addonName, addon = ...

local GF = addon.GroupFinder
local SS = addon.SecretSafe

local Host = {}
GF.Host = Host

local taken = {}          -- key -> the record of a hosted box
local focusHooked = {}    -- box -> true once its focus scripts are hooked
local parked = false
local hooksInstalled = false
local shield

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

function Host.Park()
    if not PVEFrame or parked then return end
    parked = true
    PVEFrame:SetAlpha(0)
    PVEFrame:EnableMouse(false)
    local s = EnsureShield()
    local ok, strata = pcall(PVEFrame.GetFrameStrata, PVEFrame)
    local okL, level = pcall(PVEFrame.GetFrameLevel, PVEFrame)
    s:SetFrameStrata(ok and type(strata) == "string" and strata or "MEDIUM")
    s:SetFrameLevel(((okL and type(level) == "number") and level or 0) + 500)
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
    Host.Unpark()
    if hidePanel ~= false and PVEFrame and PVEFrame:IsShown() then
        HideUIPanel(PVEFrame)
    end
end

-- The sign-up dialog's frame holds the note box. Shown with no points, so it
-- has no rect and its own buttons take no click; the hosted box has points
-- of its own.
function Host.ShowDialogFrame()
    local dialog = LFGListApplicationDialog
    if not dialog then return false end
    dialog:ClearAllPoints()
    dialog:SetAlpha(0)
    dialog:EnableMouse(false)
    dialog:Show()
    return true
end

function Host.HideDialogFrame()
    local dialog = LFGListApplicationDialog
    if not dialog then return end
    dialog:Hide()
    dialog:SetAlpha(1)
    dialog:EnableMouse(true)
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
    hooksecurefunc("LFGListFrame_SetActivePanel", function()
        if GF.UI and GF.UI.SyncPanel then GF.UI:SyncPanel() end
    end)
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
    return rec
end

local function BlankRegion(rec, region)
    if not region or not region.SetAlpha then return end
    local ok, alpha = pcall(region.GetAlpha, region)
    rec.regions[#rec.regions + 1] = { region = region, alpha = (ok and SS.safeNumber(alpha)) or 1 }
    region:SetAlpha(0)
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
        end
    end
end

-- The skin's value face on the text, primary color, and the instructions
-- line dim. The style is named so no companion string is attached to a box
-- the player types into.
local function Style(rec, opts)
    local theme = Theme()
    local editBox = rec.editBox
    if not editBox then return end
    local okF, path, size, flags = pcall(editBox.GetFont, editBox)
    if okF and SS.plainString(path) then
        rec.font = { path, SS.safeNumber(size), SS.plainString(flags) }
    end
    theme:ApplyFont(editBox, "value", nil, "NONE")
    local pr, pg, pb = theme:GetPrimaryTextColor()
    editBox:SetTextColor(pr, pg, pb, 1)
    if opts.textInsets then
        editBox:SetTextInsets(unpack(opts.textInsets))
    end
    local instructions = editBox.Instructions
    if instructions and instructions.SetFont then
        theme:ApplyFont(instructions, "value", nil, "NONE")
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
    box:SetFrameStrata(holder:GetFrameStrata())
    box:SetFrameLevel(holder:GetFrameLevel() + 1)
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
    if rec.strata then box:SetFrameStrata(rec.strata) end
    if rec.level then box:SetFrameLevel(rec.level) end
    for _, entry in ipairs(rec.regions) do
        entry.region:SetAlpha(entry.alpha)
    end
    if rec.font and rec.editBox and rec.editBox.SetFont then
        pcall(rec.editBox.SetFont, rec.editBox, rec.font[1], rec.font[2] or 12, rec.font[3] or "")
    end
    SetHolderFocus(rec.holder, false)
end

function Host.ReleaseAll()
    for key in pairs(taken) do
        Host.Release(key)
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
    push("%s: %s shown=%s visible=%s alpha=%s eff=%s ignoreParent=%s strata=%s level=%s mouse=%s",
        label, get("GetName"), get("IsShown"), get("IsVisible"), get("GetAlpha"), get("GetEffectiveAlpha"),
        get("IsIgnoringParentAlpha"), get("GetFrameStrata"), get("GetFrameLevel"), get("IsMouseEnabled"))
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
        push("parked=%s hooks=%s taken=%s", tostring(parked), tostring(hooksInstalled), tostring(next(taken) ~= nil))
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
                if eb.Instructions then Describe(push, "    instructions", eb.Instructions) end
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

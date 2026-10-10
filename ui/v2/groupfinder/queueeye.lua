-- queueeye.lua - Scoot's queue eye over Blizzard's QueueStatusButton
--
-- A square on the accent with a 3x3 grid of dots that fill and drain while
-- a queue searches, drawn by a child frame of QueueStatusButton over its
-- whole rect. Being a child gives it the button's scale, which is the Micro
-- Menu's Eye Size in Edit Mode, the button's visibility and Blizzard's
-- re-anchoring on every micro menu layout. QueueStatusButton sits in the
-- Micro Menu's system frame tree, so nothing here hooks it or writes a
-- field to it: Blizzard's eye art goes to alpha 0 by a plain setter, and
-- the one read is the eye's static flag, which says whether to animate.
--
-- The mouse: hover passes through to Blizzard's button, which shows its
-- queue status tooltip, and so does a right click, which opens its queue
-- menu. A left click is taken only while a listing or an application is
-- live, the case where Blizzard's own click opens the Premade Groups panel,
-- and it toggles the window; under any other queue it falls through too.
local addonName, addon = ...

local GF = addon.GroupFinder
local SS = addon.SecretSafe
local QueueEye = {}
GF.QueueEye = QueueEye

local OWNER = "GroupFinder:QueueEye"

-- The eye's proportions, as fractions of the button's side: the square, its
-- border, the grid's inset from the border, the gap between dots as a
-- fraction of a dot. The beat is one fill or drain step in seconds.
local SHAPE = { box = 0.78, border = 0.05, inset = 0.2, gap = 0.5, beat = 0.09, dim = 0.18 }
-- One cycle: nine steps to fill, three held full, nine to drain, three
-- held empty
local CYCLE = { fill = 9, full = 3, drain = 9, empty = 3 }

local eye, box, fill
local edges, dots = {}, {}
local searching = false
local stepIndex, elapsed = 0, 0
local refreshQueued = false

local function Theme()
    return addon.UI.Theme
end

local function Wanted()
    return addon:IsModuleEnabled("groupfinder") and GF.Setting("queueEye") ~= false
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

-- Blizzard's eye animates while anything searches; its static flag is the
-- one rule for that across every queue type
local function ReadSearching()
    local host = _G.QueueStatusButton
    local blizzEye = host and host.Eye
    if not blizzEye then return false end
    local ok, static = pcall(blizzEye.IsStaticMode, blizzEye)
    return ok and static == false
end

-- The test Blizzard's own left click makes before it opens the Premade
-- Groups panel
local function HasListItem()
    if not C_LFGList then return false end
    local okE, active = pcall(C_LFGList.HasActiveEntryInfo)
    if okE and active == true then return true end
    local okA, apps = pcall(C_LFGList.GetApplications)
    if not okA or type(apps) ~= "table" then return false end
    for _, id in ipairs(apps) do
        local okI, _, status = pcall(C_LFGList.GetApplicationInfo, id)
        status = okI and SS.plainString(status)
        if status == "applied" or status == "invited" then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Paint()
    if not eye then return end
    local r, g, b = Theme():GetAccentColor()
    local br, bg, bb = Theme():GetBackgroundSolidColor()
    fill:SetColorTexture(br, bg, bb, 1)
    for _, edge in ipairs(edges) do
        edge:SetColorTexture(r, g, b, 1)
    end
    for _, dot in ipairs(dots) do
        dot:SetColorTexture(r, g, b, 1)
    end
end

-- Which dots are lit at a step of the cycle, in reading order: the first n
-- while filling, all while full, all past the first n while draining
local function ShowStep(step)
    local lit = function() return false end
    if step < CYCLE.fill then
        lit = function(i) return i <= step + 1 end
    elseif step < CYCLE.fill + CYCLE.full then
        lit = function() return true end
    elseif step < CYCLE.fill + CYCLE.full + CYCLE.drain then
        local drained = step - CYCLE.fill - CYCLE.full + 1
        lit = function(i) return i > drained end
    end
    for i, dot in ipairs(dots) do
        dot:SetAlpha(lit(i) and 1 or SHAPE.dim)
    end
end

local function ShowStatic()
    for _, dot in ipairs(dots) do
        dot:SetAlpha(SHAPE.dim)
    end
end

local function Layout()
    if not eye then return end
    local w, h = eye:GetSize()
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return end
    local side = math.min(w, h) * SHAPE.box
    local border = math.max(1, side * SHAPE.border)
    box:SetSize(side, side)

    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    top:SetHeight(border)
    bottom:SetHeight(border)
    left:SetWidth(border)
    right:SetWidth(border)
    -- The sides run between the top and bottom edges: an overlap at a
    -- corner draws twice and shows a different color under a faded parent
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -border)
    left:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, border)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -border)
    right:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, border)

    local inner = side - border * 2
    local inset = inner * SHAPE.inset
    local span = inner - inset * 2
    -- three dots and two gaps of gap * dot across the span
    local dot = span / (3 + 2 * SHAPE.gap)
    local stride = dot * (1 + SHAPE.gap)
    for i, d in ipairs(dots) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        d:SetSize(dot, dot)
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", box, "TOPLEFT", border + inset + col * stride, -(border + inset + row * stride))
    end
end

local function OnUpdate(_, dt)
    elapsed = elapsed + dt
    if elapsed < SHAPE.beat then return end
    elapsed = 0
    stepIndex = (stepIndex + 1) % (CYCLE.fill + CYCLE.full + CYCLE.drain + CYCLE.empty)
    ShowStep(stepIndex)
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Blizzard's eye art reaches past the square, so it goes to alpha 0 while
-- Scoot's eye is on: a plain setter on the Eye frame, no hook. The Micro
-- Bar's styling keeps QueueStatusButton out of the bar's fade for
-- Blizzard's eye and lets it fade under Scoot's, so it runs again on every
-- switch.
local blizzardHidden = false

local function SetBlizzardEyeHidden(hidden)
    if hidden == blizzardHidden then return end
    blizzardHidden = hidden
    local host = _G.QueueStatusButton
    local blizzEye = host and host.Eye
    if blizzEye then pcall(blizzEye.SetAlpha, blizzEye, hidden and 0 or 1) end
    local microBar = addon.Components and addon.Components.microBar
    if microBar and microBar.ApplyStyling then microBar:ApplyStyling() end
end

function QueueEye.IsActive()
    return eye ~= nil and Wanted()
end

local function ApplyState()
    if not eye then return end
    if not Wanted() then
        eye:SetScript("OnUpdate", nil)
        eye:Hide()
        SetBlizzardEyeHidden(false)
        return
    end
    eye:Show()
    SetBlizzardEyeHidden(true)

    local now = ReadSearching()
    if now ~= searching then
        searching = now
        stepIndex, elapsed = 0, 0
    end
    if searching then
        ShowStep(stepIndex)
        eye:SetScript("OnUpdate", OnUpdate)
    else
        eye:SetScript("OnUpdate", nil)
        ShowStatic()
    end
    -- After any SetScript, which turns clicks back on
    eye:SetMouseMotionEnabled(false)
    eye:SetMouseClickEnabled(HasListItem())
end

-- Blizzard updates its eye on the same events; the read waits a tick so it
-- follows Blizzard's update whichever handler runs first
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        ApplyState()
    end)
end

function QueueEye.Refresh()
    ApplyState()
end

local function Create()
    local host = _G.QueueStatusButton
    if eye or not host then return end

    eye = CreateFrame("Button", "ScootQueueEye", host)
    eye:SetAllPoints(host)
    local okL, level = pcall(host.GetFrameLevel, host)
    if okL and type(level) == "number" then
        eye:SetFrameLevel(level + 5)
    end

    box = CreateFrame("Frame", nil, eye)
    box:SetPoint("CENTER", eye, "CENTER", 0, 0)
    fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(box)

    for i = 1, 4 do
        edges[i] = box:CreateTexture(nil, "BORDER")
    end
    edges[1]:SetPoint("TOPLEFT", box, "TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT", box, "TOPRIGHT")
    edges[2]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
    -- the sides (edges 3 and 4) are anchored in Layout, which knows the border

    for i = 1, 9 do
        dots[i] = box:CreateTexture(nil, "ARTWORK")
    end

    eye:RegisterForClicks("LeftButtonUp")
    eye:SetScript("OnClick", function()
        if GF.UI then GF.UI:Toggle() end
    end)
    eye:SetScript("OnSizeChanged", Layout)
    eye:SetScript("OnShow", QueueRefresh)
    if InCombatLockdown() then
        addon.Events.RunOutOfCombat(function() eye:SetPassThroughButtons("RightButton") end, OWNER)
    else
        eye:SetPassThroughButtons("RightButton")
    end

    Paint()
    Theme():Subscribe("GroupFinderQueueEye", Paint)
    Layout()

    for _, event in ipairs({
        "LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "LFG_ROLE_CHECK_UPDATE",
        "LFG_PROPOSAL_SHOW", "LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_SUCCEEDED",
        "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_APPLICATION_STATUS_UPDATED",
        "UPDATE_BATTLEFIELD_STATUS", "PLAYER_ENTERING_WORLD",
    }) do
        addon.Events.On(OWNER, event, QueueRefresh)
    end
    ApplyState()
end

-- From the component's initializer, so the eye exists only while the
-- module is on. QueueStatusButton is in the UI from the start; the world
-- entry covers a load order that runs this first.
function QueueEye.Install()
    if _G.QueueStatusButton then
        Create()
    else
        addon.Events.OnWorldEntered(Create)
    end
end

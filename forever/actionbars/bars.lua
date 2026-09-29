--------------------------------------------------------------------------------
-- forever/actionbars/bars.lua
-- The pool of identities, the build on world entry, the pushed state that
-- follows a native key, and /camelot actionbars. Stands on every other file
-- in the folder.
--
-- Each identity is one Camelot frame, built at load by frames.xml, whatever
-- cluster holds it. The buttons' page attributes, the drivers on Action Bar
-- 1 and the command each button reads for its hotkey text are fixed per
-- identity, so a cluster assignment moves a frame and rewrites no
-- attribute. Keybinds stay native: the player's ACTIONBUTTONn and
-- MULTIACTIONBARxBUTTONn keys fire Blizzard's own buttons, dimmed or parked,
-- paged by Blizzard's controller, and the pushed state below mirrors the
-- press onto the Camelot button holding that command.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local OWNER = ActionBars.OWNER

--------------------------------------------------------------------------------
-- The pool
--------------------------------------------------------------------------------

-- token -> the frame, the kind, the static page (nil pages by driver), the
-- binding command prefix, the label the dropdowns read, and the Blizzard
-- frame it stands in for. The eight action rows are what this phase builds.
ActionBars.POOL = {
    bar1 = { frame = "CamelotActionBar1", kind = "action", page = nil, command = "ACTIONBUTTON",
             label = "Action Bar 1", blizzard = "MainActionBar" },
    bar2 = { frame = "CamelotActionBar2", kind = "action", page = 6, command = "MULTIACTIONBAR1BUTTON",
             label = "Action Bar 2", blizzard = "MultiBarBottomLeft" },
    bar3 = { frame = "CamelotActionBar3", kind = "action", page = 5, command = "MULTIACTIONBAR2BUTTON",
             label = "Action Bar 3", blizzard = "MultiBarBottomRight" },
    bar4 = { frame = "CamelotActionBar4", kind = "action", page = 3, command = "MULTIACTIONBAR3BUTTON",
             label = "Action Bar 4", blizzard = "MultiBarRight" },
    bar5 = { frame = "CamelotActionBar5", kind = "action", page = 4, command = "MULTIACTIONBAR4BUTTON",
             label = "Action Bar 5", blizzard = "MultiBarLeft" },
    bar6 = { frame = "CamelotActionBar6", kind = "action", page = 13, command = "MULTIACTIONBAR5BUTTON",
             label = "Action Bar 6", blizzard = "MultiBar5" },
    bar7 = { frame = "CamelotActionBar7", kind = "action", page = 14, command = "MULTIACTIONBAR6BUTTON",
             label = "Action Bar 7", blizzard = "MultiBar6" },
    bar8 = { frame = "CamelotActionBar8", kind = "action", page = 15, command = "MULTIACTIONBAR7BUTTON",
             label = "Action Bar 8", blizzard = "MultiBar7" },
    pet = { kind = "pet", command = "BONUSACTIONBUTTON", label = "Pet Bar", blizzard = "PetActionBar" },
    stance = { kind = "stance", command = "SHAPESHIFTBUTTON", label = "Stance Bar", blizzard = "StanceBar" },
    microMenu = { kind = "leased", label = "Micro Menu", blizzard = "MicroMenuContainer" },
    bags = { kind = "leased", label = "Bags", blizzard = "BagsBar" },
}

ActionBars.POOL_ORDER = {
    "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8",
    "pet", "stance", "microMenu", "bags",
}

-- token -> frame, for the built identities; every Camelot button; and each
-- button by its binding command, for the pushed state.
ActionBars.Frames = {}
ActionBars.Buttons = {}
local byCommand = {}

--------------------------------------------------------------------------------
-- Pushed state
--------------------------------------------------------------------------------
-- A native key presses Blizzard's button, never the Camelot one, so the
-- functions the bindings call are hooked and the press is mirrored.

local MULTIBAR_INDEX = {
    MultiBarBottomLeft = 1, MultiBarBottomRight = 2, MultiBarRight = 3,
    MultiBarLeft = 4, MultiBar5 = 5, MultiBar6 = 6, MultiBar7 = 7,
}

local function press(command, down)
    local button = byCommand[command]
    if not button then return end
    if down then
        if button:GetButtonState() == "NORMAL" then
            button:SetButtonState("PUSHED")
        end
    elseif button:GetButtonState() == "PUSHED" then
        button:SetButtonState("NORMAL")
    end
end

local function HookPresses()
    hooksecurefunc("ActionButtonDown", function(id)
        press("ACTIONBUTTON" .. id, true)
    end)
    hooksecurefunc("ActionButtonUp", function(id)
        press("ACTIONBUTTON" .. id, false)
    end)
    hooksecurefunc("MultiActionButtonDown", function(barName, id)
        local n = MULTIBAR_INDEX[barName]
        if n then press("MULTIACTIONBAR" .. n .. "BUTTON" .. id, true) end
    end)
    hooksecurefunc("MultiActionButtonUp", function(barName, id)
        local n = MULTIBAR_INDEX[barName]
        if n then press("MULTIACTIONBAR" .. n .. "BUTTON" .. id, false) end
    end)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local built = false

local function Build()
    if built then return end

    for _, token in ipairs(ActionBars.POOL_ORDER) do
        local row = ActionBars.POOL[token]
        local frame = row.kind == "action" and _G[row.frame] or nil
        if frame then
            ActionBars.Frames[token] = frame
            for _, button in ipairs(frame.actionButtons) do
                ActionBars.Buttons[#ActionBars.Buttons + 1] = button
                byCommand[button.commandName] = button
            end
            -- The static page, the attribute Blizzard's multibars carry in
            -- their XML. The write runs OnAttributeChanged, which pages the
            -- button through UpdateAction now that the bar is wired.
            if row.page then
                for _, button in ipairs(frame.actionButtons) do
                    button:SetAttribute("actionpage", row.page)
                end
            end
        end
    end

    ActionBars.Events.Install()
    ActionBars.Paging.Register()
    ActionBars.Clusters.Build()
    ActionBars.Suppression.Apply()
    HookPresses()
    built = true
end

--- The whole build, out of combat; queued to regen when world entry lands
--- in a fight.
function ActionBars.Build()
    if built or not ActionBars.IsEnabled() then return end
    addon.Events.RunOutOfCombat(Build, "camelotActionBars.build")
end

function ActionBars.IsBuilt()
    return built
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

addon.Events.OnWorldEntered(function()
    if not ActionBars.IsEnabled() then return end
    ActionBars.Build()
    addon.EditMode.OnEditMode(OWNER, {
        enter = function() ActionBars.Suppression.Reassert() end,
        exit = function()
            ActionBars.Suppression.Reassert()
            -- The member strips never outlive Edit Mode.
            if ActionBars.Overlays then ActionBars.Overlays.Detach() end
        end,
    })
end)

addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", function()
    if not built then return end
    ActionBars.Suppression.Apply()
end)

--------------------------------------------------------------------------------
-- /camelot actionbars
--------------------------------------------------------------------------------

local SECURE_KEYS = {
    "bar", "container", "index", "commandName", "buttonType", "action",
    "ActionBarButtonMixin_OnLoad", "UpdateAction", "Update", "OnEvent", "CalculateAction",
    "ActionBarActionButtonDerivedMixin_OnClick", "SetButtonState",
}

local function frameName(frame)
    if not frame then return "nil" end
    return frame:GetName() or tostring(frame)
end

local function durationGetters()
    local names = {}
    for _, ns in ipairs({ { "C_ActionBar", C_ActionBar }, { "C_Spell", C_Spell } }) do
        for key in pairs(ns[2]) do
            if type(key) == "string" and key:find("Duration") then
                names[#names + 1] = ns[1] .. "." .. key
            end
        end
    end
    table.sort(names)
    return names
end

function ActionBars.Dump()
    local lines, push = addon.DebugLines()

    push("Camelot action bars: enabled %s, built %s, events %s, paging %s, clusters %s, park %s, lockdown %s",
        tostring(ActionBars.IsEnabled()), tostring(built), tostring(ActionBars.Events.IsInstalled()),
        tostring(ActionBars.Paging.IsRegistered()), tostring(ActionBars.Clusters.IsBuilt()),
        tostring(ActionBars.Suppression.IsApplied()), tostring(InCombatLockdown()))
    push("")

    push("identities:")
    for _, token in ipairs(ActionBars.POOL_ORDER) do
        local row = ActionBars.POOL[token]
        local frame = ActionBars.Frames[token]
        if frame then
            local first = frame.actionButtons[1]
            push("  %-10s %-18s parent %-28s shown %-5s visible %-5s level %3d  %2d/%2d buttons  page %-4s %.0fx%.0f",
                token, row.frame, frameName(frame:GetParent()), tostring(frame:IsShown()),
                tostring(frame:IsVisible()), frame:GetFrameLevel(), frame.numButtonsShowable or 0,
                frame.numButtons or 0, tostring(first and first:GetAttribute("actionpage")),
                frame:GetWidth(), frame:GetHeight())
        else
            push("  %-10s %-18s not built (%s)", token, row.frame or row.label, row.kind)
        end
    end
    push("")

    push("clusters:")
    for _, r in ipairs(ActionBars.Clusters.Report()) do
        push("  cluster %d \"%s\" %s %s %s", r.id, tostring(r.label), r.axis, r.size and ("size " .. r.size) or "",
            r.anchor and ("anchor " .. r.anchor) or (r.note or ""))
        for _, m in ipairs(r.members) do push("    %s", m) end
        if r.position then
            push("    position %s, dynamic %s", r.position, tostring(r.dynamic))
        end
        if r.position and ActionBars.EditMode and ActionBars.Overlays then
            push("    subject %s, strips %s", tostring(ActionBars.EditMode.Subject(r.id)),
                ActionBars.Overlays.IsAttachedTo(r.id) and "up" or "down")
        end
    end
    local unassigned = ActionBars.Clusters.Unassigned()
    push("  unassigned: %s", #unassigned > 0 and table.concat(unassigned, ", ") or "none")
    push("  main bar buttons mouse off: %s", tostring(ActionBars.Suppression.IsMouseOff()))
    local micro = MicroMenuContainer
    if micro then
        push("  MicroMenuContainer %.0fx%.0f at %s, left %s bottom %s", micro:GetWidth(), micro:GetHeight(),
            frameName(micro:GetParent()), tostring(micro:GetLeft()), tostring(micro:GetBottom()))
    end
    push("")

    push("blizzard frames:")
    ActionBars.Suppression.Report(push)
    push("")

    local sample = ActionBars.Frames.bar2 and ActionBars.Frames.bar2.actionButtons[1]
    if sample then
        push("secure fields on %s:", frameName(sample))
        for _, key in ipairs(SECURE_KEYS) do
            local secure, taintedBy = issecurevariable(sample, key)
            push("  %-42s %s%s", key, secure and "secure" or "tainted",
                taintedBy and (" by " .. tostring(taintedBy)) or "")
        end
        push("")
    end

    push("duration getters present:")
    for _, name in ipairs(durationGetters()) do push("  %s", name) end
    push("")

    push("paging: %s", tostring(ActionBars.Paging.conditions))
    local dropped = ActionBars.Paging.dropped
    push("  dropped at build: %s", dropped and #dropped > 0 and table.concat(dropped, ", ") or "none")
    push("  now: %s", ActionBars.Paging.Snapshot("now"))
    push("  edges (%d):", #ActionBars.Paging.Rows())
    for _, row in ipairs(ActionBars.Paging.Rows()) do push("  %s", row) end
    push("")

    local blocked, blockedCount = ActionBars.Events.BlockedRows()
    push("blocked actions naming this addon: %d, ticking buttons %d", blockedCount,
        ActionBars.Events.TickingCount())
    for _, row in ipairs(blocked) do push("  %s", row) end
    push("notes (%d):", #ActionBars.Events.NoteRows())
    for _, row in ipairs(ActionBars.Events.NoteRows()) do push("  %s", row) end

    addon.DebugShowWindow("Camelot action bars", lines)
end

addon:RegisterSlashCommand({
    name = "actionbars",
    help = "dump the action bars: identities, clusters, the parked Blizzard bars, the secure fields, "
        .. "the duration getters, the paging log and the blocked-action log",
    handler = function()
        ActionBars.Dump()
    end,
})

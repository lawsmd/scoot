--------------------------------------------------------------------------------
-- forever/professions/skillups.lua
-- Skill Up Notifications: the painter of the professionSkillUp notification
-- source (professions.lua registers the source and holds the settings;
-- forever/notifications/ draws the toast around it).
--
-- A toast is the profession's icon and a number. It rises showing the level
-- the player had, and at the anchor the digits that change roll to the new
-- level. A further point in the same profession while the toast is up rolls
-- the same number on: the push carries the skill line as its key.
--
-- With Roll From Previous Level off the toast shows the new level from the
-- start.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Professions = addon.Professions
local Notifications = addon.Notifications
local Data = Professions.Data
local Icon = Professions.Icon
local RollingNumber = Notifications.RollingNumber

-- Between the icon and the number, against the text size.
local GAP_RATIO = 0.2

-- The icon the client's professions book draws for an empty slot, for a
-- sample on a character with no profession.
local SAMPLE_ICON = "Interface\\Icons\\INV_Scroll_04"
local SAMPLE_START = 79

local painter = {}

function painter.build(toast)
    toast.Icon = Icon.Create(toast)
    toast.Number = RollingNumber.Create(toast)
end

function painter.show(toast, data, metrics)
    local showIcon = Professions.SkillUpsGet("showIcon") ~= false
    local roll = Professions.SkillUpsGet("roll") ~= false
    local number = toast.Number

    number:SetLook(metrics.face, metrics.size, metrics.style, Professions.NumberColor())
    toast.target = data.to
    local numberWidth, numberHeight
    if roll and data.from then
        numberWidth, numberHeight = number:SetValue(data.from, data.to)
    else
        numberWidth, numberHeight = number:SetValue(data.to)
    end

    local gap = math.floor(metrics.size * GAP_RATIO + 0.5)
    local width, height = numberWidth, numberHeight
    toast.Icon:SetShown(showIcon)
    number.frame:ClearAllPoints()
    if showIcon then
        Icon.Paint(toast.Icon, data.icon or SAMPLE_ICON, metrics.iconSize)
        toast.Icon:ClearAllPoints()
        toast.Icon:SetPoint("LEFT", toast, "LEFT", 0, 0)
        number.frame:SetPoint("LEFT", toast.Icon, "RIGHT", gap, 0)
        width = metrics.iconSize + gap + numberWidth
        height = math.max(metrics.iconSize, numberHeight)
    else
        number.frame:SetPoint("CENTER", toast, "CENTER", 0, 0)
    end
    return width, height
end

function painter.arrive(toast)
    return toast.Number:RollTo(toast.target)
end

function painter.update(toast, data, there)
    toast.target = data.to
    if there then return toast.Number:RollTo(data.to) end
    return 0
end

function painter.tick(toast, elapsed)
    toast.Number:Tick(elapsed)
end

-- Each sample is one point on from the last, so a second press of a Test
-- button rolls the toast that is already up.
local sampleAt = SAMPLE_START
function painter.sample()
    local first = Data.Current()[1]
    local from = sampleAt
    sampleAt = sampleAt + 1
    return { key = "sample", icon = first and first.icon or SAMPLE_ICON, from = from, to = from + 1 }
end

Notifications.SetPainter(Professions.SOURCE, painter)

Data.OnSkillUp(function(entry, oldRank)
    if entry.secondary and Professions.SkillUpsGet("secondary") == false then return end
    Notifications.Push(Professions.SOURCE, {
        key = entry.skillLine, icon = entry.icon, from = oldRank, to = entry.rank,
    })
end)

--------------------------------------------------------------------------------
-- Dump
--------------------------------------------------------------------------------

local function dump()
    local lines, push = addon.DebugLines()
    local list, complete = Data.Read()
    local tracker = Professions.TrackerState()
    push("Professions: %d read, the read %s", #list, complete and "held" or "did not hold")
    push("  tracker %s: built %s, shown %s, alpha %.2f, rows %d, preview %s",
        Professions.TrackerOn() and "on" or "off", tostring(tracker.built), tostring(tracker.shown),
        tracker.alpha, tracker.rows, tostring(tracker.preview))
    push("  skill-up notifications %s", Professions.SkillUpsOn() and "on" or "off")
    push("")
    for _, entry in ipairs(list) do
        push("  %s (skill line %d, %s): level %d, cap %d, band %d to %d, icon %s",
            entry.name, entry.skillLine, entry.secondary and "secondary" or "primary",
            entry.rank, entry.cap, entry.lower, entry.upper, tostring(entry.icon))
    end
    addon.DebugShowWindow("Professions", lines)
end

local function test(from, to)
    from, to = tonumber(from), tonumber(to)
    if not (from and to) then return addon.Commands.USAGE end
    local first = Data.Current()[1]
    Notifications.Push(Professions.SOURCE, {
        key = "test", icon = first and first.icon or SAMPLE_ICON, from = from, to = to,
    })
end

addon:RegisterSlashCommand({
    name = "professions",
    help = "the professions read and the skill-up toast",
    default = "state",
    verbs = {
        { word = "state", help = "show the professions read, each level's band and the tracker's state", fn = dump },
        { word = "test", usage = "test <from> <to>", help = "play a skill-up toast between two levels", fn = test },
    },
})

-- signup.lua - the sign-up dialog: the roles the player offers, the note to
-- the leader, Sign Up and Cancel.
--
-- A WindowShell on the dialog role, centred on the window. The roles are
-- three tiles that read and write the client's own role choice through
-- GetLFGRoles and SetLFGRoles, as Blizzard's role buttons do, and only the
-- roles the class can fill take a click. The note is Blizzard's own box,
-- hosted: its dialog frame is shown with no points at alpha 0 so the box
-- renders, and the box goes back when this dialog hides. Sign Up makes the
-- one protected call, ApplyToGroup, from its click. A search finishing
-- hides Blizzard's dialog, and the box with it, so this one hides on the
-- same event.
local addonName, addon = ...

local GF = addon.GroupFinder
local UI = GF.UI
local LAYOUT = UI.LAYOUT
local Host = GF.Host
local Str = GF.Str

local SignUp = {}
UI.SignUp = SignUp

local function Controls()
    return addon.UI.Controls
end

local dialog
local parts = {}
local lastActivityID

local function SetTextSafe(fs, value)
    if type(value) == "string" then
        fs:SetText(value)
    else
        fs:SetText("")
    end
end

local function Build()
    local C = Controls()
    local titleHeight = LAYOUT.titleHeight
    dialog = addon.UI.WindowShell.Create({
        name = addon.Brand .. "GroupFinderSignUp",
        width = LAYOUT.dialogWidth,
        height = LAYOUT.dialogHeight + titleHeight,
        role = "dialog",
        title = "SIGN UP",
        titleFontRole = "label",
        titleHeight = titleHeight,
        movable = false,
        escape = "capture",
        onEscape = function() SignUp:Hide() end,
        onClose = function() SignUp:Hide() end,
        strata = "DIALOG",
        level = LAYOUT.dialogLevel,
    })
    dialog:Hide()

    local padX = 12
    local y = -(titleHeight + 8)

    parts.name = UI.PrimaryText(dialog, "label")
    parts.name:SetPoint("TOPLEFT", dialog, "TOPLEFT", padX, y)
    parts.name:SetPoint("RIGHT", dialog, "RIGHT", -padX, 0)
    parts.name:SetWordWrap(false)

    parts.activity = UI.DimText(dialog, "desc")
    parts.activity:SetPoint("TOPLEFT", parts.name, "BOTTOMLEFT", 0, -2)
    parts.activity:SetPoint("RIGHT", dialog, "RIGHT", -padX, 0)
    parts.activity:SetWordWrap(false)

    parts.choose = UI.DimText(dialog, "desc")
    parts.choose:SetPoint("TOPLEFT", parts.activity, "BOTTOMLEFT", 0, -8)
    parts.choose:SetText(Str("LFG_LIST_CHOOSE_YOUR_ROLES", "Choose your roles"))

    parts.marks = C.CreateRoleMarks(dialog, {
        mode = "toggle",
        onChange = function(tank, healer, damage) SignUp:OnRolesChanged(tank, healer, damage) end,
    })
    -- Under the three lines above, centred as Blizzard's buttons are
    parts.marks:SetPoint("TOP", dialog, "TOP", 0, y - 62)

    -- The note box's holder, where Blizzard's sits: 210 wide, above the buttons
    local holder = CreateFrame("Frame", nil, dialog)
    Host.DressHolder(holder)
    holder:SetSize(210, 28)
    holder:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 52)
    parts.holder = holder

    parts.note = UI.DimText(dialog, "desc")
    parts.note:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 36)
    parts.note:SetJustifyH("CENTER")

    parts.signUp = UI.MakeButton(dialog, Str("SIGN_UP", "Sign Up"), function() SignUp:Apply() end, 100)
    parts.signUp:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -5, 10)

    parts.cancel = UI.MakeButton(dialog, Str("CANCEL", "Cancel"), function() SignUp:Hide() end, 100)
    parts.cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 5, 10)

    dialog:HookScript("OnHide", function() SignUp:OnHidden() end)

    GF.Listen("roles", function()
        if dialog:IsShown() then SignUp:RefreshRoles() end
    end)
    GF.Listen("results", function()
        if dialog:IsShown() then SignUp:Hide() end
    end)
end

-- The roles the class can fill take a click; the choice is the client's
-- own, read back from GetLFGRoles
function SignUp:RefreshRoles()
    local availTank, availHealer, availDPS = C_LFGList.GetAvailableRoles()
    local marks = parts.marks
    marks:SetRoleEnabled("TANK", availTank)
    marks:SetRoleEnabled("HEALER", availHealer)
    marks:SetRoleEnabled("DAMAGER", availDPS)
    local _, tank, healer, dps = GetLFGRoles()
    marks:SetRoles(tank and availTank, healer and availHealer, dps and availDPS)
    self:RefreshValid()
end

function SignUp:OnRolesChanged(tank, healer, damage)
    local leader = GetLFGRoles()
    SetLFGRoles(leader, tank and true or false, healer and true or false, damage and true or false)
    self:RefreshValid()
end

function SignUp:RefreshValid()
    local tank, healer, damage = parts.marks:GetRoles()
    local valid = (tank or healer or damage) and true or false
    parts.signUp:SetEnabled(valid)
    parts.note:SetText(valid and "" or Str("LFG_LIST_MUST_SELECT_ROLE", "Choose at least one role"))
end

function SignUp:Show(resultID)
    if not resultID then return end
    local info = GF.ResultInfo(resultID)
    if not info then return end
    if not dialog then Build() end
    self.resultID = resultID

    -- Blizzard clears the note when the activity changes between sign-ups
    local activityID = GF.ActivityID(info)
    if activityID ~= lastActivityID and C_LFGList.ClearApplicationTextFields then
        C_LFGList.ClearApplicationTextFields()
    end
    lastActivityID = activityID

    SetTextSafe(parts.name, info.name)
    parts.activity:SetText(GF.ActivityName(info) or "")
    self:RefreshRoles()

    local anchor = UI:GetFrame() or UIParent
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    dialog:Show()
    dialog:Raise()

    local blizzard = LFGListApplicationDialog
    if Host.ShowDialogFrame() and blizzard and blizzard.Description then
        Host.Take("note", blizzard.Description, parts.holder, {
            editBox = blizzard.Description.EditBox,
            artKeys = Host.SCROLL_BOX_ART,
        })
    end
end

function SignUp:Apply()
    local tank, healer, damage = parts.marks:GetRoles()
    if not (tank or healer or damage) then return end
    C_LFGList.ApplyToGroup(self.resultID, tank and true or false, healer and true or false, damage and true or false)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    self:Hide()
end

function SignUp:Hide()
    if dialog and dialog:IsShown() then dialog:Hide() end
end

function SignUp:OnHidden()
    Host.Release("note")
    Host.HideDialogFrame()
end

function SignUp:IsShown()
    return dialog ~= nil and dialog:IsShown()
end

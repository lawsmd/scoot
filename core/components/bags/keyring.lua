--------------------------------------------------------------------------------
-- core/components/bags/keyring.lua
-- The keyring's own window, on a client that has a keyring. The bag window
-- leaves the keyring out: its empty slots would read as bag space. The one
-- way to open this window is the Keyring button at the bag window's coin box;
-- it never opens with the bags, it follows none of Blizzard's open paths, and
-- it closes when the bag window does.
--
-- The frame is the bag window's portrait template with the portrait hidden
-- (Blizzard's ButtonFrameTemplate_HidePortrait), so its header is the title
-- bar alone. Four columns, centered in the body.
--
-- The frame is never smaller than its border's corners: Forever's corners are
-- about 95 units each, so four keys on one line in a frame of their own size
-- put the top and bottom corners over each other. The minimum is read off
-- the corner textures after the layout is applied, so either client's art
-- sets it.
--------------------------------------------------------------------------------

local _, addon = ...

local Bags = addon.Bags

local Keyring = {}
Bags.Keyring = Keyring

local PAD_LEFT = 8
local PAD_RIGHT = 7
local PAD_TOP = 30
local PAD_BOTTOM = 9
local GAP_TO_BAGS = 8
-- Room between the corners at the minimum size.
local CORNER_SLACK = 12

local frame

function Keyring.IsBuilt()
    return frame ~= nil
end

function Keyring.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Keyring.Content()
    return frame and frame._content
end

-- With nothing saved: left of the bag window.
local function PlaceDefault()
    frame:ClearAllPoints()
    local bags = Bags.Window.Frame()
    if bags and bags:IsShown() then
        frame:SetPoint("BOTTOMRIGHT", bags, "BOTTOMLEFT", -GAP_TO_BAGS, 0)
    else
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110)
    end
end

local function HidePortrait(f)
    if ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(f)
    elseif f.SetPortraitShown then
        f:SetPortraitShown(false)
    end
end

local function Build()
    if frame then return end
    frame = Bags.Window.NewFrame({
        name = addon.Brand .. "KeyringWindow",
        title = KEYRING or "Keyring",
        onClose = function() Keyring.Close() end,
        positionKey = "keyringWindowPosition",
    })
    HidePortrait(frame)
    frame:HookScript("OnHide", function()
        if Bags.Delete then Bags.Delete.Hide() end
    end)
    Keyring.ApplySettings()
end

function Keyring.ApplySettings()
    if not frame then return end
    local scale = tonumber(Bags.Get("scale")) or 90
    frame:SetScale(math.max(0.5, math.min(2, scale / 100)))
end

-- The smallest frame whose corners do not overlap, from the corners' sizes
-- and the offsets the layout gives them (left and top run past the frame).
local function CornerMinimum()
    local ns = frame.NineSlice
    local tl, tr, bl = ns and ns.TopLeftCorner, ns and ns.TopRightCorner, ns and ns.BottomLeftCorner
    if not (tl and tr and bl) then return 0, 0 end
    local _, _, _, tlx, tly = tl:GetPoint(1)
    local _, _, _, trx = tr:GetPoint(1)
    local _, _, _, _, bly = bl:GetPoint(1)
    local w = tl:GetWidth() + tr:GetWidth() + (tlx or 0) - (trx or 0)
    local h = tl:GetHeight() + bl:GetHeight() - (tly or 0) + (bly or 0)
    return w + CORNER_SLACK, h + CORNER_SLACK
end

function Keyring.FitContent(width, height)
    if not frame then return end
    width, height = math.max(1, width), math.max(1, height)
    local minW, minH = CornerMinimum()
    local w = math.max(PAD_LEFT + width + PAD_RIGHT, minW)
    local h = math.max(PAD_TOP + height + PAD_BOTTOM, minH)
    frame:SetSize(w, h)
    -- Centered in the body under the title bar.
    local content = frame._content
    content:SetSize(width, height)
    content:ClearAllPoints()
    local x = PAD_LEFT + math.floor((w - PAD_LEFT - PAD_RIGHT - width) / 2)
    local y = PAD_TOP + math.floor((h - PAD_TOP - PAD_BOTTOM - height) / 2)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
end

function Keyring.Open()
    if not Bags.HasKeyring() then return end
    Build()
    if frame:IsShown() then return end
    if not frame._restored then PlaceDefault() end
    frame:Show()
    Bags.Refresh()
end

function Keyring.Close()
    if not frame or not frame:IsShown() then return end
    frame:Hide()
end

function Keyring.Toggle()
    if Keyring.IsShown() then Keyring.Close() else Keyring.Open() end
end

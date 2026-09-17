-- dialogs.lua - Base dialog module with TUI override support
local addonName, addon = ...

addon.Dialogs = {}
addon.Dialogs._registry = {}

-- StaticPopupDialogs is one global table, and both addons load this file in
-- the retail client, so the fallback popup is keyed by brand.
local FALLBACK = (addon.Brand or "Scoot") .. "_FALLBACK"

function addon.Dialogs:Register(name, definition)
    if name and definition then
        self._registry[name] = definition
    end
end

function addon.Dialogs:Show(name, options)
    -- Fallback until Dialog.lua overrides with the TUI version
    options = options or {}
    local def = self._registry[name] or {}

    local text = options.text or def.text or "Dialog"
    local formatArgs = options.formatArgs or def.formatArgs
    if formatArgs and type(formatArgs) == "table" and #formatArgs > 0 then
        text = string.format(text, unpack(formatArgs))
    end

    -- Use StaticPopup as fallback
    StaticPopupDialogs[FALLBACK] = {
        text = text,
        button1 = options.acceptText or def.acceptText or OKAY,
        button2 = options.cancelText or def.cancelText or CANCEL,
        hasEditBox = options.hasEditBox or def.hasEditBox,
        maxLetters = options.maxLetters or def.maxLetters or 32,
        OnAccept = function(self, data)
            local editText = self.editBox and self.editBox:GetText()
            if options.onAccept then
                options.onAccept(data, editText)
            end
        end,
        OnCancel = function(self, data)
            if options.onCancel then
                options.onCancel(data)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(FALLBACK, nil, nil, options.data)
end

function addon.Dialogs:Confirm(message, onAccept, onCancel)
    return self:Show(nil, {
        text = message,
        onAccept = onAccept,
        onCancel = onCancel,
    })
end

function addon.Dialogs:Info(message, onDismiss)
    return self:Show(nil, {
        text = message,
        onAccept = onDismiss,
        infoOnly = true,
    })
end

function addon.Dialogs:Hide()
    StaticPopup_Hide(FALLBACK)
end

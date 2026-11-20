-- WoWHelper: guide window, guide picker and JSON import window.
local _, ns = ...
local WH = ns.WH

local PAD = 6
local HEADER_H = 20
local FOOTER_H = 18
local ICON = 14
local MAX_ROWS = 10

local ICONS = {
    accept = "Interface\\GossipFrame\\AvailableQuestIcon",
    complete = "Interface\\GossipFrame\\IncompleteQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
    ["goto"] = "Interface\\Icons\\INV_Misc_Map_01",
    fly = "Interface\\GossipFrame\\TaxiGossipIcon",
    flightpath = "Interface\\GossipFrame\\TaxiGossipIcon",
    sethearth = "Interface\\GossipFrame\\BinderGossipIcon",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01",
    train = "Interface\\GossipFrame\\TrainerGossipIcon",
    buy = "Interface\\GossipFrame\\VendorGossipIcon",
    level = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
    note = "Interface\\GossipFrame\\GossipGossipIcon",
}

local Q = "|cffffd100%s|r"     -- quest names
local G = "|cff9d9d9d%s|r"     -- coordinates / grey text

---------------------------------------------------------------------------
-- Small widget helpers (own textures, so no Blizzard templates are needed)
---------------------------------------------------------------------------
local function addBorder(f, r, g, b, a)
    local function edge(p1, p2, w, h)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

local function flatButton(parent, label, w, h, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.08)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.18)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    if tooltip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    return b
end
WH.FlatButton = flatButton
WH.AddBorder = addBorder

local function panel(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
    addBorder(f, 0, 0, 0, 1)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText(title)
    local close = flatButton(f, "x", 18, 18)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)
    tinsert(UISpecialFrames, name)
    f:Hide()
    return f
end

---------------------------------------------------------------------------
-- Step text
---------------------------------------------------------------------------
local function stepText(s)
    if s.text then return s.text end
    local a = s.action
    local quest = s.quest and Q:format(s.quest) or ("quest " .. tostring(s.questId))
    if a == "accept" then
        return "Accept " .. quest .. (s.npc and (" from " .. s.npc) or "")
    elseif a == "complete" then
        return "Complete " .. quest
    elseif a == "turnin" then
        return "Turn in " .. quest .. (s.npc and (" to " .. s.npc) or "")
    elseif a == "goto" then
        return "Go to " .. (s.location or s.npc or s.zone or "the marked location")
    elseif a == "fly" then
        return "Fly to " .. (s.location or s.zone or "the next zone")
    elseif a == "flightpath" then
        return "Get the flight path" .. (s.location and (" at " .. s.location) or "")
    elseif a == "sethearth" then
        return "Set your hearthstone" .. (s.location and (" at " .. s.location) or "")
    elseif a == "hearth" then
        return "Hearth" .. (s.location and (" to " .. s.location) or "")
    elseif a == "train" then
        return "Train new spells" .. (s.npc and (" at " .. s.npc) or "")
    elseif a == "buy" then
        return "Buy " .. (s.item or "supplies") .. (s.npc and (" from " .. s.npc) or "")
    elseif a == "level" then
        return "Grind to level " .. s.level
    end
    return "?"
end
WH.StepText = stepText

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
function WH:CreateUI()
    local db = self.db
    local f = CreateFrame("Frame", "WoWHelperFrame", UIParent)
    self.frame = f
    f:SetSize(db.width, 80)
    f:SetScale(db.scale)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(240, 60, 800, 1200) end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        WH:SavePosition()
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    addBorder(f, 0, 0, 0, 0.9)

    -- Header
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", PAD, -4)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)

    f.nextBtn = flatButton(f, ">", 18, 16, "Mark the current step done")
    f.nextBtn:SetPoint("TOPRIGHT", -PAD + 2, -3)
    f.nextBtn:SetScript("OnClick", function() WH:CompleteCurrentStep() end)
    f.prevBtn = flatButton(f, "<", 18, 16, "Go back one step")
    f.prevBtn:SetPoint("RIGHT", f.nextBtn, "LEFT", -2, 0)
    f.prevBtn:SetScript("OnClick", function() WH:PreviousStep() end)
    f.menuBtn = flatButton(f, "=", 18, 16, "Choose a guide")
    f.menuBtn:SetPoint("RIGHT", f.prevBtn, "LEFT", -2, 0)
    f.menuBtn:SetScript("OnClick", function() WH:ToggleGuidePicker() end)
    f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.counter:SetPoint("RIGHT", f.menuBtn, "LEFT", -6, 0)
    f.title:SetPoint("RIGHT", f.counter, "LEFT", -6, 0)

    -- Step rows
    f.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 0.82, 0, 0.10)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("TOPLEFT", 2, -2)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.note:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -1)
        row.note:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.note:SetJustifyH("LEFT")
        row.note:SetWordWrap(true)
        row:SetScript("OnClick", function(self, button)
            if not self.index then return end
            if button == "RightButton" then
                WH:ToggleStepDone(self.index)
            else
                WH:SetWaypointForStep(WH:GetGuide().steps[self.index], true)
            end
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Step " .. (self.index or "?"), 1, 1, 1)
            GameTooltip:AddLine("Left-click: set waypoint", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click: mark done / not done", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        f.rows[i] = row
    end

    -- Footer: arrow + distance to the current step
    f.arrow = f:CreateTexture(nil, "OVERLAY")
    f.arrow:SetSize(16, 16)
    f.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.arrow:SetPoint("BOTTOMLEFT", PAD - 2, 2)
    f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.dist:SetPoint("LEFT", f.arrow, "RIGHT", 2, 0)
    f.dist:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.dist:SetJustifyH("LEFT")

    -- Resize grip (width only matters; height follows the content)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() if not db.locked then f:StartSizing("RIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        db.width = math.floor(f:GetWidth() + 0.5)
        WH:SavePosition()
        WH:UpdateUI()
    end)
    f.grip = grip

    self:ApplyPosition()
    self:SetLocked(db.locked, true)
    f:SetShown(not db.hidden)

    C_Timer.NewTicker(0.25, function()
        if not f:IsShown() then return end
        WH:UpdateDistance()
        WH:CheckLocationStep()
    end)
end

-- Default position: just above the main chat window (and its tabs), bottom-left.
function WH:ApplyPosition()
    local f, p = self.frame, self.db.point
    f:ClearAllPoints()
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif ChatFrame1 then
        f:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", -4, 32)
    else
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 280)
    end
end

-- Saved as a BOTTOMLEFT anchor so the window keeps growing upwards.
function WH:SavePosition()
    local f = self.frame
    local left, bottom = f:GetLeft(), f:GetBottom()
    if not left then return end
    self.db.point = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
    self:ApplyPosition()
end

function WH:ResetPosition()
    self.db.point = nil
    self:ApplyPosition()
    self:Print("Window moved back above the chat frame.")
end

function WH:SetLocked(locked, quiet)
    self.db.locked = locked and true or false
    if self.frame then self.frame.grip:SetShown(not self.db.locked) end
    if not quiet then self:Print(self.db.locked and "Window locked." or "Window unlocked: drag it to move it.") end
end

function WH:SetShown(shown)
    self.db.hidden = not shown
    if self.frame then
        self.frame:SetShown(shown)
        if shown then self:UpdateUI() end
    end
end

function WH:SetScale(scale)
    self.db.scale = math.max(0.5, math.min(2, scale))
    if self.frame then self.frame:SetScale(self.db.scale) end
end

local function formatCoords(s)
    if not (s.x and s.y) then return "" end
    return " " .. G:format(("(%.1f, %.1f)"):format(s.x, s.y))
end

function WH:UpdateUI()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local db = self.db
    f:SetWidth(db.width)

    local g = self:GetGuide()
    for _, row in ipairs(f.rows) do row:Hide() end
    if not g then
        f.title:SetText("WoWHelper")
        f.counter:SetText("")
        f.dist:SetText("No guide for this character. Click = to pick one.")
        f.arrow:Hide()
        f:SetHeight(HEADER_H + FOOTER_H + PAD)
        return
    end

    local cur = self.char.progress[g.id] or 1
    f.title:SetText(("%s |cff9d9d9d(%d-%d)|r"):format(g.title, g.minLevel, g.maxLevel))
    f.counter:SetText(("%d/%d"):format(math.min(cur, #g.steps), #g.steps))

    if cur > #g.steps then
        local row = f.rows[1]
        row.index = nil
        row.icon:SetTexture(ICONS.note)
        row.text:SetText(g.next and "Guide finished." or "Guide finished. Pick the next one with =.")
        row.note:SetText("")
        row.hl:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, -HEADER_H)
        row:SetPoint("RIGHT", -PAD, 0)
        row:SetHeight(ICON + 4)
        row:Show()
        f:SetHeight(HEADER_H + ICON + 4 + FOOTER_H + PAD)
        return
    end

    local y, shown = HEADER_H, 0
    local want = math.max(1, math.min(MAX_ROWS, db.stepsShown))
    for i = cur, #g.steps do
        if shown >= want then break end
        local s = g.steps[i]
        if self:StepApplies(s) and (i == cur or not self:IsStepDone(g, i, false)) then
            shown = shown + 1
            local row = f.rows[shown]
            row.index = i
            row.icon:SetTexture(ICONS[s.action] or ICONS.note)
            row.text:SetText(stepText(s) .. (db.showCoords and formatCoords(s) or ""))
            local noteText = (db.showNotes and s.note) or ""
            row.note:SetText(noteText)
            row.hl:SetShown(i == cur)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
            row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
            row:SetHeight(100) -- give the strings room to measure wrapped height
            local h = math.max(ICON, row.text:GetStringHeight())
            if noteText ~= "" then h = h + 1 + row.note:GetStringHeight() end
            h = h + 4
            row:SetHeight(h)
            row:SetAlpha(i == cur and 1 or 0.75)
            row:Show()
            y = y + h + 1
        end
    end
    f:SetHeight(y + FOOTER_H + PAD)
    self:UpdateDistance()
end

local COMPASS = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }

function WH:UpdateDistance()
    local f = self.frame
    if not f then return end
    local s = self:GetCurrentStep()
    if not s or not (s.mapId and s.x) then
        f.arrow:Hide()
        f.dist:SetText(s and s.zone and G:format(s.zone) or "")
        return
    end
    local d, bearing = self:GetStepDistance(s)
    if not d then
        f.arrow:Hide()
        f.dist:SetText("Travel to " .. (s.zone or self:GetZoneName(s.mapId) or "the next zone"))
        return
    end
    -- bearing is counter-clockwise from north, like GetPlayerFacing()
    local idx = math.floor(((bearing % (2 * math.pi)) / (2 * math.pi)) * 8 + 0.5) % 8 + 1
    local facing = GetPlayerFacing and GetPlayerFacing()
    if facing and not (issecretvalue and issecretvalue(facing)) then
        f.arrow:SetRotation(bearing - facing)
        f.arrow:Show()
    else
        f.arrow:Hide()
    end
    f.dist:SetText(("%d yd %s"):format(d, COMPASS[idx]) .. (s.zone and ("  " .. G:format(s.zone)) or ""))
end

---------------------------------------------------------------------------
-- Guide picker
---------------------------------------------------------------------------
function WH:ToggleGuidePicker()
    if not self.picker then self:CreateGuidePicker() end
    if self.picker:IsShown() then self.picker:Hide() else self:UpdateGuidePicker() self.picker:Show() end
end

function WH:CreateGuidePicker()
    local p = panel("WoWHelperGuidePicker", 340, 420, "Choose a guide")
    self.picker = p
    p.buttons = {}
    for i = 1, 16 do
        local b = flatButton(p, "", 320, 18)
        b:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 20)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self)
            WH:SetGuide(self.guideId)
            p:Hide()
        end)
        p.buttons[i] = b
    end
    local auto = flatButton(p, "Pick for my level", 320, 20,
        "Switches to the guide for your level and skips quests you have already done.")
    auto:SetPoint("BOTTOMLEFT", 10, 36)
    auto:SetScript("OnClick", function()
        WH:AutoSelectGuide()
        p:Hide()
    end)
    local all = flatButton(p, "Show all guides", 120, 20)
    all:SetPoint("BOTTOMLEFT", 10, 10)
    all:SetScript("OnClick", function()
        p.showAll = not p.showAll
        all.text:SetText(p.showAll and "Show my guides" or "Show all guides")
        WH:UpdateGuidePicker()
    end)
    local reset = flatButton(p, "Restart current guide", 150, 20,
        "Clears your progress in the current guide and starts it from step 1.")
    reset:SetPoint("BOTTOMRIGHT", -10, 10)
    reset:SetScript("OnClick", function()
        local g = WH:GetGuide()
        if not g then return end
        WH.char.progress[g.id] = 1
        WH.char.manual[g.id] = {}
        WH:Refresh(true)
        WH:Print("Restarted %s.", g.title)
    end)
    local import = flatButton(p, "Import...", 70, 20)
    import:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    import:SetScript("OnClick", function() p:Hide() WH:ShowImport() end)
end

function WH:UpdateGuidePicker()
    local p = self.picker
    local list = self:GetGuidesForPlayer(p.showAll)
    for i, b in ipairs(p.buttons) do
        local g = list[i]
        if g then
            local cur = (g.id == self.char.guideId) and "|cff33ff99> |r" or ""
            local tag = g.source == "imported" and " |cff9d9d9d[imported]|r" or ""
            b.text:SetText(("%s%s |cff9d9d9d%d-%d|r%s"):format(cur, g.title, g.minLevel, g.maxLevel, tag))
            b.guideId = g.id
            b:Show()
        else
            b:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Import window
---------------------------------------------------------------------------
function WH:ShowImport()
    if not self.importFrame then
        local p = panel("WoWHelperImport", 480, 360, "Import a JSON guide")
        self.importFrame = p
        local scroll
        local ok = pcall(function()
            scroll = CreateFrame("ScrollFrame", "WoWHelperImportScroll", p, "UIPanelScrollFrameTemplate")
        end)
        if not ok or not scroll then
            scroll = CreateFrame("ScrollFrame", nil, p)
            scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", function(self, delta)
                local v = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 30))
                self:SetVerticalScroll(v)
            end)
        end
        scroll:SetPoint("TOPLEFT", 10, -30)
        scroll:SetPoint("BOTTOMRIGHT", -30, 40)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal)
        box:SetWidth(430)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(box)
        local boxBg = p:CreateTexture(nil, "ARTWORK")
        boxBg:SetPoint("TOPLEFT", scroll, -2, 2)
        boxBg:SetPoint("BOTTOMRIGHT", scroll, 2, -2)
        boxBg:SetColorTexture(0, 0, 0, 0.5)
        p.box = box
        scroll:EnableMouse(true)
        scroll:SetScript("OnMouseDown", function() box:SetFocus() end)

        local go = flatButton(p, "Import", 90, 22)
        go:SetPoint("BOTTOMRIGHT", -10, 10)
        go:SetScript("OnClick", function()
            local g, err = WH:ImportGuide(box:GetText())
            if g then
                WH:Print("Imported '%s' (%d steps).", g.title, #g.steps)
                box:SetText("")
                p:Hide()
                WH:SetGuide(g.id)
            else
                WH:Print("Import failed: %s", tostring(err))
            end
        end)
        local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMLEFT", 12, 16)
        hint:SetText("Paste a guide's JSON (Ctrl+V). Same id replaces the old one.")
    end
    self.importFrame:Show()
    self.importFrame.box:SetFocus()
end

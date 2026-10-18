-- BagMover: drag bag windows anywhere on screen; positions are saved per bag.
-- Usage: click and drag any bag window by its background/title area.
-- The backpack also has a Reset button.
-- Slash commands: /bagmover reset   -> forget all saved positions
--                 /bagmover lock    -> toggle locking (no dragging)

local ADDON = "BagMover"
local db

local function Print(msg)
    print("|cff33ff99BagMover:|r " .. msg)
end

local function Key(frame)
    -- Bag frames are recycled between bags, so key by bag ID, not frame name.
    if frame.GetBagID then
        local ok, id = pcall(frame.GetBagID, frame)
        if ok and id then return "bag" .. id end
    end
    local id = frame.GetID and frame:GetID()
    if frame == _G.ContainerFrameCombinedBags then return "combined" end
    return "bag" .. tostring(id or frame:GetName() or "?")
end

local function ApplyPosition(frame)
    if not db or not frame or frame.bagMoverDragging then return end
    local pos = db.positions[Key(frame)]
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end
end

local function SavePosition(frame)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    -- Convert to UIParent-relative units in case the frame's scale differs.
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    db.positions[Key(frame)] = { x = left * scale, y = bottom * scale }
end

-- Reset button on the backpack ------------------------------------------
-- Forget every saved position and let the default UI lay the bags out again.
local AllBagFrames -- defined below
local function ResetAll()
    wipe(db.positions)
    for _, f in ipairs(AllBagFrames()) do f.bagMoverDragging = false end
    if _G.UpdateContainerFrameAnchors then
        _G.UpdateContainerFrameAnchors() -- the default UI lays every open bag out again
    end
    Print("All bag windows reset to their default positions.")
end

local function IsBackpack(frame)
    if frame == _G.ContainerFrameCombinedBags then return true end
    local ok, id
    if frame.GetBagID then ok, id = pcall(frame.GetBagID, frame) end
    if not (ok and id) then id = frame.GetID and frame:GetID() end
    return id == 0
end

local function UpdateResetButton(frame)
    local btn = frame.bagMoverReset
    if IsBackpack(frame) then
        if not btn then
            btn = CreateFrame("Button", nil, frame)
            btn:SetSize(20, 20)
            -- above everything else the bag window draws
            btn:SetFrameStrata("HIGH")
            btn:SetFrameLevel(frame:GetFrameLevel() + 50)
            local close = frame.CloseButton or _G[(frame:GetName() or "") .. "CloseButton"]
            if close and close.GetObjectType then
                btn:SetPoint("RIGHT", close, "LEFT", -2, 0)
            else
                btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -6)
            end
            -- drawn from plain colors first (always renders): gold edge + dark center
            local edge = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
            edge:SetAllPoints()
            edge:SetColorTexture(1, 0.82, 0, 1)
            local back = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
            back:SetPoint("TOPLEFT", 1, -1)
            back:SetPoint("BOTTOMRIGHT", -1, 1)
            back:SetColorTexture(0.08, 0.06, 0.04, 1)
            -- the reset arrow on top: a built-in atlas if the client has one, else a texture file
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 3, -3)
            icon:SetPoint("BOTTOMRIGHT", -3, 3)
            local set = false
            if icon.SetAtlas then
                for _, atlas in ipairs({ "UI-RefreshButton", "common-icon-undo", "transmog-icon-revert", "Garr_Building-Refresh" }) do
                    if not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo(atlas) then
                        if pcall(icon.SetAtlas, icon, atlas) then set = true break end
                    end
                end
            end
            if not set then icon:SetTexture("Interface\\Buttons\\UI-RefreshButton") end
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.25)
            btn:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 4, -4) end)
            btn:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 3, -3) end)
            btn:SetScript("OnClick", ResetAll)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Reset bag positions")
                GameTooltip:AddLine("Puts every bag window back in its default place.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", GameTooltip_Hide)
            frame.bagMoverReset = btn
        end
        btn:Show()
    elseif btn then
        btn:Hide()
    end
end

local function SetupFrame(frame)
    if not frame or frame.bagMoverSetup then return end
    frame.bagMoverSetup = true

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:HookScript("OnDragStart", function(self)
        if db.locked then return end
        self.bagMoverDragging = true
        self:StartMoving()
    end)

    frame:HookScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.bagMoverDragging = false
        SavePosition(self)
    end)

    frame:HookScript("OnShow", function(self)
        ApplyPosition(self)
        UpdateResetButton(self)
    end)
    UpdateResetButton(frame)
end

AllBagFrames = function()
    local list = {}
    local n = _G.NUM_CONTAINER_FRAMES or 13
    for i = 1, n do
        local f = _G["ContainerFrame" .. i]
        if f then list[#list + 1] = f end
    end
    if _G.ContainerFrameCombinedBags then
        list[#list + 1] = _G.ContainerFrameCombinedBags
    end
    return list
end

local function ReapplyAll()
    for _, f in ipairs(AllBagFrames()) do
        if f:IsShown() then ApplyPosition(f); UpdateResetButton(f) end
    end
end

local function SetupAll()
    for _, f in ipairs(AllBagFrames()) do SetupFrame(f) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        BagMoverDB = BagMoverDB or {}
        db = BagMoverDB
        db.positions = db.positions or {}
        if db.locked == nil then db.locked = false end
    elseif event == "PLAYER_LOGIN" then
        SetupAll()

        -- The default UI re-anchors bags every time one opens/closes;
        -- re-apply our saved positions afterwards.
        if _G.UpdateContainerFrameAnchors then
            hooksecurefunc("UpdateContainerFrameAnchors", function()
                SetupAll()
                ReapplyAll()
            end)
        end
        if _G.ContainerFrame_GenerateFrame then
            hooksecurefunc("ContainerFrame_GenerateFrame", function(frame)
                SetupFrame(frame)
                ApplyPosition(frame)
            end)
        end
        if _G.ContainerFrame_OnShow then
            hooksecurefunc("ContainerFrame_OnShow", function(frame)
                SetupFrame(frame)
                ApplyPosition(frame)
            end)
        end
    end
end)

SLASH_BAGMOVER1 = "/bagmover"
SLASH_BAGMOVER2 = "/bm"
SlashCmdList["BAGMOVER"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        ResetAll()
    elseif msg == "lock" then
        db.locked = not db.locked
        Print(db.locked and "Bags locked." or "Bags unlocked. Drag to move.")
    else
        Print("Drag any bag window to move it. Commands: /bagmover reset, /bagmover lock")
    end
end

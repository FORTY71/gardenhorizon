local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local LocalPlayerId = LocalPlayer.UserId

-- ==========================================
-- REMOTES BINDING
-- ==========================================
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 5)
local PlantRemote = RemoteEvents and RemoteEvents:FindFirstChild("PlantSeed")
local PurchaseShopItemRemote = RemoteEvents and RemoteEvents:FindFirstChild("PurchaseShopItem")
local GetShopDataRemote = RemoteEvents and RemoteEvents:FindFirstChild("GetShopData")
local ClaimQuestRemote = RemoteEvents and RemoteEvents:FindFirstChild("ClaimQuest")
local RequestQuestsRemote = RemoteEvents and RemoteEvents:FindFirstChild("RequestQuests")
local UpdateQuestsRemote = RemoteEvents and RemoteEvents:FindFirstChild("UpdateQuests")
local SellItemsRemote = RemoteEvents and RemoteEvents:FindFirstChild("SellItems")

local HarvestFruit = nil
pcall(function()
    HarvestFruit = ReplicatedStorage:WaitForChild("Remotes", 5):WaitForChild("HarvestFruit", 5)
end)

-- ==========================================
-- SETTINGS GABUNGAN
-- ==========================================
local Settings = {
    -- Auto Harvest (message.txt)
    HarvestEnabled = false,
    HarvestCategory = "All",
    HarvestDelay = 0.05,
    
    -- General Farming (prada.txt)
    AutoHarvestTeleport = false,
    IgnoreFavorited = true,
    AutoPlantAtCharacter = false,
    AutoEquipPlantSeeds = false,
    Range = 50,
    HarvestBatchSize = 10,
    
    -- Shop / Seeds
    TeleportToShopOnBuy = true,
    CheckSeedStockBeforeBuy = true,
    AutoBuyLoop = false,
    AutoBuyDelay = 1.0,
    
    -- Gear Shop
    TeleportToGearShopOnBuy = true,
    CheckGearStockBeforeBuy = true,
    AutoBuyGearLoop = false,
    AutoBuyGearDelay = 1.0,
    
    -- Selling
    AutoSellLoop = false,
    AutoSellDelay = 1.0,
    AutoSellOnlyWhenInventoryFull = false,
    SellMode = "Sell All",
    TeleportToSellNpcOnSell = true,
    
    -- Quests
    AutoClaimQuests = false,
    AutoClaimQuestDelay = 1.0,
}

local function Notify(text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Garden Horizons Mod",
            Text = text,
            Duration = duration or 3
        })
    end)
end

-- ==========================================
-- CUSTOM UI LIBRARY (DARI prada.txt)
-- ==========================================
local function CreateSimpleUI()
    local ui = { Tabs = {} }
    
    local oldGui = CoreGui:FindFirstChild("GardenHorizonsPinkUI")
    if oldGui then oldGui:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "GardenHorizonsPinkUI"
    sg.ResetOnSpawn = false
    pcall(function() sg.Parent = CoreGui end)
    if not sg.Parent then sg.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local function MakeDraggable(guiObject)
        local dragging, dragInput, dragStart, startPos
        guiObject.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = guiObject.Position
            end
        end)
        guiObject.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then 
                dragInput = input 
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                guiObject.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
    end

    local main = Instance.new("Frame", sg)
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Size = UDim2.new(0, 550, 0, 380)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    main.BackgroundColor3 = Color3.fromRGB(255, 224, 235)
    main.BackgroundTransparency = 1 
    main.BorderSizePixel = 0
    main.Active = true
    main.ClipsDescendants = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    MakeDraggable(main)

    local bgImage = Instance.new("ImageLabel", main)
    bgImage.Size = UDim2.new(1, 0, 1, 0)
    bgImage.Position = UDim2.new(0, 0, 0, 0)
    bgImage.BackgroundColor3 = Color3.fromRGB(255, 224, 235)
    bgImage.Image = "rbxassetid://95101112877359" 
    bgImage.ScaleType = Enum.ScaleType.Crop
    bgImage.ZIndex = 0
    Instance.new("UICorner", bgImage).CornerRadius = UDim.new(0, 10)

    local topBar = Instance.new("Frame", main)
    topBar.Size = UDim2.new(1, 0, 0, 50)
    topBar.BackgroundColor3 = Color3.fromRGB(255, 192, 216)
    topBar.BackgroundTransparency = 0.25 
    topBar.BorderSizePixel = 0
    topBar.ZIndex = 1
    Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 10)

    local tabContainer = Instance.new("Frame", topBar)
    tabContainer.Size = UDim2.new(1, -50, 1, 0) 
    tabContainer.BackgroundTransparency = 1
    tabContainer.ZIndex = 2

    local tabLayout = Instance.new("UIListLayout", tabContainer)
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 8)
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    Instance.new("UIPadding", tabContainer).PaddingLeft = UDim.new(0, 15)

    local contentContainer = Instance.new("Frame", main)
    contentContainer.Size = UDim2.new(1, 0, 1, -50)
    contentContainer.Position = UDim2.new(0, 0, 0, 50)
    contentContainer.BackgroundTransparency = 1
    contentContainer.ClipsDescendants = true
    contentContainer.ZIndex = 2

    local colorText = Color3.fromRGB(100, 50, 80)
    local colorPanelBg = Color3.fromRGB(255, 240, 246)
    local colorActive = Color3.fromRGB(255, 140, 190)
    local colorInactive = Color3.fromRGB(240, 190, 210)

    local toggleUIBtn = Instance.new("ImageButton", sg)
    toggleUIBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    toggleUIBtn.Size = UDim2.new(0, 50, 0, 50)
    toggleUIBtn.Position = UDim2.new(0, 50, 0.5, 0)
    toggleUIBtn.BackgroundTransparency = 1 
    toggleUIBtn.Image = "rbxassetid://126475933417799"
    toggleUIBtn.Visible = false
    MakeDraggable(toggleUIBtn)

    local minimizeBtn = Instance.new("TextButton", topBar)
    minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
    minimizeBtn.Position = UDim2.new(1, -40, 0.5, -15)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 190)
    minimizeBtn.Text = "-"
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.TextSize = 20
    minimizeBtn.ZIndex = 3
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)

    local isUIOpen = true
    local function ToggleUI()
        isUIOpen = not isUIOpen
        if isUIOpen then
            TweenService:Create(toggleUIBtn, TweenInfo.new(0.3), {Size = UDim2.new(0, 0, 0, 0)}):Play()
            task.delay(0.3, function() toggleUIBtn.Visible = false end)
            main.Visible = true
            TweenService:Create(main, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 550, 0, 380)}):Play()
        else
            TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)}):Play()
            task.delay(0.4, function() 
                main.Visible = false 
                toggleUIBtn.Visible = true
                TweenService:Create(toggleUIBtn, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 50, 0, 50)}):Play()
            end)
        end
    end

    minimizeBtn.MouseButton1Click:Connect(ToggleUI)
    toggleUIBtn.MouseButton1Click:Connect(ToggleUI)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then ToggleUI() end
    end)

    local activePage = nil

    function ui:AddTab(name)
        local tabBtn = Instance.new("TextButton", tabContainer) 
        tabBtn.Size = UDim2.new(0, 90, 0, 34)
        tabBtn.BackgroundColor3 = colorActive
        tabBtn.Text = name
        tabBtn.Font = Enum.Font.GothamBold
        tabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        tabBtn.TextSize = 13
        tabBtn.ZIndex = 3
        Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 8)

        local page = Instance.new("ScrollingFrame", contentContainer)
        page.Size = UDim2.new(1, 0, 1, 0)
        page.Position = UDim2.new(1, 0, 0, 0)
        page.BackgroundTransparency = 1
        page.Visible = false
        page.ScrollBarThickness = 5
        page.ScrollBarImageColor3 = colorActive
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.ZIndex = 3

        local list = Instance.new("UIListLayout", page)
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0, 8)
        local pad = Instance.new("UIPadding", page)
        pad.PaddingTop = UDim.new(0, 15); pad.PaddingLeft = UDim.new(0, 15); pad.PaddingRight = UDim.new(0, 15); pad.PaddingBottom = UDim.new(0, 20)

        tabBtn.MouseButton1Click:Connect(function()
            if activePage == page then return end
            for _, t in pairs(ui.Tabs) do
                t.Button.BackgroundColor3 = Color3.fromRGB(255, 204, 224)
                t.Button.TextColor3 = colorText
            end
            tabBtn.BackgroundColor3 = colorActive
            tabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            if activePage then
                local oldPage = activePage
                TweenService:Create(oldPage, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(-1, 0, 0, 0)}):Play()
                task.delay(0.35, function() if activePage ~= oldPage then oldPage.Visible = false end end)
            end
            page.Visible = true
            page.Position = UDim2.new(1, 0, 0, 0)
            TweenService:Create(page, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 0)}):Play()
            activePage = page
        end)

        table.insert(ui.Tabs, {Button = tabBtn, Page = page})
        
        if #ui.Tabs == 1 then
            page.Visible = true; page.Position = UDim2.new(0, 0, 0, 0); activePage = page
            tabBtn.BackgroundColor3 = colorActive; tabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            tabBtn.BackgroundColor3 = Color3.fromRGB(255, 204, 224); tabBtn.TextColor3 = colorText
        end

        local tabObj = {}

        function tabObj:AddToggle(text, default, callback)
            local container = Instance.new("Frame", page)
            container.Size = UDim2.new(1, 0, 0, 35)
            container.BackgroundColor3 = colorPanelBg
            container.BackgroundTransparency = 0.35
            Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

            local lbl = Instance.new("TextLabel", container)
            lbl.Size = UDim2.new(1, -50, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0); lbl.BackgroundTransparency = 1
            lbl.Text = text; lbl.TextColor3 = colorText; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 14; lbl.TextXAlignment = Enum.TextXAlignment.Left

            local btn = Instance.new("TextButton", container)
            btn.Size = UDim2.new(0, 40, 0, 20); btn.Position = UDim2.new(1, -50, 0.5, -10)
            btn.BackgroundColor3 = default and colorActive or colorInactive; btn.Text = ""
            Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
            
            local circle = Instance.new("Frame", btn)
            circle.Size = UDim2.new(0, 16, 0, 16); circle.Position = default and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)
            circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)

            local state = default
            btn.MouseButton1Click:Connect(function()
                state = not state
                TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = state and colorActive or colorInactive}):Play()
                TweenService:Create(circle, TweenInfo.new(0.25), {Position = state and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)}):Play()
                callback(state)
            end)
            callback(state)
        end

        function tabObj:AddDropdown(text, options, callback)
            local container = Instance.new("Frame", page)
            container.Size = UDim2.new(1, 0, 0, 35); container.BackgroundColor3 = colorPanelBg
            container.BackgroundTransparency = 0.35; container.ClipsDescendants = true
            Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

            local btn = Instance.new("TextButton", container)
            btn.Size = UDim2.new(1, 0, 0, 35); btn.BackgroundTransparency = 1
            btn.Text = "  " .. text .. " : " .. tostring(options[1])
            btn.TextColor3 = colorText; btn.Font = Enum.Font.GothamBold; btn.TextSize = 13; btn.TextXAlignment = Enum.TextXAlignment.Left

            local list = Instance.new("UIListLayout", container)
            list.SortOrder = Enum.SortOrder.LayoutOrder

            local open = false
            btn.MouseButton1Click:Connect(function()
                open = not open
                TweenService:Create(container, TweenInfo.new(0.2), {Size = open and UDim2.new(1, 0, 0, 35 + (#options * 30)) or UDim2.new(1, 0, 0, 35)}):Play()
            end)

            for _, opt in ipairs(options) do
                local optBtn = Instance.new("TextButton", container)
                optBtn.Size = UDim2.new(1, 0, 0, 30); optBtn.BackgroundTransparency = 1
                optBtn.Text = "    - " .. tostring(opt); optBtn.TextColor3 = colorText
                optBtn.Font = Enum.Font.Gotham; optBtn.TextSize = 13; optBtn.TextXAlignment = Enum.TextXAlignment.Left
                
                optBtn.MouseButton1Click:Connect(function()
                    btn.Text = "  " .. text .. " : " .. tostring(opt)
                    open = false
                    TweenService:Create(container, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 35)}):Play()
                    callback(opt)
                end)
            end
            callback(options[1])
        end

        return tabObj
    end
    
    return ui
end

-- ==========================================
-- LOGIKA PANEN (DARI message.txt)
-- ==========================================
local function findClientPlants()
    local cp = Workspace:FindFirstChild("ClientPlants")
    if cp then return cp end
    for _, child in ipairs(Workspace:GetChildren()) do
        local ln = child.Name:lower()
        if ln:find("plant") or ln:find("farm") then return child end
    end
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") then
            local sub = child:FindFirstChild("ClientPlants")
            if sub then return sub end
        end
    end
    return nil
end

local function isFruitHarvestable(fruit)
    if fruit:GetAttribute("FullyGrown") == true then return true end
    local gp = tonumber(fruit:GetAttribute("GrowthProgress") or fruit:GetAttribute("Growth") or "")
    if gp and gp >= 1 then return true end
    local rm = tonumber(fruit:GetAttribute("RipenessMultiplier") or "")
    if rm and rm > 0 then return true end
    local rs = tostring(fruit:GetAttribute("RipenessStage") or "")
    if rs ~= "" and rs:lower() ~= "unripe" and rs:lower() ~= "growing" and rs:lower() ~= "none" then return true end
    return false
end

local RIPENESS_MAP = {
    Unripe = function(v) return v and v < 1 end,
    Ripe   = function(v) return v and v >= 1 and v < 1.5 end,
    Lush   = function(v) return v and v >= 1.5 end,
}

local function fruitMatchesCategory(fruit, category)
    if category == "All" then return true end
    local stage = tostring(fruit:GetAttribute("RipenessStage") or "")
    if stage ~= "" then
        return stage:lower() == category:lower()
    end
    local rm = tonumber(fruit:GetAttribute("RipenessMultiplier") or "")
    if rm then
        local fn = RIPENESS_MAP[category]
        if fn then return fn(rm) end
    end
    return false
end

local function fireHarvest(plantUuid, anchorIndex)
    pcall(function()
        if HarvestFruit then
            HarvestFruit:FireServer({
                [1] = {
                    ["GrowthAnchorIndex"] = anchorIndex,
                    ["Uuid"]              = plantUuid,
                },
            })
        end
    end)
end

-- ==========================================
-- SETUP UI TABS
-- ==========================================
local MenuUI = CreateSimpleUI()

-- TAB 1: Harvest & Farm
local HarvestTab = MenuUI:AddTab("Harvest")
HarvestTab:AddToggle("Enable Auto Harvest", false, function(state) Settings.HarvestEnabled = state end)
HarvestTab:AddDropdown("Harvest Mode", {"All", "Unripe", "Ripe", "Lush"}, function(selected) Settings.HarvestCategory = selected end)
HarvestTab:AddToggle("Auto Harvest Teleport", false, function(state) Settings.AutoHarvestTeleport = state end)
HarvestTab:AddToggle("Ignore Favorited Items", true, function(state) Settings.IgnoreFavorited = state end)

-- TAB 2: Planting
local PlantTab = MenuUI:AddTab("Planting")
PlantTab:AddToggle("Auto Plant @ Character", false, function(state) Settings.AutoPlantAtCharacter = state end)
PlantTab:AddToggle("Auto Equip Seeds", false, function(state) Settings.AutoEquipPlantSeeds = state end)

-- TAB 3: Auto Buy
local ShopTab = MenuUI:AddTab("Shop")
ShopTab:AddToggle("Auto Buy Seeds", false, function(state) Settings.AutoBuyLoop = state end)
ShopTab:AddToggle("Check Seed Stock", true, function(state) Settings.CheckSeedStockBeforeBuy = state end)
ShopTab:AddToggle("Teleport To Shop", true, function(state) Settings.TeleportToShopOnBuy = state end)
ShopTab:AddToggle("Auto Buy Gear", false, function(state) Settings.AutoBuyGearLoop = state end)

-- TAB 4: Selling
local SellTab = MenuUI:AddTab("Selling")
SellTab:AddToggle("Auto Sell Items", false, function(state) Settings.AutoSellLoop = state end)
SellTab:AddToggle("Sell Only When Full", false, function(state) Settings.AutoSellOnlyWhenInventoryFull = state end)
SellTab:AddDropdown("Sell Mode", {"Sell All", "Sell Selected"}, function(selected) Settings.SellMode = selected end)
SellTab:AddToggle("Teleport To Sell NPC", true, function(state) Settings.TeleportToSellNpcOnSell = state end)

-- TAB 5: Quests
local QuestTab = MenuUI:AddTab("Quests")
QuestTab:AddToggle("Auto Claim Quests", false, function(state) Settings.AutoClaimQuests = state end)


-- ==========================================
-- MAIN LOOPS
-- ==========================================
-- Loop Auto Harvest
task.spawn(function()
    while true do
        if Settings.HarvestEnabled and HarvestFruit then
            local clientPlants = findClientPlants()
            if clientPlants then
                for _, plant in ipairs(clientPlants:GetChildren()) do
                    if not Settings.HarvestEnabled then break end

                    local owner = plant:GetAttribute("OwnerUserId") or plant:GetAttribute("OwnerId") or plant:GetAttribute("Owner")
                    if tostring(owner) ~= tostring(LocalPlayerId) then continue end

                    local plantUuid = plant:GetAttribute("Uuid") or plant:GetAttribute("UUID") or plant:GetAttribute("Id")
                    if not plantUuid then continue end

                    for _, fruit in ipairs(plant:GetChildren()) do
                        if not Settings.HarvestEnabled then break end
                        if not fruit:IsA("Model") then continue end
                        if not isFruitHarvestable(fruit) then continue end
                        if not fruitMatchesCategory(fruit, Settings.HarvestCategory) then continue end

                        local anchor = tonumber(fruit:GetAttribute("GrowthAnchorIndex") or fruit:GetAttribute("AnchorIndex") or 1) or 1
                        fireHarvest(tostring(plantUuid), anchor)
                        task.wait(Settings.HarvestDelay)
                    end
                end
            end
        end
        task.wait(0.15)
    end
end)

-- Placeholder Loop untuk AutoSell / AutoBuy / AutoClaim
-- Karena script asli prada.txt hanya berisi struktur Settings, 
-- kamu bisa menambahkan logika pemanggilan Remote Event terkait di sini.
task.spawn(function()
    while true do
        if Settings.AutoSellLoop then
            -- Tambahkan logika memanggil SellItemsRemote di sini
        end
        
        if Settings.AutoClaimQuests then
            -- Tambahkan logika memanggil ClaimQuestRemote di sini
        end
        task.wait(Settings.AutoSellDelay)
    end
end)

print("[PradaOS Mod] Combined Menu Loaded Successfully.")

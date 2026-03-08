local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Remotes
local PlantRemote = ReplicatedStorage.RemoteEvents:WaitForChild("PlantSeed", 5)
local PurchaseShopItemRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("PurchaseShopItem")
local GetShopDataRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("GetShopData")
local ClaimQuestRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("ClaimQuest")
local RequestQuestsRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("RequestQuests")
local UpdateQuestsRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("UpdateQuests")
local SellItemsRemote = ReplicatedStorage.RemoteEvents:FindFirstChild("SellItems")

-- Modules
local ItemInventory = nil
pcall(function()
    ItemInventory = require(ReplicatedStorage:WaitForChild("Inventory"):WaitForChild("ItemInventory"))
end)

local SeedShopData = nil
pcall(function()
    SeedShopData = require(ReplicatedStorage:WaitForChild("Shop"):WaitForChild("ShopData"):WaitForChild("SeedShopData"))
end)

local GearShopData = nil
pcall(function()
    GearShopData = require(ReplicatedStorage:WaitForChild("Shop"):WaitForChild("ShopData"):WaitForChild("GearShopData"))
end)

-- Settings
local Settings = {
    Enabled = false,
    AutoHarvestTeleport = false,
    IgnoreFavorited = true,
    FruitCategory = "All", -- "All", "Ripe", "Lush", "Unripe"
    Delay = 0.05,
    Range = 50,
    HarvestBatchSize = 10,

    AutoPlantAtCharacter = false,
    AutoEquipPlantSeeds = false,
    SavedPlantPosition = nil,
    SelectedSeed = nil,
    
    TeleportToShopOnBuy = true,
    CheckSeedStockBeforeBuy = true,
    AutoBuyLoop = false,
    AutoBuyDelay = 1.0,
    SeedShopNpcPosition = Vector3.new(177, 204, 672),
    
    SelectedGear = nil,
    TeleportToGearShopOnBuy = true,
    CheckGearStockBeforeBuy = true,
    AutoBuyGearLoop = false,
    AutoBuyGearDelay = 1.0,
    GearShopNpcPosition = Vector3.new(212, 204, 609),
    
    AutoSellLoop = false,
    AutoSellDelay = 1.0,
    AutoSellOnlyWhenInventoryFull = false,
    InventoryFullSellCooldown = 1.0,
    SellMode = "Sell All",
    TeleportToSellNpcOnSell = true,
    SellNpcPosition = Vector3.new(150, 204, 674),
    
    AutoClaimQuests = false,
    AutoClaimQuestDelay = 1.0,
}

-- Variables
local lastPlantTime = 0
local lastHarvestTeleportTime = 0
local lastAutoBuyTime = 0
local lastAutoBuyGearTime = 0
local lastAutoSellTime = 0
local lastInventoryFullSellTime = 0
local lastAutoClaimQuestTime = 0
local warnedMissingSavedPosition = false
local warnedMissingQuestRemotes = false
local warnedMissingSellRemotes = false

local harvestCooldownByPrompt = {}
local harvestFailCountByPrompt = {}
local harvestBlacklistUntilByPrompt = {}
local HARVEST_PROMPT_SCAN_INTERVAL = 0.35
local harvestPromptScanCache = {}
local harvestPromptScanCacheAt = 0
local latestQuestData = nil
local INVENTORY_FULL_TEXT = "Your inventory is full! Sell or remove items to make space"

if UpdateQuestsRemote and UpdateQuestsRemote:IsA("RemoteEvent") then
    UpdateQuestsRemote.OnClientEvent:Connect(function(data)
        if type(data) == "table" then
            latestQuestData = data
        end
    end)
end

local function Notify(text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Garden Horizons",
            Text = text,
            Duration = duration or 3
        })
    end)
end

-- ==========================
-- UI FRAMEWORK
-- ==========================
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
                guiObject.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X, 
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
                dragging = false 
            end
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
    bgImage.Name = "CustomBackground"
    bgImage.Size = UDim2.new(1, 0, 1, 0)
    bgImage.Position = UDim2.new(0, 0, 0, 0)
    bgImage.BackgroundTransparency = 0
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
    
    local cover = Instance.new("Frame", main)
    cover.Size = UDim2.new(1, 0, 0, 10)
    cover.Position = UDim2.new(0, 0, 0, 40)
    cover.BackgroundColor3 = Color3.fromRGB(255, 192, 216)
    cover.BackgroundTransparency = 0.25 
    cover.BorderSizePixel = 0
    cover.ZIndex = 1

    local tabContainer = Instance.new("Frame", topBar)
    tabContainer.Size = UDim2.new(1, -50, 1, 0) 
    tabContainer.BackgroundTransparency = 1
    tabContainer.ZIndex = 2

    local tabLayout = Instance.new("UIListLayout", tabContainer)
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 8)
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local topPad = Instance.new("UIPadding", tabContainer)
    topPad.PaddingLeft = UDim.new(0, 15)

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
    toggleUIBtn.ScaleType = Enum.ScaleType.Fit
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
            TweenService:Create(toggleUIBtn, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)}):Play()
            task.delay(0.3, function() toggleUIBtn.Visible = false end)
            
            main.Visible = true
            main.Size = UDim2.new(0, 0, 0, 0)
            TweenService:Create(main, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 550, 0, 380)}):Play()
        else
            TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)}):Play()
            task.delay(0.4, function() 
                if not isUIOpen then 
                    main.Visible = false 
                    toggleUIBtn.Visible = true
                    toggleUIBtn.Size = UDim2.new(0, 0, 0, 0)
                    TweenService:Create(toggleUIBtn, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 50, 0, 50)}):Play()
                end 
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
        tabBtn.Size = UDim2.new(0, 100, 0, 34)
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
        pad.PaddingTop = UDim.new(0, 15)
        pad.PaddingLeft = UDim.new(0, 15)
        pad.PaddingRight = UDim.new(0, 15)
        pad.PaddingBottom = UDim.new(0, 20)

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
            page.Visible = true
            page.Position = UDim2.new(0, 0, 0, 0)
            activePage = page
            tabBtn.BackgroundColor3 = colorActive
            tabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            tabBtn.BackgroundColor3 = Color3.fromRGB(255, 204, 224)
            tabBtn.TextColor3 = colorText
        end

        local tabObj = {}

        function tabObj:AddLabel(text)
            local lbl = Instance.new("TextLabel", page)
            lbl.Size = UDim2.new(1, 0, 0, 25)
            lbl.BackgroundTransparency = 1
            lbl.Text = text
            lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 15
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.ZIndex = 4
            return lbl
        end

        function tabObj:AddToggle(text, default, callback)
            local container = Instance.new("Frame", page)
            container.Size = UDim2.new(1, 0, 0, 35)
            container.BackgroundColor3 = colorPanelBg
            container.BackgroundTransparency = 0.35
            container.ZIndex = 4
            Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

            local lbl = Instance.new("TextLabel", container)
            lbl.Size = UDim2.new(1, -50, 1, 0)
            lbl.Position = UDim2.new(0, 10, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = text
            lbl.TextColor3 = colorText
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 14
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.ZIndex = 5

            local btn = Instance.new("TextButton", container)
            btn.Size = UDim2.new(0, 40, 0, 20)
            btn.Position = UDim2.new(1, -50, 0.5, -10)
            btn.BackgroundColor3 = default and colorActive or colorInactive
            btn.Text = ""
            btn.ZIndex = 5
            Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
            
            local circle = Instance.new("Frame", btn)
            circle.Size = UDim2.new(0, 16, 0, 16)
            circle.Position = default and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)
            circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            circle.ZIndex = 6
            Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)

            local state = default
            btn.MouseButton1Click:Connect(function()
                state = not state
                TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = state and colorActive or colorInactive}):Play()
                TweenService:Create(circle, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = state and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)}):Play()
                callback(state)
            end)
            callback(state)
        end

        function tabObj:AddButton(text, callback)
            local btn = Instance.new("TextButton", page)
            btn.Size = UDim2.new(1, 0, 0, 35)
            btn.BackgroundColor3 = colorActive
            btn.Text = text
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 14
            btn.ZIndex = 4
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
            btn.MouseButton1Click:Connect(callback)
        end

        function tabObj:AddSlider(text, min, max, default, callback)
            local container = Instance.new("Frame", page)
            container.Size = UDim2.new(1, 0, 0, 55)
            container.BackgroundColor3 = colorPanelBg
            container.BackgroundTransparency = 0.35
            container.ZIndex = 4
            Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

            local lbl = Instance.new("TextLabel", container)
            lbl.Size = UDim2.new(1, -20, 0, 25)
            lbl.Position = UDim2.new(0, 10, 0, 5)
            lbl.BackgroundTransparency = 1
            lbl.Text = text .. ": " .. tostring(default)
            lbl.TextColor3 = colorText
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 14
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.ZIndex = 5

            local bar = Instance.new("TextButton", container)
            bar.Size = UDim2.new(1, -20, 0, 8)
            bar.Position = UDim2.new(0, 10, 0, 35)
            bar.BackgroundColor3 = colorInactive
            bar.Text = ""
            bar.AutoButtonColor = false
            bar.ZIndex = 5
            Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

            local fill = Instance.new("Frame", bar)
            fill.Size = UDim2.new(math.clamp((default - min) / (max - min), 0, 1), 0, 1, 0)
            fill.BackgroundColor3 = colorActive
            fill.ZIndex = 6
            Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

            local dragging = false
            local function update(input)
                local pos = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                fill.Size = UDim2.new(pos, 0, 1, 0)
                local val = min + pos * (max - min)
                val = math.floor(val * 100) / 100
                lbl.Text = text .. ": " .. tostring(val)
                callback(val)
            end

            bar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true; update(input)
                end
            end)
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then update(input) end
            end)
            callback(default)
        end

        function tabObj:AddDropdown(text, options, multi, callback)
            local container = Instance.new("Frame", page)
            container.Size = UDim2.new(1, 0, 0, 35)
            container.BackgroundColor3 = colorPanelBg
            container.BackgroundTransparency = 0.35
            container.ClipsDescendants = true
            container.ZIndex = 4
            Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

            local btn = Instance.new("TextButton", container)
            btn.Size = UDim2.new(1, 0, 0, 35)
            btn.BackgroundTransparency = 1
            btn.Text = "  " .. text .. " (Click to open)"
            btn.TextColor3 = colorText
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 13
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.ZIndex = 5

            local list = Instance.new("UIListLayout", container)
            list.SortOrder = Enum.SortOrder.LayoutOrder

            local open = false
            local selected = multi and {} or nil
            local optionBtns = {}

            btn.MouseButton1Click:Connect(function()
                open = not open
                local newHeight = open and (35 + (#options * 30)) or 35
                TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, newHeight)}):Play()
            end)

            for _, opt in ipairs(options) do
                local optBtn = Instance.new("TextButton", container)
                optBtn.Size = UDim2.new(1, 0, 0, 30)
                optBtn.BackgroundColor3 = colorPanelBg
                optBtn.BackgroundTransparency = 1
                optBtn.Text = "  " .. opt
                optBtn.TextColor3 = colorText
                optBtn.Font = Enum.Font.Gotham
                optBtn.TextSize = 13
                optBtn.TextXAlignment = Enum.TextXAlignment.Left
                optBtn.BorderSizePixel = 0
                optBtn.ZIndex = 5

                optBtn.MouseButton1Click:Connect(function()
                    if multi then
                        if selected[opt] then
                            selected[opt] = nil
                            optBtn.TextColor3 = colorText
                            optBtn.Font = Enum.Font.Gotham
                        else
                            selected[opt] = true
                            optBtn.TextColor3 = colorActive
                            optBtn.Font = Enum.Font.GothamBold
                        end
                        callback(selected)
                    else
                        selected = opt
                        for _, b in ipairs(optionBtns) do 
                            b.TextColor3 = colorText 
                            b.Font = Enum.Font.Gotham
                        end
                        optBtn.TextColor3 = colorActive
                        optBtn.Font = Enum.Font.GothamBold
                        btn.Text = "  " .. text .. ": " .. options[1]
                        open = false
                        TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, 35)}):Play()
                        callback(selected)
                    end
                end)
                table.insert(optionBtns, optBtn)
            end
            
            if not multi and #options > 0 then
                selected = options[1]
                optionBtns[1].TextColor3 = colorActive
                optionBtns[1].Font = Enum.Font.GothamBold
                btn.Text = "  " .. text .. ": " .. options[1]
                callback(selected)
            elseif multi then
                callback(selected)
            end
        end

        return tabObj
    end

    return ui, sg
end

-- ==========================
-- INIT SHOP OPTIONS
-- ==========================
local seedOptions = {}
local seedPriceByName = {}
if SeedShopData and SeedShopData.ShopData then
    local seedEntries = {}
    for _, shopEntry in pairs(SeedShopData.ShopData) do
        if type(shopEntry) == "table" and type(shopEntry.Name) == "string" then
            if shopEntry.DisplayInShop ~= false then
                table.insert(seedEntries, { Name = shopEntry.Name, Price = tonumber(shopEntry.Price) or math.huge })
                seedPriceByName[shopEntry.Name] = tonumber(shopEntry.Price) or nil
            end
        end
    end
    table.sort(seedEntries, function(a, b)
        if a.Price == b.Price then return a.Name < b.Name end
        return a.Price < b.Price
    end)
    for _, entry in ipairs(seedEntries) do table.insert(seedOptions, entry.Name) end
end
if #seedOptions == 0 then seedOptions = {"Carrot"} end

Settings.SelectedSeed = seedOptions[1]
local selectedAutoPlantSeedsMap = {}
local autoPlantEquipCycleIndex = 1
local selectedBuySeedsMap = {}
local buySeedCycleIndex = 1

local function pickFirstSelectedValue(selection, valueMap)
    if type(selection) == "table" then
        local labels = {}
        for label, isSelected in pairs(selection) do
            if isSelected then table.insert(labels, label) end
        end
        table.sort(labels)
        local firstLabel = labels[1]
        if not firstLabel then return nil end
        if valueMap then return valueMap[firstLabel] or firstLabel end
        return firstLabel
    end
    if valueMap then return valueMap[selection] or selection end
    return selection
end

local gearOptions = {}
local gearPriceByName = {}
if GearShopData and GearShopData.ShopData then
    local gearEntries = {}
    for _, shopEntry in pairs(GearShopData.ShopData) do
        if type(shopEntry) == "table" and type(shopEntry.Name) == "string" then
            if shopEntry.DisplayInShop ~= false then
                table.insert(gearEntries, { Name = shopEntry.Name, Price = tonumber(shopEntry.Price) or math.huge })
                gearPriceByName[shopEntry.Name] = tonumber(shopEntry.Price) or nil
            end
        end
    end
    table.sort(gearEntries, function(a, b)
        if a.Price == b.Price then return a.Name < b.Name end
        return a.Price < b.Price
    end)
    for _, entry in ipairs(gearEntries) do table.insert(gearOptions, entry.Name) end
end
if #gearOptions == 0 then gearOptions = {"Recall Wrench"} end

Settings.SelectedGear = gearOptions[1]
local selectedBuyGearsMap = {}
local buyGearCycleIndex = 1

-- ==========================
-- BUILD TABS
-- ==========================
local UI = CreateSimpleUI()

local MainTab = UI:AddTab("Main")
local ShopTab = UI:AddTab("Shop")

MainTab:AddLabel("--- Auto Harvest ---")
MainTab:AddToggle("Enable Auto Harvest", false, function(value) Settings.Enabled = value end)
MainTab:AddToggle("Ignore Favorited", true, function(value) Settings.IgnoreFavorited = value end)
MainTab:AddToggle("Auto Teleport", false, function(value) Settings.AutoHarvestTeleport = value end)
-- Dropdown Kategori Kematangan disuntikkan di sini
MainTab:AddDropdown("Harvest Category", {"All", "Ripe", "Lush", "Unripe"}, false, function(value) 
    local selected = pickFirstSelectedValue(value, nil)
    if selected then Settings.FruitCategory = tostring(selected) end
end)
MainTab:AddSlider("Harvest Delay (s)", 0.05, 1.0, Settings.Delay, function(value) Settings.Delay = value end)

MainTab:AddLabel("--- Utility ---")
MainTab:AddToggle("Auto Claim Quests", false, function(value) 
    Settings.AutoClaimQuests = value
    if value and RequestQuestsRemote and RequestQuestsRemote:IsA("RemoteEvent") then pcall(function() RequestQuestsRemote:FireServer() end) end
end)

MainTab:AddLabel("--- Auto Plant ---")
MainTab:AddToggle("Auto Plant at Character", false, function(value)
    if value and not Settings.SavedPlantPosition then
        Settings.AutoPlantAtCharacter = false
        Notify("Set a plant position first.", 3)
        return
    end
    Settings.AutoPlantAtCharacter = value
    warnedMissingSavedPosition = false
end)
MainTab:AddToggle("Auto Equip Seeds", false, function(value) Settings.AutoEquipPlantSeeds = value end)
MainTab:AddDropdown("Auto Plant Seeds", seedOptions, true, function(value)
    selectedAutoPlantSeedsMap = {}
    if type(value) == "table" then
        for seedName, isSelected in pairs(value) do
            if isSelected then selectedAutoPlantSeedsMap[tostring(seedName)] = true end
        end
    end
    autoPlantEquipCycleIndex = 1
end)

local SavedPositionLabel = MainTab:AddLabel("Saved Position: Not set")
MainTab:AddButton("Save Plant Position", function()
    local char = LocalPlayer.Character
    if not char then SavedPositionLabel.Text = "Saved Position: Failed (no character)"; return end
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not root then SavedPositionLabel.Text = "Saved Position: Failed (no root)"; return end

    Settings.SavedPlantPosition = root.Position
    warnedMissingSavedPosition = false
    SavedPositionLabel.Text = string.format("Saved Position: X %.2f | Y %.2f | Z %.2f", root.Position.X, root.Position.Y, root.Position.Z)
end)

ShopTab:AddLabel("--- Seed Shop ---")
ShopTab:AddDropdown("Seed", seedOptions, true, function(value)
    selectedBuySeedsMap = {}
    if type(value) == "table" then
        for key, isSelected in pairs(value) do
            if type(key) == "number" then selectedBuySeedsMap[tostring(isSelected)] = true
            elseif isSelected then selectedBuySeedsMap[tostring(key)] = true end
        end
    elseif type(value) == "string" and value ~= "" then
        selectedBuySeedsMap[value] = true
    end
    local selected = pickFirstSelectedValue(value, nil)
    if selected then Settings.SelectedSeed = tostring(selected) end
    buySeedCycleIndex = 1
end)
ShopTab:AddButton("Open Seed Shop Menu", function()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui and playerGui:FindFirstChild("SeedShop") then playerGui.SeedShop.Enabled = true end
end)
ShopTab:AddToggle("Teleport To NPC On Buy", true, function(value) Settings.TeleportToShopOnBuy = value end)
ShopTab:AddToggle("Check Stock Before Buy", Settings.CheckSeedStockBeforeBuy, function(value) Settings.CheckSeedStockBeforeBuy = value end)
ShopTab:AddToggle("Auto Buy Loop", false, function(value) Settings.AutoBuyLoop = value end)
ShopTab:AddSlider("Seed Buy Delay (s)", 0.1, 5.0, Settings.AutoBuyDelay, function(value) Settings.AutoBuyDelay = value end)

ShopTab:AddLabel("--- Gear Shop ---")
ShopTab:AddDropdown("Gear", gearOptions, true, function(value)
    selectedBuyGearsMap = {}
    if type(value) == "table" then
        for key, isSelected in pairs(value) do
            if type(key) == "number" then selectedBuyGearsMap[tostring(isSelected)] = true
            elseif isSelected then selectedBuyGearsMap[tostring(key)] = true end
        end
    elseif type(value) == "string" and value ~= "" then
        selectedBuyGearsMap[value] = true
    end
    local selected = pickFirstSelectedValue(value, nil)
    if selected then Settings.SelectedGear = tostring(selected) end
    buyGearCycleIndex = 1
end)
ShopTab:AddButton("Open Gear Shop Menu", function()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui and playerGui:FindFirstChild("GearShop") then playerGui.GearShop.Enabled = true end
end)
ShopTab:AddToggle("Teleport To NPC On Buy (Gear)", true, function(value) Settings.TeleportToGearShopOnBuy = value end)
ShopTab:AddToggle("Check Stock Before Buy (Gear)", Settings.CheckGearStockBeforeBuy, function(value) Settings.CheckGearStockBeforeBuy = value end)
ShopTab:AddToggle("Auto Buy Loop (Gear)", false, function(value) Settings.AutoBuyGearLoop = value end)
ShopTab:AddSlider("Gear Buy Delay (s)", 0.1, 5.0, Settings.AutoBuyGearDelay, function(value) Settings.AutoBuyGearDelay = value end)

ShopTab:AddLabel("--- Auto Sell ---")
ShopTab:AddDropdown("Sell Mode", {"Sell All", "Sell Held Item", "Sell All on Inventory Full"}, false, function(value)
    local selected = pickFirstSelectedValue(value, nil)
    if selected == "Sell All" then
        Settings.SellMode = "SellAll"; Settings.AutoSellOnlyWhenInventoryFull = false
    elseif selected == "Sell Held Item" then
        Settings.SellMode = "Sell Held Item"; Settings.AutoSellOnlyWhenInventoryFull = false
    elseif selected == "Sell All on Inventory Full" then
        Settings.SellMode = "SellAll"; Settings.AutoSellOnlyWhenInventoryFull = true
    end
end)
ShopTab:AddToggle("Teleport To NPC On Sell", true, function(value) Settings.TeleportToSellNpcOnSell = value end)
ShopTab:AddToggle("Auto Sell Loop", false, function(value) Settings.AutoSellLoop = value end)
ShopTab:AddSlider("Auto Sell Delay (s)", 0.1, 10.0, Settings.AutoSellDelay, function(value) Settings.AutoSellDelay = value end)

ShopTab:AddButton("Buy Selected Seed", function() tryBuyNextSelectedSeed(false) end)
ShopTab:AddButton("Buy Selected Gear", function() tryBuyNextSelectedGear(false) end)
ShopTab:AddButton("Sell Now", function() trySell(Settings.SellMode, false) end)

-- ==========================
-- MAIN LOGIC FUNCTIONS
-- ==========================
local function getCharacterRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

local function isNearNpc(rootPos, targetPos, horizontalDist, maxYDiff)
    local dx = rootPos.X - targetPos.X
    local dz = rootPos.Z - targetPos.Z
    local horizontal = math.sqrt(dx * dx + dz * dz)
    local yDiff = math.abs(rootPos.Y - targetPos.Y)
    return horizontal <= horizontalDist and yDiff <= maxYDiff
end

local function teleportRootAndWait(root, targetPos, timeoutSec, horizontalDist, maxYDiff, stableFramesRequired)
    local timeout = timeoutSec or 0.75
    local nearHorizontal = horizontalDist or 2.5
    local nearY = maxYDiff or 10
    local stableFrames = stableFramesRequired or 5
    local started = tick()
    local stableCount = 0

    while tick() - started < timeout do
        root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
        task.wait()

        local currentRoot = getCharacterRoot()
        if not currentRoot then return false end
        root = currentRoot

        if isNearNpc(root.Position, targetPos, nearHorizontal, nearY) then
            stableCount = stableCount + 1
            if stableCount >= stableFrames then
                for _ = 1, 3 do
                    root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
                    task.wait()
                end
                return true
            end
        else
            stableCount = 0
        end
    end

    return isNearNpc(root.Position, targetPos, nearHorizontal, nearY)
end

function trySell(mode, silent)
    if not SellItemsRemote then
        if not silent then Notify("SellItems remote not found.", 3) end
        return false
    end

    local sellMode = mode
    if sellMode == "Sell Held Item" then sellMode = "SellSingle"
    elseif sellMode ~= "SellSingle" and sellMode ~= "SellAll" then
        sellMode = Settings.SellMode == "Sell Held Item" and "SellSingle" or "SellAll"
    end

    local originalPos = nil
    local didTeleport = false
    local root = getCharacterRoot()

    if Settings.TeleportToSellNpcOnSell then
        if not root then
            if not silent then Notify("Character root not found.", 3) end
            return false
        end
        local npcPos = Settings.SellNpcPosition
        if not npcPos then return false end

        originalPos = root.Position
        local reached = teleportRootAndWait(root, npcPos, 1.2, 2.5, 10, 5)
        if not reached then
            if not silent then Notify("Could not reach sell NPC.", 3) end
            return false
        end
        didTeleport = true
        task.wait(0.15)
    end

    local ok, result = pcall(function()
        if SellItemsRemote:IsA("RemoteFunction") then return SellItemsRemote:InvokeServer(sellMode) end
        SellItemsRemote:FireServer(sellMode)
        return true
    end)

    if didTeleport and originalPos then
        local backRoot = getCharacterRoot()
        if backRoot then backRoot.CFrame = CFrame.new(originalPos) end
    end

    if not ok then
        if not silent then Notify("Sell failed (invoke error).", 3) end
        return false
    end

    local response = tostring(result or "")
    local responseLower = string.lower(response)
    local sold = result == true or string.find(responseLower, "here's", 1, true) ~= nil or string.find(responseLower, "sold", 1, true) ~= nil

    if sold then return true end

    if not silent then
        if response ~= "" and response ~= "nil" then Notify(response, 3)
        else Notify("Nothing to sell.", 2) end
    end
    return false
end

local function isInventoryFullNotificationText(text)
    if type(text) ~= "string" then return false end
    local normalized = string.gsub(text, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")

    if normalized == INVENTORY_FULL_TEXT then return true end
    if string.sub(normalized, 1, #INVENTORY_FULL_TEXT) ~= INVENTORY_FULL_TEXT then return false end

    local suffix = string.sub(normalized, #INVENTORY_FULL_TEXT + 1)
    suffix = string.gsub(suffix, "^%s+", "")
    if suffix == "" then return true end
    if string.match(suffix, "^%.[%s]*%[X%d+%]$") then return true end
    if string.match(suffix, "^%[X%d+%]$") then return true end

    return false
end

local function shouldSellFromInventoryFullNotification()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return false end

    local notification = playerGui:FindFirstChild("Notification")
    if not notification then return false end

    local frame = notification:FindFirstChild("Frame")
    if not frame then return false end

    local frameChildren = frame:GetChildren()
    local slot = frameChildren[5]
    if slot then
        local content = slot:FindFirstChild("CONTENT")
        local shadow = content and content:FindFirstChild("CONTENT_SHADOW")
        if shadow and shadow:IsA("TextLabel") and isInventoryFullNotificationText(shadow.Text) then
            return true
        end
    end

    for _, node in ipairs(frame:GetDescendants()) do
        if node:IsA("TextLabel") and isInventoryFullNotificationText(node.Text) then
            return true
        end
    end
    return false
end

-- Function to check Ripeness from Attributes (Untuk Filter Kategori Buah)
local RIPENESS_MAP = {
    Unripe = function(v) return v and v < 1 end,
    Ripe   = function(v) return v and v >= 1 and v < 1.5 end,
    Lush   = function(v) return v and v >= 1.5 end,
}

local function isNodeMatchingCategory(node, category)
    if not node then return false end
    local stage = tostring(node:GetAttribute("RipenessStage") or "")
    if stage ~= "" and stage:lower() ~= "none" then 
        return stage:lower() == category:lower() 
    end
    
    local rm = tonumber(node:GetAttribute("RipenessMultiplier"))
    if rm then
        local fn = RIPENESS_MAP[category]
        if fn then return fn(rm) end
    end
    return false
end

local function checkCategoryForPrompt(prompt, model, category)
    if category == "All" then return true end
    if isNodeMatchingCategory(prompt, category) then return true end
    if prompt.Parent and isNodeMatchingCategory(prompt.Parent, category) then return true end
    if model and isNodeMatchingCategory(model, category) then return true end
    return false
end

-- End of Category Filter Logic

local function getPromptWorldPosition(prompt)
    if not prompt or not prompt.Parent then return nil end
    if prompt.Parent:IsA("Attachment") then return prompt.Parent.WorldPosition end
    if prompt.Parent:IsA("BasePart") then return prompt.Parent.Position end
    return nil
end

local function getPromptModel(promptObj)
    if not promptObj or not promptObj.Parent then return nil end
    local node = promptObj.Parent
    if node:IsA("Attachment") then node = node.Parent end
    if node and node:IsA("BasePart") then node = node.Parent end
    while node and node ~= workspace and not node:IsA("Model") do node = node.Parent end
    if node and node:IsA("Model") then return node end
    return nil
end

local function getOwnerModel(model)
    local node = model
    while node and node ~= workspace do
        if node:IsA("Model") and node:GetAttribute("OwnerUserId") ~= nil then return node end
        node = node.Parent
    end
    return nil
end

local function isIgnoredSignPrompt(promptObj)
    local node = promptObj
    while node and node ~= workspace do
        if node.Name == "PlayerSign" or node.Name == "GrowAllSign" then
            local parentNode = node.Parent
            while parentNode and parentNode ~= workspace do
                if parentNode.Name == "Plots" then return true end
                parentNode = parentNode.Parent
            end
        end
        node = node.Parent
    end
    return false
end

local function refreshHarvestPromptScanCache()
    local clientPlants = workspace:FindFirstChild("ClientPlants")
    if not clientPlants then
        harvestPromptScanCache = {}
        harvestPromptScanCacheAt = tick()
        return
    end

    local entries = {}
    for _, d in ipairs(clientPlants:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Parent and d.Enabled and (not isIgnoredSignPrompt(d)) then
            local model = getPromptModel(d)
            local ownerUserId = nil
            local isFavorited = false
            if model then
                local ownerModel = getOwnerModel(model)
                if ownerModel then
                    local ownerAttr = ownerModel:GetAttribute("OwnerUserId")
                    ownerUserId = tonumber(ownerAttr) or ownerAttr
                    isFavorited = ownerModel:GetAttribute("Favorited") == true
                end
            end
            local pos = getPromptWorldPosition(d)
            if pos then
                -- Menyimpan model ke dalam cache agar bisa dicek kategorinya
                table.insert(entries, {
                    Prompt = d, Pos = pos, OwnerUserId = ownerUserId, IsFavorited = isFavorited, Model = model
                })
            end
        end
    end
    harvestPromptScanCache = entries
    harvestPromptScanCacheAt = tick()
end

local function getClosestHarvestPrompts(limit, maxDistOverride)
    local root = getCharacterRoot()
    if not root then return {} end

    local now = tick()
    if now - harvestPromptScanCacheAt >= HARVEST_PROMPT_SCAN_INTERVAL or #harvestPromptScanCache == 0 then
        refreshHarvestPromptScanCache()
    end

    local myPos = root.Position
    local maxDist = tonumber(maxDistOverride) or Settings.Range
    local candidates = {}

    for _, entry in ipairs(harvestPromptScanCache) do
        local prompt = entry.Prompt
        if prompt and prompt.Parent and prompt.Enabled then
            local blacklistedUntil = harvestBlacklistUntilByPrompt[prompt]
            if not (blacklistedUntil and now < blacklistedUntil) then
                local cooldownUntil = harvestCooldownByPrompt[prompt]
                if not (cooldownUntil and now < cooldownUntil) then
                    if entry.OwnerUserId == nil or entry.OwnerUserId == LocalPlayer.UserId then
                        if (not Settings.IgnoreFavorited) or (not entry.IsFavorited) then
                            -- Filter Kemampuan Buah Dimasukkan Disini
                            if checkCategoryForPrompt(prompt, entry.Model, Settings.FruitCategory) then
                                local dist = (myPos - entry.Pos).Magnitude
                                if dist < maxDist then
                                    table.insert(candidates, { Prompt = prompt, Pos = entry.Pos, Dist = dist })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b) return a.Dist < b.Dist end)

    local out = {}
    local take = math.max(1, math.floor(tonumber(limit) or 1))
    for i = 1, math.min(#candidates, take) do table.insert(out, candidates[i].Prompt) end
    return out
end

local function markHarvestFailure(prompt)
    local fails = (harvestFailCountByPrompt[prompt] or 0) + 1
    harvestFailCountByPrompt[prompt] = fails
    harvestCooldownByPrompt[prompt] = tick() + 0.2
    if fails >= 4 then
        harvestBlacklistUntilByPrompt[prompt] = tick() + 3
        harvestFailCountByPrompt[prompt] = 0
    end
end

local function triggerHarvestPrompt(prompt)
    if typeof(fireproximityprompt) == "function" then
        return pcall(function() fireproximityprompt(prompt, 0) end)
    end
    return pcall(function() prompt:InputHoldBegin(); prompt:InputHoldEnd() end)
end

local function harvestPromptBatch(prompts)
    if type(prompts) ~= "table" or #prompts == 0 then return false end
    local anySuccess = false
    for _, prompt in ipairs(prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local ok = triggerHarvestPrompt(prompt)
            if ok then
                anySuccess = true
                harvestCooldownByPrompt[prompt] = tick() + 0.35
                harvestFailCountByPrompt[prompt] = 0
            else markHarvestFailure(prompt) end
        end
    end
    return anySuccess
end

-- ==========================
-- OTHER SYSTEM FUNCTIONS (Buy, Plant, Quests, etc.)
-- ==========================
local function getSeedStockAmount(seedName)
    if not GetShopDataRemote then return nil, "GetShopData remote not found." end
    local ok, data = pcall(function() return GetShopDataRemote:InvokeServer("SeedShop") end)
    if not ok or type(data) ~= "table" or type(data.Items) ~= "table" then return nil, "Failed to fetch stock." end

    for itemName, itemData in pairs(data.Items) do
        if tostring(itemName):lower() == tostring(seedName):lower() then
            if type(itemData) == "table" then return tonumber(itemData.Amount) or 0, nil end
            return 0, nil
        end
    end
    return 0, nil
end

local function getPlayerShillings()
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    local function readNumericStat(container, name)
        if not container then return nil end
        local valueObj = container:FindFirstChild(name)
        if valueObj and (valueObj:IsA("IntValue") or valueObj:IsA("NumberValue")) then return tonumber(valueObj.Value) end
        return nil
    end

    local amount = readNumericStat(stats, "Shillings")
    if amount ~= nil then return amount end
    amount = readNumericStat(LocalPlayer, "Shillings")
    if amount ~= nil then return amount end

    if stats then
        local numericValues = {}
        for _, child in ipairs(stats:GetChildren()) do
            if child:IsA("IntValue") or child:IsA("NumberValue") then table.insert(numericValues, child) end
        end
        if #numericValues == 1 then
            local val = tonumber(numericValues[1].Value)
            if val ~= nil then return val end
        end
    end
    return nil
end

local function canAffordPrice(price)
    local numericPrice = tonumber(price)
    if not numericPrice or numericPrice <= 0 then return true end
    local shillings = getPlayerShillings()
    if shillings == nil then return true end
    return shillings >= numericPrice
end

local function tryBuySelectedSeed(silent, forcedSeedName)
    local seedName = forcedSeedName or Settings.SelectedSeed
    if not PurchaseShopItemRemote then return false end
    if not seedName then return false end

    if Settings.CheckSeedStockBeforeBuy then
        local stockAmount, stockErr = getSeedStockAmount(seedName)
        if stockAmount == nil then return false end
        if stockAmount <= 0 then return false end
    end

    local seedPrice = seedPriceByName[seedName]
    if not canAffordPrice(seedPrice) then return false end

    local originalPos = nil
    local didTeleport = false
    local root = getCharacterRoot()

    if Settings.TeleportToShopOnBuy then
        if not root then return false end
        local npcPos = Settings.SeedShopNpcPosition
        if not npcPos then return false end
        originalPos = root.Position
        local reached = teleportRootAndWait(root, npcPos, 1.2, 2.5, 10, 5)
        if not reached then return false end
        didTeleport = true
        task.wait(0.2)
    end

    local ok, result, reason = pcall(function() return PurchaseShopItemRemote:InvokeServer("SeedShop", seedName) end)
    if not ok then return false end

    if result then
        if didTeleport and originalPos then
            local backRoot = getCharacterRoot()
            if backRoot then backRoot.CFrame = CFrame.new(originalPos) end
        end
        if not silent then Notify("Bought: " .. seedName, 2) end
        return true
    else
        local reasonText = string.lower(tostring(reason or ""))
        local outOfStock = string.find(reasonText, "out of stock", 1, true) ~= nil or string.find(reasonText, "no stock", 1, true) ~= nil
        if outOfStock and didTeleport and originalPos then
            local backRoot = getCharacterRoot()
            if backRoot then backRoot.CFrame = CFrame.new(originalPos) end
        end
        if not silent then Notify("Purchase failed: " .. tostring(reason or "Unknown"), 3) end
        return false
    end
end

local function getSelectedBuySeedList()
    local selectedSeedList = {}
    for _, seedName in ipairs(seedOptions) do
        if selectedBuySeedsMap[seedName] then table.insert(selectedSeedList, seedName) end
    end
    if #selectedSeedList == 0 and Settings.SelectedSeed then table.insert(selectedSeedList, Settings.SelectedSeed) end
    return selectedSeedList
end

function tryBuyNextSelectedSeed(silent)
    local selectedSeedList = getSelectedBuySeedList()
    if #selectedSeedList == 0 then return false end

    if buySeedCycleIndex < 1 or buySeedCycleIndex > #selectedSeedList then buySeedCycleIndex = 1 end
    local startIndex = buySeedCycleIndex
    for offset = 0, #selectedSeedList - 1 do
        local idx = ((startIndex - 1 + offset) % #selectedSeedList) + 1
        local seedName = selectedSeedList[idx]
        if tryBuySelectedSeed(silent, seedName) then
            buySeedCycleIndex = (idx % #selectedSeedList) + 1
            return true
        end
    end
    buySeedCycleIndex = (startIndex % #selectedSeedList) + 1
    return false
end

local function getGearStockAmount(gearName)
    if not GetShopDataRemote then return nil, "GetShopData remote not found." end
    local ok, data = pcall(function() return GetShopDataRemote:InvokeServer("GearShop") end)
    if not ok or type(data) ~= "table" or type(data.Items) ~= "table" then return nil, "Failed to fetch stock." end

    for itemName, itemData in pairs(data.Items) do
        if tostring(itemName):lower() == tostring(gearName):lower() then
            if type(itemData) == "table" then return tonumber(itemData.Amount) or 0, nil end
            return 0, nil
        end
    end
    return 0, nil
end

local function tryBuySelectedGear(silent, forcedGearName)
    local gearName = forcedGearName or Settings.SelectedGear
    if not PurchaseShopItemRemote then return false end
    if not gearName then return false end
    
    if Settings.CheckGearStockBeforeBuy then
        local stockAmount, stockErr = getGearStockAmount(gearName)
        if stockAmount == nil or stockAmount <= 0 then return false end
    end

    local gearPrice = gearPriceByName[gearName]
    if not canAffordPrice(gearPrice) then return false end

    local originalPos = nil
    local didTeleport = false
    local root = getCharacterRoot()

    if Settings.TeleportToGearShopOnBuy then
        if not root then return false end
        local npcPos = Settings.GearShopNpcPosition
        if not npcPos then return false end

        originalPos = root.Position
        local reached = teleportRootAndWait(root, npcPos, 1.2, 2.5, 10, 5)
        if not reached then return false end
        didTeleport = true
        task.wait(0.2)
    end

    local ok, result, reason = pcall(function() return PurchaseShopItemRemote:InvokeServer("GearShop", gearName) end)
    if not ok then return false end

    if result then
        if didTeleport and originalPos then
            local backRoot = getCharacterRoot()
            if backRoot then backRoot.CFrame = CFrame.new(originalPos) end
        end
        if not silent then Notify("Bought: " .. gearName, 2) end
        return true
    else
        local reasonText = string.lower(tostring(reason or ""))
        local outOfStock = string.find(reasonText, "out of stock", 1, true) ~= nil or string.find(reasonText, "no stock", 1, true) ~= nil
        if outOfStock and didTeleport and originalPos then
            local backRoot = getCharacterRoot()
            if backRoot then backRoot.CFrame = CFrame.new(originalPos) end
        end
        if not silent then Notify("Purchase failed: " .. tostring(reason or "Unknown"), 3) end
        return false
    end
end

local function getSelectedBuyGearList()
    local selectedGearList = {}
    for _, gearName in ipairs(gearOptions) do
        if selectedBuyGearsMap[gearName] then table.insert(selectedGearList, gearName) end
    end
    if #selectedGearList == 0 and Settings.SelectedGear then table.insert(selectedGearList, Settings.SelectedGear) end
    return selectedGearList
end

function tryBuyNextSelectedGear(silent)
    local selectedGearList = getSelectedBuyGearList()
    if #selectedGearList == 0 then return false end
    if buyGearCycleIndex < 1 or buyGearCycleIndex > #selectedGearList then buyGearCycleIndex = 1 end

    local startIndex = buyGearCycleIndex
    for offset = 0, #selectedGearList - 1 do
        local idx = ((startIndex - 1 + offset) % #selectedGearList) + 1
        local gearName = selectedGearList[idx]
        if tryBuySelectedGear(silent, gearName) then
            buyGearCycleIndex = (idx % #selectedGearList) + 1
            return true
        end
    end
    buyGearCycleIndex = (startIndex % #selectedGearList) + 1
    return false
end

local function getEquippedSeedTool()
    local char = LocalPlayer.Character
    if not char then return nil end

    local function normalizeSeedName(seedName)
        return string.lower((tostring(seedName or "")):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function resolvePlantTypeFromTool(tool)
        if not tool then return nil end
        local plantType = tool:GetAttribute("PlantType")
        if plantType and tostring(plantType) ~= "" then return tostring(plantType) end
        local name = tostring(tool.Name or "")
        local parsed = string.match(name, "^[xX]%d+%s+(.+)%s+[Ss]eed")
        if parsed and parsed ~= "" then return parsed end
        parsed = string.match(name, "^(.+)%s+[Ss]eed")
        if parsed and parsed ~= "" then return parsed end
        return nil
    end

    local function isSeedAllowed(plantType)
        if not plantType then return false end
        if next(selectedAutoPlantSeedsMap) == nil then return true end
        return selectedAutoPlantSeedsMap[tostring(plantType)] == true
    end

    local function isValidSeedTool(tool)
        if not tool or not tool:IsA("Tool") then return false end
        if tool:GetAttribute("IsCrate") or tool:GetAttribute("IsHarvested") then return false end

        local plantType = resolvePlantTypeFromTool(tool)
        if not isSeedAllowed(plantType) then
            local toolNameLower = string.lower(tostring(tool.Name or ""))
            local looksLikeSeedTool = string.find(toolNameLower, "seed", 1, true) ~= nil
            if not looksLikeSeedTool then return false end
            if next(selectedAutoPlantSeedsMap) == nil then return true end

            local matchedSelected = false
            for seedName, isSelected in pairs(selectedAutoPlantSeedsMap) do
                if isSelected and string.find(toolNameLower, normalizeSeedName(seedName), 1, true) then
                    matchedSelected = true; break
                end
            end
            if not matchedSelected then return false end
            return true
        end

        local toolNameLower = string.lower(tostring(tool.Name or ""))
        if string.find(toolNameLower, "seed", 1, true) == nil then return false end

        if ItemInventory and ItemInventory.getItemCount then
            local ok, count = pcall(ItemInventory.getItemCount, tool)
            if ok and count ~= nil then
                local numericCount = tonumber(count)
                if numericCount ~= nil then return numericCount > 0 end
                return true
            end
        end
        return true
    end

    for _, tool in ipairs(char:GetChildren()) do
        if isValidSeedTool(tool) then return tool end
    end

    if not Settings.AutoEquipPlantSeeds then return nil end

    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:WaitForChild("Backpack", 2)
    if not backpack then return nil end

    local candidateTools = {}
    local selectedSeedList = {}
    if next(selectedAutoPlantSeedsMap) == nil then
        for _, seedName in ipairs(seedOptions) do table.insert(selectedSeedList, seedName) end
    else
        for _, seedName in ipairs(seedOptions) do
            if selectedAutoPlantSeedsMap[seedName] then table.insert(selectedSeedList, seedName) end
        end
    end

    for _, tool in ipairs(backpack:GetChildren()) do
        if isValidSeedTool(tool) then table.insert(candidateTools, tool) end
    end
    if #candidateTools == 0 then return nil end

    local orderedSeedNames = {}
    for _, seedName in ipairs(selectedSeedList) do table.insert(orderedSeedNames, seedName) end
    if #orderedSeedNames == 0 then
        for _, tool in ipairs(candidateTools) do
            local parsed = resolvePlantTypeFromTool(tool)
            if parsed and not table.find(orderedSeedNames, parsed) then table.insert(orderedSeedNames, parsed) end
        end
    end
    if #orderedSeedNames == 0 then
        for _, tool in ipairs(candidateTools) do table.insert(orderedSeedNames, tostring(tool.Name)) end
    end

    if autoPlantEquipCycleIndex > #orderedSeedNames then autoPlantEquipCycleIndex = 1 end
    local preferredSeedName = orderedSeedNames[autoPlantEquipCycleIndex]
    autoPlantEquipCycleIndex = autoPlantEquipCycleIndex + 1
    if autoPlantEquipCycleIndex > #orderedSeedNames then autoPlantEquipCycleIndex = 1 end

    local toolToEquip = nil
    local preferredLower = normalizeSeedName(preferredSeedName)
    for _, tool in ipairs(candidateTools) do
        local toolLower = string.lower(tostring(tool.Name or ""))
        if string.find(toolLower, preferredLower, 1, true) and string.find(toolLower, "seed", 1, true) then
            toolToEquip = tool; break
        end
    end
    if not toolToEquip then
        for _, tool in ipairs(candidateTools) do
            local parsed = resolvePlantTypeFromTool(tool)
            if parsed and normalizeSeedName(parsed) == preferredLower then
                toolToEquip = tool; break
            end
        end
    end
    if not toolToEquip then toolToEquip = candidateTools[1] end
    if not toolToEquip then return nil end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    for _ = 1, 4 do
        pcall(function() humanoid:UnequipTools(); humanoid:EquipTool(toolToEquip) end)
        task.wait(0.08)
        if toolToEquip.Parent == char or toolToEquip:IsDescendantOf(char) then return toolToEquip end

        pcall(function() toolToEquip.Parent = char end)
        task.wait(0.05)
        if toolToEquip.Parent == char or toolToEquip:IsDescendantOf(char) then return toolToEquip end
    end
    return nil
end

local function plantAtCharacterPosition()
    if not Settings.AutoPlantAtCharacter then return end
    local now = tick()
    if now - lastPlantTime < Settings.Delay then return end

    local tool = getEquippedSeedTool()
    if not tool then return end

    local plantType = tool:GetAttribute("PlantType")
    if not plantType then
        local name = tostring(tool.Name or "")
        plantType = string.match(name, "^[xX]%d+%s+(.+)%s+[Ss]eed") or string.match(name, "^(.+)%s+[Ss]eed")
    end
    if not plantType then return end

    local plantPos = Settings.SavedPlantPosition
    if not plantPos then
        Settings.AutoPlantAtCharacter = false
        if not warnedMissingSavedPosition then
            warnedMissingSavedPosition = true
            Notify("Set a plant position first.", 3)
        end
        return
    end

    lastPlantTime = now
    pcall(function()
        if PlantRemote:IsA("RemoteFunction") then PlantRemote:InvokeServer(plantType, plantPos)
        else PlantRemote:FireServer(plantType, plantPos) end
    end)
end

local function isQuestEntryClaimable(entry)
    if type(entry) ~= "table" then return false end
    if entry.Claimed == true or entry.IsClaimed == true then return false end
    if entry.Completed == true or entry.IsCompleted == true or entry.Done == true then return true end

    local status = tostring(entry.Status or ""):lower()
    if status == "completed" or status == "complete" then return true end

    local progress = tonumber(entry.Progress or entry.Current or entry.Value or entry.Amount or 0) or 0
    local goal = tonumber(entry.Goal or entry.Target or entry.Required or entry.Max or 0) or 0
    return goal > 0 and progress >= goal
end

local function autoClaimQuests()
    if not (ClaimQuestRemote and ClaimQuestRemote:IsA("RemoteEvent")) then return end
    if RequestQuestsRemote and RequestQuestsRemote:IsA("RemoteEvent") then pcall(function() RequestQuestsRemote:FireServer() end) end
    if type(latestQuestData) ~= "table" then return end

    for _, questType in ipairs({ "Daily", "Weekly" }) do
        local bucket = latestQuestData[questType]
        local active = bucket and bucket.Active
        if type(active) == "table" then
            for i = 1, 5 do
                local questIndex = tostring(i)
                if isQuestEntryClaimable(active[questIndex]) then
                    pcall(function() ClaimQuestRemote:FireServer(questType, questIndex) end)
                end
            end
        end
    end
end

-- ==========================
-- MAIN LOOP
-- ==========================
task.spawn(function()
    while task.wait(Settings.Delay) do
        local ok, err = pcall(function()
            local now = tick()

            -- Sistem Auto Harvest (Old Version + Filter Buah)
            if Settings.Enabled then
                local batchSize = math.max(1, math.floor(tonumber(Settings.HarvestBatchSize) or 5))
                local closestPrompts = getClosestHarvestPrompts(batchSize)
                
                if Settings.AutoHarvestTeleport and now - lastHarvestTeleportTime >= 0.5 then
                    local teleportPrompts = getClosestHarvestPrompts(1, math.huge)
                    local teleportPrompt = teleportPrompts[1]
                    if teleportPrompt then
                        local root = getCharacterRoot()
                        local promptPos = getPromptWorldPosition(teleportPrompt)
                        if root and promptPos then
                            root.CFrame = CFrame.new(promptPos + Vector3.new(0, 3, 0))
                            lastHarvestTeleportTime = now
                        end
                    end
                    closestPrompts = getClosestHarvestPrompts(batchSize)
                end

                local firstPrompt = closestPrompts[1]
                if firstPrompt then harvestPromptBatch(closestPrompts) end
            end

            -- Other Systems
            if Settings.AutoPlantAtCharacter then plantAtCharacterPosition() end

            if Settings.AutoBuyLoop then
                if now - lastAutoBuyTime >= Settings.AutoBuyDelay then
                    lastAutoBuyTime = now
                    tryBuyNextSelectedSeed(true)
                end
            end

            if Settings.AutoBuyGearLoop then
                if now - lastAutoBuyGearTime >= Settings.AutoBuyGearDelay then
                    lastAutoBuyGearTime = now
                    tryBuyNextSelectedGear(true)
                end
            end

            if Settings.AutoSellLoop then
                if not SellItemsRemote then
                    if not warnedMissingSellRemotes then warnedMissingSellRemotes = true; Notify("SellItems remote not found.", 3) end
                elseif now - lastAutoSellTime >= Settings.AutoSellDelay then
                    lastAutoSellTime = now
                    if Settings.AutoSellOnlyWhenInventoryFull then
                        if now - lastInventoryFullSellTime >= Settings.InventoryFullSellCooldown and shouldSellFromInventoryFullNotification() then
                            lastInventoryFullSellTime = now
                            trySell(Settings.SellMode, true)
                        end
                    else
                        trySell(Settings.SellMode, true)
                    end
                end
            end

            if Settings.AutoClaimQuests then
                if not (ClaimQuestRemote and RequestQuestsRemote and UpdateQuestsRemote) then
                    if not warnedMissingQuestRemotes then warnedMissingQuestRemotes = true; Notify("Quest remotes not found.", 3) end
                else
                    if now - lastAutoClaimQuestTime >= Settings.AutoClaimQuestDelay then
                        lastAutoClaimQuestTime = now
                        autoClaimQuests()
                    end
                end
            end
        end)
        if not ok then warn("[Garden] Main loop recovered from error:", err) end
    end
end)

print("[Garden Horizons] System Loaded (Old Method + Category Filter).")

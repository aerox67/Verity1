local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local LocalPlayer = Players.LocalPlayer

-- CONFIG API & KEYS (Pre-filled automatically)
local CONFIG_FILE = "Verity_Config.json"
local GEMINI_API_KEY = ""
local OPENROUTER_API_KEY = ""
local FISH_API_KEY = "sk-fish-tYLnEFuG_H7y3fDmwK5zgp23pQVfKOp-wDRhFDwFhY0" 
local FISH_VOICE_ID = "2d1806418d654c3f936b71e9827d427c"

-- ACTIVE MODEL CHOICE: "Gemini" or "OpenRouter"
local currentAIModel = "Gemini"

-- ACTIVE AI LANGUAGE: "id" (Indonesian) or "en" (English)
local currentLanguage = "en"

local SONG_BPM = 120
local function beats(n)
    return (60 / SONG_BPM) * n
end

local NORMAL_FACE = "rbxthumb://type=Asset&id=99982487168868&w=420&h=420"
local TALKING_FACE = "rbxthumb://type=Asset&id=114293272612131&w=420&h=420"
local FALL_FACE = "rbxthumb://type=Asset&id=111386390222268&w=420&h=420"
local COLOR_VERITY = Color3.fromRGB(255, 225, 50)

local spawnVerity
local verityPart, verityMesh, verityGui, verityGuiText, verityFace, bubbleFrame, bubbleStroke, verityBubbleText
local bubbleDisplayToken = 0
local isVeritySpeaking = false
local isHeld, hasIntroduced = false, false
local holdAnimTrack = nil
local sizeSpring = {current = Vector3.new(0,0,0), velocity = Vector3.new(0,0,0), target = Vector3.new(2.0,2.0,2.0), stiffness = 240, damping = 11}
local isRespawning = false
local isVerityBusy = false
local isFlying = false
local isFollowing = false

local function getRequestFunction()
    return (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
        or (fluxus and fluxus.request)
        or (Krnl and Krnl.request)
        or nil
end

local hasFileSystem = false
pcall(function()
    if writefile and readfile and isfile and getcustomasset then hasFileSystem = true end
end)

local function safeWriteFile(name, data)
    if hasFileSystem then pcall(function() writefile(name, data) end) end
end

local function safeReadFile(name)
    if hasFileSystem then
        local success, data = pcall(function()
            if isfile(name) then return readfile(name) end
        end)
        if success then return data end
    end
    return nil
end

local function loadConfig()
    if not hasFileSystem then return end
    local data = safeReadFile(CONFIG_FILE)
    if data then
        local ok, decoded = pcall(function() return HttpService:JSONDecode(data) end)
        if ok and type(decoded) == "table" then
            if decoded.geminiKey and decoded.geminiKey ~= "" then GEMINI_API_KEY = decoded.geminiKey end
            if decoded.openrouterKey and decoded.openrouterKey ~= "" then OPENROUTER_API_KEY = decoded.openrouterKey end
            if decoded.activeModel and decoded.activeModel ~= "" then currentAIModel = decoded.activeModel end
            if decoded.language and decoded.language ~= "" then currentLanguage = decoded.language end
        end
    end
end

local function saveConfig()
    if not hasFileSystem then return end
    local data = { geminiKey = GEMINI_API_KEY, openrouterKey = OPENROUTER_API_KEY, activeModel = currentAIModel, language = currentLanguage }
    pcall(function() safeWriteFile(CONFIG_FILE, HttpService:JSONEncode(data)) end)
end
loadConfig()

local function getPlayerContext(player)
    if not player then return "an unknown date" end
    local daysAgo = player.AccountAge
    local joinTime = os.time() - (daysAgo * 86400)
    return os.date("%B %d, %Y", joinTime)
end

local success, gameInfo = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
local gameName = (success and type(gameInfo) == "table" and gameInfo.Name) or "Unknown Game"
local gameDesc = (success and type(gameInfo) == "table" and gameInfo.Description) or "No description available."
gameDesc = string.sub(gameDesc, 1, 400):gsub("\n", " ")

local pName = LocalPlayer.Name
local pDisplayName = LocalPlayer.DisplayName
local pJoinDate = getPlayerContext(LocalPlayer)

local function removeCollisionWithCharacters()
    if not verityPart then return end
    for _, obj in pairs(verityPart:GetChildren()) do
        if obj:IsA("NoCollisionConstraint") then obj:Destroy() end
    end
    local function addNoCollision(character)
        if not character then return end
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                local nc = Instance.new("NoCollisionConstraint")
                nc.Part0 = verityPart
                nc.Part1 = part
                nc.Parent = verityPart
            end
        end
    end
    for _, plr in pairs(Players:GetPlayers()) do
        if plr.Character then addNoCollision(plr.Character) end
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.6)
        removeCollisionWithCharacters()
    end)
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.6)
    removeCollisionWithCharacters()
end)

local function getSystemPrompt()
    local langInstruction = ""
    if currentLanguage == "id" then
        langInstruction = "CRITICAL INSTRUCTION: You MUST ALWAYS reply and speak exclusively in fluent, natural Indonesian (Bahasa Indonesia)."
    else
        langInstruction = "CRITICAL INSTRUCTION: You MUST ALWAYS reply and speak exclusively in fluent, natural English."
    end

    return string.format(
        "You are Verity, a vibrant, exotic, and joyful helper spirit in the form of a ball! " ..
        langInstruction .. " " ..
        "Keep your answers very short (1 short sentence max). Write normal, natural Indonesian/English with normal word spacing. NEVER insert spaces inside a word, NEVER spell words letter-by-letter, and NEVER output broken syllables. " ..
        "You are currently playing the Roblox map/game named '%s' with PlaceID %d. " ..
        "Game Description/Details: '%s'. " ..
        "Your master is %s (Display Name: %s), who joined Roblox on %s. " ..
        "Always act like you know this map and can help your master navigate or talk about it!",
        gameName, game.PlaceId, gameDesc, pName, pDisplayName, pJoinDate
    )
end

local conversationHistory = {
    {role = "system", content = getSystemPrompt()},
    {role = "user", content = "Hello Verity, what game are we playing?"},
    {role = "assistant", content = string.format("Hello! We are playing the map '%s'!", gameName)}
}

local function updateSystemPromptInHistory()
    if #conversationHistory > 0 and conversationHistory[1].role == "system" then
        conversationHistory[1].content = getSystemPrompt()
    end
end

local function addMemory(role, content)
    table.insert(conversationHistory, {role = role, content = content})
    if #conversationHistory > 16 then
        table.remove(conversationHistory, 2)
        table.remove(conversationHistory, 2)
    end
end

local function countUtf8Characters(value)
    local count = #tostring(value or "")
    pcall(function()
        count = utf8.len(tostring(value or "")) or count
    end)
    return count
end

local function showVerityBubble(message)
    if not verityGui or not verityGuiText then return end

    local cleanMessage = tostring(message or "")
        :gsub("<[^>]->", "")
        :gsub("[%c]+", " ")
        :gsub("%s+", " ")
        :match("^%s*(.-)%s*$") or ""

    if cleanMessage == "" then return end

    bubbleDisplayToken = bubbleDisplayToken + 1
    local token = bubbleDisplayToken

    verityGuiText.Text = cleanMessage
    verityGui.Enabled = true
    if bubbleFrame then bubbleFrame.BackgroundTransparency = 0.08 end
    if bubbleStroke then bubbleStroke.Transparency = 0.15 end

    local duration = math.clamp(
        1.6 + countUtf8Characters(cleanMessage) * 0.075,
        2.2,
        9
    )

    task.delay(duration, function()
        if token == bubbleDisplayToken and verityGui then
            verityGui.Enabled = false
            if verityGuiText then verityGuiText.Text = "" end
        end
    end)
end

local function playVeritySpeech(textToSpeak, faceType, soundId)
    textToSpeak = tostring(textToSpeak or "")
        :gsub("<[^>]->", "")
        :gsub("[%c\r\n\t]+", " ")
        :gsub("%s+", " ")
        :gsub("%s+([,%.%!%?%:;])", "%1")
        :match("^%s*(.-)%s*$") or ""

    if textToSpeak == "" then return end

    isVeritySpeaking = true

    local requestFunc = getRequestFunction()
    local audioSound = nil

    if soundId and soundId ~= "" then
        pcall(function()
            audioSound = Instance.new("Sound")
            audioSound.Name = "VerityVoice"
            audioSound.SoundId = soundId
            audioSound.Volume = 2
            audioSound.Looped = false
            audioSound.Parent = SoundService
        end)
    elseif FISH_API_KEY ~= "" and requestFunc and hasFileSystem then
        local success, response = pcall(function()
            return requestFunc({
                Url = "https://api.fish.audio/v1/tts",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. FISH_API_KEY,
                    ["model"] = "s2.1-pro-free",
                    ["Accept"] = "audio/mp3"
                },
                Body = HttpService:JSONEncode({
                    text = textToSpeak,
                    reference_id = FISH_VOICE_ID,
                    format = "mp3"
                })
            })
        end)

        if success and response and response.Success and response.Body then
            pcall(function()
                local fileName = "verity_tts_cache.mp3"
                writefile(fileName, response.Body)

                if isfile(fileName) then
                    local ttsSoundId = getcustomasset(fileName)
                    if ttsSoundId then
                        audioSound = Instance.new("Sound")
                        audioSound.Name = "VerityVoice"
                        audioSound.SoundId = ttsSoundId
                        audioSound.Volume = 2
                        audioSound.PlaybackSpeed = 1
                        audioSound.Looped = false
                        audioSound.Parent = SoundService
                    end
                end
            end)
        end
    end

    if not audioSound then
        if verityFace then verityFace.Texture = faceType or TALKING_FACE end
        if verityGuiText then verityGuiText.Text = textToSpeak end
        if bubbleFrame then bubbleFrame.BackgroundTransparency = 0.25 end
        if bubbleStroke then bubbleStroke.Transparency = 0.2 end
        if verityGui then verityGui.Enabled = true end

        local fallbackTime = math.max(1.5, countUtf8Characters(textToSpeak) / 12)
        task.wait(fallbackTime)

        if verityPart and verityPart.Parent then
            if verityGuiText then verityGuiText.Text = "" end
            if bubbleFrame then bubbleFrame.BackgroundTransparency = 1 end
            if bubbleStroke then bubbleStroke.Transparency = 1 end
            if verityFace then verityFace.Texture = NORMAL_FACE end
            if verityGui then verityGui.Enabled = false end
        end
        isVeritySpeaking = false
        return
    end

    if not audioSound.IsLoaded then
        pcall(function() audioSound.Loaded:Wait() end)
    end

    if verityFace then verityFace.Texture = faceType or TALKING_FACE end
    if verityGuiText then verityGuiText.Text = textToSpeak end
    if bubbleFrame then bubbleFrame.BackgroundTransparency = 0.25 end
    if bubbleStroke then bubbleStroke.Transparency = 0.2 end
    if verityGui then verityGui.Enabled = true end
    audioSound:Play()

    local len = 0
    pcall(function() len = audioSound.TimeLength end)

    if not len or len <= 0 then
        len = math.max(1.5, countUtf8Characters(textToSpeak) / 12)
    end

    task.wait(len + 0.5)

    if audioSound and audioSound.Parent then
        audioSound:Destroy()
    end

    if verityPart and verityPart.Parent then
        if verityGuiText then verityGuiText.Text = "" end
        if bubbleFrame then bubbleFrame.BackgroundTransparency = 1 end
        if bubbleStroke then bubbleStroke.Transparency = 1 end
        if verityFace then verityFace.Texture = NORMAL_FACE end
        if verityGui then verityGui.Enabled = false end
        isVeritySpeaking = false
    end
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
if playerGui:FindFirstChild("VerityGui") then
    playerGui.VerityGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VerityGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local function makeDraggable(frame)
    local dragging, dragInput, dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local function addButtonFeedback(btn)
    local baseSize = btn.Size
    local hoverTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local pressTween = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, hoverTween, {
            Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset + 4, baseSize.Y.Scale, baseSize.Y.Offset + 2)
        }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, hoverTween, {Size = baseSize}):Play()
    end)
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, pressTween, {
            Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset - 4, baseSize.Y.Scale, baseSize.Y.Offset - 3)
        }):Play()
    end)
    btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn, hoverTween, {Size = baseSize}):Play()
    end)
end

local function addSoftGradient(parent, brightTop)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(brightTop and 1 or 0.85, brightTop and 1 or 0.85, brightTop and 1 or 0.85)),
        ColorSequenceKeypoint.new(1, Color3.new(0.75, 0.75, 0.75))
    })
    gradient.Rotation = 90
    gradient.Parent = parent
    return gradient
end

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(0, 470, 0, 45)
topBar.Position = UDim2.new(1, -485, 0, 15)
topBar.BackgroundTransparency = 1
topBar.Parent = screenGui

local topBarLayout = Instance.new("UIListLayout", topBar)
topBarLayout.FillDirection = Enum.FillDirection.Horizontal
topBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
topBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
topBarLayout.Padding = UDim.new(0, 8)

local modelSwitchBtn = Instance.new("TextButton")
modelSwitchBtn.Size = UDim2.new(0, 110, 0, 42)
modelSwitchBtn.BackgroundColor3 = (currentAIModel == "Gemini") and Color3.fromRGB(40, 120, 220) or Color3.fromRGB(110, 30, 160)
modelSwitchBtn.BackgroundTransparency = 0.1
modelSwitchBtn.TextColor3 = Color3.new(1, 1, 1)
modelSwitchBtn.Text = "🤖 Mode: " .. currentAIModel
modelSwitchBtn.TextScaled = true
modelSwitchBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
modelSwitchBtn.LayoutOrder = 1
modelSwitchBtn.Parent = topBar
Instance.new("UICorner", modelSwitchBtn).CornerRadius = UDim.new(0, 14)
local msStroke = Instance.new("UIStroke", modelSwitchBtn)
msStroke.Color = COLOR_VERITY
msStroke.Thickness = 2
addSoftGradient(modelSwitchBtn, true)

local langSwitchBtn = Instance.new("TextButton")
langSwitchBtn.Size = UDim2.new(0, 100, 0, 42)
langSwitchBtn.BackgroundColor3 = (currentLanguage == "id") and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(180, 90, 30)
langSwitchBtn.BackgroundTransparency = 0.1
langSwitchBtn.TextColor3 = Color3.new(1, 1, 1)
langSwitchBtn.Text = (currentLanguage == "id") and "🇮🇩 ID" or "🇬🇧 EN"
langSwitchBtn.TextScaled = true
langSwitchBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
langSwitchBtn.LayoutOrder = 2
langSwitchBtn.Parent = topBar
Instance.new("UICorner", langSwitchBtn).CornerRadius = UDim.new(0, 14)
local lsStroke = Instance.new("UIStroke", langSwitchBtn)
lsStroke.Color = COLOR_VERITY
lsStroke.Thickness = 2
addSoftGradient(langSwitchBtn, true)

local settingsToggleBtn = Instance.new("TextButton")
settingsToggleBtn.Size = UDim2.new(0, 100, 0, 42)
settingsToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
settingsToggleBtn.BackgroundTransparency = 0.1
settingsToggleBtn.TextColor3 = Color3.new(1, 1, 1)
settingsToggleBtn.Text = "⚙️ Config"
settingsToggleBtn.TextScaled = true
settingsToggleBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
settingsToggleBtn.LayoutOrder = 3
settingsToggleBtn.Parent = topBar
Instance.new("UICorner", settingsToggleBtn).CornerRadius = UDim.new(0, 14)
local stStroke = Instance.new("UIStroke", settingsToggleBtn)
stStroke.Color = COLOR_VERITY
stStroke.Thickness = 2
addSoftGradient(settingsToggleBtn, true)

local uiEditorToggleBtn = Instance.new("TextButton")
uiEditorToggleBtn.Size = UDim2.new(0, 100, 0, 42)
uiEditorToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
uiEditorToggleBtn.BackgroundTransparency = 0.1
uiEditorToggleBtn.TextColor3 = Color3.new(1, 1, 1)
uiEditorToggleBtn.Text = "🎨 Editor"
uiEditorToggleBtn.TextScaled = true
uiEditorToggleBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
uiEditorToggleBtn.LayoutOrder = 4
uiEditorToggleBtn.Parent = topBar
Instance.new("UICorner", uiEditorToggleBtn).CornerRadius = UDim.new(0, 14)
local utStroke = Instance.new("UIStroke", uiEditorToggleBtn)
utStroke.Color = Color3.fromRGB(255, 100, 200)
utStroke.Thickness = 2
addSoftGradient(uiEditorToggleBtn, true)

addButtonFeedback(modelSwitchBtn)
addButtonFeedback(langSwitchBtn)
addButtonFeedback(settingsToggleBtn)
addButtonFeedback(uiEditorToggleBtn)

modelSwitchBtn.MouseButton1Click:Connect(function()
    if currentAIModel == "OpenRouter" then
        currentAIModel = "Gemini"
        modelSwitchBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 220)
    else
        currentAIModel = "OpenRouter"
        modelSwitchBtn.BackgroundColor3 = Color3.fromRGB(30, 90, 160)
    end
    modelSwitchBtn.Text = "🤖 Mode: " .. currentAIModel
    saveConfig()
    task.spawn(function()
        playVeritySpeech("AI mode switched to " .. currentAIModel, TALKING_FACE)
    end)
end)

langSwitchBtn.MouseButton1Click:Connect(function()
    if currentLanguage == "id" then
        currentLanguage = "en"
        langSwitchBtn.Text = "🇬🇧 EN"
        langSwitchBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 30)
    else
        currentLanguage = "id"
        langSwitchBtn.Text = "🇮🇩 ID"
        langSwitchBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 70)
    end
    updateSystemPromptInHistory()
    saveConfig()
    task.spawn(function()
        if currentLanguage == "id" then
            playVeritySpeech("Bahasa diubah ke Bahasa Indonesia!", TALKING_FACE)
        else
            playVeritySpeech("Language changed to English!", TALKING_FACE)
        end
    end)
end)

local isUiHidden = false
local hideToggleButton = Instance.new("TextButton")
hideToggleButton.Size = UDim2.new(0, 90, 0, 38)
hideToggleButton.Position = UDim2.new(0, 15, 0, 15)
hideToggleButton.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
hideToggleButton.BackgroundTransparency = 0.15
hideToggleButton.TextColor3 = Color3.new(1, 1, 1)
hideToggleButton.Text = "👁️ Hide UI"
hideToggleButton.TextSize = 13
hideToggleButton.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
hideToggleButton.Parent = screenGui
Instance.new("UICorner", hideToggleButton).CornerRadius = UDim.new(0, 12)
local htStroke = Instance.new("UIStroke", hideToggleButton)
htStroke.Color = COLOR_VERITY
htStroke.Thickness = 2
addSoftGradient(hideToggleButton, true)
addButtonFeedback(hideToggleButton)
makeDraggable(hideToggleButton)

local settingsFrame = Instance.new("Frame")
settingsFrame.Size = UDim2.new(0, 420, 0, 350)
settingsFrame.Position = UDim2.new(0.5, -210, 0.5, -175)
settingsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
settingsFrame.BackgroundTransparency = 0.03
settingsFrame.Visible = false
settingsFrame.Parent = screenGui
Instance.new("UICorner", settingsFrame).CornerRadius = UDim.new(0, 22)
local sfStroke = Instance.new("UIStroke", settingsFrame)
sfStroke.Color = COLOR_VERITY
sfStroke.Thickness = 2.5
addSoftGradient(settingsFrame, true)
makeDraggable(settingsFrame)

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, 0, 0, 45)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "⚙️ AI API Settings (Gemini & OpenRouter)"
settingsTitle.TextColor3 = COLOR_VERITY
settingsTitle.TextSize = 14
settingsTitle.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
settingsTitle.Parent = settingsFrame

local function createInputBox(name, placeholder, defaultText, posY, parent)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.9, 0, 0, 20)
    label.Position = UDim2.new(0.05, 0, 0, posY)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(210, 210, 220)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextSize = 13
    label.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Medium)
    label.Parent = parent

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.9, 0, 0, 38)
    box.Position = UDim2.new(0.05, 0, 0, posY + 22)
    box.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    box.TextColor3 = Color3.new(1, 1, 1)
    box.PlaceholderText = placeholder
    box.Text = defaultText
    box.TextSize = 13
    box.ClearTextOnFocus = false
    box.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Regular)
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
    local bStroke = Instance.new("UIStroke", box)
    bStroke.Color = Color3.fromRGB(70, 70, 95)
    bStroke.Thickness = 1.5
    return box
end

local geminiInput = createInputBox("Gemini API Key:", "Enter Gemini API Key...", GEMINI_API_KEY, 45, settingsFrame)
local openrouterInput = createInputBox("OpenRouter API Key:", "Enter OpenRouter API Key...", OPENROUTER_API_KEY, 115, settingsFrame)

local saveApiBtn = Instance.new("TextButton")
saveApiBtn.Size = UDim2.new(0.42, 0, 0, 40)
saveApiBtn.Position = UDim2.new(0.05, 0, 1, -50)
saveApiBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
saveApiBtn.BackgroundTransparency = 0.1
saveApiBtn.TextColor3 = Color3.new(1, 1, 1)
saveApiBtn.Text = "Save & Apply"
saveApiBtn.TextSize = 14
saveApiBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
saveApiBtn.Parent = settingsFrame
Instance.new("UICorner", saveApiBtn).CornerRadius = UDim.new(0, 12)
addSoftGradient(saveApiBtn, true)

local closeApiBtn = Instance.new("TextButton")
closeApiBtn.Size = UDim2.new(0.42, 0, 0, 40)
closeApiBtn.Position = UDim2.new(0.53, 0, 1, -50)
closeApiBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeApiBtn.BackgroundTransparency = 0.1
closeApiBtn.TextColor3 = Color3.new(1, 1, 1)
closeApiBtn.Text = "Close"
closeApiBtn.TextSize = 14
closeApiBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
closeApiBtn.Parent = settingsFrame
Instance.new("UICorner", closeApiBtn).CornerRadius = UDim.new(0, 12)
addSoftGradient(closeApiBtn, true)

addButtonFeedback(saveApiBtn)
addButtonFeedback(closeApiBtn)

local function setPanelOpen(frame, open)
    if open then
        frame.Visible = true
        frame.Size = UDim2.new(frame:GetAttribute("BaseSizeXScale") or 0, (frame:GetAttribute("BaseSizeXOffset") or frame.Size.X.Offset) * 0.9, frame:GetAttribute("BaseSizeYScale") or 0, (frame:GetAttribute("BaseSizeYOffset") or frame.Size.Y.Offset) * 0.9)
        TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.new(frame:GetAttribute("BaseSizeXScale") or 0, frame:GetAttribute("BaseSizeXOffset"), frame:GetAttribute("BaseSizeYScale") or 0, frame:GetAttribute("BaseSizeYOffset"))
        }):Play()
    else
        local tween = TweenService:Create(frame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.new(frame:GetAttribute("BaseSizeXScale") or 0, (frame:GetAttribute("BaseSizeXOffset") or frame.Size.X.Offset) * 0.9, frame:GetAttribute("BaseSizeYScale") or 0, (frame:GetAttribute("BaseSizeYOffset") or frame.Size.Y.Offset) * 0.9)
        })
        tween.Completed:Connect(function() frame.Visible = false end)
        tween:Play()
    end
end

local function rememberBaseSize(frame)
    frame:SetAttribute("BaseSizeXScale", frame.Size.X.Scale)
    frame:SetAttribute("BaseSizeXOffset", frame.Size.X.Offset)
    frame:SetAttribute("BaseSizeYScale", frame.Size.Y.Scale)
    frame:SetAttribute("BaseSizeYOffset", frame.Size.Y.Offset)
end
rememberBaseSize(settingsFrame)

settingsToggleBtn.MouseButton1Click:Connect(function()
    setPanelOpen(settingsFrame, not settingsFrame.Visible)
end)
closeApiBtn.MouseButton1Click:Connect(function()
    setPanelOpen(settingsFrame, false)
end)
saveApiBtn.MouseButton1Click:Connect(function()
    GEMINI_API_KEY = geminiInput.Text
    OPENROUTER_API_KEY = openrouterInput.Text
    saveConfig()
    settingsFrame.Visible = false
end)

local uiEditorFrame = Instance.new("Frame")
uiEditorFrame.Size = UDim2.new(0, 380, 0, 360)
uiEditorFrame.Position = UDim2.new(0.5, -190, 0.5, -180)
uiEditorFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
uiEditorFrame.BackgroundTransparency = 0.03
uiEditorFrame.Visible = false
uiEditorFrame.Parent = screenGui
Instance.new("UICorner", uiEditorFrame).CornerRadius = UDim.new(0, 22)
local uefStroke = Instance.new("UIStroke", uiEditorFrame)
uefStroke.Color = Color3.fromRGB(255, 100, 200)
uefStroke.Thickness = 2.5
addSoftGradient(uiEditorFrame, true)
makeDraggable(uiEditorFrame)
rememberBaseSize(uiEditorFrame)

local editorTitle = Instance.new("TextLabel")
editorTitle.Size = UDim2.new(1, 0, 0, 45)
editorTitle.BackgroundTransparency = 1
editorTitle.Text = "🎨 Custom UI & Action Panel Editor"
editorTitle.TextColor3 = Color3.fromRGB(255, 100, 200)
editorTitle.TextSize = 16
editorTitle.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
editorTitle.Parent = uiEditorFrame

local labelTrans = Instance.new("TextLabel")
labelTrans.Size = UDim2.new(0.9, 0, 0, 20)
labelTrans.Position = UDim2.new(0.05, 0, 0, 55)
labelTrans.BackgroundTransparency = 1
labelTrans.Text = "Chat Bar Transparency:"
labelTrans.TextColor3 = Color3.fromRGB(210, 210, 220)
labelTrans.TextXAlignment = Enum.TextXAlignment.Left
labelTrans.TextSize = 13
labelTrans.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Medium)
labelTrans.Parent = uiEditorFrame

local transToggleBtn = Instance.new("TextButton")
transToggleBtn.Size = UDim2.new(0.9, 0, 0, 38)
transToggleBtn.Position = UDim2.new(0.05, 0, 0, 80)
transToggleBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
transToggleBtn.BackgroundTransparency = 0.1
transToggleBtn.TextColor3 = Color3.new(1, 1, 1)
transToggleBtn.Text = "Toggle Transparency (Solid / Clear)"
transToggleBtn.TextSize = 13
transToggleBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
transToggleBtn.Parent = uiEditorFrame
Instance.new("UICorner", transToggleBtn).CornerRadius = UDim.new(0, 12)
addSoftGradient(transToggleBtn, true)
addButtonFeedback(transToggleBtn)

local transState = false

local labelColor = Instance.new("TextLabel")
labelColor.Size = UDim2.new(0.9, 0, 0, 20)
labelColor.Position = UDim2.new(0.05, 0, 0, 130)
labelColor.BackgroundTransparency = 1
labelColor.Text = "Change Theme Accent Color:"
labelColor.TextColor3 = Color3.fromRGB(210, 210, 220)
labelColor.TextXAlignment = Enum.TextXAlignment.Left
labelColor.TextSize = 13
labelColor.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Medium)
labelColor.Parent = uiEditorFrame

local function createColorBtn(name, color, posX, parent, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.27, 0, 0, 38)
    btn.Position = UDim2.new(posX, 0, 0, 155)
    btn.BackgroundColor3 = color
    btn.BackgroundTransparency = 0.1
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Text = name
    btn.TextSize = 12
    btn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
    addSoftGradient(btn, true)
    btn.MouseButton1Click:Connect(callback)
    addButtonFeedback(btn)
    return btn
end

local function applyAccentColor(color)
    COLOR_VERITY = color
    stStroke.Color = COLOR_VERITY
    sfStroke.Color = COLOR_VERITY
    htStroke.Color = COLOR_VERITY
    msStroke.Color = COLOR_VERITY
    lsStroke.Color = COLOR_VERITY
    if bubbleStroke then bubbleStroke.Color = COLOR_VERITY end
    if verityPart then verityPart.Color = COLOR_VERITY end
end

createColorBtn("Yellow", Color3.fromRGB(255, 225, 50), 0.05, uiEditorFrame, function()
    applyAccentColor(Color3.fromRGB(255, 225, 50))
end)

createColorBtn("Cyan", Color3.fromRGB(0, 220, 255), 0.36, uiEditorFrame, function()
    applyAccentColor(Color3.fromRGB(0, 220, 255))
end)

createColorBtn("Purple", Color3.fromRGB(180, 50, 255), 0.68, uiEditorFrame, function()
    applyAccentColor(Color3.fromRGB(180, 50, 255))
end)

local labelDropPos = Instance.new("TextLabel")
labelDropPos.Size = UDim2.new(0.9, 0, 0, 20)
labelDropPos.Position = UDim2.new(0.05, 0, 0, 205)
labelDropPos.BackgroundTransparency = 1
labelDropPos.Text = "Toggle Drop & Throw Action Panel Layout:"
labelDropPos.TextColor3 = Color3.fromRGB(210, 210, 220)
labelDropPos.TextXAlignment = Enum.TextXAlignment.Left
labelDropPos.TextSize = 13
labelDropPos.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Medium)
labelDropPos.Parent = uiEditorFrame

local dropLayoutToggleBtn = Instance.new("TextButton")
dropLayoutToggleBtn.Size = UDim2.new(0.9, 0, 0, 38)
dropLayoutToggleBtn.Position = UDim2.new(0.05, 0, 0, 230)
dropLayoutToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 110, 200)
dropLayoutToggleBtn.BackgroundTransparency = 0.1
dropLayoutToggleBtn.TextColor3 = Color3.new(1, 1, 1)
dropLayoutToggleBtn.Text = "Layout Style: Center Floating (Click to Change)"
dropLayoutToggleBtn.TextSize = 12
dropLayoutToggleBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
dropLayoutToggleBtn.Parent = uiEditorFrame
Instance.new("UICorner", dropLayoutToggleBtn).CornerRadius = UDim.new(0, 12)
addSoftGradient(dropLayoutToggleBtn, true)
addButtonFeedback(dropLayoutToggleBtn)

local closeEditorBtn = Instance.new("TextButton")
closeEditorBtn.Size = UDim2.new(0.9, 0, 0, 42)
closeEditorBtn.Position = UDim2.new(0.05, 0, 1, -55)
closeEditorBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeEditorBtn.BackgroundTransparency = 0.1
closeEditorBtn.TextColor3 = Color3.new(1, 1, 1)
closeEditorBtn.Text = "Close Editor"
closeEditorBtn.TextSize = 14
closeEditorBtn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
closeEditorBtn.Parent = uiEditorFrame
Instance.new("UICorner", closeEditorBtn).CornerRadius = UDim.new(0, 12)
addSoftGradient(closeEditorBtn, true)
addButtonFeedback(closeEditorBtn)

uiEditorToggleBtn.MouseButton1Click:Connect(function()
    setPanelOpen(uiEditorFrame, not uiEditorFrame.Visible)
end)
closeEditorBtn.MouseButton1Click:Connect(function()
    setPanelOpen(uiEditorFrame, false)
end)

local chatFrame = Instance.new("Frame")
chatFrame.Size = UDim2.new(0, 420, 0, 52)
chatFrame.Position = UDim2.new(0.5, -210, 1, -75)
chatFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
chatFrame.BackgroundTransparency = 0.15
chatFrame.Parent = screenGui
Instance.new("UICorner", chatFrame).CornerRadius = UDim.new(0, 26)
local chatStroke = Instance.new("UIStroke", chatFrame)
chatStroke.Color = Color3.fromRGB(75, 75, 100)
chatStroke.Thickness = 2
addSoftGradient(chatFrame, true)
makeDraggable(chatFrame)

transToggleBtn.MouseButton1Click:Connect(function()
    transState = not transState
    if transState then
        chatFrame.BackgroundTransparency = 0.8
    else
        chatFrame.BackgroundTransparency = 0.15
    end
end)

local chatInput = Instance.new("TextBox")
chatInput.Size = UDim2.new(0.72, 0, 1, 0)
chatInput.Position = UDim2.new(0.05, 0, 0, 0)
chatInput.BackgroundTransparency = 1
chatInput.PlaceholderText = "Type message..."
chatInput.PlaceholderColor3 = Color3.fromRGB(150, 150, 180)
chatInput.TextColor3 = Color3.new(1, 1, 1)
chatInput.TextSize = 14
chatInput.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Regular)
chatInput.Parent = chatFrame

local function createStyledButton(name, text, color, sizeX, posX, parent)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(sizeX, 0, 0, 38)
    btn.Position = UDim2.new(posX, 0, 0.5, -19)
    btn.BackgroundColor3 = color
    btn.BackgroundTransparency = 0.1
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Text = text
    btn.TextSize = 12
    btn.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
    addSoftGradient(btn, true)
    addButtonFeedback(btn)
    return btn
end

local sendButton = createStyledButton("Send", "Send", Color3.fromRGB(50, 140, 255), 0.2, 0.77, chatFrame)

hideToggleButton.MouseButton1Click:Connect(function()
    isUiHidden = not isUiHidden
    topBar.Visible = not isUiHidden
    chatFrame.Visible = not isUiHidden
    settingsFrame.Visible = false
    uiEditorFrame.Visible = false
    
    if isUiHidden then
        hideToggleButton.Text = "👁️ Show UI"
        hideToggleButton.BackgroundColor3 = Color3.fromRGB(180, 45, 45)
    else
        hideToggleButton.Text = "👁️ Hide UI"
        hideToggleButton.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    end
end)

local dropButton = Instance.new("TextButton")
dropButton.Size = UDim2.new(0, 140, 0, 42)
dropButton.Position = UDim2.new(0.35, -75, 0.78, 0)
dropButton.Text = "Drop Verity"
dropButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
dropButton.BackgroundTransparency = 0.1
dropButton.TextColor3 = Color3.new(1, 1, 1)
dropButton.TextSize = 13
dropButton.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
dropButton.Visible = false
dropButton.Parent = screenGui
Instance.new("UICorner", dropButton).CornerRadius = UDim.new(0, 14)
addSoftGradient(dropButton, true)
addButtonFeedback(dropButton)
makeDraggable(dropButton)

local throwButton = Instance.new("TextButton")
throwButton.Size = UDim2.new(0, 140, 0, 42)
throwButton.Position = UDim2.new(0.65, -75, 0.78, 0)
throwButton.Text = "Throw Verity"
throwButton.BackgroundColor3 = Color3.fromRGB(40, 140, 250)
throwButton.BackgroundTransparency = 0.1
throwButton.TextColor3 = Color3.new(1, 1, 1)
throwButton.TextSize = 13
throwButton.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
throwButton.Visible = false
throwButton.Parent = screenGui
Instance.new("UICorner", throwButton).CornerRadius = UDim.new(0, 14)
addSoftGradient(throwButton, true)
addButtonFeedback(throwButton)
makeDraggable(throwButton)

local dropLayoutMode = 1
dropLayoutToggleBtn.MouseButton1Click:Connect(function()
    dropLayoutMode = dropLayoutMode % 2 + 1
    if dropLayoutMode == 1 then
        dropLayoutToggleBtn.Text = "Layout Style: Center Floating"
        dropButton.Position = UDim2.new(0.35, -75, 0.78, 0)
        throwButton.Position = UDim2.new(0.65, -75, 0.78, 0)
    else
        dropLayoutToggleBtn.Text = "Layout Style: Docked Above Chat"
        dropButton.Position = UDim2.new(0.5, -145, 1, -135)
        throwButton.Position = UDim2.new(0.5, 5, 1, -135)
    end
end)

local function askAI(promptContext)
    local requestFunc = getRequestFunction()
    if not requestFunc then
        return "Executor error!"
    end

    updateSystemPromptInHistory()

    if currentAIModel == "OpenRouter" and OPENROUTER_API_KEY ~= "" then
        addMemory("user", promptContext)

        local success, response = pcall(function()
            return requestFunc({
                Url = "https://openrouter.ai/api/v1/chat/completions",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. OPENROUTER_API_KEY,
                    ["HTTP-Referer"] = "https://roblox.com",
                    ["X-Title"] = "Verity AI"
                },
                Body = HttpService:JSONEncode({
                    model = "deepseek/deepseek-chat",
                    messages = conversationHistory,
                    max_tokens = 150
                })
            })
        end)

        if success and response and response.Body then
            local ok, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
            if ok and data and data.choices and data.choices[1] and data.choices[1].message then
                local content = data.choices[1].message.content
                if content and content ~= "" then
                    addMemory("assistant", content)
                    return content
                end
            end
        end
        return "Failed to connect to OpenRouter AI!"

    elseif currentAIModel == "Gemini" and GEMINI_API_KEY ~= "" then
        addMemory("user", promptContext)

        local geminiContents = {}
        for _, msg in ipairs(conversationHistory) do
            if msg.role ~= "system" then
                table.insert(geminiContents, {
                    role = (msg.role == "assistant") and "model" or "user",
                    parts = {{ text = msg.content }}
                })
            end
        end

        local success, response = pcall(function()
            return requestFunc({
                Url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. GEMINI_API_KEY,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = HttpService:JSONEncode({
                    system_instruction = {
                        parts = { { text = getSystemPrompt() } }
                    },
                    contents = geminiContents
                })
            })
        end)

        if success and response and response.Body then
            local ok, data = pcall(function() return HttpService:JSONDecode(response.Body) end)if ok and data and data.candidates and data.candidates[1] and data.candidates[1].content then
                local content = data.candidates[1].content.parts[1].text
                if content and content ~= "" then
                    addMemory("assistant", content)
                    return content
                end
            end
        end
        return "Failed to connect to Gemini AI!"
    else
        return "API Key for " .. currentAIModel .. " mode is not configured! Open ⚙️ Config."
    end
end

local function teleportVerityToPlayer()
    if not verityPart then return end
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    isFlying = false
    isFollowing = false
    isHeld = false
    dropButton.Visible = false
    throwButton.Visible = false

    verityPart.Anchored = false
    verityPart.AssemblyLinearVelocity = Vector3.zero
    verityPart.AssemblyAngularVelocity = Vector3.zero
    verityPart.CFrame = root.CFrame * CFrame.new(0, 3, -4)
end

local function verityDie()
    if isRespawning then return end
    isRespawning = true
    isHeld = false
    isFlying = false
    isFollowing = false
    dropButton.Visible = false
    throwButton.Visible = false
    if holdAnimTrack then
        pcall(function() holdAnimTrack:Stop() end)
        holdAnimTrack = nil
    end
    teleportVerityToPlayer()

    task.spawn(function()
        if currentLanguage == "id" then
            playVeritySpeech("Wah, hampir saja jatuh!", FALL_FACE)
        else
            playVeritySpeech("Whoops, almost fell!", FALL_FACE)
        end
        isRespawning = false
    end)
end

RunService.RenderStepped:Connect(function(dt)
    if not verityPart or not verityPart.Parent then return end

    if verityPart.Position.Y < (workspace.FallenPartsDestroyHeight + 20) or verityPart.Position.Y < -150 then
        verityDie()
        return
    end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if isHeld then
        local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
        local head = char:FindFirstChild("Head")
        if hand and head then
            local grip = hand:FindFirstChild("RightGripAttachment")
            local holdPos = grip and grip.WorldPosition or (hand.Position + Vector3.new(0, -1, 0))
            
            verityPart.AssemblyLinearVelocity = Vector3.zero
            verityPart.AssemblyAngularVelocity = Vector3.zero
            verityPart.CFrame = CFrame.lookAt(holdPos, head.Position)
        end
    else
        if isFollowing and root then
            local direction = Vector3.new(root.Position.X - verityPart.Position.X, 0, root.Position.Z - verityPart.Position.Z)
            local distance = direction.Magnitude
            local playerSpeed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
            local targetSpeed = math.clamp(math.max(playerSpeed * 0.9, 8), 6, 25)

            if distance > 5.5 then
                local moveDir = direction.Unit
                local currentVel = verityPart.AssemblyLinearVelocity
                local desired = moveDir * targetSpeed
                verityPart.AssemblyLinearVelocity = Vector3.new(
                    currentVel.X + (desired.X - currentVel.X) * 0.12,
                    currentVel.Y + ((root.Position.Y + 3 - verityPart.Position.Y) * 3 - currentVel.Y) * 0.1,
                    currentVel.Z + (desired.Z - currentVel.Z) * 0.12
                )
                local spin = math.clamp(targetSpeed * 0.3, 2, 12)
                verityPart.AssemblyAngularVelocity = Vector3.new(-moveDir.Z * spin, 0, moveDir.X * spin)
            elseif distance > 3 then
                verityPart.AssemblyLinearVelocity = verityPart.AssemblyLinearVelocity * 0.75
            else
                verityPart.AssemblyLinearVelocity = Vector3.new(0, verityPart.AssemblyLinearVelocity.Y * 0.8, 0)
                verityPart.AssemblyAngularVelocity = Vector3.zero
                verityPart.CFrame = CFrame.lookAt(verityPart.Position, Vector3.new(root.Position.X, root.Position.Y, root.Position.Z))
            end
        else
            if isFlying then
                local vel = verityPart.AssemblyLinearVelocity
                if vel.Magnitude > 3 then
                    verityPart.AssemblyLinearVelocity = vel * 0.95
                else
                    isFlying = false
                end
            end
            if not isFlying and not isFollowing and root then
                verityPart.CFrame = CFrame.lookAt(verityPart.Position, Vector3.new(root.Position.X, root.Position.Y, root.Position.Z))
            end
        end
    end

    if verityFace and verityFace.Texture == TALKING_FACE then
        local s = 1 + math.sin(tick() * 14) * 0.12
        sizeSpring.target = Vector3.new(2.0 / s, 2.0 * s, 2.0 / s)
    elseif verityFace and verityFace.Texture == FALL_FACE then
        local s = 1 + math.sin(tick() * 20) * 0.15
        sizeSpring.target = Vector3.new(2.0 / s, 2.0 * s, 2.0 / s)
    else
        sizeSpring.target = Vector3.new(2.0, 2.0, 2.0)
    end

    local force = (sizeSpring.target - sizeSpring.current) * sizeSpring.stiffness
    sizeSpring.velocity = sizeSpring.velocity + (force - sizeSpring.velocity * sizeSpring.damping) * dt
    sizeSpring.current = sizeSpring.current + sizeSpring.velocity * dt

    if verityMesh then
        verityMesh.Scale = Vector3.new(
            math.max(sizeSpring.current.X, 0.6) / 2.0,
            math.max(sizeSpring.current.Y, 1.0) / 2.0,
            math.max(sizeSpring.current.Z, 0.6) / 2.0
        )
    end
end)

sendButton.MouseButton1Click:Connect(function()
    if chatInput.Text == "" or isVerityBusy then return end
    local msg = chatInput.Text
    chatInput.Text = ""
    local lower = msg:lower()

    if lower:find("teleport to me") or lower:find("tp to me") or lower == "tp" then
        teleportVerityToPlayer()
        isFollowing = false
        isFlying = false
        task.spawn(function()
            if currentLanguage == "id" then
                playVeritySpeech("Wussh! Aku teleport!", TALKING_FACE)
            else
                playVeritySpeech("Whoosh! Teleporting!", TALKING_FACE)
            end
        end)
        return
    end

    if lower:find("follow") then
        isFollowing = true
        isFlying = false
        isHeld = false
        dropButton.Visible = false
        throwButton.Visible = false
        task.spawn(function()
            if currentLanguage == "id" then
                playVeritySpeech("Siap, aku ikut!", TALKING_FACE)
            else
                playVeritySpeech("Alright, following you!", TALKING_FACE)
            end
        end)
        return
    end

    if lower:find("stop") then
        isFollowing = false
        task.spawn(function()
            if currentLanguage == "id" then
                playVeritySpeech("Oke, berhenti!", TALKING_FACE)
            else
                playVeritySpeech("Okay, stopped!", TALKING_FACE)
            end
        end)
        return
    end

    isVerityBusy = true

    if verityFace then verityFace.Texture = NORMAL_FACE end
    if verityGuiText then verityGuiText.Text = "..." end
    if bubbleFrame then bubbleFrame.BackgroundTransparency = 0.25 end
    if bubbleStroke then bubbleStroke.Transparency = 0.2 end

    task.spawn(function()
        local reply = askAI(msg)
        playVeritySpeech(reply, TALKING_FACE)
        isVerityBusy = false
    end)
end)

dropButton.MouseButton1Click:Connect(function()
    isHeld = false
    isFlying = false
    isFollowing = false
    dropButton.Visible = false
    throwButton.Visible = false
    if holdAnimTrack then pcall(function() holdAnimTrack:Stop() end) holdAnimTrack = nil end
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local root = char.HumanoidRootPart
        verityPart.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 4)
    end
end)

throwButton.MouseButton1Click:Connect(function()
    isHeld = false
    isFlying = true
    isFollowing = false
    dropButton.Visible = false
    throwButton.Visible = false
    if holdAnimTrack then pcall(function() holdAnimTrack:Stop() end) holdAnimTrack = nil end

    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local root = char.HumanoidRootPart
        local dir = workspace.CurrentCamera.CFrame.LookVector

        verityPart.CFrame = CFrame.new(root.Position + dir * 3 + Vector3.new(0, 1.5, 0))
        verityPart.AssemblyLinearVelocity = dir * 80 + Vector3.new(0, 20, 0)

        task.spawn(function()
            playVeritySpeech("Whoosh!", FALL_FACE)
        end)
    end
end)

function spawnVerity(pos, isRespawnCall)
    if verityPart and verityPart.Parent then verityPart:Destroy() end

    verityPart = Instance.new("Part")
    verityPart.Name = "VerityHead"
    verityPart.Shape = Enum.PartType.Ball
    verityPart.Size = Vector3.new(2.0, 2.0, 2.0)
    verityPart.Color = COLOR_VERITY
    verityPart.Position = pos
    verityPart.Material = Enum.Material.SmoothPlastic
    verityPart.CanCollide = true
    verityPart.Parent = workspace

    verityMesh = Instance.new("SpecialMesh", verityPart)
    verityMesh.MeshType = Enum.MeshType.Sphere

    verityFace = Instance.new("Decal", verityPart)
    verityFace.Texture = FALL_FACE

    verityGui = Instance.new("BillboardGui")
    verityGui.Name = "VeritySpeechBubble"
    verityGui.Adornee = verityPart
    verityGui.Parent = verityPart
    verityGui.Size = UDim2.new(0, 280, 0, 105)
    verityGui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
    verityGui.AlwaysOnTop = true
    verityGui.LightInfluence = 0
    verityGui.MaxDistance = 80
    verityGui.Enabled = false

    bubbleFrame = Instance.new("Frame")
    bubbleFrame.Name = "Bubble"
    bubbleFrame.Parent = verityGui
    bubbleFrame.Size = UDim2.new(1, 0, 1, -15)
    bubbleFrame.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
    bubbleFrame.BackgroundTransparency = 0.08
    bubbleFrame.BorderSizePixel = 0
    Instance.new("UICorner", bubbleFrame).CornerRadius = UDim.new(0, 16)

    bubbleStroke = Instance.new("UIStroke")
    bubbleStroke.Parent = bubbleFrame
    bubbleStroke.Color = COLOR_VERITY
    bubbleStroke.Thickness = 2.5
    bubbleStroke.Transparency = 0.15
    addSoftGradient(bubbleFrame, true)

    local bubblePadding = Instance.new("UIPadding")
    bubblePadding.Parent = bubbleFrame
    bubblePadding.PaddingLeft = UDim.new(0, 14)
    bubblePadding.PaddingRight = UDim.new(0, 14)
    bubblePadding.PaddingTop = UDim.new(0, 10)
    bubblePadding.PaddingBottom = UDim.new(0, 10)

    verityGuiText = Instance.new("TextLabel")
    verityGuiText.Name = "Message"
    verityGuiText.Parent = bubbleFrame
    verityGuiText.Size = UDim2.new(1, 0, 1, 0)
    verityGuiText.BackgroundTransparency = 1
    verityGuiText.Text = ""
    verityGuiText.TextColor3 = Color3.fromRGB(255, 245, 145)
    verityGuiText.TextStrokeTransparency = 0.8
    verityGuiText.Font = Enum.Font.GothamMedium
    verityGuiText.TextSize = 17
    verityGuiText.TextWrapped = true
    verityGuiText.TextScaled = false
    verityGuiText.TextXAlignment = Enum.TextXAlignment.Left
    verityGuiText.TextYAlignment = Enum.TextYAlignment.Center
    verityBubbleText = verityGuiText

    local tail = Instance.new("Frame")
    tail.Name = "Tail"
    tail.Parent = verityGui
    tail.Size = UDim2.new(0, 20, 0, 20)
    tail.Position = UDim2.new(0.5, -10, 1, -26)
    tail.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
    tail.BackgroundTransparency = 0.08
    tail.BorderSizePixel = 0
    tail.Rotation = 45

    local tailStroke = Instance.new("UIStroke")
    tailStroke.Parent = tail
    tailStroke.Color = COLOR_VERITY
    tailStroke.Thickness = 2.5
    tailStroke.Transparency = 0.15

    task.defer(removeCollisionWithCharacters)

    verityPart.Touched:Connect(function(hit)
        local name = hit.Name:lower()
        if name:find("kill") or name:find("lava") or name:find("death") or name:find("acid") then
            verityDie()
        end
    end)

    local cd = Instance.new("ClickDetector", verityPart)
    cd.MaxActivationDistance = 50
    cd.MouseClick:Connect(function()
        if not isHeld then
            isHeld = true
            isFlying = false
            isFollowing = false
            dropButton.Visible = true
            throwButton.Visible = true

            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then
                local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
                local anim = Instance.new("Animation")
                anim.AnimationId = hum.RigType == Enum.HumanoidRigType.R15 and "rbxassetid://507768375" or "rbxassetid://182393478"
                holdAnimTrack = animator:LoadAnimation(anim)
                holdAnimTrack.Priority = Enum.AnimationPriority.Action
                holdAnimTrack:Play()
            end
        end
    end)

    if isRespawnCall then hasIntroduced = true end
end

local function playVerityFallAnimation(groundY)
    if not verityPart or not verityPart.Parent then return end

    verityPart.Anchored = true
    local x, z = verityPart.Position.X, verityPart.Position.Z
    local baseY = groundY + 1.75

    local DESCENT_SLOWDOWN = 0.45
    local frames = {
        {beats(0),                    28.0, 0},
        {beats(1),                    28.0, 0},
        {beats(4) + DESCENT_SLOWDOWN,  0.0, 0},
        {beats(5) + DESCENT_SLOWDOWN,  2.60, -4},
        {beats(6) + DESCENT_SLOWDOWN,  0.0, 3},
        {beats(6.5) + DESCENT_SLOWDOWN, 0.75, -2},
        {beats(7) + DESCENT_SLOWDOWN,  0.0, 0},
    }

    verityPart.Position = Vector3.new(x, baseY + frames[1][2], z)
    for i = 1, #frames - 1 do
        if not verityPart or not verityPart.Parent then return end
        local a, b = frames[i], frames[i+1]
        local duration = b[1] - a[1]
        local style = (b[2] > a[2]) and Enum.EasingDirection.Out or Enum.EasingDirection.In
        local tw = TweenService:Create(verityPart, TweenInfo.new(duration, Enum.EasingStyle.Quad, style), {
            Position = Vector3.new(x, baseY + b[2], z),
            Orientation = Vector3.new(b[3], 0, 0)
        })
        tw:Play()
        tw.Completed:Wait()
    end

    if verityPart and verityPart.Parent then
        verityPart.Position = Vector3.new(x, baseY, z)
        verityPart.Orientation = Vector3.zero
        verityPart.Anchored = false
        verityPart.AssemblyLinearVelocity = Vector3.zero
        verityPart.AssemblyAngularVelocity = Vector3.zero
    end
end

local function spawnMysteryBox()
    local currentCharacter = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local currentRoot = currentCharacter:WaitForChild("HumanoidRootPart")

    local rayOrigin = currentRoot.Position + Vector3.new(0, 5, 0)
    local rayDirection = Vector3.new(0, -30, 0)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {currentCharacter}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    local groundY = raycastResult and raycastResult.Position.Y or (currentRoot.Position.Y - 3)

    local boxModel = Instance.new("Model")
    boxModel.Name = "VerityMysteryBox"
    boxModel.Parent = workspace

    local box = Instance.new("Part")
    box.Name = "Box"
    box.Size = Vector3.new(3.5, 3.5, 3.5)
    box.CFrame = CFrame.new(currentRoot.Position.X + currentRoot.CFrame.LookVector.X * 8, groundY + 30, currentRoot.Position.Z + currentRoot.CFrame.LookVector.Z * 8)
    box.Anchored = true
    box.CanCollide = true
    box.Color = COLOR_VERITY
    box.Material = Enum.Material.SmoothPlastic
    box.Parent = boxModel
    boxModel.PrimaryPart = box

    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = "rbxassetid://9756362"
    mesh.Scale = Vector3.new(0.95, 0.95, 0.95)
    mesh.Parent = box

    local boxGui = Instance.new("BillboardGui")
    boxGui.Size = UDim2.new(0, 200, 0, 50)
    boxGui.StudsOffset = Vector3.new(0, 2.7, 0)
    boxGui.AlwaysOnTop = true
    boxGui.Parent = box
    local boxText = Instance.new("TextLabel")
    boxText.Size = UDim2.new(1,0,1,0)
    boxText.BackgroundTransparency = 1
    boxText.Text = "Touch the Box!"
    boxText.TextColor3 = COLOR_VERITY
    boxText.TextScaled = true
    boxText.FontFace = Font.new("rbxasset://fonts.families/GothamSSm.json", Enum.FontWeight.Bold)
    boxText.TextStrokeTransparency = 0.3
    boxText.Parent = boxGui

    local glow = Instance.new("PointLight")
    glow.Color = COLOR_VERITY
    glow.Brightness = 1.8
    glow.Range = 10
    glow.Parent = box

    local boxSound = Instance.new("Sound")
    boxSound.Name = "BoxHum"
    boxSound.SoundId = "rbxassetid://137768546968340"
    boxSound.Volume = 1.2
    boxSound.Looped = true
    boxSound.Parent = box
    boxSound:Play()

    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Adornee = box
    selectionBox.Color3 = COLOR_VERITY
    selectionBox.LineThickness = 0.035
    selectionBox.Parent = box

    local triggered = false
    local landed = false
    local startX, startZ = box.Position.X, box.Position.Z
    local groundBoxY = groundY + 1.75

    task.spawn(function()
        local drop = TweenService:Create(box, TweenInfo.new(beats(4), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = Vector3.new(startX, groundBoxY, startZ)
        })
        drop:Play()
        drop.Completed:Wait()
        if not box.Parent or triggered then return end

        local squash = TweenService:Create(mesh, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Scale = Vector3.new(1.08, 0.78, 1.08)
        })
        squash:Play(); squash.Completed:Wait()

        local bounce1 = TweenService:Create(box, TweenInfo.new(beats(1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = Vector3.new(startX, groundBoxY + 2.4, startZ), Orientation = Vector3.new(0,0,5)
        })
        local stretch1 = TweenService:Create(mesh, TweenInfo.new(beats(1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Scale = Vector3.new(0.88, 1.10, 0.88)
        })
        bounce1:Play(); stretch1:Play(); bounce1.Completed:Wait()

        local land1 = TweenService:Create(box, TweenInfo.new(beats(1), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = Vector3.new(startX, groundBoxY, startZ), Orientation = Vector3.new(0,0,-3)
        })
        local squash1 = TweenService:Create(mesh, TweenInfo.new(beats(1), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Scale = Vector3.new(1.06, 0.82, 1.06)
        })
        land1:Play(); squash1:Play(); land1.Completed:Wait()

        local bounce2 = TweenService:Create(box, TweenInfo.new(beats(0.5), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
            Position = Vector3.new(startX, groundBoxY + 0.75, startZ), Orientation = Vector3.new(0,0,1.5)
        })
        local stretch2 = TweenService:Create(mesh, TweenInfo.new(beats(0.5), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
            Scale = Vector3.new(0.94, 1.03, 0.94)
        })
        bounce2:Play(); stretch2:Play(); bounce2.Completed:Wait()

        local land2 = TweenService:Create(box, TweenInfo.new(beats(0.5), Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
            Position = Vector3.new(startX, groundBoxY, startZ), Orientation = Vector3.zero
        })
        local normal = TweenService:Create(mesh, TweenInfo.new(beats(0.5), Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
            Scale = Vector3.new(0.95, 0.95, 0.95)
        })
 })
        land2:Play(); normal:Play(); land2.Completed:Wait()
        landed = true

        local idleStart = os.clock()
        while box.Parent and not triggered do
            local t = os.clock() - idleStart
            box.Position = Vector3.new(startX, groundBoxY + math.sin(t * 2.4) * 0.10, startZ)
            task.wait(0.03)
        end
    end)

    box.Touched:Connect(function(hit)
        if triggered or not landed then return end
        local char = hit.Parent
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and char == LocalPlayer.Character then
            triggered = true
            boxText.Text = "Verity!"
            if boxSound then boxSound:Stop(); boxSound:Destroy() end

            local veritySpawnY = groundY + 29.75
            local hitUp = TweenService:Create(box, TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Position = Vector3.new(startX, veritySpawnY, startZ)
            })
            hitUp:Play(); hitUp.Completed:Wait()

            task.wait(0.12)

            local fade = TweenService:Create(box, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
            fade:Play()
            TweenService:Create(glow, TweenInfo.new(0.25), {Brightness = 0}):Play()
            fade.Completed:Wait()

            boxModel:Destroy()
            spawnVerity(Vector3.new(startX, groundY + 29.75, startZ), false)
            task.spawn(function()
                playVerityFallAnimation(groundY)
                hasIntroduced = true
                isVerityBusy = true
                playVeritySpeech("Hello! I'm Verity, your personal helper friend. Ask me anything; I know everything.", TALKING_FACE, "rbxassetid://71231208892767")
                isVerityBusy = false
            end)
        end
    end)
end

spawnMysteryBox()

print("[Verity] Fixed & Beautified UI by GHOST!")

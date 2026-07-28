--[[
	HIKA.LUA - CLIENT ADMIN PANEL

	Place this as a LocalScript inside:
	StarterPlayer > StarterPlayerScripts

	FEATURES:
	- Client-sided Void Movement
	- Automatically loads with the player
	- Continues after respawning
	- Random and directional movement
	- Fully adjustable sliders
	- Spin / riot movement
	- Draggable window
	- Custom UI toggle keybind
	- Mouse becomes free while the panel is visible
	- Previous mouse state is restored when the panel closes
	- Save and load configurations
	- Built-in configurations
	- Auto-load configuration
	- Auto-execute Void Movement
	- Silent loading
	- Top-right notifications

	IMPORTANT CLIENT-SIDE LIMITATION:
	A normal LocalScript cannot permanently write arbitrary data between
	separate game sessions. Configurations saved through the UI remain
	available until you leave that server.

	For permanent startup settings, edit STARTUP and BUILT_IN_CONFIGS below.
]]

--------------------------------------------------
-- SERVICES
--------------------------------------------------

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------
-- REMOVE AN OLDER COPY
--------------------------------------------------

local oldGui = playerGui:FindFirstChild("HikaLuaPanel")

if oldGui then
	oldGui:Destroy()
end

--------------------------------------------------
-- STARTUP SETTINGS
--------------------------------------------------

-- Edit these values to permanently change what happens when the
-- LocalScript starts each time you join.
local STARTUP = {
	-- Automatically begin Void Movement.
	AutoExecute = false,

	-- Start with the main panel hidden.
	SilentLoad = false,

	-- Display a top-right loaded notification.
	ShowLoadNotification = true,

	-- Built-in configuration to load automatically.
	-- Use "" to disable automatic config loading.
	AutoLoadConfig = "Default",

	-- Default panel toggle key.
	ToggleKey = Enum.KeyCode.PageUp,
}

--------------------------------------------------
-- DEFAULT SETTINGS
--------------------------------------------------

local Settings = {
	VoidMovement = false,
	TeleportMode = "RANDOM",

	-- Defaults recreated from the supplied reference screenshots.
	Distance = 8580000000,
	TeleportInterval = 0.000001,
	JitterStrength = 98,

	PositiveX = 7100000000,
	NegativeX = 3760000000,

	PositiveY = 8440000000,
	NegativeY = 5590000000,

	PositiveZ = 7870000000,
	NegativeZ = 3280000000,

	MotionEnabled = true,
	SpinSpeed = 122300,

	XZJitter = 79200,
	YJitter = 41700,
	SpreadDistance = 83640,
}

--------------------------------------------------
-- BUILT-IN CONFIGURATIONS
--------------------------------------------------

-- Add or edit configurations here to make them permanently available
-- every time the LocalScript starts.
local BUILT_IN_CONFIGS = {
	Default = {
		TeleportMode = "RANDOM",

		Distance = 8580000000,
		TeleportInterval = 0.000001,
		JitterStrength = 98,

		PositiveX = 7100000000,
		NegativeX = 3760000000,

		PositiveY = 8440000000,
		NegativeY = 5590000000,

		PositiveZ = 7870000000,
		NegativeZ = 3280000000,

		MotionEnabled = true,
		SpinSpeed = 122300,

		XZJitter = 79200,
		YJitter = 41700,
		SpreadDistance = 83640,
	},

	Maximum = {
		TeleportMode = "RANDOM",

		Distance = 1000000000,
		TeleportInterval = 0.03,
		JitterStrength = 100,

		PositiveX = 1000000000,
		NegativeX = 1000000000,

		PositiveY = 1000000000,
		NegativeY = 1000000000,

		PositiveZ = 1000000000,
		NegativeZ = 1000000000,

		MotionEnabled = true,
		SpinSpeed = 20000,

		XZJitter = 10000,
		YJitter = 10000,
		SpreadDistance = 100000,
	},

	DirectionalVoid = {
		TeleportMode = "DIRECTIONAL",

		Distance = 100000000,
		TeleportInterval = 0.05,
		JitterStrength = 10,

		PositiveX = 1000000000,
		NegativeX = 50000,

		PositiveY = 250000,
		NegativeY = 50000,

		PositiveZ = 50000,
		NegativeZ = 50000,

		MotionEnabled = true,
		SpinSpeed = 2500,

		XZJitter = 250,
		YJitter = 100,
		SpreadDistance = 500,
	},
}

-- Configurations saved using the interface are stored here.
-- They last until you leave the current server.
local SessionConfigs = {}

--------------------------------------------------
-- CHARACTER VARIABLES
--------------------------------------------------

local character
local humanoid
local rootPart

local movementConnection
local movementAccumulator = 0
local spinConnection

local originalCFrame
local currentSpin = Vector3.zero

--------------------------------------------------
-- INTERFACE STATE
--------------------------------------------------

local panelVisible = not STARTUP.SilentLoad
local currentToggleKey = STARTUP.ToggleKey
local waitingForToggleKey = false

-- Separate keybind for Void Movement. Unknown means unassigned.
local currentVoidKey = Enum.KeyCode.Unknown
local waitingForVoidKey = false

local savedMouseBehavior
local savedMouseIconEnabled

local mouseUnlockConnection

local controls = {}

--------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------

local function copyTable(source)
	local result = {}

	for key, value in pairs(source) do
		if typeof(value) == "table" then
			result[key] = copyTable(value)
		else
			result[key] = value
		end
	end

	return result
end

local function trim(text)
	return string.gsub(
		string.gsub(text, "^%s+", ""),
		"%s+$",
		""
	)
end

local function randomFloat(minimum, maximum)
	return minimum + math.random() * (maximum - minimum)
end

local function getRandomDirection()
	local vector

	repeat
		vector = Vector3.new(
			randomFloat(-1, 1),
			randomFloat(-1, 1),
			randomFloat(-1, 1)
		)
	until vector.Magnitude > 0.001

	return vector.Unit
end

local function formatNumber(value, decimalPlaces)
	decimalPlaces = decimalPlaces or 0

	if decimalPlaces > 0 then
		return string.format(
			"%." .. decimalPlaces .. "f",
			value
		)
	end

	local absoluteValue = math.abs(value)

	if absoluteValue >= 1000000000 then
		return string.format("%.2fb", value / 1000000000)
	elseif absoluteValue >= 1000000 then
		return string.format("%.2fm", value / 1000000)
	elseif absoluteValue >= 1000 then
		return string.format("%.1fk", value / 1000)
	end

	return tostring(math.floor(value + 0.5))
end

local function captureCurrentConfig()
	return {
		TeleportMode = Settings.TeleportMode,

		Distance = Settings.Distance,
		TeleportInterval = Settings.TeleportInterval,
		JitterStrength = Settings.JitterStrength,

		PositiveX = Settings.PositiveX,
		NegativeX = Settings.NegativeX,

		PositiveY = Settings.PositiveY,
		NegativeY = Settings.NegativeY,

		PositiveZ = Settings.PositiveZ,
		NegativeZ = Settings.NegativeZ,

		MotionEnabled = Settings.MotionEnabled,
		SpinSpeed = Settings.SpinSpeed,

		XZJitter = Settings.XZJitter,
		YJitter = Settings.YJitter,
		SpreadDistance = Settings.SpreadDistance,
	}
end

local function applyConfig(config)
	if typeof(config) ~= "table" then
		return false
	end

	for key, value in pairs(config) do
		if Settings[key] ~= nil then
			Settings[key] = value
		end
	end

	return true
end

local function getConfig(name)
	return SessionConfigs[name] or BUILT_IN_CONFIGS[name]
end

--------------------------------------------------
-- CHARACTER HANDLING
--------------------------------------------------

local function updateCharacter(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")

	if not originalCFrame then
		originalCFrame = rootPart.CFrame
	end

	if Settings.VoidMovement then
		task.wait(0.35)

		if rootPart then
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

if player.Character then
	task.spawn(updateCharacter, player.Character)
end

player.CharacterAdded:Connect(function(newCharacter)
	updateCharacter(newCharacter)
end)

--------------------------------------------------
-- VOID MOVEMENT
--------------------------------------------------

local function getWeightedDirection()
	local choices = {
		{
			Direction = Vector3.new(1, 0, 0),
			Weight = Settings.PositiveX,
		},
		{
			Direction = Vector3.new(-1, 0, 0),
			Weight = Settings.NegativeX,
		},
		{
			Direction = Vector3.new(0, 1, 0),
			Weight = Settings.PositiveY,
		},
		{
			Direction = Vector3.new(0, -1, 0),
			Weight = Settings.NegativeY,
		},
		{
			Direction = Vector3.new(0, 0, 1),
			Weight = Settings.PositiveZ,
		},
		{
			Direction = Vector3.new(0, 0, -1),
			Weight = Settings.NegativeZ,
		},
	}

	local totalWeight = 0

	for _, choice in ipairs(choices) do
		totalWeight += math.max(choice.Weight, 0)
	end

	if totalWeight <= 0 then
		return getRandomDirection()
	end

	local roll = randomFloat(0, totalWeight)
	local accumulated = 0

	for _, choice in ipairs(choices) do
		accumulated += math.max(choice.Weight, 0)

		if roll <= accumulated then
			return choice.Direction
		end
	end

	return choices[1].Direction
end

local function getRandomAxisDirection()
	local vector = Vector3.new(
		randomFloat(
			-Settings.NegativeX,
			Settings.PositiveX
		),

		randomFloat(
			-Settings.NegativeY,
			Settings.PositiveY
		),

		randomFloat(
			-Settings.NegativeZ,
			Settings.PositiveZ
		)
	)

	if vector.Magnitude <= 0.001 then
		return getRandomDirection()
	end

	return vector.Unit
end

local function getTeleportDirection()
	local chosenDirection

	if Settings.TeleportMode == "DIRECTIONAL" then
		chosenDirection = getWeightedDirection()
	else
		chosenDirection = getRandomAxisDirection()
	end

	local jitterAmount = Settings.JitterStrength / 100

	local mixedDirection = chosenDirection:Lerp(
		getRandomDirection(),
		jitterAmount
	)

	if mixedDirection.Magnitude <= 0.001 then
		return chosenDirection
	end

	return mixedDirection.Unit
end

local function teleportIntoVoid()
	if not character or not rootPart or not humanoid then
		return
	end

	if humanoid.Health <= 0 then
		return
	end

	if not originalCFrame then
		originalCFrame = rootPart.CFrame
	end

	local direction = getTeleportDirection()

	local distanceOffset =
		direction * Settings.Distance

	local spreadOffset =
		getRandomDirection()
		* randomFloat(0, Settings.SpreadDistance)

	local motionOffset = Vector3.zero

	if Settings.MotionEnabled then
		motionOffset = Vector3.new(
			randomFloat(
				-Settings.XZJitter,
				Settings.XZJitter
			),

			randomFloat(
				-Settings.YJitter,
				Settings.YJitter
			),

			randomFloat(
				-Settings.XZJitter,
				Settings.XZJitter
			)
		)
	end

	local targetPosition =
		originalCFrame.Position
		+ distanceOffset
		+ spreadOffset
		+ motionOffset

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	humanoid:ChangeState(
		Enum.HumanoidStateType.Physics
	)

	local rotation = CFrame.Angles(
		math.rad(currentSpin.X),
		math.rad(currentSpin.Y),
		math.rad(currentSpin.Z)
	)

	character:PivotTo(
		CFrame.new(targetPosition) * rotation
	)
end

local function stopMovementLoop()
	Settings.VoidMovement = false
	movementAccumulator = 0

	if movementConnection then
		movementConnection:Disconnect()
		movementConnection = nil
	end

	if humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function startMovementLoop()
	if movementConnection then
		movementConnection:Disconnect()
		movementConnection = nil
	end

	Settings.VoidMovement = true
	movementAccumulator = 0

	if rootPart then
		originalCFrame = rootPart.CFrame
	end

	-- Heartbeat is the fastest reliable Roblox scheduler. An interval of
	-- 0.000001 therefore means "every available simulation frame".
	movementConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not Settings.VoidMovement then
			return
		end

		if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
			return
		end

		local interval = math.max(Settings.TeleportInterval, 0.000001)

		if interval <= deltaTime then
			teleportIntoVoid()
			movementAccumulator = 0
			return
		end

		movementAccumulator += deltaTime

		if movementAccumulator >= interval then
			movementAccumulator %= interval
			teleportIntoVoid()
		end
	end)
end

local function returnCharacter()
	stopMovementLoop()

	if character and rootPart and originalCFrame then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		character:PivotTo(originalCFrame)

		if humanoid then
			humanoid:ChangeState(
				Enum.HumanoidStateType.GettingUp
			)
		end
	end
end

spinConnection = RunService.RenderStepped:Connect(
	function(deltaTime)
		if not Settings.VoidMovement then
			return
		end

		if not Settings.MotionEnabled then
			return
		end

		local amount =
			Settings.SpinSpeed * deltaTime

		currentSpin += Vector3.new(
			amount * 0.35,
			amount,
			amount * 0.65
		)

		currentSpin = Vector3.new(
			currentSpin.X % 360,
			currentSpin.Y % 360,
			currentSpin.Z % 360
		)
	end
)

--------------------------------------------------
-- COLOURS
--------------------------------------------------

local colours = {
	Background = Color3.fromRGB(17, 8, 15),
	Topbar = Color3.fromRGB(31, 10, 24),
	Sidebar = Color3.fromRGB(22, 9, 18),

	Card = Color3.fromRGB(35, 13, 28),
	CardSecondary = Color3.fromRGB(53, 18, 42),

	Border = Color3.fromRGB(224, 93, 165),
	Grid = Color3.fromRGB(94, 34, 72),

	Accent = Color3.fromRGB(255, 116, 190),
	AccentBright = Color3.fromRGB(255, 174, 219),
	AccentDark = Color3.fromRGB(165, 46, 112),

	Text = Color3.fromRGB(255, 234, 247),
	SecondaryText = Color3.fromRGB(232, 168, 207),
	DarkText = Color3.fromRGB(174, 86, 137),

	ToggleOff = Color3.fromRGB(76, 31, 61),
	White = Color3.fromRGB(255, 241, 249),

	Success = Color3.fromRGB(255, 139, 201),
	Danger = Color3.fromRGB(255, 103, 150),
}

--------------------------------------------------
-- UI HELPERS
--------------------------------------------------

local function addCorner(object, radius)
	local corner = Instance.new("UICorner")
	-- Industrial/robotic design: almost square, never heavily rounded.
	corner.CornerRadius = UDim.new(0, math.min(radius or 0, 2))
	corner.Parent = object

	return corner
end

local function addStroke(
	object,
	colour,
	transparency
)
	local stroke = Instance.new("UIStroke")
	stroke.Color = colour or colours.Border
	stroke.Transparency = transparency or 0
	stroke.Thickness = 1.35
	stroke.Parent = object

	return stroke
end

local function createLabel(
	parent,
	text,
	size,
	position
)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = colours.Text
	label.Font = Enum.Font.RobotoMono
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent

	return label
end

local function createButton(
	parent,
	text,
	size,
	position
)
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = colours.CardSecondary
	button.BorderSizePixel = 0
	button.Text = string.upper(text)
	button.TextColor3 = colours.Text
	button.Font = Enum.Font.RobotoMono
	button.TextSize = 10
	button.AutoButtonColor = false
	button.Parent = parent

	addCorner(button, 7)

	return button
end

local function createCard(
	parent,
	titleText,
	height
)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, height)
	card.BackgroundColor3 = colours.Card
	card.BorderSizePixel = 0
	card.Parent = parent

	addCorner(card, 9)
	addStroke(card, colours.Border, 0.35)

	local titleLabel = createLabel(
		card,
		string.upper(titleText),
		UDim2.new(1, -24, 0, 30),
		UDim2.fromOffset(12, 2)
	)

	titleLabel.TextColor3 = colours.DarkText
	titleLabel.TextSize = 10
	titleLabel.Font = Enum.Font.RobotoMono

	return card
end

--------------------------------------------------
-- CREATE SCREEN GUI
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "hika.lua"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = playerGui

--------------------------------------------------
-- FULL-SCREEN MODAL MOUSE UNLOCKER
--------------------------------------------------

-- Modal buttons release the mouse in first-person mode.
-- This remains behind the actual panel.
local mouseUnlocker = Instance.new("TextButton")
mouseUnlocker.Name = "MouseUnlocker"
mouseUnlocker.Size = UDim2.fromScale(1, 1)
mouseUnlocker.Position = UDim2.fromScale(0, 0)
mouseUnlocker.BackgroundTransparency = 1
mouseUnlocker.Text = ""
mouseUnlocker.Modal = true
mouseUnlocker.AutoButtonColor = false
mouseUnlocker.Visible = panelVisible
mouseUnlocker.ZIndex = 0
mouseUnlocker.Parent = screenGui

--------------------------------------------------
-- MAIN WINDOW
--------------------------------------------------

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(940, 590)
main.Position = UDim2.new(0.5, -470, 0.5, -295)
main.BackgroundColor3 = colours.Background
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Visible = panelVisible
main.ZIndex = 2
main.Parent = screenGui

addCorner(main, 2)
addStroke(main, colours.Border, 0.05)

local accentRail = Instance.new("Frame")
accentRail.Name = "AccentRail"
accentRail.Size = UDim2.new(1, 0, 0, 2)
accentRail.Position = UDim2.fromOffset(0, 48)
accentRail.BackgroundColor3 = colours.Accent
accentRail.BorderSizePixel = 0
accentRail.ZIndex = 20
accentRail.Parent = main

local leftRail = Instance.new("Frame")
leftRail.Name = "LeftRail"
leftRail.Size = UDim2.new(0, 2, 1, -48)
leftRail.Position = UDim2.fromOffset(156, 48)
leftRail.BackgroundColor3 = colours.AccentDark
leftRail.BorderSizePixel = 0
leftRail.ZIndex = 20
leftRail.Parent = main

--------------------------------------------------
-- TOP BAR
--------------------------------------------------

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 48)
topBar.BackgroundColor3 = colours.Topbar
topBar.BorderSizePixel = 0
topBar.ZIndex = 3
topBar.Parent = main

local buildLabel = Instance.new("TextLabel")
buildLabel.Size = UDim2.fromOffset(230, 20)
buildLabel.Position = UDim2.new(1, -330, 0, 14)
buildLabel.BackgroundTransparency = 1
buildLabel.Text = "CLIENT MODULE // VOID CONTROL"
buildLabel.TextColor3 = colours.DarkText
buildLabel.Font = Enum.Font.RobotoMono
buildLabel.TextSize = 10
buildLabel.TextXAlignment = Enum.TextXAlignment.Right
buildLabel.ZIndex = 4
buildLabel.Parent = topBar

local title = createLabel(
	topBar,
	"hika.lua",
	UDim2.new(0, 180, 1, 0),
	UDim2.fromOffset(18, 0)
)

title.TextSize = 17
title.Font = Enum.Font.RobotoMono
title.TextColor3 = colours.AccentBright
title.TextStrokeColor3 = colours.AccentDark
title.TextStrokeTransparency = 0.72
title.ZIndex = 4

local gameName = createLabel(
	topBar,
	"",
	UDim2.new(0, 180, 1, 0),
	UDim2.fromOffset(148, 0)
)

gameName.TextSize = 12
gameName.TextColor3 = colours.SecondaryText
gameName.ZIndex = 4

local minimiseButton = createButton(
	topBar,
	"—",
	UDim2.fromOffset(34, 30),
	UDim2.new(1, -78, 0, 8)
)

minimiseButton.TextSize = 17
minimiseButton.ZIndex = 5

local closeButton = createButton(
	topBar,
	"×",
	UDim2.fromOffset(34, 30),
	UDim2.new(1, -40, 0, 8)
)

closeButton.BackgroundColor3 =
	Color3.fromRGB(73, 20, 45)

closeButton.TextColor3 = colours.Danger
closeButton.TextSize = 18
closeButton.ZIndex = 5

--------------------------------------------------
-- BODY
--------------------------------------------------

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -48)
body.Position = UDim2.fromOffset(0, 48)
body.BackgroundTransparency = 1
body.ZIndex = 3
body.Parent = main

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 156, 1, 0)
sidebar.BackgroundColor3 = colours.Sidebar
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 3
sidebar.Parent = body

local sidebarTitle = createLabel(
	sidebar,
	"",
	UDim2.new(1, -24, 0, 30),
	UDim2.fromOffset(12, 12)
)

sidebarTitle.TextColor3 = colours.DarkText
sidebarTitle.TextSize = 10
sidebarTitle.Font = Enum.Font.RobotoMono
sidebarTitle.ZIndex = 4

local voidTab = createButton(
	sidebar,
	"   Void",
	UDim2.new(1, -16, 0, 38),
	UDim2.fromOffset(8, 16)
)

voidTab.BackgroundColor3 =
	colours.CardSecondary

voidTab.TextSize = 13
voidTab.TextXAlignment =
	Enum.TextXAlignment.Left

voidTab.ZIndex = 4

local settingsTab = createButton(
	sidebar,
	"   Settings",
	UDim2.new(1, -16, 0, 38),
	UDim2.fromOffset(8, 62)
)

settingsTab.BackgroundColor3 = colours.Card
settingsTab.TextColor3 = colours.SecondaryText
settingsTab.TextSize = 13
settingsTab.TextXAlignment =
	Enum.TextXAlignment.Left

settingsTab.ZIndex = 4

local statusLabel = createLabel(
	sidebar,
	"Status: Disabled",
	UDim2.new(1, -16, 0, 38),
	UDim2.new(0, 8, 1, -50)
)

statusLabel.BackgroundTransparency = 0
statusLabel.BackgroundColor3 = colours.Card
statusLabel.TextColor3 = colours.SecondaryText
statusLabel.TextXAlignment =
	Enum.TextXAlignment.Center

statusLabel.ZIndex = 4

addCorner(statusLabel, 8)

--------------------------------------------------
-- NOTIFICATIONS
--------------------------------------------------

local notificationHolder = Instance.new("Frame")
notificationHolder.Name = "Notifications"
notificationHolder.Size = UDim2.fromOffset(330, 400)
notificationHolder.Position =
	UDim2.new(1, -344, 0, 14)

notificationHolder.BackgroundTransparency = 1
notificationHolder.ZIndex = 100
notificationHolder.Parent = screenGui

local notificationLayout =
	Instance.new("UIListLayout")

notificationLayout.Padding = UDim.new(0, 8)
notificationLayout.HorizontalAlignment =
	Enum.HorizontalAlignment.Right

notificationLayout.SortOrder =
	Enum.SortOrder.LayoutOrder

notificationLayout.Parent = notificationHolder

local function showNotification(
	titleText,
	messageText,
	duration
)
	duration = duration or 4

	local notification = Instance.new("Frame")
	notification.Size = UDim2.fromOffset(320, 78)
	notification.BackgroundColor3 =
		Color3.fromRGB(15, 20, 30)

	notification.BackgroundTransparency = 1
	notification.BorderSizePixel = 0
	notification.ZIndex = 101
	notification.Parent = notificationHolder

	addCorner(notification, 9)

	local stroke = addStroke(
		notification,
		colours.Border,
		1
	)

	local notificationTitle = createLabel(
		notification,
		titleText,
		UDim2.new(1, -24, 0, 25),
		UDim2.fromOffset(12, 9)
	)

	notificationTitle.Font = Enum.Font.RobotoMono
	notificationTitle.TextSize = 13
	notificationTitle.TextTransparency = 1
	notificationTitle.ZIndex = 102

	local notificationMessage = createLabel(
		notification,
		messageText,
		UDim2.new(1, -24, 0, 31),
		UDim2.fromOffset(12, 35)
	)

	notificationMessage.TextColor3 =
		colours.SecondaryText

	notificationMessage.TextSize = 11
	notificationMessage.TextWrapped = true
	notificationMessage.TextYAlignment =
		Enum.TextYAlignment.Top

	notificationMessage.TextTransparency = 1
	notificationMessage.ZIndex = 102

	TweenService:Create(
		notification,
		TweenInfo.new(0.2),
		{
			BackgroundTransparency = 0,
		}
	):Play()

	TweenService:Create(
		stroke,
		TweenInfo.new(0.2),
		{
			Transparency = 0.25,
		}
	):Play()

	TweenService:Create(
		notificationTitle,
		TweenInfo.new(0.2),
		{
			TextTransparency = 0,
		}
	):Play()

	TweenService:Create(
		notificationMessage,
		TweenInfo.new(0.2),
		{
			TextTransparency = 0,
		}
	):Play()

	task.delay(duration, function()
		if not notification.Parent then
			return
		end

		TweenService:Create(
			notification,
			TweenInfo.new(0.2),
			{
				BackgroundTransparency = 1,
			}
		):Play()

		TweenService:Create(
			stroke,
			TweenInfo.new(0.2),
			{
				Transparency = 1,
			}
		):Play()

		TweenService:Create(
			notificationTitle,
			TweenInfo.new(0.2),
			{
				TextTransparency = 1,
			}
		):Play()

		TweenService:Create(
			notificationMessage,
			TweenInfo.new(0.2),
			{
				TextTransparency = 1,
			}
		):Play()

		task.wait(0.22)

		if notification.Parent then
			notification:Destroy()
		end
	end)
end

--------------------------------------------------
-- MOUSE LOCK / UNLOCK
--------------------------------------------------

local function unlockMouse()
	if mouseUnlockConnection then
		mouseUnlockConnection:Disconnect()
		mouseUnlockConnection = nil
	end

	savedMouseBehavior =
		UserInputService.MouseBehavior

	savedMouseIconEnabled =
		UserInputService.MouseIconEnabled

	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior =
		Enum.MouseBehavior.Default

	mouseUnlocker.Visible = true

	-- First-person controller scripts may repeatedly try to lock the mouse.
	-- Force it to stay unlocked only while the panel is visible.
	mouseUnlockConnection =
		RunService.RenderStepped:Connect(function()
			if panelVisible then
				UserInputService.MouseIconEnabled = true
				UserInputService.MouseBehavior =
					Enum.MouseBehavior.Default
			end
		end)
end

local function restoreMouse()
	if mouseUnlockConnection then
		mouseUnlockConnection:Disconnect()
		mouseUnlockConnection = nil
	end

	mouseUnlocker.Visible = false

	if savedMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled =
			savedMouseIconEnabled
	end

	if savedMouseBehavior then
		UserInputService.MouseBehavior =
			savedMouseBehavior
	end

	savedMouseBehavior = nil
	savedMouseIconEnabled = nil
end

local function setPanelVisible(visible)
	panelVisible = visible
	main.Visible = visible
	mouseUnlocker.Visible = visible

	if visible then
		unlockMouse()
	else
		restoreMouse()
	end
end

--------------------------------------------------
-- PAGE CREATOR
--------------------------------------------------

local function createPage(name)
	local page = Instance.new("ScrollingFrame")
	page.Name = name
	page.Size = UDim2.new(1, -156, 1, 0)
	page.Position = UDim2.fromOffset(156, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = colours.Accent
	page.ZIndex = 3
	page.Parent = body

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = page

	return page
end

local voidPage = createPage("VoidPage")
voidPage.CanvasSize = UDim2.fromOffset(0, 660)

local settingsPage = createPage("SettingsPage")
settingsPage.CanvasSize = UDim2.fromOffset(0, 760)
settingsPage.Visible = false

--------------------------------------------------
-- TOGGLE CREATOR
--------------------------------------------------

local function createToggle(
	parent,
	labelText,
	yPosition,
	defaultValue,
	callback
)
	local textLabel = createLabel(
		parent,
		labelText,
		UDim2.new(1, -80, 0, 28),
		UDim2.fromOffset(14, yPosition)
	)

	textLabel.ZIndex = 6

	local toggleButton = Instance.new("TextButton")
	toggleButton.Size = UDim2.fromOffset(44, 24)
	toggleButton.Position = UDim2.new(
		1,
		-58,
		0,
		yPosition + 2
	)

	toggleButton.BackgroundColor3 =
		defaultValue
		and colours.Accent
		or colours.ToggleOff

	toggleButton.BorderSizePixel = 0
	toggleButton.Text = ""
	toggleButton.AutoButtonColor = false
	toggleButton.ZIndex = 6
	toggleButton.Parent = parent

	addCorner(toggleButton, 12)

	local circle = Instance.new("Frame")
	circle.Size = UDim2.fromOffset(18, 18)
	circle.Position =
		defaultValue
		and UDim2.fromOffset(23, 3)
		or UDim2.fromOffset(3, 3)

	circle.BackgroundColor3 = colours.White
	circle.BorderSizePixel = 0
	circle.ZIndex = 7
	circle.Parent = toggleButton

	addCorner(circle, 9)

	local enabled = defaultValue

	local function setVisual(value)
		enabled = value

		TweenService:Create(
			toggleButton,
			TweenInfo.new(0.15),
			{
				BackgroundColor3 =
					value
					and colours.Accent
					or colours.ToggleOff,
			}
		):Play()

		TweenService:Create(
			circle,
			TweenInfo.new(0.15),
			{
				Position =
					value
					and UDim2.fromOffset(23, 3)
					or UDim2.fromOffset(3, 3),
			}
		):Play()
	end

	toggleButton.MouseButton1Click:Connect(function()
		enabled = not enabled
		setVisual(enabled)
		callback(enabled)
	end)

	return {
		Set = function(value, runCallback)
			setVisual(value)

			if runCallback then
				callback(value)
			end
		end,

		Get = function()
			return enabled
		end,
	}
end

--------------------------------------------------
-- SLIDER CREATOR
--------------------------------------------------

local function createSlider(
	parent,
	labelText,
	yPosition,
	minimum,
	maximum,
	defaultValue,
	step,
	suffix,
	decimalPlaces,
	callback
)
	step = step or 1
	suffix = suffix or ""
	decimalPlaces = decimalPlaces or 0

	local label = createLabel(
		parent,
		labelText,
		UDim2.new(0.52, 0, 0, 20),
		UDim2.fromOffset(14, yPosition)
	)

	label.TextSize = 12
	label.ZIndex = 6

	local valueLabel = createLabel(
		parent,
		"",
		UDim2.new(0.45, -14, 0, 20),
		UDim2.new(0.55, 0, 0, yPosition)
	)

	valueLabel.TextColor3 =
		colours.SecondaryText

	valueLabel.TextSize = 11
	valueLabel.TextXAlignment =
		Enum.TextXAlignment.Right

	valueLabel.ZIndex = 6

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -28, 0, 5)
	track.Position =
		UDim2.fromOffset(14, yPosition + 25)

	track.BackgroundColor3 =
		Color3.fromRGB(72, 35, 61)

	track.BorderSizePixel = 0
	track.ZIndex = 6
	track.Parent = parent

	addCorner(track, 3)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = colours.Accent
	fill.BorderSizePixel = 0
	fill.ZIndex = 7
	fill.Parent = track

	addCorner(fill, 3)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(13, 13)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = colours.White
	knob.BorderSizePixel = 0
	knob.ZIndex = 8
	knob.Parent = track

	addCorner(knob, 7)

	local hitbox = Instance.new("TextButton")
	hitbox.Size = UDim2.new(1, 0, 0, 24)
	hitbox.Position = UDim2.fromOffset(0, -9)
	hitbox.BackgroundTransparency = 1
	hitbox.Text = ""
	hitbox.AutoButtonColor = false
	hitbox.ZIndex = 9
	hitbox.Parent = track

	local currentValue = defaultValue
	local dragging = false

	local function snapValue(value)
		local snapped =
			math.floor((value / step) + 0.5) * step

		return math.clamp(
			snapped,
			minimum,
			maximum
		)
	end

	local function setValue(value, runCallback)
		currentValue = snapValue(value)

		local percentage =
			(currentValue - minimum)
			/ (maximum - minimum)

		fill.Size =
			UDim2.new(percentage, 0, 1, 0)

		knob.Position =
			UDim2.new(percentage, 0, 0.5, 0)

		valueLabel.Text =
			formatNumber(
				currentValue,
				decimalPlaces
			) .. suffix

		if runCallback ~= false then
			callback(currentValue)
		end
	end

	local function updateFromPosition(inputX)
		if track.AbsoluteSize.X <= 0 then
			return
		end

		local percentage = math.clamp(
			(
				inputX
				- track.AbsolutePosition.X
			) / track.AbsoluteSize.X,
			0,
			1
		)

		local value =
			minimum
			+ ((maximum - minimum) * percentage)

		setValue(value, true)
	end

	hitbox.InputBegan:Connect(function(input)
		if input.UserInputType
			== Enum.UserInputType.MouseButton1
			or input.UserInputType
			== Enum.UserInputType.Touch
		then
			dragging = true
			updateFromPosition(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end

		if input.UserInputType
			== Enum.UserInputType.MouseMovement
			or input.UserInputType
			== Enum.UserInputType.Touch
		then
			updateFromPosition(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType
			== Enum.UserInputType.MouseButton1
			or input.UserInputType
			== Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	setValue(defaultValue, false)

	return {
		Set = function(value, runCallback)
			setValue(value, runCallback)
		end,

		Get = function()
			return currentValue
		end,
	}
end

--------------------------------------------------
-- VOID PAGE LAYOUT
--------------------------------------------------

local columns = Instance.new("Frame")
columns.Size = UDim2.new(1, 0, 0, 620)
columns.BackgroundTransparency = 1
columns.ZIndex = 4
columns.Parent = voidPage

local leftColumn = Instance.new("Frame")
leftColumn.Size = UDim2.new(0.54, -8, 1, 0)
leftColumn.BackgroundTransparency = 1
leftColumn.ZIndex = 4
leftColumn.Parent = columns

local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 14)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftColumn

local rightColumn = Instance.new("Frame")
rightColumn.Size = UDim2.new(0.46, -8, 1, 0)
rightColumn.Position = UDim2.new(0.54, 8, 0, 0)
rightColumn.BackgroundTransparency = 1
rightColumn.ZIndex = 4
rightColumn.Parent = columns

local rightLayout = Instance.new("UIListLayout")
rightLayout.Padding = UDim.new(0, 14)
rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
rightLayout.Parent = rightColumn

--------------------------------------------------
-- TELEPORT CARD
--------------------------------------------------

local teleportCard = createCard(
	leftColumn,
	"Teleport",
	230
)

teleportCard.LayoutOrder = 1
teleportCard.ZIndex = 5

controls.VoidMovement = createToggle(
	teleportCard,
	"Void Spam",
	38,
	Settings.VoidMovement,
	function(enabled)
		if enabled then
			statusLabel.Text = "Status: Running"
			statusLabel.TextColor3 = colours.Success
			startMovementLoop()
		else
			statusLabel.Text = "Status: Disabled"
			statusLabel.TextColor3 =
				colours.SecondaryText

			stopMovementLoop()
		end
	end
)

local voidKeyButton = createButton(
	teleportCard,
	"KEY: NONE",
	UDim2.fromOffset(96, 26),
	UDim2.new(1, -168, 0, 39)
)
voidKeyButton.TextColor3 = colours.SecondaryText
voidKeyButton.ZIndex = 7

voidKeyButton.MouseButton1Click:Connect(function()
	waitingForVoidKey = true
	voidKeyButton.Text = "PRESS KEY..."
	voidKeyButton.TextColor3 = colours.Accent
end)

local modeLabel = createLabel(
	teleportCard,
	"Teleport Mode",
	UDim2.new(0.5, 0, 0, 28),
	UDim2.fromOffset(14, 74)
)

modeLabel.TextSize = 12
modeLabel.ZIndex = 6

local modeButton = createButton(
	teleportCard,
	"RANDOM  ▾",
	UDim2.fromOffset(118, 28),
	UDim2.new(1, -132, 0, 74)
)

modeButton.TextColor3 = colours.SecondaryText
modeButton.ZIndex = 6

local function updateModeButton()
	modeButton.Text =
		Settings.TeleportMode .. "  ▾"
end

modeButton.MouseButton1Click:Connect(function()
	if Settings.TeleportMode == "RANDOM" then
		Settings.TeleportMode = "DIRECTIONAL"
	else
		Settings.TeleportMode = "RANDOM"
	end

	updateModeButton()
end)

controls.Distance = createSlider(
	teleportCard,
	"Distance",
	108,
	1000,
	10000000000,
	Settings.Distance,
	1000,
	" studs",
	0,
	function(value)
		Settings.Distance = value
	end
)

controls.TeleportInterval = createSlider(
	teleportCard,
	"Teleport Interval",
	148,
	0.000001,
	2,
	Settings.TeleportInterval,
	0.000001,
	"s",
	6,
	function(value)
		Settings.TeleportInterval = value
	end
)

controls.JitterStrength = createSlider(
	teleportCard,
	"Jitter Strength",
	188,
	0,
	100,
	Settings.JitterStrength,
	1,
	"%",
	0,
	function(value)
		Settings.JitterStrength = value
	end
)

--------------------------------------------------
-- DIRECTION CARD
--------------------------------------------------

local directionalCard = createCard(
	leftColumn,
	"Directional",
	334
)

directionalCard.LayoutOrder = 2
directionalCard.ZIndex = 5

local directionRows = {
	{
		Label = "+X Direction",
		Key = "PositiveX",
	},
	{
		Label = "-X Direction",
		Key = "NegativeX",
	},
	{
		Label = "+Y Direction",
		Key = "PositiveY",
	},
	{
		Label = "-Y Direction",
		Key = "NegativeY",
	},
	{
		Label = "+Z Direction",
		Key = "PositiveZ",
	},
	{
		Label = "-Z Direction",
		Key = "NegativeZ",
	},
}

for index, information in ipairs(directionRows) do
	local key = information.Key

	controls[key] = createSlider(
		directionalCard,
		information.Label,
		36 + ((index - 1) * 48),
		0,
		10000000000,
		Settings[key],
		1000,
		"",
		0,
		function(value)
			Settings[key] = value
		end
	)
end

--------------------------------------------------
-- MOTION CARD
--------------------------------------------------

local motionCard = createCard(
	rightColumn,
	"Motion",
	273
)

motionCard.LayoutOrder = 1
motionCard.ZIndex = 5

controls.MotionEnabled = createToggle(
	motionCard,
	"Spin / Riot Motion",
	38,
	Settings.MotionEnabled,
	function(enabled)
		Settings.MotionEnabled = enabled
	end
)

controls.SpinSpeed = createSlider(
	motionCard,
	"Spin Speed",
	80,
	0,
	200000,
	Settings.SpinSpeed,
	10,
	" deg/s",
	0,
	function(value)
		Settings.SpinSpeed = value
	end
)

controls.XZJitter = createSlider(
	motionCard,
	"XZ Jitter",
	125,
	0,
	100000,
	Settings.XZJitter,
	1,
	"",
	0,
	function(value)
		Settings.XZJitter = value
	end
)

controls.YJitter = createSlider(
	motionCard,
	"Y Jitter",
	170,
	0,
	100000,
	Settings.YJitter,
	1,
	"",
	0,
	function(value)
		Settings.YJitter = value
	end
)

controls.SpreadDistance = createSlider(
	motionCard,
	"Spread Distance",
	215,
	0,
	1000000,
	Settings.SpreadDistance,
	1,
	" studs",
	0,
	function(value)
		Settings.SpreadDistance = value
	end
)

--------------------------------------------------
-- INFORMATION CARD
--------------------------------------------------

local informationCard = createCard(
	rightColumn,
	"Information",
	176
)

informationCard.LayoutOrder = 2
informationCard.ZIndex = 5

local informationText = createLabel(
	informationCard,
	"",
	UDim2.new(1, -28, 1, -44),
	UDim2.fromOffset(14, 35)
)

informationText.TextWrapped = true
informationText.TextYAlignment =
	Enum.TextYAlignment.Top

informationText.TextColor3 =
	colours.SecondaryText

informationText.TextSize = 11
informationText.ZIndex = 6

informationText.Text =
	"RANDOM generates positions using all six directional ranges.\n\n"
	.. "DIRECTIONAL chooses an axis based on the six slider values.\n\n"
	.. "Jitter changes the direction. Spread adds a random offset. "
	.. "XZ and Y Jitter create rapid movement around each position."

--------------------------------------------------
-- RETURN BUTTON
--------------------------------------------------

local returnButton = createButton(
	rightColumn,
	"RETURN CHARACTER",
	UDim2.new(1, 0, 0, 46),
	UDim2.fromOffset(0, 0)
)

returnButton.BackgroundColor3 =
	colours.CardSecondary

returnButton.LayoutOrder = 3
returnButton.ZIndex = 5

returnButton.MouseButton1Click:Connect(function()
	controls.VoidMovement.Set(false, false)

	statusLabel.Text = "Status: Disabled"
	statusLabel.TextColor3 =
		colours.SecondaryText

	returnCharacter()
end)

--------------------------------------------------
-- REFRESH VOID CONTROLS
--------------------------------------------------

local function refreshVoidControls()
	updateModeButton()

	controls.Distance.Set(
		Settings.Distance,
		false
	)

	controls.TeleportInterval.Set(
		Settings.TeleportInterval,
		false
	)

	controls.JitterStrength.Set(
		Settings.JitterStrength,
		false
	)

	controls.PositiveX.Set(
		Settings.PositiveX,
		false
	)

	controls.NegativeX.Set(
		Settings.NegativeX,
		false
	)

	controls.PositiveY.Set(
		Settings.PositiveY,
		false
	)

	controls.NegativeY.Set(
		Settings.NegativeY,
		false
	)

	controls.PositiveZ.Set(
		Settings.PositiveZ,
		false
	)

	controls.NegativeZ.Set(
		Settings.NegativeZ,
		false
	)

	controls.MotionEnabled.Set(
		Settings.MotionEnabled,
		false
	)

	controls.SpinSpeed.Set(
		Settings.SpinSpeed,
		false
	)

	controls.XZJitter.Set(
		Settings.XZJitter,
		false
	)

	controls.YJitter.Set(
		Settings.YJitter,
		false
	)

	controls.SpreadDistance.Set(
		Settings.SpreadDistance,
		false
	)
end

--------------------------------------------------
-- SETTINGS PAGE LAYOUT
--------------------------------------------------

local settingsContainer = Instance.new("Frame")
settingsContainer.Size = UDim2.new(1, 0, 0, 720)
settingsContainer.BackgroundTransparency = 1
settingsContainer.ZIndex = 4
settingsContainer.Parent = settingsPage

local settingsLayout = Instance.new("UIListLayout")
settingsLayout.Padding = UDim.new(0, 14)
settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
settingsLayout.Parent = settingsContainer

--------------------------------------------------
-- STARTUP SETTINGS CARD
--------------------------------------------------

local startupCard = createCard(
	settingsContainer,
	"Startup",
	226
)

startupCard.LayoutOrder = 1
startupCard.ZIndex = 5

local autoExecuteToggle = createToggle(
	startupCard,
	"Auto Execute",
	40,
	STARTUP.AutoExecute,
	function(enabled)
		STARTUP.AutoExecute = enabled

		showNotification(
			"Auto Execute",
			enabled
				and "Void Spam will automatically start when this script next loads during this session."
				or "Automatic Void Spam has been disabled.",
			4
		)
	end
)

local silentLoadToggle = createToggle(
	startupCard,
	"Silent Load",
	78,
	STARTUP.SilentLoad,
	function(enabled)
		STARTUP.SilentLoad = enabled

		showNotification(
			"Silent Load",
			enabled
				and "The panel will begin hidden when this script next loads."
				or "The panel will begin visible when this script next loads.",
			4
		)
	end
)

local loadNotificationToggle = createToggle(
	startupCard,
	"Loaded Notification",
	116,
	STARTUP.ShowLoadNotification,
	function(enabled)
		STARTUP.ShowLoadNotification = enabled
	end
)

local keybindLabel = createLabel(
	startupCard,
	"Toggle UI Keybind",
	UDim2.new(0.55, 0, 0, 30),
	UDim2.fromOffset(14, 160)
)

keybindLabel.ZIndex = 6

local keybindButton = createButton(
	startupCard,
	currentToggleKey.Name,
	UDim2.fromOffset(160, 32),
	UDim2.new(1, -174, 0, 159)
)

keybindButton.TextColor3 =
	colours.SecondaryText

keybindButton.ZIndex = 6

local keybindHelp = createLabel(
	startupCard,
	"Click the keybind, then press any keyboard key.",
	UDim2.new(1, -28, 0, 20),
	UDim2.fromOffset(14, 196)
)

keybindHelp.TextColor3 = colours.DarkText
keybindHelp.TextSize = 10
keybindHelp.ZIndex = 6

keybindButton.MouseButton1Click:Connect(function()
	waitingForToggleKey = true
	keybindButton.Text = "PRESS A KEY..."
	keybindButton.TextColor3 = colours.Accent
end)

--------------------------------------------------
-- CONFIGURATION CARD
--------------------------------------------------

local configCard = createCard(
	settingsContainer,
	"Configurations",
	360
)

configCard.LayoutOrder = 2
configCard.ZIndex = 5

local nameLabel = createLabel(
	configCard,
	"Configuration Name",
	UDim2.new(1, -28, 0, 22),
	UDim2.fromOffset(14, 39)
)

nameLabel.TextSize = 12
nameLabel.ZIndex = 6

local configNameBox = Instance.new("TextBox")
configNameBox.Size = UDim2.new(1, -28, 0, 34)
configNameBox.Position = UDim2.fromOffset(14, 65)
configNameBox.BackgroundColor3 =
	colours.CardSecondary

configNameBox.BorderSizePixel = 0
configNameBox.PlaceholderText =
	"Example: Fast Random"

configNameBox.PlaceholderColor3 =
	colours.DarkText

configNameBox.Text = ""
configNameBox.TextColor3 = colours.Text
configNameBox.Font = Enum.Font.RobotoMono
configNameBox.TextSize = 12
configNameBox.ClearTextOnFocus = false
configNameBox.ZIndex = 6
configNameBox.Parent = configCard

addCorner(configNameBox, 7)
addStroke(configNameBox, colours.Border, 0.45)

local saveConfigButton = createButton(
	configCard,
	"SAVE CURRENT CONFIG",
	UDim2.new(0.5, -21, 0, 36),
	UDim2.fromOffset(14, 111)
)

saveConfigButton.BackgroundColor3 = colours.Accent
saveConfigButton.ZIndex = 6

local loadConfigButton = createButton(
	configCard,
	"LOAD SELECTED CONFIG",
	UDim2.new(0.5, -21, 0, 36),
	UDim2.new(0.5, 7, 0, 111)
)

loadConfigButton.ZIndex = 6

local selectedConfigLabel = createLabel(
	configCard,
	"Selected: None",
	UDim2.new(1, -28, 0, 24),
	UDim2.fromOffset(14, 159)
)

selectedConfigLabel.TextColor3 =
	colours.SecondaryText

selectedConfigLabel.TextSize = 11
selectedConfigLabel.ZIndex = 6

local cycleConfigButton = createButton(
	configCard,
	"SELECT CONFIG  ▾",
	UDim2.new(1, -28, 0, 37),
	UDim2.fromOffset(14, 190)
)

cycleConfigButton.TextColor3 =
	colours.SecondaryText

cycleConfigButton.ZIndex = 6

local autoLoadLabel = createLabel(
	configCard,
	"Auto Load: "
		.. (
			STARTUP.AutoLoadConfig ~= ""
			and STARTUP.AutoLoadConfig
			or "Disabled"
		),
	UDim2.new(1, -28, 0, 24),
	UDim2.fromOffset(14, 238)
)

autoLoadLabel.TextColor3 =
	colours.SecondaryText

autoLoadLabel.TextSize = 11
autoLoadLabel.ZIndex = 6

local setAutoLoadButton = createButton(
	configCard,
	"SET SELECTED AS AUTO LOAD",
	UDim2.new(0.5, -21, 0, 36),
	UDim2.fromOffset(14, 271)
)

setAutoLoadButton.ZIndex = 6

local disableAutoLoadButton = createButton(
	configCard,
	"DISABLE AUTO LOAD",
	UDim2.new(0.5, -21, 0, 36),
	UDim2.new(0.5, 7, 0, 271)
)

disableAutoLoadButton.ZIndex = 6

local deleteConfigButton = createButton(
	configCard,
	"DELETE SELECTED SESSION CONFIG",
	UDim2.new(1, -28, 0, 34),
	UDim2.fromOffset(14, 316)
)

deleteConfigButton.BackgroundColor3 =
	Color3.fromRGB(73, 20, 45)

deleteConfigButton.TextColor3 = colours.Danger
deleteConfigButton.ZIndex = 6

local configNames = {}
local configIndex = 0
local selectedConfigName

local function rebuildConfigNames()
	configNames = {}

	for name in pairs(BUILT_IN_CONFIGS) do
		table.insert(configNames, name)
	end

	for name in pairs(SessionConfigs) do
		if not table.find(configNames, name) then
			table.insert(configNames, name)
		end
	end

	table.sort(configNames)

	if #configNames == 0 then
		configIndex = 0
		selectedConfigName = nil

		selectedConfigLabel.Text =
			"Selected: None"

		cycleConfigButton.Text =
			"NO CONFIGURATIONS"

		return
	end

	if configIndex < 1 or configIndex > #configNames then
		configIndex = 1
	end

	selectedConfigName =
		configNames[configIndex]

	selectedConfigLabel.Text =
		"Selected: " .. selectedConfigName

	cycleConfigButton.Text =
		selectedConfigName .. "  ▾"
end

rebuildConfigNames()

local configDropdown = Instance.new("Frame")
configDropdown.Name = "ConfigDropdown"
configDropdown.Size = UDim2.new(1, -28, 0, 0)
configDropdown.Position = UDim2.fromOffset(14, 229)
configDropdown.BackgroundColor3 = colours.CardSecondary
configDropdown.BorderSizePixel = 0
configDropdown.ClipsDescendants = true
configDropdown.Visible = false
configDropdown.ZIndex = 20
configDropdown.Parent = configCard
addCorner(configDropdown, 7)
addStroke(configDropdown, colours.Border, 0.35)

local dropdownLayout = Instance.new("UIListLayout")
dropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
dropdownLayout.Parent = configDropdown

local function closeConfigDropdown()
	configDropdown.Visible = false
	configDropdown.Size = UDim2.new(1, -28, 0, 0)
end

local function openConfigDropdown()
	rebuildConfigNames()

	for _, child in ipairs(configDropdown:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	if #configNames == 0 then
		return
	end

	for _, configName in ipairs(configNames) do
		local option = createButton(
			configDropdown,
			configName,
			UDim2.new(1, 0, 0, 32),
			UDim2.fromOffset(0, 0)
		)
		option.TextXAlignment = Enum.TextXAlignment.Left
		option.TextColor3 = colours.SecondaryText
		option.ZIndex = 21

		option.MouseButton1Click:Connect(function()
			for index, name in ipairs(configNames) do
				if name == configName then
					configIndex = index
					break
				end
			end
			rebuildConfigNames()
			closeConfigDropdown()
		end)
	end

	local height = math.min(#configNames * 32, 160)
	configDropdown.Size = UDim2.new(1, -28, 0, height)
	configDropdown.Visible = true
end

cycleConfigButton.MouseButton1Click:Connect(function()
	if configDropdown.Visible then
		closeConfigDropdown()
	else
		openConfigDropdown()
	end
end)

saveConfigButton.MouseButton1Click:Connect(function()
	local configName = trim(configNameBox.Text)

	if configName == "" then
		showNotification(
			"Configuration",
			"Enter a configuration name first.",
			3
		)

		return
	end

	SessionConfigs[configName] =
		captureCurrentConfig()

	configNameBox.Text = ""

	rebuildConfigNames()

	for index, name in ipairs(configNames) do
		if name == configName then
			configIndex = index
			break
		end
	end

	rebuildConfigNames()

	showNotification(
		"Configuration Saved",
		configName
			.. " was saved for this server session.",
		4
	)
end)

loadConfigButton.MouseButton1Click:Connect(function()
	if not selectedConfigName then
		showNotification(
			"Configuration",
			"No configuration is selected.",
			3
		)

		return
	end

	local config = getConfig(selectedConfigName)

	if not config then
		showNotification(
			"Configuration",
			"The selected configuration could not be found.",
			3
		)

		return
	end

	applyConfig(copyTable(config))
	refreshVoidControls()

	showNotification(
		"Configuration Loaded",
		selectedConfigName
			.. " has been loaded.",
		4
	)
end)

setAutoLoadButton.MouseButton1Click:Connect(function()
	if not selectedConfigName then
		showNotification(
			"Auto Load",
			"Select a configuration first.",
			3
		)

		return
	end

	STARTUP.AutoLoadConfig =
		selectedConfigName

	autoLoadLabel.Text =
		"Auto Load: " .. selectedConfigName

	showNotification(
		"Auto Load",
		selectedConfigName
			.. " is now selected for automatic loading.",
		4
	)
end)

disableAutoLoadButton.MouseButton1Click:Connect(function()
	STARTUP.AutoLoadConfig = ""
	autoLoadLabel.Text = "Auto Load: Disabled"

	showNotification(
		"Auto Load",
		"Automatic configuration loading has been disabled.",
		3
	)
end)

deleteConfigButton.MouseButton1Click:Connect(function()
	if not selectedConfigName then
		return
	end

	if not SessionConfigs[selectedConfigName] then
		showNotification(
			"Configuration",
			"Built-in configurations cannot be deleted.",
			3
		)

		return
	end

	local deletedName = selectedConfigName

	SessionConfigs[deletedName] = nil
	configIndex = 1

	rebuildConfigNames()

	showNotification(
		"Configuration Deleted",
		deletedName .. " was deleted.",
		3
	)
end)

--------------------------------------------------
-- CLIENT-SIDE NOTE
--------------------------------------------------

local noteCard = createCard(
	settingsContainer,
	"Client-Side Saving",
	92
)

noteCard.LayoutOrder = 3
noteCard.ZIndex = 5

local noteText = createLabel(
	noteCard,
	"UI-saved configurations last until you leave the current server. "
		.. "Add permanent configurations to BUILT_IN_CONFIGS near the top of the LocalScript.",
	UDim2.new(1, -28, 0, 48),
	UDim2.fromOffset(14, 34)
)

noteText.TextWrapped = true
noteText.TextYAlignment =
	Enum.TextYAlignment.Top

noteText.TextColor3 =
	colours.SecondaryText

noteText.TextSize = 10
noteText.ZIndex = 6

--------------------------------------------------
-- PAGE SWITCHING
--------------------------------------------------

local function showVoidPage()
	voidPage.Visible = true
	settingsPage.Visible = false

	voidTab.BackgroundColor3 =
		colours.CardSecondary

	voidTab.TextColor3 = colours.Text

	settingsTab.BackgroundColor3 =
		colours.Card

	settingsTab.TextColor3 =
		colours.SecondaryText
end

local function showSettingsPage()
	voidPage.Visible = false
	settingsPage.Visible = true

	voidTab.BackgroundColor3 =
		colours.Card

	voidTab.TextColor3 =
		colours.SecondaryText

	settingsTab.BackgroundColor3 =
		colours.CardSecondary

	settingsTab.TextColor3 = colours.Text
end

voidTab.MouseButton1Click:Connect(
	showVoidPage
)

settingsTab.MouseButton1Click:Connect(
	showSettingsPage
)

--------------------------------------------------
-- DRAGGABLE WINDOW
--------------------------------------------------

local draggingWindow = false
local dragStart
local startPosition

local function beginWindowDrag(input)
	if input.UserInputType
		== Enum.UserInputType.MouseButton1
		or input.UserInputType
		== Enum.UserInputType.Touch
	then
		-- Prevent dragging when pressing a top-bar button.
		local mousePosition =
			UserInputService:GetMouseLocation()

		local minimisePosition =
			minimiseButton.AbsolutePosition

		local minimiseSize =
			minimiseButton.AbsoluteSize

		local closePosition =
			closeButton.AbsolutePosition

		local closeSize =
			closeButton.AbsoluteSize

		local overMinimise =
			mousePosition.X >= minimisePosition.X
			and mousePosition.X
				<= minimisePosition.X + minimiseSize.X
			and mousePosition.Y >= minimisePosition.Y
			and mousePosition.Y
				<= minimisePosition.Y + minimiseSize.Y

		local overClose =
			mousePosition.X >= closePosition.X
			and mousePosition.X
				<= closePosition.X + closeSize.X
			and mousePosition.Y >= closePosition.Y
			and mousePosition.Y
				<= closePosition.Y + closeSize.Y

		if overMinimise or overClose then
			return
		end

		draggingWindow = true
		dragStart = input.Position
		startPosition = main.Position
	end
end

topBar.InputBegan:Connect(beginWindowDrag)

UserInputService.InputChanged:Connect(function(input)
	if not draggingWindow then
		return
	end

	if input.UserInputType
		== Enum.UserInputType.MouseMovement
		or input.UserInputType
		== Enum.UserInputType.Touch
	then
		local difference =
			input.Position - dragStart

		main.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + difference.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + difference.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType
		== Enum.UserInputType.MouseButton1
		or input.UserInputType
		== Enum.UserInputType.Touch
	then
		draggingWindow = false
	end
end)

--------------------------------------------------
-- MINIMISE AND CLOSE
--------------------------------------------------

local minimised = false

minimiseButton.MouseButton1Click:Connect(function()
	minimised = not minimised
	body.Visible = not minimised

	if minimised then
		main.Size = UDim2.fromOffset(940, 48)
		minimiseButton.Text = "+"
	else
		main.Size = UDim2.fromOffset(940, 590)
		minimiseButton.Text = "—"
	end
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

--------------------------------------------------
-- CUSTOM KEYBIND
--------------------------------------------------

UserInputService.InputBegan:Connect(function(
	input,
	processed
)
	if waitingForVoidKey then
		if input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode ~= Enum.KeyCode.Unknown
		then
			currentVoidKey = input.KeyCode
			waitingForVoidKey = false
			voidKeyButton.Text = "KEY: " .. currentVoidKey.Name
			voidKeyButton.TextColor3 = colours.SecondaryText
			showNotification("Void Keybind", "Void Spam key set to " .. currentVoidKey.Name .. ".", 3)
		end
		return
	end

	if waitingForToggleKey then
		if input.UserInputType
			== Enum.UserInputType.Keyboard
			and input.KeyCode
				~= Enum.KeyCode.Unknown
		then
			currentToggleKey = input.KeyCode
			STARTUP.ToggleKey = input.KeyCode
			waitingForToggleKey = false

			keybindButton.Text =
				currentToggleKey.Name

			keybindButton.TextColor3 =
				colours.SecondaryText

			showNotification(
				"UI Keybind",
				"The panel key is now "
					.. currentToggleKey.Name
					.. ".",
				3
			)
		end

		return
	end

	if processed then
		return
	end

	if currentVoidKey ~= Enum.KeyCode.Unknown
		and input.KeyCode == currentVoidKey
	then
		local newState = not Settings.VoidMovement
		controls.VoidMovement.Set(newState, true)
		return
	end

	if input.KeyCode == currentToggleKey then
		setPanelVisible(not panelVisible)
	end
end)

--------------------------------------------------
-- AUTOMATIC STARTUP
--------------------------------------------------

task.defer(function()
	if STARTUP.AutoLoadConfig ~= "" then
		local startupConfig =
			getConfig(STARTUP.AutoLoadConfig)

		if startupConfig then
			applyConfig(copyTable(startupConfig))
			refreshVoidControls()
		end
	end

	setPanelVisible(not STARTUP.SilentLoad)

	if STARTUP.AutoExecute then
		task.wait(0.25)

		controls.VoidMovement.Set(true, false)

		statusLabel.Text = "Status: Running"
		statusLabel.TextColor3 = colours.Success

		startMovementLoop()
	end

	if STARTUP.ShowLoadNotification then
		task.wait(0.15)

		local loadedConfigText =
			STARTUP.AutoLoadConfig ~= ""
			and (
				" Config: "
				.. STARTUP.AutoLoadConfig
				.. "."
			)
			or ""

		local message

		if STARTUP.SilentLoad then
			message =
				"Loaded silently."
				.. loadedConfigText
				.. " Press "
				.. currentToggleKey.Name
				.. " to open the panel."
		else
			message =
				"hika.lua loaded."
				.. loadedConfigText
				.. " Press "
				.. currentToggleKey.Name
				.. " to toggle it."
		end

		showNotification(
			"hika.lua Loaded",
			message,
			5
		)
	end
end)

--------------------------------------------------
-- CLEANUP
--------------------------------------------------

script.Destroying:Connect(function()
	stopMovementLoop()
	restoreMouse()

	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end)

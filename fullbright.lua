-- FullBright
local Lighting = game:GetService("Lighting")

Lighting.Brightness = 2
Lighting.ClockTime = 14
Lighting.FogEnd = 100000
Lighting.GlobalShadows = false
Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)

Lighting:GetPropertyChangedSignal("Brightness"):Connect(function()
    Lighting.Brightness = 2
end)

Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
    Lighting.ClockTime = 14
end)

Lighting:GetPropertyChangedSignal("FogEnd"):Connect(function()
    Lighting.FogEnd = 100000
end)

Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(function()
    Lighting.GlobalShadows = false
end)

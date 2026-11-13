-- Run AFTER loading the patched Drawing library in a client.
-- Studio: see tests/POLYGONS.md for a temporary ModuleScript adapter.
local env = getgenv and getgenv() or _G
local Drawing = env.Drawing or require(script.Parent:WaitForChild("Drawing"))
local players = game:GetService("Players")
local input = game:GetService("UserInputService")
local run = game:GetService("RunService")
local gui = Instance.new("ScreenGui")
gui.Name = "PolygonRegressionBackground"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999998
gui.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
local objects, connections = {}, {}
local function label(text,x,y)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.TextColor3=Color3.new(1,1,1)
    l.TextSize=14
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.Size=UDim2.fromOffset(230,24)
    l.Position=UDim2.fromOffset(x,y)
    l.Text=text
    l.Parent=gui
end
local cases = {
    {"Triangle", "Acute", {{10,10},{190,30},{65,125}}},
    {"Triangle", "Obtuse / reverse", {{15,100},{195,110},{150,85}}},
    {"Quad", "Convex", {{15,25},{180,10},{195,110},{40,125}}},
    {"Quad", "Concave", {{10,10},{195,20},{75,65},{15,125}}},
    {"Quad", "Crossing: even-odd", {{10,10},{190,125},{10,125},{190,10}}},
    {"Triangle", "Collinear: no fill", {{10,10},{70,50},{160,110}}},
    {"Triangle", "Fractional / flat top", {{10.5,10.5},{190.5,10.5},{100.5,125.5}}},
    {"Quad", "Repeated vertex", {{10,10},{190,10},{100,125},{100,125}}},
    {"Quad", "Rectangle: merged rows", {{10,10},{190,10},{190,125},{10,125}}},
}
local keys={"PointA","PointB","PointC","PointD"}
for i,case in ipairs(cases) do
    local x=10+((i-1)%3)*240
    local y=45+math.floor((i-1)/3)*185
    label(case[2],x,y)
    for row=0,3 do
        for col=0,4 do
            local tile=Instance.new("Frame")
            tile.BorderSizePixel=0
            local c=(row+col)%2==0 and 0.15 or 0.35
            tile.BackgroundColor3=Color3.new(c,c,c)
            tile.Position=UDim2.fromOffset(x+col*42,y+25+row*35)
            tile.Size=UDim2.fromOffset(42,35)
            tile.Parent=gui
        end
    end
    local p=Drawing.new(case[1])
    for j,v in ipairs(case[3]) do p[keys[j]]=Vector2.new(x+v[1],y+25+v[2]) end
    p.Color=Color3.fromRGB(255,100,130)
    p.Transparency=0.5
    p.Filled=true
    p.Thickness=3
    p.ZIndex=5
    objects[#objects+1]=p
end
label("F fill | T alpha | V visible",10,5)
label("C color | M move | R remove",250,5)
label("D destroy | Q clean up",490,5)
local filled,visible,opaque,moving=false,true,false,false
filled=true
local baseA=objects[1].PointA
local elapsed=0
connections[#connections+1]=run.RenderStepped:Connect(function(dt)
    if moving and objects[1].__OBJECT_EXISTS then
        elapsed=elapsed+dt
        objects[1].PointA=baseA+Vector2.new(math.sin(elapsed*2)*30,0)
    end
end)
local function cleanup()
    for _,c in ipairs(connections) do c:Disconnect() end
    for _,p in ipairs(objects) do p:Remove() end
    gui:Destroy()
end
connections[#connections+1]=input.InputBegan:Connect(function(event,processed)
    if processed then return end
    local k=event.KeyCode
    if k==Enum.KeyCode.Q then cleanup() return end
    if k==Enum.KeyCode.F then
        filled=not filled
        for _,p in ipairs(objects) do p.Filled=filled end
    elseif k==Enum.KeyCode.T then
        opaque=not opaque
        for _,p in ipairs(objects) do
            p.Transparency=opaque and 1 or 0.5
            p.Transparency=p.Transparency -- repeat assignment regression
        end
    elseif k==Enum.KeyCode.V then
        visible=not visible
        for _,p in ipairs(objects) do p.Visible=visible end
    elseif k==Enum.KeyCode.C then
        for _,p in ipairs(objects) do p.Color=Color3.fromHSV(math.random(),0.6,1) end
    elseif k==Enum.KeyCode.M then moving=not moving
    elseif k==Enum.KeyCode.R then objects[1]:Remove()
    elseif k==Enum.KeyCode.D then objects[2]:Destroy()
    end
end)
print("Polygon visual harness: use a viewport >= 740x620. Q removes only harness objects.")

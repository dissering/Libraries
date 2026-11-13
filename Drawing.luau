local DrawingCache = {}
local DrawingObjects = {}

local Fonts = {
    [0] = Enum.Font.Arial,
    [1] = Enum.Font.BuilderSans,
    [2] = Enum.Font.Gotham,
    [3] = Enum.Font.RobotoMono
}

local function gethui()
    local success, result = pcall(function()
        return game:GetService("CoreGui")
    end)
    return success and result or game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
end
getgenv().gethui = gethui

local UI = Instance.new("ScreenGui")
UI.Name = "DrawingLib"
UI.DisplayOrder = 999999
UI.IgnoreGuiInset = true
UI.ResetOnSpawn = false
UI.Parent = gethui()

local Drawing = {
    Fonts = {
        UI = 0,
        System = 1,
        Plex = 2,
        Monospace = 3
    }
}

-- BEGIN POLYGON RASTERIZER (pure geometry; exercised by tests/polygon_geometry.py)
-- Emit disjoint integer rectangles using the even-odd rule at pixel centers.
-- Points must follow the perimeter. Crossing quads use even-odd filling.
local function rasterizePolygon(points, width, height, emit)
    local minY, maxY = math.huge, -math.huge
    for _, p in ipairs(points) do
        -- Invalid coordinates must never become loop bounds or GUI dimensions.
        if p.X ~= p.X or p.Y ~= p.Y
            or math.abs(p.X) == math.huge or math.abs(p.Y) == math.huge then
            return
        end
        minY = math.min(minY, p.Y)
        maxY = math.max(maxY, p.Y)
    end
    local first = math.max(0, math.ceil(minY - 0.5))
    local last = math.min(height - 1, math.ceil(maxY - 0.5) - 1)
    local previous = {}
    for y = first, last do
        local sampleY = y + 0.5
        local hits = {}
        for i, a in ipairs(points) do
            local b = points[i % #points + 1]
            -- Half-open edges exclude horizontal edges and double-counted vertices.
            if (a.Y <= sampleY and sampleY < b.Y)
                or (b.Y <= sampleY and sampleY < a.Y) then
                hits[#hits + 1] = a.X + (sampleY - a.Y) / (b.Y - a.Y) * (b.X - a.X)
            end
        end
        table.sort(hits)
        local current = {}
        for i = 1, #hits - 1, 2 do
            local left = math.max(0, math.ceil(hits[i] - 0.5))
            local right = math.min(width, math.ceil(hits[i + 1] - 0.5))
            if right > left then
                local rect
                for _, old in ipairs(previous) do
                    if old.x == left and old.w == right - left then
                        rect = old
                        break
                    end
                end
                if rect then
                    rect.h = rect.h + 1
                else
                    rect = {x = left, y = y, w = right - left, h = 1}
                end
                current[#current + 1] = rect
            end
        end
        for _, old in ipairs(previous) do
            local continued = false
            for _, rect in ipairs(current) do
                if rect == old then continued = true break end
            end
            if not continued then emit(old.x, old.y, old.w, old.h) end
        end
        previous = current
    end
    for _, rect in ipairs(previous) do emit(rect.x, rect.y, rect.w, rect.h) end
end
-- END POLYGON RASTERIZER

Drawing.new = function(drawingType)
    if type(drawingType) ~= "string" then
        error("Drawing.new: argument must be a string, got " .. type(drawingType), 2)
    end

    local validTypes = {
        Line = true,
        Square = true,
        Rectangle = true,
        Circle = true,
        Text = true,
        Image = true,
        Triangle = true,
        Quad = true
    }
    
    if not validTypes[drawingType] then
        error("Drawing.new: invalid drawing type '" .. drawingType .. "'", 2)
    end

    local drawingObj = Instance.new("Frame")
    drawingObj.BackgroundTransparency = 1
    drawingObj.BorderSizePixel = 0
    drawingObj.Size = UDim2.fromOffset(0, 0)
    drawingObj.Position = UDim2.fromOffset(0, 0)
    drawingObj.Parent = UI
    
    local properties = {
        Visible = true,
        Color = Color3.new(1, 1, 1),
        Transparency = 1,
        ZIndex = 1
    }
    
    local self = newproxy(true)
    local mt = getmetatable(self)
    
    local removed = false
    
    mt.__index = function(_, key)
        if key == "__OBJECT_EXISTS" then
            return not removed
        end
        return properties[key]
    end
    
    mt.__newindex = function(_, key, value)
        if removed then return end
        
        if key == "__OBJECT_EXISTS" then
            return
        end
        
        properties[key] = value
        
        if key == "Visible" then
            drawingObj.Visible = value
        elseif key == "Color" then
            drawingObj.BackgroundColor3 = value
        elseif key == "Transparency" then
            drawingObj.BackgroundTransparency = 1 - value
        elseif key == "ZIndex" then
            drawingObj.ZIndex = value
        end
    end
    
    mt.__tostring = function()
        return "Drawing"
    end
    
    mt.__metatable = "The metatable is locked"
    
    properties.Remove = function()
        if removed then return end
        
        removed = true
        
        if drawingObj and drawingObj.Parent then
            drawingObj:Destroy()
        end
        
        for i, obj in ipairs(DrawingCache) do
            if obj.proxy == self then
                table.remove(DrawingCache, i)
                break
            end
        end
        
        DrawingObjects[self] = nil
    end
    
    properties.Destroy = properties.Remove
    
    table.insert(DrawingCache, {proxy = self, instance = drawingObj})
    DrawingObjects[self] = true
    
    if drawingType == "Line" then
        drawingObj.AnchorPoint = Vector2.new(0.5, 0.5)
        
        properties.From = Vector2.zero
        properties.To = Vector2.zero
        properties.Thickness = 1
        
        local updateLine = function()
            if removed then return end
            
            local from = properties.From
            local to = properties.To
            local dx = to.X - from.X
            local dy = to.Y - from.Y
            local length = math.sqrt(dx * dx + dy * dy)
            
            drawingObj.Size = UDim2.fromOffset(length, properties.Thickness)
            drawingObj.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
            drawingObj.Rotation = math.deg(math.atan2(dy, dx))
            drawingObj.BackgroundTransparency = 1 - properties.Transparency
            drawingObj.BackgroundColor3 = properties.Color
        end
        
        local oldNewindex = mt.__newindex
        mt.__newindex = function(t, k, v)
            oldNewindex(t, k, v)
            if k == "From" or k == "To" or k == "Thickness" then
                updateLine()
            end
        end
        
    elseif drawingType == "Square" or drawingType == "Rectangle" then
        local stroke = Instance.new("UIStroke")
        stroke.Parent = drawingObj
        stroke.Thickness = 1
        stroke.Color = Color3.new(1, 1, 1)
        
        properties.Size = Vector2.zero
        properties.Position = Vector2.zero
        properties.Filled = false
        properties.Thickness = 1
        
        local updateSquare = function()
            if removed then return end
            
            drawingObj.Size = UDim2.fromOffset(properties.Size.X, properties.Size.Y)
            drawingObj.Position = UDim2.fromOffset(properties.Position.X, properties.Position.Y)
            
            if properties.Filled then
                drawingObj.BackgroundTransparency = 1 - properties.Transparency
                drawingObj.BackgroundColor3 = properties.Color
                stroke.Enabled = false
            else
                drawingObj.BackgroundTransparency = 1
                stroke.Enabled = true
                stroke.Color = properties.Color
                stroke.Thickness = properties.Thickness
                stroke.Transparency = 1 - properties.Transparency
            end
        end
        
        local oldNewindex = mt.__newindex
        mt.__newindex = function(t, k, v)
            oldNewindex(t, k, v)
            if k == "Size" or k == "Position" or k == "Filled" or k == "Thickness" or k == "Color" or k == "Transparency" then
                updateSquare()
            end
        end
        
    elseif drawingType == "Circle" then
        local stroke = Instance.new("UIStroke")
        stroke.Parent = drawingObj
        stroke.Thickness = 1
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = drawingObj
        
        properties.Radius = 50
        properties.Position = Vector2.zero
        properties.Filled = false
        properties.Thickness = 1
        properties.NumSides = 64
        
        local updateCircle = function()
            if removed then return end
            
            local diameter = properties.Radius * 2
            drawingObj.Size = UDim2.fromOffset(diameter, diameter)
            drawingObj.Position = UDim2.fromOffset(properties.Position.X - properties.Radius, properties.Position.Y - properties.Radius)
            
            if properties.Filled then
                drawingObj.BackgroundTransparency = 1 - properties.Transparency
                drawingObj.BackgroundColor3 = properties.Color
                stroke.Enabled = false
            else
                drawingObj.BackgroundTransparency = 1
                stroke.Enabled = true
                stroke.Color = properties.Color
                stroke.Thickness = properties.Thickness
                stroke.Transparency = 1 - properties.Transparency
            end
        end
        
        local oldNewindex = mt.__newindex
        mt.__newindex = function(t, k, v)
            oldNewindex(t, k, v)
            if k == "Radius" or k == "Position" or k == "Filled" or k == "Thickness" or k == "Color" or k == "Transparency" then
                updateCircle()
            end
        end
        
    elseif drawingType == "Triangle" or drawingType == "Quad" then
        -- Keep the original root: DrawingCache and Remove retain the same instance.
        drawingObj.Name = "Drawing" .. drawingType
        drawingObj.ClipsDescendants = false
        local count = drawingType == "Triangle" and 3 or 4
        local keys = {"PointA", "PointB", "PointC", "PointD"}
        properties.PointA = Vector2.zero
        properties.PointB = count == 3 and Vector2.new(50, 100) or Vector2.new(100, 0)
        properties.PointC = count == 3 and Vector2.new(100, 0) or Vector2.new(100, 100)
        if count == 4 then properties.PointD = Vector2.new(0, 100) end
        properties.Filled = false
        properties.Thickness = 1

        local lines, spans = {}, {}
        local activeSpans = 0
        local dirty = true
        local function newPart(name)
            local frame = Instance.new("Frame")
            frame.Name = name
            frame.BorderSizePixel = 0
            frame.BackgroundColor3 = properties.Color
            frame.BackgroundTransparency = 1 - properties.Transparency
            frame.ZIndex = properties.ZIndex
            frame.Visible = false
            frame.Parent = drawingObj
            return frame
        end
        for i = 1, count do
            lines[i] = newPart("Outline")
            lines[i].AnchorPoint = Vector2.new(0.5, 0.5)
        end
        local function updatePolygon()
            if removed then return end
            -- The root must NEVER contribute a rectangular background.
            drawingObj.BackgroundTransparency = 1
            drawingObj.Visible = properties.Visible
            local points = {}
            for i = 1, count do points[i] = properties[keys[i]] end
            for i, line in ipairs(lines) do
                line.Visible = not properties.Filled
                if not properties.Filled then
                    local a, b = points[i], points[i % count + 1]
                    local dx, dy = b.X - a.X, b.Y - a.Y
                    line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
                    line.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), properties.Thickness)
                    line.Rotation = math.deg(math.atan2(dy, dx))
                end
            end
            if properties.Filled and properties.Visible and dirty then
                local used = 0
                local size = UI.AbsoluteSize
                rasterizePolygon(points, math.floor(size.X), math.floor(size.Y), function(x, y, w, h)
                    used = used + 1
                    local span = spans[used]
                    if not span then
                        span = newPart("FillSpan")
                        spans[used] = span
                    end
                    span.Position = UDim2.fromOffset(x, y)
                    span.Size = UDim2.fromOffset(w, h)
                end)
                activeSpans = used
                dirty = false
            end
            for i, span in ipairs(spans) do
                span.Visible = properties.Filled and i <= activeSpans
            end
            for _, parts in ipairs({lines, spans}) do
                for _, part in ipairs(parts) do
                    part.BackgroundColor3 = properties.Color
                    part.BackgroundTransparency = 1 - properties.Transparency
                    part.ZIndex = properties.ZIndex
                end
            end
        end
        local oldNewindex = mt.__newindex
        mt.__newindex = function(t, k, v)
            if removed then return end
            local previous = properties[k]
            oldNewindex(t, k, v)
            drawingObj.BackgroundTransparency = 1
            if k == "PointA" or k == "PointB" or k == "PointC"
                or (count == 4 and k == "PointD") then
                if previous ~= v then dirty = true end
            elseif k ~= "Filled" and k ~= "Thickness" and k ~= "Color"
                and k ~= "Transparency" and k ~= "Visible" and k ~= "ZIndex" then
                return
            end
            if previous ~= v then updatePolygon() end
        end
        local resizeConnection = UI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            dirty = true
            updatePolygon()
        end)
        local oldRemove = properties.Remove
        properties.Remove = function()
            if removed then return end
            resizeConnection:Disconnect()
            oldRemove()
        end
        properties.Destroy = properties.Remove
        updatePolygon()

    elseif drawingType == "Text" then
        drawingObj:Destroy()
        
        drawingObj = Instance.new("TextLabel")
        drawingObj.BackgroundTransparency = 1
        drawingObj.BorderSizePixel = 0
        drawingObj.TextColor3 = Color3.new(1, 1, 1)
        drawingObj.TextSize = 13
        drawingObj.Font = Enum.Font.Code
        drawingObj.Text = ""
        drawingObj.AutomaticSize = Enum.AutomaticSize.XY
        drawingObj.Parent = UI
        
        properties.Text = ""
        properties.Size = 13
        properties.Center = false
        properties.Outline = false
        properties.OutlineColor = Color3.new(0, 0, 0)
        properties.Position = Vector2.zero
        properties.Font = 2
        properties.TextBounds = Vector2.zero
        
        local updateText = function()
            if removed then return end
            
            drawingObj.Text = tostring(properties.Text)
            drawingObj.TextSize = properties.Size
            drawingObj.Position = UDim2.fromOffset(properties.Position.X, properties.Position.Y)
            drawingObj.TextColor3 = properties.Color
            drawingObj.TextTransparency = 1 - properties.Transparency
            drawingObj.Font = Fonts[properties.Font] or Enum.Font.Code
            
            if properties.Center then
                drawingObj.TextXAlignment = Enum.TextXAlignment.Center
                drawingObj.TextYAlignment = Enum.TextYAlignment.Center
            else
                drawingObj.TextXAlignment = Enum.TextXAlignment.Left
                drawingObj.TextYAlignment = Enum.TextYAlignment.Top
            end
            
            if properties.Outline then
                drawingObj.TextStrokeTransparency = 0
                drawingObj.TextStrokeColor3 = properties.OutlineColor
            else
                drawingObj.TextStrokeTransparency = 1
            end
            
            game:GetService("RunService").RenderStepped:Wait()
            properties.TextBounds = drawingObj.TextBounds
        end
        
        local oldNewindex = mt.__newindex
        mt.__newindex = function(t, k, v)
            oldNewindex(t, k, v)
            if k ~= "TextBounds" then
                task.spawn(updateText)
            end
        end
        
    elseif drawingType == "Image" then
        drawingObj:Destroy()
        
        drawingObj = Instance.new("ImageLabel")
        drawingObj.BackgroundTransparency = 1
        drawingObj.BorderSizePixel = 0
        drawingObj.Parent = UI
        
        properties.Data = ""
        properties.Size = Vector2.zero
        properties.Position = Vector2.zero
        properties.Rounding = 0
        
        local updateImage = function()
            if removed then return end
            
            drawingObj.Image = properties.Data
            drawingObj.Size = UDim2.fromOffset(properties.Size.X, properties.Size.Y)
            drawingObj.Position = UDim2.fromOffset(properties.Position.X, properties.Position.Y)
            drawingObj.ImageTransparency = 1 - properties.Transparency
            drawingObj.ImageColor3 = properties.Color
        end
        
        local oldNewindex = mt.__newindex
        mt.__newindex = function(t, k, v)
            oldNewindex(t, k, v)
            if k == "Data" or k == "Size" or k == "Position" or k == "Transparency" or k == "Color" then
                updateImage()
            end
        end
    end
    
    return self
end

getgenv().Drawing = Drawing

getgenv().isrenderobj = function(obj)
    if type(obj) ~= "userdata" then
        return false
    end
    
    local success, exists = pcall(function()
        return obj.__OBJECT_EXISTS
    end)
    
    return success and exists == true
end

getgenv().cleardrawcache = function()
    for i = #DrawingCache, 1, -1 do
        local data = DrawingCache[i]
        if data and data.proxy then
            pcall(function()
                data.proxy:Remove()
            end)
        end
    end
    
    DrawingCache = {}
    DrawingObjects = {}
end

getgenv().getrenderproperty = function(obj, prop)
    if not getgenv().isrenderobj(obj) then
        return nil
    end
    return obj[prop]
end

getgenv().setrenderproperty = function(obj, prop, value)
    if not getgenv().isrenderobj(obj) then
        return
    end
    obj[prop] = value
end


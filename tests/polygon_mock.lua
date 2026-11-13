-- Minimal state/lifecycle model. This is NOT a Roblox renderer.
local registry, globals = {}, {}
local function signal()
    local callbacks = {}
    return {
        Connect=function(_,fn)
            local entry={fn=fn,active=true}
            callbacks[#callbacks+1]=entry
            return {Disconnect=function() entry.active=false end}
        end,
        Fire=function() for _,entry in ipairs(callbacks) do if entry.active then entry.fn() end end end,
        Count=function() local n=0 for _,e in ipairs(callbacks) do if e.active then n=n+1 end end return n end
    }
end
local function instance(kind)
    local data = {ClassName=kind, Visible=true, AbsoluteSize={X=64,Y=48}, signals={}}
    local object
    object=setmetatable({},{
        __index=function(_,key)
            if key=="Destroy" then return function()
                data.destroyed=true
                for _,child in ipairs(registry) do if child.Parent==object then child:Destroy() end end
                data.Parent=nil
            end end
            if key=="GetPropertyChangedSignal" then return function(_,name)
                data.signals[name]=data.signals[name] or signal()
                return data.signals[name]
            end end
            return data[key]
        end,
        __newindex=function(_,k,v) data[k]=v end
    })
    registry[#registry+1]=object
    return object
end
Instance={new=instance}
Enum={Font={Arial=0,BuilderSans=1,Gotham=2,RobotoMono=3}}
Vector2={new=function(x,y) return {X=x,Y=y} end,zero={X=0,Y=0}}
UDim2={fromOffset=function(x,y) return {x=x,y=y} end}
Color3={new=function(r,g,b) return {r=r,g=g,b=b} end}
newproxy=function() return setmetatable({},{}) end
getgenv=function() return globals end
local core=instance("CoreGui")
game={GetService=function() return core end}
math.atan2=math.atan2 or math.atan
assert(load(DRAWING_SOURCE,"Drawing.luau"))()
local Drawing=globals.Drawing
local UI
for _,v in ipairs(registry) do if v.Name=="DrawingLib" then UI=v end end
local resize=UI:GetPropertyChangedSignal("AbsoluteSize")
local function children(root,name)
    local out={}
    for _,v in ipairs(registry) do
        if v.Parent==root and (not name or v.Name==name) then out[#out+1]=v end
    end
    return out
end
for _,kind in ipairs({"Triangle","Quad"}) do
    local before=#registry
    local p=Drawing.new(kind)
    local root=registry[before+1]
    assert(root.Parent==UI and not root.destroyed, "original root must survive")
    local lines=children(root,"Outline")
    assert(#lines==(kind=="Triangle" and 3 or 4))
    p.PointA=Vector2.new(2,2)
    p.PointB=Vector2.new(40,2)
    p.PointC=Vector2.new(20,30)
    if kind=="Quad" then p.PointD=Vector2.new(2,30) end
    p.Filled=true
    local spans=children(root,"FillSpan")
    assert(#spans>0 and root.BackgroundTransparency==1)
    for _,line in ipairs(lines) do assert(not line.Visible) end
    p.Transparency=0.5
    p.Transparency=0.5 -- identical assignment must not expose root background
    p.Color=Color3.new(1,0,0)
    p.ZIndex=9
    for _,part in ipairs(children(root)) do
        assert(part.BackgroundTransparency==0.5 and part.BackgroundColor3==p.Color and part.ZIndex==9)
    end
    assert(root.BackgroundTransparency==1)
    local allocated=#registry
    p.Color=Color3.new(0,1,0)
    p.Visible=false
    p.PointC=Vector2.new(30,40)
    assert(#registry==allocated and not root.Visible)
    p.Visible=true
    assert(root.Visible)
    UI.AbsoluteSize={X=32,Y=24}
    resize:Fire()
    for _,span in ipairs(children(root,"FillSpan")) do
        if span.Visible then
            assert(span.Position.x+span.Size.x<=32 and span.Position.y+span.Size.y<=24)
        end
    end
    p.Filled=false
    p.Thickness=4
    for _,line in ipairs(lines) do assert(line.Visible and line.Size.y==4) end
    for _,span in ipairs(children(root,"FillSpan")) do assert(not span.Visible) end
    p.Filled=true
    p:Remove()
    p:Destroy()
    p.PointA=Vector2.new(1,1)
    assert(not p.__OBJECT_EXISTS and root.destroyed and #children(root)==0)
    assert(resize:Count()==0, "resize listener leaked")
end
local a,b=Drawing.new("Triangle"),Drawing.new("Quad")
globals.cleardrawcache()
assert(not a.__OBJECT_EXISTS and not b.__OBJECT_EXISTS and resize:Count()==0)
resize:Fire()
print("PASS: mocked API style, equal assignment, toggle, clipping, cache cleanup, Remove/Destroy, connections")

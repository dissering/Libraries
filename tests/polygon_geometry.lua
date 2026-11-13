local cases = {
    {{X=2,Y=2},{X=25,Y=26},{X=40,Y=2}},
    {{X=2,Y=2},{X=40,Y=2},{X=40,Y=30},{X=2,Y=30}},
    {{X=2,Y=2},{X=40,Y=2},{X=14,Y=12},{X=2,Y=30}}, -- concave
    {{X=2,Y=2},{X=40,Y=30},{X=2,Y=30},{X=40,Y=2}}, -- crossing
    {{X=2,Y=2},{X=10,Y=10},{X=20,Y=20}}, -- collinear
    {{X=2,Y=2},{X=2,Y=2},{X=2,Y=2}}, -- repeated
    {{X=-1000000,Y=-1000000},{X=1000000,Y=-1000000},
     {X=1000000,Y=1000000},{X=-1000000,Y=1000000}},
    {{X=2.5,Y=2.5},{X=30.5,Y=2.5},{X=20.5,Y=35.5}},
}
math.randomseed(92341)
for n = 1, 1000 do
    local points = {}
    for i = 1, 3 + n % 2 do
        points[i] = {X=math.random(-20,80)+0.123, Y=math.random(-20,80)+0.321}
    end
    cases[#cases+1] = points
end
-- Independent per-pixel ray-crossing oracle (no sorting or span construction).
local function inside(points, x, y)
    local result = false
    for i, a in ipairs(points) do
        local b = points[i % #points + 1]
        if (a.Y > y) ~= (b.Y > y)
            and x < (b.X-a.X)*(y-a.Y)/(b.Y-a.Y)+a.X then
            result = not result
        end
    end
    return result
end
local function check(points)
    local pixels, rectangles = {}, 0
    rasterizePolygon(points, 64, 48, function(x,y,w,h)
        rectangles = rectangles + 1
        assert(x >= 0 and y >= 0 and x+w <= 64 and y+h <= 48)
        assert(w > 0 and h > 0)
        for row=y,y+h-1 do
            for col=x,x+w-1 do
                local index = row*64+col
                assert(not pixels[index], "overlapping fill rectangles")
                pixels[index] = true
            end
        end
    end)
    assert(rectangles <= 96, "exceeded two spans per viewport row")
    for y=0,47 do
        for x=0,63 do
            assert((pixels[y*64+x] == true) == inside(points,x+0.5,y+0.5),
                "pixel mismatch at "..x..","..y)
        end
    end
    return rectangles
end
for _, points in ipairs(cases) do
    check(points)
    local reversed = {}
    for i=#points,1,-1 do reversed[#reversed+1] = points[i] end
    check(reversed)
end
assert(check(cases[2]) == 1, "rectangle rows must merge")
assert(check(cases[5]) == 0 and check(cases[6]) == 0)
local count = 0
rasterizePolygon({{X=0/0,Y=0},{X=1,Y=1},{X=0,Y=2}},64,48,function() count=count+1 end)
rasterizePolygon({{X=math.huge,Y=0},{X=1,Y=1},{X=0,Y=2}},64,48,function() count=count+1 end)
assert(count == 0)
print("PASS: 2016 geometry cases; oracle coverage, no overlaps, clipping, winding, degeneracy, merging")

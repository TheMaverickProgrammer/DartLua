-- create a namespace
Window = {}

-- create the prototype with default values
Window.prototype = {x=0, y=0, width=100, height=100, }

-- create a metatable
Window.mt = {}

-- declare the constructor function
function Window.new (o)
    setmetatable(o, Window.mt)
    return o
end

Window.mt.__index = function (table, key)
    return Window.prototype[key]
end

local w = Window.new{x=10, y=20}

-- Expect: 10
print(w.x)

-- Expect: 20
print(w.y)

-- Expect: 100
print(w.width)

-- Testing lua's table support on __index.
Window.prototype.width = 200
Window.mt.__index = Window.prototype

-- Expect: 200
print(w.width)

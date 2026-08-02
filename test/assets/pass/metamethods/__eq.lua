local x = {value=13}
local y = {value=100}
local mt = {
    __eq = function(l, r)
        return l.value == r.value
    end
}

setmetatable(x, mt)
setmetatable(y, mt)

-- Expect: false
print(x == y)

-- Expect: true
print(x ~= y)

x.value = 100

-- Expect: true
print(y == x)

-- Expect: false
print(y ~= x)


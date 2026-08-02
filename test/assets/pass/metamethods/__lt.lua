local x = {value=13}
local y = {value=100}
local mt = {
    __lt = function(l, r)
        return l.value < r.value
    end
}

setmetatable(x, mt)
setmetatable(y, mt)

-- Expect: true
print(x < y)

-- Expect: false
print(x > y)

-- Expect: false
print(y < x)

-- Expect: true
print(y > x)

x.value = 100

-- Expect: false
print(x < y)

-- Expect: false
print(x > y)

-- Expect: false
print(y < x)

-- Expect: false
print(y > x)
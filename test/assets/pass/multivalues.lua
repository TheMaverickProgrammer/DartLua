local function foo()
    return 1, 2, 3
end

local a, b, c = foo()

-- Expect: 1 2 3
print(a, b, c)

-- Expect: 1 2 3
print(foo())

-- Expect: 1 Y Z
print(foo(), 'Y', 'Z')

-- Expect: X Y 1 2 3
print('X', 'Y', foo())

--[[ Below are some sanity checks I wrote.
There was a regression and now I need be sure
these multi-assignment cases are correct.
--]]

local x = 4, 5
local y = 5
local z = x+2, y

-- Expect: 4 5 6
print(x, y, z)

-- Expect: 8 9 10
x, y, z = x+4, y+4, z+4
print(x, y, z)

local t = {fire=0, grass=1, aqua=2}
local p = t.fire, t.grass

-- Expect: 0
print(p)

t.elec = t.grass+4, t.aqua+4

-- Expect: 5
print(t.elec)

t.holy, t.dark = t.grass+2, t.aqua+2

-- Expect: 3 4
print(t.holy, t.dark)
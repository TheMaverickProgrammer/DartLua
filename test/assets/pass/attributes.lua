local x <const> = math.pi

-- Expect: 3.141592653589793
print(x)

-- Expect: false [   7:26 ] Attempt to re-assign a constant variable x.
print(pcall(function() x = 22/7 end))

-- This is allowed b/c y is just pointing to x's value.
local y = x
y = 12

-- Expect: 12
print(y)
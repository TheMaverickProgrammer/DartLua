-- This is why we're here.
local str = 'Hello, world'

-- Expects Hello, world
print(str)

-- Testing variadic args in print.

-- Expects 1, 2, 3, nil, true
print(1, 2, 3, nil, true)

-- Empty variadic should print nothing.
print()

-- Expects 1
print(1)

-- Expect: nil
print(xyz)

-- This is why we're here.
local str = 'Hello, world'

-- Expect: Hello, world
print(str)

-- Testing variadic args in print.

-- Expect: 1 2 3 nil true
print(1, 2, 3, nil, true)

-- Expect: \n
print()

-- Expect: 1
print(1)


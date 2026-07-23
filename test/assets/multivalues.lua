function foo()
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
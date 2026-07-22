function foo()
    return 1, 2, 3
end

local a, b, c = foo()

-- Expects 1, 2, 3
print(a, b, c)

print('---')

-- Expects 1, 2, 3
print(foo())

-- Expects 1, Y, Z
print(foo(), 'Y', 'Z')

-- Expects X. Y, 1, 2, 3
print('X', 'Y', foo())
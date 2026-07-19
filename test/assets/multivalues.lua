function foo()
    return 1, 2, 3
end

local a, b, c = foo()

-- Expect: 1, 2, 3
print(a, b, c)

print('---')

-- Expect: 1, 2, 3
print(foo())
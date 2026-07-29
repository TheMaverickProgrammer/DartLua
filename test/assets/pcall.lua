function good()
    local x = 100
    return x
end

function bad()
    x.foo = {}
end

local ok, val = pcall(good)

-- Expect: true 100
print(ok, val)

local ok, err = pcall(bad)

-- Expect: false [   7:6  ] Expected lua object for operator ".". Was nil.
print(ok, err)
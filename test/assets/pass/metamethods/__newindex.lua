local t = {}

-- Private access to original table t
local _t = t

-- Create proxy
t = {}

-- Create metatable
local mt = {
    __index = function (t,k)
    print("Access to element " .. tostring(k))
    return _t[k]
    end,

    __newindex = function (t,k,v)
    print("Update of element " .. tostring(k) .. " to " .. tostring(v))
    _t[k] = v
    end
}

setmetatable(t, mt)

-- Expect: Update of element 2 to hello
t[2] = 'hello'

-- Expect: Access to element 2
print(t[2])
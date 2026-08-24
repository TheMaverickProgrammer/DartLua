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

-- Skip the metatable behavior.
-- Does NOT write to _t.
rawset(t, 2, 'hello')

-- Skip the metatable behavior.
-- B/c the key exists on t.
-- Expect: hello
print(t[2])

-- Trigger metatable behavior.
-- DOES write to _t.
-- Expect: Update of element 5 to world
t[5] = 'world'

-- Skip the metatable behavior.
-- No key "5" on t.
-- Expect: nil
print(rawget(t, 5))

t = {}
local u = t

-- Expect: true
print(t == u)

-- Expect: true
print(rawequal(t, u))

local v = {}

-- Expect: false
print(t == v)

-- Expect: false
print(rawequal(t, v))

setmetatable(t, { __eq = function(a, b) return true end })

-- Expect: true
print(t == v)

-- Expect: false
print(rawequal(t, v))
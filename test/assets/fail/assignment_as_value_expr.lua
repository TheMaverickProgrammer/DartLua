-- This sanity check ensures assignment is not also an evaluated result
-- that can be passed into other expressions.
local t = {}

-- Expect: [   7:12 ] Expecting closing parentheses. Found "=".
-- Expect: [   7:21 ] Expected literal value or variable. Found ")".
print(t[2] = 'hello')

local z = 7
local y = 5
local x = y = z

-- Expect: [  11:13 ] Assignment is not a value expression.
-- This sanity check ensures assignment is not also an evaluated result
-- that can be passed into other expressions.
local t = {}

-- Expect: [   6:12 ] Assignment is not a value expression.
print(t[2] = 'hello')
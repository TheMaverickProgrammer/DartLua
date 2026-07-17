-- Test bit shifts
local val = 10

-- Expects 5
print(val >> 1)

-- Expects 20
print(val << 1)

-- Expects 0
print(val & 1)

-- Expects 2
print(val & 2)

-- Expects 11
print(val | 1)

-- Expects 10
print(val | 0)
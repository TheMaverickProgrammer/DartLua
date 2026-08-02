-- Test bit shifts
local val = 10

-- Expect: 5
print(val >> 1)

-- Expect: 20
print(val << 1)

-- Expect: 0
print(val & 1)

-- Expect: 2
print(val & 2)

-- Expect: 11
print(val | 1)

-- Expect: 10
print(val | 0)
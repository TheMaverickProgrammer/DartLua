x = { value=500 }

-- Expected: 500
-- Expected: 500
-- Expected: 500
print(x.value)
print(_ENV.x.value)
print(_G.x.value)

_G.x.value = "wumbo"

-- Expected: "wumbo"
-- Expected: "wumbo"
print(x.value)
print(_ENV.x.value)

-- Change the x variable..
_ENV.x = false

-- Expected: "false"
-- Expected: "false"
-- Expected: "false"
print(x)
print(_ENV.x)
print(_G.x)


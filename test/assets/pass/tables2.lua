local t = {[true]={}}
t["1"] = true
t[1] = false

-- Expect: true
print(tostring(t["1"]))

-- Expect: false
print(tostring(t[1]))

-- Expect: table
print(tostring(t[true]))

-- Expect: true=table : boolean
-- Expect: 1=true : string
-- Expect: 1=false : number
local count = 0
for k,v in pairs(t) do
    count = count + 1
	print(tostring(k).."="..tostring(v).." : " .. type(k))
end

-- Expect: count=3
print("count="..count)
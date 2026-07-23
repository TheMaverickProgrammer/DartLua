--[[
--This is a scratch pad file for testing stuff quickly.
--TODO: make these tests
--]]

--[[
local tab = {}
tab.func()
--]]

--[[
local tab = global_nil_var or {cat='meow',dog='woof'}
print(type(tab))

for k, v in pairs(tab) do
	print(k..'='..v)
end
--]]

--[[
print('hello' == 'hello')
local t = 'hello'
print(type(t) == 'string')

print(true == 'true')
print(false == 'false')
]]

--[[
local num = 1
-- Reported error
num["var"]
-- No reported error
num.var
--]]

-- Makes 11 elements, but the
-- length operator starts counting from 1.
local list = {}
for i=0, 10 do
	list[i] = i
end

-- Expect: len(list)=11
print('len(list)='..#list)

-- Expect: list > 0
if #list > 0 then
	print('list > 0')
end
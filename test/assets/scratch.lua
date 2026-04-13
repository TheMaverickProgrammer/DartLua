--[[
--This is a scratch pad file for testing stuff quickly.
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

local num = 1
-- Reported error
num["var"]
-- No reported error
num.var

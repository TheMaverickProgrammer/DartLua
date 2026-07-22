-- What sounds do these animals make?
local animals = {
	cat='meow',
	dog='woof',
	fish='blub',
	bird='tweet',
	bear='growl'
}

print('type(animals)='..type(animals))
print('len(animals)='..#animals)

for k, v in pairs(animals) do
	print(k..'='..v)
end

-- Edge case table behavior
local t = {
	'foo',
	grass='green',
	cool=true,
	uncool=false
}

print('len(t)='..#t)

for k, v in pairs(t) do
	if type(v) == 'boolean' then
		print(k..'='..(v and 'true' or 'false'))
	else
		print(k..'='..v)
	end
end


-- Tables as lists
local list = {}

-- This is technically 11 elements, but the
-- length operator starts counting from 1.
for i=0, 10 do
	list[i] = i
end

-- Expects len(list)=11
print('len(list)='..#list)

if #list > 0 then
	print('list > 0')
end

local compound = {
	arr={0, 1, 2, 3, 4, 5, 'a', 'b', 'c', 'd', 'e'}
}
-- Length operator on a compound expression.

-- Expects 11
print(#compound.arr)

-- Expects 11
print(#(compound.arr))
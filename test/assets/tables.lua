-- What sounds do these animals make?
local animals = {
	cat='meow',
	dog='woof',
	fish='blub',
	bird='tweet',
	bear='growl'
}

-- Expect: type(animals)=table
-- Expect: len(animals)=0
print('type(animals)='..type(animals))
print('len(animals)='..#animals)

-- Expect: cat=meow
-- Expect: dog=woof
-- Expect: fish=blub
-- Expect: bird=tweet
-- Expect: bear=growl
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

-- Expect: len(t)=1
print('len(t)='..#t)

-- Expect: 1=foo
-- Expect: grass=green
-- Expect: cool=true
-- Expect: uncool=false
for k, v in pairs(t) do
	if type(v) == 'boolean' then
		print(k..'='..(v and 'true' or 'false'))
	else
		print(k..'='..v)
	end
end

-- Tables as lists
local list = {}

-- Makes 11 elements, but the
-- length operator starts counting from 1.
for i=0, 10 do
	list[i] = i
end

-- Expect: len(list)=10
print('len(list)='..#list)

-- Expect: 0 = 0
-- Expect: 1 = 1
-- Expect: 2 = 2
-- Expect: 3 = 3
-- Expect: 4 = 4
-- Expect: 5 = 5
-- Expect: 6 = 6
-- Expect: 7 = 7
-- Expect: 8 = 8
-- Expect: 9 = 9
-- Expect: 10 = 10
for k,v in pairs(list) do
    print(k,'=',v)
end

-- Expect: 1 = 1
-- Expect: 2 = 2
-- Expect: 3 = 3
-- Expect: 4 = 4
-- Expect: 5 = 5
-- Expect: 6 = 6
-- Expect: 7 = 7
-- Expect: 8 = 8
-- Expect: 9 = 9
-- Expect: 10 = 10
for k,v in ipairs(list) do
    print(k,'=',v)
end

-- Expect: list > 0
if #list > 0 then
	print('list > 0')
end

local compound = {
	arr={1, 2, 3, 4, 5, 'a', 'b', 'c', 'd', 'e'}
}

-- Testing length operator on compound expression.

-- Expect: 10
print(#compound.arr)

-- Expect: 10
print(#(compound.arr))
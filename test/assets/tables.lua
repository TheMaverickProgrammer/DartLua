-- What sounds do these animals make?
local animals = {
	cat='meow',
	dog='woof',
	fish='blub',
	bird='tweet',
	bear='growl'
}

print(type(animals))

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

for k, v in pairs(t) do
	if type(v) == 'boolean' then
		print(k..'='..(v and 'true' or 'false'))
	else
		print(k..'='..v)
	end
end


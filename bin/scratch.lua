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

for k,v in pairs(list) do
    print(k,'=',v)
end
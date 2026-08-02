-- Count up
local count = 5
for i=0, count do
	print('loop='..i)
end

-- Expect: loop=0
-- Expect: loop=1
-- Expect: loop=2
-- Expect: loop=3
-- Expect: loop=4
-- Expect: loop=5

-- Count by 2s
for j=2, count*2, 2 do
	print('jump='..j)
end

-- Expect: jump=2
-- Expect: jump=4
-- Expect: jump=6
-- Expect: jump=8
-- Expect: jump=10
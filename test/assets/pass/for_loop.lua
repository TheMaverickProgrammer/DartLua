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

function foo(x) return x end

-- Expect: i=1
-- Expect: i=2
-- Expect: i=3
-- Expect: i=4
-- Expect: i=5
-- Expect: i=6
-- Expect: i=7
-- Expect: i=8
-- Expect: i=9
-- Expect: i=10
for i=foo(1), foo(10), foo(1) do
	print('i='..i)
end
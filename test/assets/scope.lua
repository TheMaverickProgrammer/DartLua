x = 10

function print_x()
	print(x)
end

function scope(y)
	print(x)
	local x = y
	print(x)
end

-- Expect: 10
print_x()

-- Expect: 10
-- Expect: 42
scope(42)

-- Expect: 10
print_x()

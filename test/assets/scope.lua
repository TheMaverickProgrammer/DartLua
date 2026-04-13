x = 10

function print_x()
	print(x)
end

function scope(y)
	print(x)
	local x = y
	print(x)
end

print_x()
scope(42)
print_x()

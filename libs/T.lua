select(2, ...) 'T'

local function wipe(t)
	setmetatable(t, nil)
	for k in pairs(t) do
		t[k] = nil
	end
	t.reset, t.reset = nil, 1
end
M.wipe = wipe

M.empty = setmetatable({}, {__metatable=false, __newindex=pass})

function M.map(...)
	local t = {}
	for i = 1, select('#', ...), 2 do
		t[select(i, ...)] = select(i + 1, ...)
	end
	return t
end
local function loop(count)
    if count < 10000000 then
        -- Lua handles proper tail calls automatically here
        return loop(count + 1)
    end
    return count
end

loop(0)

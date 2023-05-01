local path = require("plenary.path")

local utils = {}

utils.dirsep = vim.loop.os_uname().sysname == "Windows" and "\\" or "/"
utils.storage_path = path:new(vim.fn.stdpath("data"), "arti")

function utils.read_file(filepath)
    local f = require("io").open(tostring(filepath), "r")

    if f then
        local data = f:read("*a")
        f:close()
        return data
    end

    error("Couldn't read file '" .. tostring(filepath) .. "'")
end

function utils.split_lines(s)
    local result = { }

    for line in s:gmatch("[^\n]+") do
        table.insert(result, line)
    end

    return result
end

function utils.list_reinsert(t, inv, cmp)
    assert(vim.tbl_islist(t))

    if not cmp then cmp = function(a, b) return a == b end end

    local idx = 0

    for i, v in ipairs(t) do
        if cmp(v, inv) then
            idx = i
            break
        end
    end

    if idx > 0 then
        table.remove(t, idx)
    end

    table.insert(t, 1, inv)
end

function utils.get_visual_selection()
    local _, ssrow, sscol, _ = unpack(vim.fn.getpos("'<"))
    local _, serow, secol, _ = unpack(vim.fn.getpos("'>"))
    local nlines = math.abs(serow - ssrow) + 1

    local lines = vim.api.nvim_buf_get_lines(0, ssrow - 1, serow, false)
    if vim.tbl_isempty(lines) then return "" end

    lines[1] = string.sub(lines[1], sscol, -1)

    if nlines == 1 then
        lines[nlines] = string.sub(lines[nlines], 1, secol - sscol + 1)
    else
        lines[nlines] = string.sub(lines[nlines], 1, secol)
    end

    return table.concat(lines, "\n")
end

function utils.cmdline_split(s)
    local cmd, w = { }, { }
    local quote, escape = false, false

    for c in s:gmatch(".") do
        table.insert(w, c)

        if c == '\\' then
            escape = true
        elseif c == '"' and not escape then
            quote = not quote
        elseif c == ' ' and not quote and not escape then
            table.remove(w, #w) -- Remove Last ' '
            table.insert(cmd, table.concat(w))
            w = { }
        elseif escape then
            escape = false
        end
    end

    if #w > 0 then -- Check last word
        table.insert(cmd, table.concat(w))
    end

    return cmd
end

function utils.get_number_of_cores()
    return #vim.tbl_keys(vim.loop.cpu_info())
end

function utils.get_filename(filepath)
    return vim.fn.fnamemodify(tostring(filepath), ":t")
end

function utils.get_stem(filepath)
    local filename = utils.get_filename(filepath)
    local idx = filename:match(".*%.()")

    if idx == nil then
        return filename
    end

    return filename:sub(0, idx - 2)
end

function utils.load_luafile(filepath)
    local ret = loadfile(tostring(filepath))

    if type(ret) ~= "function" then
        error("Error loading lua file '" .. tostring(filepath) .. "'")
    end

    return ret
end

function utils.do_luafile(filepath, env)
    local loaded_code = utils.load_luafile(filepath)

    if type(env) == "table" then
        return setfenv(loaded_code, env)()
    end

    return loaded_code()
end

function utils.write_file(filepath, data)
    local f = require("io").open(tostring(filepath), "w")

    if f then
        f:write(data)
        f:close()
    else
        print("Couldn't write file '" .. tostring(filepath) ..  "'")
    end
end

return utils

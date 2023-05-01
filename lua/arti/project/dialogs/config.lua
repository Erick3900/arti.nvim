local select = require('arti.project.dialogs.select')
local table_d = require('arti.project.dialogs.table')

local M = {}

function M.update_config(ws, selconfig, config, state)
    if vim.tbl_islist(selconfig.choices) then
        local choices = vim.deepcopy(selconfig.choices)
        table.insert(choices, "..")

        select(choices, {
            prompt_title = vim.F.if_nil(selconfig.label, selconfig.name),
            entry_maker = function(entry)
                local entry_local = {
                    display = entry,
                    ordinal = entry
                }

                if entry == state[selconfig.name] then
                    entry_local.display = entry_local.display .. " [A]"
                end

                return entry_local
            end
        }, function(entry)
            if entry.display ~= ".." then
                state[selconfig.name] = entry.ordinal
                ws:update_state(state)
            end

            M.edit_config(ws, config, state)
        end)
    else
        vim.ui.input({
            prompt = vim.F.if_nil(selconfig.label, selconfig.name),
            default = vim.F.if_nil(state[selconfig.name], ""),
        }, function(str)
            if str then
                state[selconfig.name] = str
                ws:update_state(state)
            end

            M.edit_config(ws, config, state)
        end)
    end
end

function M.edit_config(ws, config, state)
    if not config then return end
    if not state then return end

    table_d(config, {
        prompt_title = "Configuration",
        columns = {
            { width = 40 },
            { remaining = true }
        },
        entry_maker = function(entry)
            return {
                ordinal = vim.F.if_nil(entry.label, entry.name),
                state = vim.F.if_nil(state[entry.name], entry.default or ""),
                value = entry
            }
        end,
        displayer = function(entry)
            return {
                { entry.ordinal, "TelescopeResultsIdentifier" },
                { entry.state,   "TelescopeResultsNumber" }
            }
        end
    }, function(entry)
        M.update_config(ws, entry.value, config, state)
    end)
end

local function edit_config(ws)
    local config = ws:get_config()
    local state = ws:get_state()

    vim.validate({
        config = { config, "table" },
        state = { state, "table" }
    })

    if not vim.tbl_islist(config) then
        error("Config must be a list")
    end

    if vim.tbl_islist(state) then
        error("State must be an object")
    end

    if not vim.tbl_isempty(config) then
        M.edit_config(ws, config, state)
    end
end

return edit_config

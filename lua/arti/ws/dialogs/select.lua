local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local config = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local function select(entries, options, callback)
    options = options or {}

    pickers.new({}, {
        prompt_title = options.prompt_title,
        sorter = vim.F.if_nil(options.sorter, config.generic_sorter({})),
        finder = finders.new_table({
            entry_maker = options.entry_maker,
            results = entries
        }),
        previewer = options.previewer,
        attach_mappings = function(promptbufnr)
            actions.select_default:replace(function()
                actions.close(promptbufnr)
                callback(action_state.get_selected_entry())
            end)

            return true
        end
    }):find()
end

return select

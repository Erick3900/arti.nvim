local select = require('arti.project.dialogs.select')
local entry_display = require('telescope.pickers.entry_display')

local function table(items, options, callback)
    options = options or {}

    local displayer = entry_display.create({
        separator = vim.F.if_nil(options.separator, " "),
        items = options.columns
    })

    local make_display = function(entry)
        return displayer(options.displayer(entry))
    end

    select(items, {
        prompt_title = options.promp_title,
        entry_maker = function(entry)
            local entry_local = options.entry_maker(entry)
            entry_local.display = make_display
            return entry_local
        end,
        previewer = options.previewer
    }, callback)
end

return table

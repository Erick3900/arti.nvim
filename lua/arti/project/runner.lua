local utils = require('arti.utils')
local dialogs = require('arti.project.dialogs')
local previewers = require('telescope.previewers')

local runner = {
    jobs = {},
    term_win_id = nil,
    term_buf_id = nil,
    types = {
        TASK = 1,
        LAUNCH = 2
    }
}

function runner.show_jobs(config)
    if vim.tbl_isempty(runner.jobs) then
        vim.notify("Job queue is empty")
        return
    end

    dialogs.table(vim.tbl_values(runner.jobs), {
        prompt_title = "Running Jobs",
        columns = {
            { width = 1 },
            { width = 6 },
            { width = 10 },
            { remaining = true },
        },
        entry_maker = function(entry)
            return {
                ordinal = entry.name,
                name = entry.name,
                pid = vim.fn.jobpid(entry.jobid),
                type = entry.jobtype,
                ws = entry.ws,
                value = entry,
            }
        end,
        displayer = function(entry)
            return {
                config.icons[entry.value.jobtype:lower()],
                { entry.type, "TelescopeResultsIdentifier" },
                { entry.pid,  "TelescopeResultsNumber" },
                entry.ws:get_name() .. ": \"" .. entry.name .. "\"",
            }
        end,
        previewer = previewers.new_buffer_previewer({
            dyn_title = function(_, entry) return entry.name end,
            define_preview = function(self, e)
                vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "json")

                local v = vim.deepcopy(e.value)
                v.ws = nil -- Remove Workspace before apply serialization

                local serpent = require('arti.serpent')

                vim.api.nvim_buf_set_lines(
                    self.state.bufnr,
                    0, -1, false,
                    utils.split_lines(
                        serpent.pretty_dump(
                            v,
                            {
                                nocode = true
                            }
                        )
                    )
                )
            end
        }),
    }, function(entry)
        vim.fn.jobstop(entry.value.jobid)
    end)
end

function runner.close_terminal()
    if runner.term_buf_id ~= nil then
        if vim.fn.winbufnr(runner.term_buf_id) ~= -1 then
            vim.api.nvim_win_close(runner.term_win_id, true)
        end

        vim.api.nvim_command("silent! :bd! " .. tostring(runner.term_buf_id))

        runner.term_buf_id = nil
        runner.term_win_id = nil
    end
end

function runner.select_os_command(entry, cmdkey)
    local os_name = vim.loop.os_uname().sysname:lower()

    local cmds = {
        command = nil,
        args = nil
    }

    if type(entry[os_name]) == "table" then
        cmds.command = vim.F.if_nil(entry[os_name][cmdkey], entry[cmdkey])

        if not vim.tbl_islist(cmds.command) then
            cmds.args = vim.F.if_nil(entry[os_name].args, entry.args)
        end
    else
        cmds.command = entry[cmdkey]

        if not vim.tbl_islist(cmds.command) then
            cmds.args = entry.args
        end
    end

    return cmds
end

function runner._scroll_output()
    if runner.term_buf_id ~= nil then
        if runner.term_buf_id ~= vim.api.nvim_get_current_buf() then
            vim.fn.win_execute(runner.term_win_id, "norm G")
        end
    elseif vim.bo.buftype ~= "quickfix" then
        vim.api.nvim_command("cbottom")
    end
end

function runner._run(config, ws, cmds, entry, on_exit, idx)
    assert(vim.tbl_islist(cmds))

    idx = idx or 1

    if idx > #cmds then
        return
    end

    entry = entry or {}
    entry.ws = ws

    local options = {
        cwd = entry.cwd,
        env = entry.env,
        detach = entry.detach,
    }

    if options.detach ~= true then
        local handle_output = function(_, lines, _)
            runner._scroll_output()
        end

        options.on_stdout = handle_output
        options.on_stderr = handle_output

        options.on_exit = function(id, code, _)
            runner._scroll_output()

            if idx == #cmds and vim.is_callable(on_exit) then
                on_exit(code)
            else
                runner._run(config, ws, cmds, entry, on_exit, idx + 1)
            end

            runner.jobs[id] = nil
        end
    end

    local start_job = function()
        runner.close_terminal()

        vim.api.nvim_command(vim.F.if_nil(config.terminal.position, "botright") .. " split")

        runner.term_win_id = vim.api.nvim_get_current_win()
        runner.term_buf_id = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(runner.term_win_id, runner.term_buf_id)
        vim.api.nvim_command("resize " .. tostring(vim.F.if_nil(config.terminal.size, 8)))

        entry.jobid = vim.fn.termopen(cmds[idx], options)
        vim.api.nvim_command("wincmd p")

        if options.detach ~= true then
            runner.jobs[entry.jobid] = entry
        end
    end

    local ok, err = pcall(start_job)

    if not ok then
        vim.notify(err)

        if vim.is_callable(on_exit) then
            on_exit(-1)
        end
    end
end

function runner._run_shell(config, ws, os_cmd, options, on_exit)
    local run_cmds = runner._parse_command(os_cmd)

    runner._run(config, ws, run_cmds, options, on_exit)
end

function runner._run_process(config, ws, cmds, options, on_exit)
    local run_cmds = runner._parse_program(cmds, options)

    runner._run(config, ws, run_cmds, options, on_exit)
end

function runner._run_lua(config, ws, task, on_exit)
    -- TODO
end

function runner._parse_command(os_cmd)
    local cmds = vim.tbl_islist(os_cmd.command) and os_cmd.command or { os_cmd }
    local run_cmds = {}

    for _, cmd in ipairs(cmds) do
        local run_c = { cmd.command or cmd }

        if vim.tbl_islist(cmd.args) then
            vim.list_extend(run_c, cmd.args)
        end

        table.insert(run_cmds, table.concat(run_c, " "))
    end

    return run_cmds
end

function runner._parse_program(os_cmd, concat)
    local cmds = vim.tbl_islist(os_cmd.command) and os_cmd.command or { os_cmd }
    local run_cmds = {}

    for _, cmd in ipairs(cmds) do
        local c = cmd.command or cmd
        local run_c = {}

        if type(c) == "string" then
            run_c = utils.cmdline_split(c)
        else
            run_c = { c }
        end

        if vim.tbl_islist(cmd.args) then
            vim.list_extend(run_c, cmd.args)
        end

        table.insert(run_cmds, concat and table.concat(run_c, " ") or run_c)
    end

    return run_cmds
end

function runner.run(config, ws, task, on_exit)
    local os_cmd = runner.select_os_command(task, "command")

    task.jobtype = runner.types.LAUNCH

    if task.type == "shell" then
        runner._run_shell(config, ws, os_cmd, task, on_exit)
    elseif task.type == "process" then
        runner._run_process(config, ws, os_cmd, task, on_exit)
    elseif task.type == "lua" then
        runner._run_lua(config, ws, task, on_exit)
    else
        error("Incalid task type '" .. tostring(task.type) .. "'")
    end
end

function runner.launch(config, ws, launch, on_exit)
    local os_cmd = runner.select_os_command(launch, "program")

    launch.jobtype = runner.types.TASK
    runner._run_process(config, ws, os_cmd, launch, on_exit)
end

return runner

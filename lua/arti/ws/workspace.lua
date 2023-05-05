local path       = require('plenary.path')
local utils      = require('arti.utils')
local runner     = require('arti.ws.runner')
local dialogs    = require('arti.ws.dialogs')
local previewers = require('telescope.previewers')

function show_entries(config, ws, entries, options, callback)
    dialogs.table(
        entries,
        {
            prompt_title = options.title,
            columns = {
                { width = 1 },
                { width = 50 },
                { remaining = true }
            },
            entry_maker = function(entry)
                return {
                    ordinal = entry.name,
                    value = entry
                }
            end,
            displayer = function(entry)
                return {
                    config.icons[options.icon],
                    { entry.value.name,                            "TelescopeResultsIdentifier" },
                    { entry.value.default == true and "[D]" or "", "TelescopeResultsNumber" }
                }
            end,
            previewer = previewers.new_buffer_previewer({
                dyn_title = function(_, entry)
                    return entry.name
                end,
                define_preview = function(self, entry)
                    local serpent = require('arti.serpent')
                    local res_obj = entry.value
                    local preview = utils.split_lines(serpent.pretty_dump(res_obj, { nocode = true }))

                    table.remove(preview, 1)
                    table.remove(preview, #preview)
                    table.remove(preview, #preview)
                    table.remove(preview, #preview)
                    table.insert(preview, 1, "{")
                    table.insert(preview, "}")

                    vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "lua")
                    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview)
                end
            })
        },
        function(entry)
            callback(entry.value)
        end
    )
end

return function(config, rootpath)
    local workspace = {
        rootpath = tostring(rootpath),
        runningjobs = {},
        states = {
            STARTING = 1,
            LOCK = 2,
            STOP = nil
        }
    }

    function workspace:ws_root()
        return tostring(path:new(self.rootpath, config.impl.workspace))
    end

    function workspace:ws_open(filename)
        vim.api.nvim_command(":e " .. tostring(path:new(self:ws_root(), filename)))
    end

    function workspace:open_launch()
        self:ws_open(config.impl.launch)
    end

    function workspace:open_tasks()
        self:ws_open(config.impl.tasks)
    end

    function workspace:open_variables()
        self:ws_open(config.impl.variables)
    end

    function workspace:open_config()
        self:ws_open(config.impl.config)
    end

    function workspace:edit_config()
        dialogs.edit_config(self)
    end

    function workspace:get_config()
        return self:_do_luafile(config.impl.config)
    end

    function workspace:get_variables()
        local variables_path = path:new(self:ws_root(), config.impl.variables)

        local variables_lua = function() return {} end

        if variables_path:is_file() then
            variables_lua = utils.load_luafile(variables_path)
        end

        return variables_lua
    end

    function workspace:get_state()
        local state_path = path:new(self:ws_root(), config.impl.state)

        local state_lua = {}

        if state_path:is_file() then
            state_lua = utils.do_luafile(tostring(state_path))
        end

        return self:sync_state(state_lua)
    end

    function workspace:get_name()
        return utils.get_filename(self.rootpath)
    end

    function workspace:is_active()
        return self.rootpath == vim.fn.getcwd()
    end

    function workspace:set_active()
        vim.api.nvim_set_current_dir(self.rootpath)
    end

    function workspace:_do_luafile(filename, fallback, env)
        fallback = fallback or {}
        local filepath = path:new(self:ws_root(), filename)

        if filepath:is_file() then
            local ret = utils.do_luafile(filepath, env)

            if type(ret) == "table" then
                return ret
            end
        end

        return fallback
    end

    function workspace:get_current_variables(vars)
        local filepath = vim.api.nvim_buf_get_name(0)

        local defaults = {
            env = vim.env,
            dirsep = utils.dirsep,
            file = filepath,
            filename = utils.get_filename(filepath),
            file_stem = utils.get_stem(filepath),
            selected_test = utils.get_visual_selection(),
            number_of_cores = utils.get_number_of_cores(),
            user_home = vim.loop.os_homedir(),
            workspace_folder = self.rootpath,
            workspace_name = self:get_name(),
            cwd = vim.fn.getcwd(),
            state = self:get_state()
        }

        if vars ~= false then
            local loaded_vars = self:get_variables()
            setmetatable(defaults, { __index = _G })
            defaults.ws = setfenv(loaded_vars, defaults)()
        end

        return defaults
    end

    function workspace:sync_state(state)
        local updated = false
        local ws_config = self:get_config()

        if type(ws_config) == "table" and vim.tbl_islist(ws_config) then
            for _, s_config in ipairs(ws_config) do
                if state[s_config.name] == nil and s_config.default then
                    state[s_config.name] = s_config.default
                    updated = true
                end
            end
        end

        if updated then
            self:update_state(state)
        end

        return state
    end

    function workspace:update_state(state)
        local state_path = path:new(self:ws_root(), config.impl.state)
        local serpent = require('arti.serpent')

        state.empty_dict = vim._empty_dict_mt

        utils.write_file(state_path, serpent.pretty_dump(state))
    end

    function workspace:get_tasks()
        local ws_tasks = self:_do_luafile(config.impl.tasks, {}, self:get_current_variables())

        if ws_tasks then
            return ws_tasks
        end

        return {}
    end

    function workspace:get_tasks_by_name(intasks)
        local tasks = vim.F.if_nil(intasks, self:get_tasks())
        local byname = {}

        for _, task in ipairs(tasks) do
            if task.name then
                if byname[task.name] then
                    error("Duplicate task '" .. task.name .. "'")
                else
                    byname[task.name] = task
                end
            end
        end

        return byname
    end

    function workspace:get_launch_by_name(inlaunchs)
        local launchs = vim.F.if_nil(inlaunchs, self:get_launch())
        local byname = {}

        for _, launch in ipairs(launchs) do
            if launch.name then
                if byname[launch.name] then
                    error("Duplicate launch config '"..launch.name.."'")
                else
                    byname[launch.name] = launch
                end
            end
        end

        return byname
    end

    function workspace:get_launch()
        local ws_launch = self:_do_luafile(config.impl.launch, {}, self:get_current_variables())

        if ws_launch then
            return ws_launch
        end

        return {}
    end

    function workspace:get_default_task()
        local tasks = self:get_tasks()

        if type(tasks) == "table" and vim.tbl_islist(tasks) then
            for _, task in ipairs(tasks) do
                if task.default == true then
                    return task
                end
            end
        end

        return nil
    end

    function workspace:get_default_launch()
        local launchs = self:get_launch()

        if type(launchs) == "table" and vim.tbl_islist(launchs) then
            for _, launch in ipairs(launchs) do
                if launch.default == true then
                    return launch
                end
            end
        end

        return nil
    end

    function workspace:launch_default()
        local launch = self:get_default_launch()

        if launch then
            self:launch(launch)
        else
            vim.notify("Default launch configuration not found")
        end
    end

    function workspace:tasks_default()
        local task = self:get_default_task()

        if task then
            self:run(task)
        else
            vim.notify("Default task configuration not found")
        end
    end

    function workspace:show_launch()
        local launchs = self:get_launch()

        show_entries(
            config,
            self,
            launchs,
            {
                title = "Launch",
                icon = "launch"
            },
            function(entry)
                self:launch(entry)
            end
        )
    end

    function workspace:show_tasks()
        local tasks = self:get_tasks()

        show_entries(
            config,
            self,
            tasks,
            {
                title = "Tasks",
                icon = "task"
            },
            function(entry)
                self:run(entry)
            end
        )
    end

    function workspace:get_depends(entry, byname, depends)
        depends = depends or {}

        if vim.tbl_islist(entry.depends) then
            for _, dep in ipairs(entry.depends) do
                if byname[dep] then
                    utils.list_reinsert(
                        depends,
                        byname[dep],
                        function(lhs, rhs)
                            return lhs.name == rhs.name
                        end
                    )

                    self:get_depends(byname[dep], byname, depends)
                else
                    error("Task '" .. dep .. "' not found")
                end
            end
        end

        return depends
    end

    function workspace:run_depends(depends, callback, idx)
        idx = idx or 1

        if idx > #depends then
            if vim.is_callable(callback) then
                callback(true)
            end

            return
        end

        if self.runningjobs[depends[idx].name] == self.states.LOCK then
            return
        end

        self.runningjobs[depends[idx].name] = self.states.LOCK

        runner.run(
            config,
            self,
            depends[idx],
            function(code)
                if code == 0 then
                    self:run_depends(depends, callback, idx + 1)
                elseif vim.is_callable(callback) then
                    callback(false)
                end

                self.runningjobs[depends[idx].name] = self.states.STOP
            end
        )
    end

    function workspace:run(entry, tasks)
        if self.runningjobs[entry.name] then
            return
        end

        if entry.detach ~= true then
            self.runningjobs[entry.name] = self.states.STARTING
        end

        local byname = self:get_tasks_by_name(tasks)
        local depends = self:get_depends(entry, byname)

        self:run_depends(depends, function(ok)
            if ok then
                runner.run(config, self, entry, function(code)
                    self.runningjobs[entry.name] = self.states.STOP

                    if code ~= 0 then
                        print("Task "..entry.name.." failed")
                    end

                    if vim.is_callabl(entry.on_exit) then
                        entry.on_exit(code)
                    end
                end)
            else
                self.runningjobs[entry.name] = self.states.STOP
            end
        end)
    end

    function workspace:launch(entry)
        if self.runningjobs[entry.name] then
            return
        end

        self.runningjobs[entry.name] = self.states.STARTING

        runner.close_terminal()

        local byname = self:get_tasks_by_name()
        local depends = self:get_depends(entry, byname)

        self:run_depends(depends, function(ok)
            if ok then
                runner.launch(config, self, entry, function(code)
                    self.runningjobs[entry.name] = self.states.STOP

                    if vim.is_callable(entry.on_exit) then
                        entry.on_exit(code)
                    end
                end)
            else
                self.runningjobs[entry.name] = self.states.STOP
            end
        end)
    end

    return workspace
end

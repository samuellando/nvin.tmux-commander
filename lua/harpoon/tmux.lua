local harpoon = require("harpoon")
local log = require("harpoon.dev").log
local global_config = harpoon.get_global_settings()
local utils = require("harpoon.utils")

local M = {}
local tmux_windows = {}

if global_config.tmux_autoclose_windows then
    local harpoon_tmux_group = vim.api.nvim_create_augroup(
        "HARPOON_TMUX",
        { clear = true }
    )

    vim.api.nvim_create_autocmd("VimLeave", {
        callback = function()
            require("harpoon.tmux").clear_all()
        end,
        group = harpoon_tmux_group,
    })
end

local function create_terminal(name)
    log.trace("tmux: _create_terminal())")

    local window_id

    -- Create a new tmux window and store the window id
    local out, ret, _ = utils.get_os_command_output({
        "tmux",
        "new-window",
        "-P",
        "-d",
        "-n",
        name,
        "-F",
        "#{pane_id}",
    }, vim.loop.cwd())

    if ret == 0 then
        window_id = out[1]:sub(2)
    end

    if window_id == nil then
        log.error("tmux: _create_terminal(): window_id is nil")
        return nil
    end

    return window_id
end

-- Checks if the tmux window with the given window id exists
local function terminal_exists(window_id)
    log.trace("_terminal_exists(): Window:", window_id)

    local exists = false

    local window_list, _, _ = utils.get_os_command_output({
        "tmux",
        "list-windows",
        "-F",
        "#W"
    }, vim.loop.cwd())

    -- This has to be done this way because tmux has-session does not give
    -- updated results
    for _, line in pairs(window_list) do
        local window_info = line

        if string.find(window_info, string.sub(window_id, 2)) then
            exists = true
        end
    end

    return exists
end

local function get_window_id(window_id)
    log.trace("_get_window_id(): Window:", window_id)

    local window_list, _, _ = utils.get_os_command_output({
        "tmux",
        "list-windows",
        "-F",
        "#S:#W"
    }, vim.loop.cwd())

    -- This has to be done this way because tmux has-session does not give
    -- updated results
    for _, line in pairs(window_list) do
        local window_info = line

        if string.find(window_info, string.sub(window_id, 2)) then
            return window_info
        end
    end
    log.error("Window does not exist")
end

local function find_terminal(args)
    log.trace("tmux: _find_terminal(): Window:", args)

    if type(args) == "string" then
        -- assume args is a valid tmux target identifier
        -- if invalid, the error returned by tmux will be thrown
        return {
            window_id = get_window_id(args),
            pane = false,
        }
    end
end

local function get_first_empty_slot()
    log.trace("_get_first_empty_slot()")
    for idx, cmd in pairs(harpoon.get_term_config().cmds) do
        if cmd == "" then
            return idx
        end
    end
    return M.get_length() + 1
end

function M.gotoTerminal(idx)
    log.trace("tmux: gotoTerminal(): Window:", idx)
    local window_handle = find_terminal(idx)

    local _, ret, stderr = utils.get_os_command_output({
        "tmux",
        window_handle.pane and "select-pane" or "select-window",
        "-t",
        window_handle.window_id,
    }, vim.loop.cwd())

    if ret ~= 0 then
        error("Failed to go to terminal." .. stderr[1])
    end
end

function M.sendCommand(idx, cmd, ...)
    log.trace("tmux: sendCommand(): Window:", idx)
    local window_handle = find_terminal(idx)

    if type(cmd) == "number" then
        cmd = harpoon.get_term_config().cmds[cmd]
    end

    if global_config.enter_on_sendcmd then
        cmd = cmd .. "\n"
    end

    log.error("ID", window_handle.window_id)

    if cmd then
        log.debug("sendCommand:", cmd)

        local _, ret, stderr = utils.get_os_command_output({
            "tmux",
            "send-keys",
            "-t",
            window_handle.window_id..".",
            string.format(cmd, ...),
        }, vim.loop.cwd())

        if ret ~= 0 then
            error("Failed to send command. " .. stderr[1])
        end
    end
end

function M.clear_all()
    log.trace("tmux: clear_all(): Clearing all tmux windows.")

    for _, window in pairs(tmux_windows) do
        -- Delete the current tmux window
        utils.get_os_command_output({
            "tmux",
            "kill-window",
            "-t",
            window.window_id,
        }, vim.loop.cwd())
    end

    tmux_windows = {}
end

function M.get_length()
    log.trace("_get_length()")
    return table.maxn(harpoon.get_term_config().cmds)
end

function M.valid_index(idx)
    if idx == nil or idx > M.get_length() or idx <= 0 then
        return false
    end
    return true
end

function M.emit_changed()
    log.trace("_emit_changed()")
    if harpoon.get_global_settings().save_on_change then
        harpoon.save()
    end
end

function M.add_cmd(cmd)
    log.trace("add_cmd()")
    local found_idx = get_first_empty_slot()
    harpoon.get_term_config().cmds[found_idx] = cmd
    M.emit_changed()
end

function M.rm_cmd(idx)
    log.trace("rm_cmd()")
    if not M.valid_index(idx) then
        log.debug("rm_cmd(): no cmd exists for index", idx)
        return
    end
    table.remove(harpoon.get_term_config().cmds, idx)
    M.emit_changed()
end

function M.set_cmd_list(new_list)
    log.trace("set_cmd_list(): New list:", new_list)
    for k in pairs(harpoon.get_term_config().cmds) do
        harpoon.get_term_config().cmds[k] = nil
    end
    for k, v in pairs(new_list) do
        harpoon.get_term_config().cmds[k] = v
    end
    M.emit_changed()
end

function M.create_terminal(name)
    log.trace("create_terminal()", name)
    if not terminal_exists(name) then
        create_terminal(name)
        return true
    end
    M.emit_changed()
    return false
end

return M

local M = {}

--- @param config Config
local function get_ft_config(config, ft)
  local ts_langs = { "typescript", "typescriptreact", "vue", "svelte", "astro" }

  if vim.tbl_contains(ts_langs, ft) then
    ft = "typescript"
  end

  local ft_config = config.filetypes[ft]

  if not ft_config then
    vim.notify("Nvim-Quicktype: Unsupported file type: " .. ft, vim.log.levels.WARN)
    return nil
  end

  return ft_config
end

local function write_debug_info(debug_dir, command)
  if debug_dir then
    local debug_file = debug_dir .. "/quicktype_debug_" .. os.time() .. ".log"
    local file = io.open(debug_file, "w")
    if file then
      file:write("Executed command:\n" .. command .. "\n")
      file:close()
      print("Debug info written to: " .. debug_file)
    else
      print("Failed to write debug info to: " .. debug_file)
    end
  end
end

local function is_valid_json(str)
  -- Attempt to decode the string as JSON
  local success, _ = pcall(vim.json.decode, str)
  return success
end

local function get_json_str_from_reg(clipboard_source_register)
  -- If clipboard_source_register is set, get the JSON from that register
  if clipboard_source_register then
    return vim.fn.getreg(clipboard_source_register)
  end

  -- Try to get JSON from the "+" (system) register first
  local json_str = vim.fn.getreg("+")
  if json_str ~= "" and is_valid_json(json_str) then
    return json_str
  end
  -- Try to get JSON from the '"' (unnamed) register
  json_str = vim.fn.getreg('"')
  if json_str ~= "" and is_valid_json(json_str) then
    return json_str
  end
  --  Fallback to the "0" register
  return vim.fn.getreg("0")
end

--- @param config Config
M.generate_type = function(config)
  -- Get the JSON string from the register
  local json_str = get_json_str_from_reg(config.global.clipboard_source_register)
  -- Check if the string is valid JSON
  if not is_valid_json(json_str) then
    vim.notify("The clipboard content is not valid JSON.", vim.log.levels.ERROR)
    return
  end

  -- Get the configuration for the current filetype
  local ft = vim.bo.ft
  local ft_config = get_ft_config(config, ft)

  -- If ft_config is nil, it means the file type is not supported
  if not ft_config then
    return
  end

  -- Prompt the user for the top-level type name.
  local top_level_type_name = vim.fn.input("Enter the top-level type name: ")

  -- Build the command
  local argv = {}

  table.insert(argv, config.global.quicktype_cmd)
  table.insert(argv, "--src-lang")
  table.insert(argv, config.global.src_lang)

  if config.global.no_combine_classes then
    table.insert(argv, "--no-combine-classes")
  end

  if config.global.all_properties_optional then
    table.insert(argv, "--all-properties-optional")
  end

  if config.global.alphabetize_properties then
    table.insert(argv, "--alphabetize-properties")
  end

  table.insert(argv, "--telemetry")
  table.insert(argv, config.global.telemetry)
  table.insert(argv, "-l")
  table.insert(argv, ft_config.lang)
  table.insert(argv, "-t")
  table.insert(argv, top_level_type_name)

  for option, value in pairs(ft_config.additional_options) do
    table.insert(argv, "--" .. option)
    if type(value) ~= "boolean" then
      table.insert(argv, tostring(value))
    end
  end

  vim.system(argv, { stdin = json_str }, function(system_completed)
    if system_completed.code ~= 0 then
      vim.schedule(function()
        vim.api.nvim_echo({ { "Error generating types. Exit code: " .. vim.v.shell_error } }, true, { err = true })
      end)

      if config.global.debug_dir then
        write_debug_info(config.global.debug_dir, table.concat(argv, " "))
      end

      return
    end

    local lines = vim.split(system_completed.stdout, "\n", { plain = true })
    vim.schedule(function()
      vim.api.nvim_buf_set_lines(0, vim.fn.line("."), vim.fn.line("."), false, lines)
    end)
  end)
end

return M

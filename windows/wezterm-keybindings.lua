local wezterm = require 'wezterm'
local act = wezterm.action

return function(config)
  config.key_map_preference = 'Physical'
  config.keys = {
    { key = 'phys:C', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
    { key = 'phys:V', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
    { key = 'phys:V', mods = 'CTRL', action = act.PasteFrom 'Clipboard' },
    { key = 'phys:C', mods = 'CTRL', action = act.SendString '\x03' },
    { key = 'Insert', mods = 'CTRL', action = act.CopyTo 'Clipboard' },
    { key = 'Insert', mods = 'SHIFT', action = act.PasteFrom 'Clipboard' },
    {
      key = 'phys:T',
      mods = 'CTRL|SHIFT',
      action = act.SpawnTab 'CurrentPaneDomain',
    },
    {
      key = 'phys:W',
      mods = 'CTRL|SHIFT',
      action = act.CloseCurrentTab { confirm = true },
    },
    {
      key = 'Tab',
      mods = 'CTRL',
      action = act.ActivateTabRelative(1),
    },
    {
      key = 'Tab',
      mods = 'CTRL|SHIFT',
      action = act.ActivateTabRelative(-1),
    },
    {
      key = 'phys:L',
      mods = 'CTRL|SHIFT',
      action = act.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS' },
    },
    {
      key = 'phys:P',
      mods = 'CTRL|SHIFT',
      action = act.ActivateCommandPalette,
    },
    {
      key = 'phys:R',
      mods = 'CTRL|SHIFT',
      action = act.PromptInputLine {
        description = 'Название вкладки',
        action = wezterm.action_callback(function(window, pane, title)
          if title and title ~= '' then
            window:active_tab():set_title(title)
          end
        end),
      },
    },
  }
  
  -- Copy and search have separate key tables. Keep their native actions and
  -- bind their letter commands to the same positions in every keyboard layout.
  if wezterm.gui then
    local tables = wezterm.gui.default_key_tables()
    for _, name in ipairs { 'copy_mode', 'search_mode' } do
      for _, binding in ipairs(tables[name]) do
        local letter = binding.key:match('^mapped:([a-zA-Z])$') or binding.key:match('^([a-zA-Z])$')
        if letter then
          if letter == letter:upper() and not binding.mods:find('SHIFT', 1, true) then
            binding.mods = binding.mods == 'NONE' and 'SHIFT' or binding.mods .. '|SHIFT'
          end
          binding.key = 'phys:' .. letter:upper()
        end
      end
    end
    config.key_tables = tables
  end
  
  
end

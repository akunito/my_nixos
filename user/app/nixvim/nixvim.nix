{ config, lib, pkgs, pkgs-unstable, inputs, userSettings, systemSettings, ... }:

{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;

    # AI "Composer" Agent: Avante with OpenRouter
    plugins.avante = {
      enable = true;
      settings = {
        provider = "openai";
        openai = {
          endpoint = "https://openrouter.ai/api/v1";
          model = "anthropic/claude-3.5-sonnet"; # OpenRouter model ID
          temperature = 0;
          max_tokens = 4096;
        };
      };
    };

    # Required dependencies for Avante
    plugins.dressing.enable = true;
    plugins.nui.enable = true;

    # AI Autocomplete: Supermaven (via extraPlugins since no official module exists)
    extraPlugins = [ pkgs.vimPlugins.supermaven-nvim ];

    # Core Intelligence: LSP
    plugins.lsp = {
      enable = true;
      servers = {
        nixd.enable = true;
        lua_ls.enable = true;
        pyright.enable = true;
        ts_ls.enable = true;
      };
    };

    # Treesitter
    plugins.treesitter = {
      enable = true;
      highlight.enable = true;
    };

    # Formatting: Conform with format-on-save
    plugins.conform-nvim = {
      enable = true;
      formatOnSave = {
        lspFallback = true;
        timeoutMs = 500;
      };
      formattersByFt = {
        nix = [ "nixfmt" ];
        lua = [ "stylua" ];
      };
    };

    # UI & UX Plugins
    plugins.telescope.enable = true;
    plugins.gitsigns.enable = true;
    plugins.which-key.enable = true;
    # web-devicons: Required by Telescope for file icons
    # Official NixVim configuration - must be enabled explicitly
    plugins.web-devicons = {
      enable = true;
      autoLoad = true;  # Load at startup so it's available when Telescope requires it
      settings = {
        color_icons = true;
        strict = true;
      };
    };

    # Keymaps: Cursor-like mappings
    keymaps = [
      {
        mode = "n";
        key = "<leader>k";
        action = ":AvanteToggle<CR>";
        options = {
          desc = "Toggle Avante chat";
          silent = true;
        };
      }
      {
        mode = "n";
        key = "<C-p>";
        action = "<cmd>Telescope find_files<CR>";
        options = {
          desc = "Telescope: Find files";
          silent = true;
        };
      }
      {
        mode = "n";
        key = "<C-S-f>";
        action = "<cmd>Telescope live_grep<CR>";
        options = {
          desc = "Telescope: Live grep";
          silent = true;
        };
      }
    ];

    # Pre-config: Override require to safely handle plugins that might not be in runtime path yet
    # NixVim generates require() calls but plugins might not be loaded yet
    extraConfigLuaPre = ''
      -- Store original require and create safe wrapper for all plugins
      _G._nixvim_original_require = require
      
      -- List of plugins that might not be loaded yet (add more as needed)
      local plugins_to_safely_handle = {
        "nvim-web-devicons",
        "which-key",
        "telescope",
        "gitsigns",
        "dressing",
        "conform",
        "avante",
        "avante_lib",
        "supermaven-nvim",
      }
      
      -- Create dummy modules for plugins that might not be available
      local function create_dummy_module(module_name)
        if module_name == "nvim-web-devicons" then
          return {
            setup = function() end,
            get_icon = function() return nil, nil end,
            has_loaded = function() return false end,
          }
        elseif module_name == "which-key" then
          return {
            setup = function() end,
            register = function() end,
          }
        elseif module_name == "telescope" then
          return {
            setup = function() end,
            load_extension = function() end,
          }
        elseif module_name == "gitsigns" then
          return {
            setup = function() end,
          }
        elseif module_name == "dressing" then
          return {
            setup = function() end,
          }
        elseif module_name == "conform" then
          return {
            setup = function() end,
          }
        elseif module_name == "avante" or module_name == "avante_lib" then
          return {
            setup = function() end,
            load = function() end,
          }
        elseif module_name == "supermaven-nvim" then
          return {
            setup = function() end,
          }
        else
          -- Generic dummy module
          return {
            setup = function() end,
          }
        end
      end
      
      require = function(module)
        -- Check if this is a plugin we need to handle safely
        for _, plugin_name in ipairs(plugins_to_safely_handle) do
          if module == plugin_name then
            local ok, result = pcall(_G._nixvim_original_require, module)
            if ok then
              return result
            else
              -- Return a dummy module to prevent errors until plugin loads
              return create_dummy_module(module)
            end
          end
        end
        -- For other modules, use original require
        return _G._nixvim_original_require(module)
      end
    '';

    # Neovim options (set via extraConfigLua to avoid module system conflicts)
    extraConfigLua = ''
      -- Configure Supermaven (with safe require)
      local ok_supermaven, supermaven = pcall(require, "supermaven-nvim")
      if ok_supermaven and supermaven then
        supermaven.setup({
          keymaps = {
            accept_suggestion = "<Tab>",
            clear_suggestion = "<C-]>",
            accept_word = "<C-j>",
          },
        })
      end

      -- Neovim options (including clipboard for Wayland)
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.expandtab = true
      vim.opt.clipboard = "unnamedplus"  -- System clipboard integration (works with wl-copy on Wayland)
    '';
  };

  # Ensure formatters are available
  home.packages = with pkgs; [
    nixfmt
    stylua
  ];
}

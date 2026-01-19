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
    plugins.nvim-web-devicons.enable = true;
    plugins.web-devicons.enable = true;  # Explicitly enable to silence deprecation warning

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

    # Neovim options (set via extraConfigLua to avoid module system conflicts)
    extraConfigLua = ''
      -- Configure Supermaven
      require("supermaven-nvim").setup({
        keymaps = {
          accept_suggestion = "<Tab>",
          clear_suggestion = "<C-]>",
          accept_word = "<C-j>",
        },
      })

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

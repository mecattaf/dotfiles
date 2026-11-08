# One held client generation: no Host restart or provider credentials.
{ ... }: {
  home-manager.users.tom = {
    home.file.".local/share/applications/agency-web.desktop" = {
      force = true;
      text = "[Desktop Entry]\nType=Application\nName=Agency Web\nExec=agency-web\nTerminal=false\nIcon=google-chrome\nCategories=Network;\n";
    };
    home.file.".local/lib/agency-chat-window/client".source = ./domicile-chat/helpers;
    home.file.".local/lib/kitty-dsh/agent-windows-v1".source = ./domicile-chat/agent-client;
    xdg.configFile."kitty-dsh/agent-windows.json".text = builtins.toJSON {
      launcher = "/home/tom/.local/lib/kitty-dsh/agent-windows-v1/client";
    };

  };
}

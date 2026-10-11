{
  lib,
  pkgs,
  osConfig,
  ...
}:
{
  # Linux Chrome uses NSS for locally trusted roots, including with Chrome Root Store.
  home.activation.browserTrust =
    lib.mkIf
      (builtins.elem osConfig.networking.hostName [
        "client"
        "strix"
      ])
      (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          browser_nss="$HOME/.local/share/pki/nssdb"
          if [ -d "$HOME/.pki/nssdb" ]; then browser_nss="$HOME/.pki/nssdb"; fi
          run mkdir -p "$browser_nss"
          if [ ! -f "$browser_nss/cert9.db" ]; then
            run ${pkgs.nssTools}/bin/certutil -N --empty-password -d "sql:$browser_nss"
          fi
          run ${pkgs.nssTools}/bin/certutil -A -d "sql:$browser_nss" \
            -n 'Coordinator browser CA' -t 'C,,' -i ${../certs/browser-root.crt}
        ''
      );
}

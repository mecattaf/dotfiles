function vi --description 'Native local Neovim UI for NAS files and surviving NAS buffers'
    if contains -- "$NVIM_REMOTE_ROLE" seat brain; or begin
            not set -q NVIM_REMOTE_ROLE; and contains -- (hostname) nas client
        end
        command nvim-remote --directory (pwd -P) -- $argv
    else
        command nvim $argv
    end
end

this is a specialized aicademy website on how i use llm s specifically claude

visually it should be similar to 
https://missing.csail.mit.edu/2020/data-wrangling/

https://practical.li/neovim/source-control/lazygit/

## Setup Instructions

1. **Install the Claude GitHub App**: 
   - Go to https://github.com/apps/claude
   - Install it on your nvim configuration repository

2. **Add Repository Secret**:
   - Go to Settings → Secrets and variables → Actions
   - Add `ANTHROPIC_API_KEY` with your API key

3. **Create the files above** in your repository

4. **Using with Octo.nvim**:
   ```vim
   :Octo issue create
   ```
   Then use the template or write your issue with `@claude` to trigger

5. **Review PRs with Neogit**:
   ```vim
   :Neogit
   ```
   Navigate to the PR branch to review changes

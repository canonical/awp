<!-- The README text of one harness: auto-wp.py substitutes each section
     into the placeholder of the same name in the language layer's
     README.md (spec/auto-wp.md 3.4). A section ends at the next marker
     or at end of file; its single trailing newline is not part of it,
     and an empty section is a placeholder that expands to nothing. -->

<!-- HARNESS -->
GitHub Copilot CLI

<!-- HARNESS_INSTALL -->
export PATH="$HOME/.local/bin:$PATH"
command -v copilot >/dev/null || curl -fsSL https://gh.io/copilot-install | bash

<!-- HARNESS_START -->
copilot --disable-builtin-mcps --sync-session=off

<!-- HARNESS_LOGIN -->
Inside the container, run `copilot login --device-code` and complete the displayed authorization in your host browser. Login is stored in the container's credential store, or in plaintext under `~/.copilot/` if no credential store is available. Never copy the host's `~/.copilot/` or credentials into it. Your account and organization policy must allow Copilot CLI; model requests consume your account's allowance. The start command disables built-in MCP servers and account session sync, and keeps trust and tool-approval prompts enabled. Do not use `/delegate`, `/share` or `/remote` for campaign source code.

<!-- HARNESS_HOST -->
Outside a container, keep trust and tool-approval prompts enabled; do not use `--allow-all` or `--allow-all-tools`.

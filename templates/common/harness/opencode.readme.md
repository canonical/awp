<!-- The README text of one harness: auto-wp.py substitutes each section
     into the placeholder of the same name in the language layer's
     README.md (spec/auto-wp.md 3.4). A section ends at the next marker
     or at end of file; its single trailing newline is not part of it,
     and an empty section is a placeholder that expands to nothing. -->

<!-- HARNESS -->
OpenCode

<!-- HARNESS_INSTALL -->
command -v opencode >/dev/null || curl -fsSL https://opencode.ai/v2/install | bash

<!-- HARNESS_START -->
opencode service set disabled true
opencode

<!-- HARNESS_LOGIN -->
OpenCode V2 is required (`opencode --version`); the older `opencode.ai/install` endpoint installs V1. On first start, run `/connect` and `/models`. Anthropic requires an API key, not a Claude subscription token; OpenRouter also uses an API key. The connection is stored in the container's OpenCode database (`opencode debug paths`), not necessarily `auth.json`. Never copy the host's OpenCode data directory into it. Type `/` to list project commands. OpenCode allows actions by default; add `permissions` rules to `opencode.json` to require approval.

<!-- HARNESS_HOST -->
Outside a container, add `permissions` rules to `opencode.json` to require approval; the default policy allows actions.

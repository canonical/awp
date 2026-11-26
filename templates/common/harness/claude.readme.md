<!-- The README text of one harness: auto-wp.py substitutes each section
     into the placeholder of the same name in the language layer's
     README.md (spec/auto-wp.md 3.4). A section ends at the next marker
     or at end of file; its single trailing newline is not part of it,
     and an empty section is a placeholder that expands to nothing. -->

<!-- HARNESS -->
Claude Code

<!-- HARNESS_INSTALL -->
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash

<!-- HARNESS_START -->
claude --dangerously-skip-permissions

<!-- HARNESS_LOGIN -->
On first start, log in using the URL and code printed by Claude Code. Login stays in the container. Never copy the host's `~/.claude/.credentials.json` into it.

<!-- HARNESS_HOST -->
Outside a container, omit `--dangerously-skip-permissions` and approve actions individually.

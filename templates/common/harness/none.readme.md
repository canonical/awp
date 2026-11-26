<!-- The README text of one harness: auto-wp.py substitutes each section
     into the placeholder of the same name in the language layer's
     README.md (spec/auto-wp.md 3.4). A section ends at the next marker
     or at end of file; its single trailing newline is not part of it,
     and an empty section is a placeholder that expands to nothing. -->

<!-- HARNESS -->
a manually installed harness

<!-- HARNESS_INSTALL -->

<!-- HARNESS_START -->

<!-- HARNESS_LOGIN -->
No agent harness is installed. Inside `workshop shell` (or the LXD container), install a harness that reads `.agents/skills`, `.claude/skills` or `.opencode/skills`. Start it in the `tmux` session and log in inside the container. Never copy a host credential into it. Adapt the next step if your harness cannot load the project commands; load the `time-loop` skill explicitly.

<!-- HARNESS_HOST -->
Choose a permission policy that asks before acting when running outside a container.

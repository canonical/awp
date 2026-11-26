
# Point OpenCode at a local OpenAI-compatible inference server (--local-inference).
#
# Appended to the `setup-project` hook, NOT `setup-base`. Workshop's launch
# order is: base, then each SDK's `setup-base` (as root), then **mount the
# project**, then `setup-project` (as the workshop user). This snippet needs
# both of the things only the later hook has -- the project mount, where the
# address file lives, and the user's own home to write into. In `setup-base`
# it ran before the mount existed and skipped every first launch. opencode
# itself is installed by `opencode.sh` from `setup-base`, so it is already on
# PATH by the time this runs.
#
# The host is NOT hardcoded: it is read from `.local-llm-machine-ip.txt`, the
# one-line LAN address of the local LLM host that this project already uses for
# the cross-provider judge (`skills/sl-auditor/SKILL.md`, `no_ceiling_gate.py`,
# `skills/time-loop/SKILL.md`). Looked for in the container's home first, then
# in the project directory -- the latter because this hook runs only at launch
# and refresh, and the container's home does not exist before the first launch,
# so the home copy alone can never be found on that first run. If neither is
# present, no configuration is written and the reason is printed: as sl-auditor
# puts it for the judge, the right move is to ask for the file, never to invent
# an address.
#
# Override any of these in the environment of `workshop launch` / `workshop
# refresh`:
#   AUTOWP_INFERENCE_HOST           host running the server (default: the file)
#   AUTOWP_INFERENCE_PORT           its OpenAI-compatible port
#   AUTOWP_INFERENCE_SUBAGENT_PORT  a second server, used only by subagents
#   AUTOWP_INFERENCE_MODEL          model name as the server reports it
#   AUTOWP_INFERENCE_USER           container user whose config is written
#   AUTOWP_PROJECT_DIR              the mounted project directory, searched for
#                                   the address file (default /project)
#   AUTOWP_INFERENCE_CONTEXT        declared context window, per model entry
#                                   (default 120000). Must stay at or below
#                                   OLLAMA_CONTEXT_LENGTH on BOTH servers.
#   AUTOWP_INFERENCE_OUTPUT         declared output budget (default 16000)
#   AUTOWP_INFERENCE_KEEP_TOKENS    compaction.keep.tokens (default 15000)
#   AUTOWP_INFERENCE_TOOL_MAX_LINES tool_output.max_lines (default 300)
#   AUTOWP_INFERENCE_TOOL_MAX_BYTES tool_output.max_bytes (default 12288)
#   AUTOWP_INFERENCE_REASONING_EFFORT
#                                   reasoning effort for the `build` agent
#                                   (default low). An EMPTY value omits the
#                                   key, leaving the model's own default.
#   AUTOWP_INFERENCE_SMALL_MODEL    a second, smaller model for the `explore`
#                                   subagent (unset by default: `explore`
#                                   stays on the subagent slot)
#
# The written config addresses eight failure modes seen with a single-slot
# local runner; see the generated README's "Local inference" section.
#   1. headerTimeout: a long prompt is processed before any response header is
#      sent, so the 5-minute default aborts turns the server would finish.
#      OpenCode retries three times and then halts the session.
#   2. A provider named `ollama` is taken over by OpenCode's discovery plugin,
#      which replaces `settings` and so drops those timeouts: discovery is
#      disabled here, and `package` and `models` are given explicitly.
#   3. Subagents get their own server (a separate prefix cache), because a
#      subagent's prompt shares almost no prefix with its parent's and would
#      otherwise evict it, forcing a full reprocess of the whole context.
#   4. `limit` on every model entry: with none declared OpenCode falls back to
#      its own assumed window (262 144 observed in 2.3.2), so `buffer: "50%"`
#      compacted at about 131k tokens -- measured decode there is 28.9 tok/s
#      against 45-52 tok/s under 60k. 120000 moves the threshold to 60k AND
#      keeps the declared window at or below the servers' OLLAMA_CONTEXT_LENGTH:
#      OpenCode sizes prompts against its own figure, never the server's, so a
#      declared window larger than the server's truncates silently.
#   5. `compaction.keep.tokens` 15000 rather than 24000: kept text is re-read
#      after every compaction, and compactions are now more frequent.
#   6. `tool_output` 300 lines / 12 KiB rather than the 2000 / 50 KiB default,
#      which let a single bash output of 48.9k characters into the context.
#      Output past the cap is spilled to a file under
#      ~/.local/share/opencode/tool-output/ (the skill gives the absolute path).
#   7. `reasoning_effort` on the `build` agent's REQUEST BODY, not through a
#      model variant: 83.5 % of decode tokens were invisible reasoning, while
#      visible assistant text averaged 523 characters a turn. The variant
#      syntax (`provider/model#low`) changes the model id, and an id the
#      provider cannot resolve falls back to a cloud model without saying so;
#      an unknown request-body key is at worst ignored by the server.
#   8. `AUTOWP_INFERENCE_SMALL_MODEL`, when set, gives `explore` a smaller
#      model on the main server. Unset, `explore` stays on the subagent slot
#      exactly as before, because a model that is not loaded is not faster.
(
    set -eu
    set -o pipefail
    umask 022

    port=${AUTOWP_INFERENCE_PORT:-11434}
    subagent_port=${AUTOWP_INFERENCE_SUBAGENT_PORT:-11435}
    model=${AUTOWP_INFERENCE_MODEL:-qwen3.8:27b-mlx}
    user=${AUTOWP_INFERENCE_USER:-workshop}
    context=${AUTOWP_INFERENCE_CONTEXT:-120000}
    output=${AUTOWP_INFERENCE_OUTPUT:-16000}
    keep_tokens=${AUTOWP_INFERENCE_KEEP_TOKENS:-15000}
    tool_max_lines=${AUTOWP_INFERENCE_TOOL_MAX_LINES:-300}
    tool_max_bytes=${AUTOWP_INFERENCE_TOOL_MAX_BYTES:-12288}
    # No colon: a value set to the empty string is kept empty, and omits the key.
    reasoning_effort=${AUTOWP_INFERENCE_REASONING_EFFORT-low}
    small_model=${AUTOWP_INFERENCE_SMALL_MODEL:-}

    # The optional fragments, assembled before the heredoc so the JSON below
    # has no conditional commas in it. `limit` is the same on every entry:
    # OpenCode sizes prompts against one window for all of them.
    limit="\"limit\": { \"context\": $context, \"output\": $output }"
    small_entry=
    explore_model="ollama-sub/$model"
    if [ -n "$small_model" ]; then
        small_entry=",
        \"$small_model\": { \"name\": \"$small_model (small)\", $limit }"
        explore_model="ollama/$small_model"
    fi
    build_agent=
    if [ -n "$reasoning_effort" ]; then
        build_agent=",
    \"build\": { \"request\": { \"body\": { \"reasoning_effort\": \"$reasoning_effort\" } } }"
    fi

    home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6) || home=
    home=${home:-/home/$user}
    conf="$home/.config/opencode/opencode.json"
    ip_file="$home/.local-llm-machine-ip.txt"
    # The project directory, mounted into the workshop. Unlike the container's
    # home it exists *before* the first launch, so it is the only place a user
    # can put the address in time for this hook's first run.
    project=${AUTOWP_PROJECT_DIR:-/project}
    project_ip="$project/.local-llm-machine-ip.txt"

    if [ -e "$conf" ]; then
        # Kept, like every other pre-existing file auto-wp finds, so that a
        # `workshop refresh` never discards local edits. Checked before the
        # host is resolved: nothing is going to be written, so a missing
        # address is not a problem here.
        printf 'auto-wp: %s exists; left as it is\n' "$conf" >&2
    else
        # The project's existing convention for the local LLM host: one line,
        # the address only. Searched in three places, first hit wins:
        #   1. AUTOWP_INFERENCE_HOST, for a test run on another host;
        #   2. the container's home, the convention the skills already read;
        #   3. the project directory, which exists before the first launch.
        # (3) exists because of (2)'s ordering problem: this hook runs at
        # launch and refresh only, and the container's home does not exist
        # until the first launch has happened -- so a first launch could never
        # find a file that can only be created afterwards.
        read_ip() { sed -n '1{s/[[:space:]]//g; p; q;}' "$1" 2>/dev/null; }
        host=${AUTOWP_INFERENCE_HOST:-}
        src="AUTOWP_INFERENCE_HOST"
        if [ -z "$host" ] && [ -r "$ip_file" ]; then
            host=$(read_ip "$ip_file"); src=$ip_file
        fi
        if [ -z "$host" ] && [ -r "$project_ip" ]; then
            host=$(read_ip "$project_ip"); src=$project_ip
            # The shipped gates read `$(cat ~/.local-llm-machine-ip.txt)`
            # (skills/sl-auditor, sl-internal/scripts/no_ceiling_gate.py), so
            # seed the home copy too or the cross-provider judge still fails.
            if [ -n "$host" ] && [ ! -e "$ip_file" ]; then
                install -m 644 "$project_ip" "$ip_file" 2>/dev/null \
                    && printf 'auto-wp: seeded %s from %s\n' "$ip_file" "$project_ip"
            fi
        fi
        if [ -z "$host" ]; then
            # Deliberately not an error: the file lives in the container's
            # home, which does not exist before this hook has run, so failing
            # here would leave no container in which to create it. Nothing is
            # written, so no configuration points at a guessed address.
            printf 'auto-wp: no local inference host. Looked in:\n' >&2
            printf 'auto-wp:   %s (%s)\n' "$ip_file" \
                "$([ -e "$ip_file" ] && echo 'empty or unreadable' || echo 'missing')" >&2
            printf 'auto-wp:   %s (%s)\n' "$project_ip" \
                "$([ -e "$project_ip" ] && echo 'empty or unreadable' || echo 'missing')" >&2
            printf 'auto-wp: put the LLM host address, one line, in the project directory\n' >&2
            printf 'auto-wp: (it is mounted here, so this works before a launch), then refresh:\n' >&2
            printf 'auto-wp:   echo 192.0.2.10 > %s && workshop refresh\n' "$project_ip" >&2
            printf 'auto-wp: %s was NOT written; OpenCode keeps its current provider.\n' "$conf" >&2
            exit 0
        fi
        install -d -m 755 "$home/.config" "$home/.config/opencode"
        # Expanding heredoc: \$schema is escaped so the shell leaves it alone.
        cat >"$conf" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",

  "plugins": ["-opencode.provider.ollama"],

  "providers": {
    "ollama": {
      "name": "Local inference",
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "http://$host:$port/v1",
        "apiKey": "ollama",
        "headerTimeout": 3600000,
        "chunkTimeout": false,
        "timeout": false
      },
      "models": {
        "$model": { "name": "$model (local)", $limit }$small_entry
      }
    },

    "ollama-sub": {
      "name": "Local inference (subagent slot)",
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "http://$host:$subagent_port/v1",
        "apiKey": "ollama",
        "headerTimeout": 3600000,
        "chunkTimeout": false,
        "timeout": false
      },
      "models": {
        "$model": { "name": "$model (subagent slot)", $limit }
      }
    }
  },

  "agents": {
    "general": { "model": "ollama-sub/$model" },
    "explore": { "model": "$explore_model" }$build_agent
  },

  "compaction": {
    "buffer": "50%",
    "keep": { "tokens": $keep_tokens }
  },

  "model": "ollama/$model",

  "tool_output": {
    "max_lines": $tool_max_lines,
    "max_bytes": $tool_max_bytes
  }
}
EOF
        chown -R "$user" "$home/.config" 2>/dev/null || true
        chmod 644 "$conf"
        printf 'auto-wp: wrote %s (local inference: %s:%s, subagents %s, from %s)\n' \
            "$conf" "$host" "$port" "$subagent_port" "$src"
    fi
)

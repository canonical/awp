
# Point OpenCode at a local OpenAI-compatible inference server (--local-inference).
# Appended after opencode.sh, so the binary is already installed and on PATH.
#
# The host is NOT hardcoded: it is read from `~/.local-llm-machine-ip.txt`, the
# one-line LAN address of the local LLM host that this project already uses for
# the cross-provider judge (`skills/sl-auditor/SKILL.md`, `no_ceiling_gate.py`,
# `skills/time-loop/SKILL.md`). If that file is absent, no configuration is
# written and the reason is printed: as sl-auditor puts it for the judge, the
# right move is to ask for the file, never to invent an address.
#
# Override any of these in the environment of `workshop launch` / `workshop
# refresh`:
#   AUTOWP_INFERENCE_HOST           host running the server (default: the file)
#   AUTOWP_INFERENCE_PORT           its OpenAI-compatible port
#   AUTOWP_INFERENCE_SUBAGENT_PORT  a second server, used only by subagents
#   AUTOWP_INFERENCE_MODEL          model name as the server reports it
#   AUTOWP_INFERENCE_USER           container user whose config is written
#
# The written config addresses three failure modes seen with a single-slot
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
(
    set -eu
    set -o pipefail
    umask 022

    port=${AUTOWP_INFERENCE_PORT:-11434}
    subagent_port=${AUTOWP_INFERENCE_SUBAGENT_PORT:-11435}
    model=${AUTOWP_INFERENCE_MODEL:-qwen3.8:27b-mlx}
    user=${AUTOWP_INFERENCE_USER:-workshop}

    home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6) || home=
    home=${home:-/home/$user}
    conf="$home/.config/opencode/opencode.json"
    ip_file="$home/.local-llm-machine-ip.txt"

    if [ -e "$conf" ]; then
        # Kept, like every other pre-existing file auto-wp finds, so that a
        # `workshop refresh` never discards local edits. Checked before the
        # host is resolved: nothing is going to be written, so a missing
        # address is not a problem here.
        printf 'auto-wp: %s exists; left as it is\n' "$conf" >&2
    else
        # The project's existing convention for the local LLM host: one line,
        # the address only. An explicit environment variable still wins, for a
        # test run that needs a different host.
        host=${AUTOWP_INFERENCE_HOST:-}
        if [ -z "$host" ] && [ -r "$ip_file" ]; then
            host=$(sed -n '1{s/[[:space:]]//g; p; q;}' "$ip_file")
        fi
        if [ -z "$host" ]; then
            # Deliberately not an error: the file lives in the container's
            # home, which does not exist before this hook has run, so failing
            # here would leave no container in which to create it. Nothing is
            # written, so no configuration points at a guessed address.
            printf 'auto-wp: no local inference host: %s is %s.\n' "$ip_file" \
                "$([ -e "$ip_file" ] && echo 'empty or unreadable' || echo 'missing')" >&2
            printf 'auto-wp: create it with one line, the LLM host address, then run `workshop refresh`:\n' >&2
            printf 'auto-wp:   echo 192.0.2.10 > %s\n' "$ip_file" >&2
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
        "$model": { "name": "$model (local)" }
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
        "$model": { "name": "$model (subagent slot)" }
      }
    }
  },

  "agents": {
    "general": { "model": "ollama-sub/$model" },
    "explore": { "model": "ollama-sub/$model" }
  },

  "compaction": {
    "buffer": "50%",
    "keep": { "tokens": 24000 }
  },

  "model": "ollama/$model"
}
EOF
        chown -R "$user" "$home/.config" 2>/dev/null || true
        chmod 644 "$conf"
        printf 'auto-wp: wrote %s (local inference: %s:%s, subagents %s, from %s)\n' \
            "$conf" "$host" "$port" "$subagent_port" \
            "${AUTOWP_INFERENCE_HOST:+AUTOWP_INFERENCE_HOST}${AUTOWP_INFERENCE_HOST:-$ip_file}"
    fi
)

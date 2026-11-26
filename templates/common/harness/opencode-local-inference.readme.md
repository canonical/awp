<!-- Replaces the HARNESS_LOGIN section of opencode.md under
     --local-inference: there is no cloud account to connect, and what
     has to be true of the inference host takes its place. -->

<!-- HARNESS_LOGIN -->
**Local inference.** No login and no API key — but one file has to be in place before the first `workshop launch`.

The address of the LLM host comes from **`.local-llm-machine-ip.txt`**: one line, the address and nothing else, the same file the cross-provider judge uses (`skills/sl-auditor/SKILL.md`). Put it **in this directory**, which is mounted into the workshop:

```sh
echo 192.0.2.10 > .local-llm-machine-ip.txt
```

If `auto-wp.py` found the file on the machine that generated this project, it is already here. The container's own `~/.local-llm-machine-ip.txt` is read first and wins, but it cannot help on a *first* launch: there is nowhere to put it until the launch has created that home, so the copy in this directory is the one that works then.

With the file present, Workshop writes `~/.config/opencode/opencode.json` in the container as it launches, naming a local OpenAI-compatible provider, and `opencode` starts on that model. An existing config is kept, so your edits survive `workshop refresh`. Without the file **nothing is written** and the hook prints where it looked — an invented address is worse than none; create the file and `workshop refresh` to apply it.

Two servers must be reachable before a campaign starts: the main one on port 11434 and a second on 11435 that only subagents use, which is what stops a subagent evicting the parent's prompt cache. On the LLM host, with Ollama:

```sh
OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=2h ollama serve
OLLAMA_HOST=0.0.0.0:11435 OLLAMA_KEEP_ALIVE=2h ollama serve
```

Two things there are easy to get wrong. Give both servers the **same** context length and make it at least the window the configuration declares (`limit.context`, 120000 by default) — with Ollama, `OLLAMA_CONTEXT_LENGTH`. OpenCode sizes prompts against its own declared window, never the server's, so a smaller one truncates prompts with no error. And keep `OLLAMA_KEEP_ALIVE` longer than the gap between cycles: when a runner unloads it takes its prompt cache with it, and the next cycle reprocesses the whole context.

Every value the hook writes has an `AUTOWP_INFERENCE_*` override, each listed with its default and its reason in the comment block above the snippet in `.workshop/autowp-packages/hooks/setup-project`. A local model is slower than a cloud one: expect long turns, and check `opencode` is still advancing before assuming it has stalled.

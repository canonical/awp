---
name: directory-structure
description: >-
  A reference blueprint for laying out an AI-agent project so that agent
  capabilities (personas, tools, skills) are decoupled from the runtime
  framework/harness — swapping frameworks should touch only the harness layer.
  Defines the four layers (agents/personas = who the agent is, tools = atomic
  abilities with explicit IO schemas, skills = multi-step playbooks, harness =
  the framework-coupled engine), the separation rule for each, and best
  practices (declarative config over inline code, framework isolation,
  Jinja2 prompt templating). Use when the user asks how to structure or lay out
  an AI-agent project, where personas/tools/skills/harness code should live, how
  to keep an agent codebase framework-agnostic or harness-independent, or how to
  organize an agent repo for easy framework migration.
---

# Harness-Independent Agent Directory Structure

This document outlines the modern, production-grade directory layout for AI agents, specifically designed to decouple core agent capabilities (**Personas, Tools, and Skills**) from the underlying orchestration frameworks or runtimes (**Harnesses** like LangChain, AutoGen, CrewAI, or custom loops).

---

## 1. Directory Blueprint

```text
my-agent-project/
├── config/                      # All agent layers (agents/tools/skills/harness) + infra config
│   ├── telemetry.yaml           # Observability, logging, and tracing definitions
│   ├── agents/                  # The "Brain" Layer: Identity & Core Configuration
│   │   ├── personas/            # Pure declarative definitions of agent profiles
│   │   │   ├── researcher/
│   │   │   │   ├── config.yaml  # Model configs (temperature, max tokens, top_p)
│   │   │   │   └── system.md    # Static instructions, constraints, and worldview
│   │   │   └── writer/
│   │   │       ├── config.yaml
│   │   │       └── system.j2    # Dynamic Jinja2 prompt template for runtime injection
│   │   └── registry.py          # Framework-agnostic agent index and loader logic
│   │
│   ├── tools/                   # The "Hands" Layer: Atomic, idempotent execution blocks
│   │   ├── __init__.py          # Exports structural capability definitions (e.g., Pydantic)
│   │   ├── web_search.py        # Independent tool wrapper with explicit IO schemas
│   │   └── db_reader.py         # Data persistence interaction utility
│   │
│   ├── skills/                  # The "Playbook" Layer: High-level procedural workflows
│   │   └── code_audit/
│   │       ├── SKILL.md         # Narrative, multi-step orchestration guide for the LLM
│   │       ├── scripts/         # Local deterministic Python scripts execution support
│   │       └── assets/          # Static files, output formatting schemas, validation JSONs
│   │
│   └── harness/                 # The "Engine" Layer: The Runtime Orchestration
│       ├── main.py              # Framework execution boundary (LangGraph, CrewAI, Custom Loop)
│       └── guardrails.py        # Intercepting layer for routing, permissions, and safety

```

---

## 2. Component Demarcation

### A. Personas (`config/agents/personas/`)

* **Purpose:** Defines *who* the agent is, its boundaries, tone, and operational rules.
* **Separation Rule:** Absolutely zero executable orchestration code or framework-specific objects (`LangChain.Runnable`, etc.) are permitted here.
* **Modern Practice:** Use text formats (`.md`) or templating extensions (`.j2`). System prompts are treated as configuration artifacts rather than inline strings inside code files.

### B. Tools (`config/tools/`)

* **Purpose:** Atomic, fine-grained integrations that provide external capabilities (e.g., querying an API, reading a file, mutating state).
* **Separation Rule:** Tools must use primitive parameters or standard serialization layers like Pydantic models. They remain generic enough to be converted into an OpenAI tool call schema, an Anthropic tool schema, or a LangChain tool wrapper inside the harness layer.
* **Emerging Strategy:** Abstract these as **Model Context Protocol (MCP)** servers if sharing tools across multiple distinct applications is required.

### C. Skills (`config/skills/`)

* **Purpose:** Procedural knowledge graphs or structural multi-step guidelines designed to teach an LLM *how* to achieve a long-horizon objective.
* **Separation Rule:** Captures workflow intent. While a Tool provides raw ability (e.g., `execute_grep`), a Skill combines logic, sub-steps, evaluation metrics, and deterministic scripts (`config/skills/code_audit/scripts/`) into an integrated operational playbook.

### D. Harness (`config/harness/`)

* **Purpose:** The wrapper, engine, or application scaffold that drives execution. It handles token tracking, asynchronous execution, framework state machines, human-in-the-loop gates, and exception-retry flows.
* **Separation Rule:** This is the only folder tightly coupled to your framework of choice. If you migrate from a library-driven agent loop to a custom state machine, **only this folder should undergo code modification.**

---

## 3. Best Practices for Modern Implementations

1. **Declarative Configurations over Implicit Code:** Always store context models, retry backoffs, model temperatures, and instructions inside external structures (`.yaml`/`.json`/`.md`) rather than burying them in your core application loop.
2. **Framework Isolation:** Ensure your elements inside `config/tools/` and `config/skills/` are fully callable via pure Python. Test them through standard unit-testing packages (`pytest`) completely independently of an AI model wrapper.
3. **Dynamic Prompt Injections via Templates:** Utilize templating modules like Jinja2 (`.j2`) to build dynamic execution strings for the core persona. This abstracts runtime concerns (like inserting the present day's date or the user's explicit metadata context) out of the static persona structure.

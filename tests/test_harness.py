"""tests/lib/harness.sh: the input-prompt regex (tests.md 5.5).

Claude Code 2.1.3xx draws its prompt as "❯" followed by a no-break space
(U+00A0). A regex with a plain space there makes harness_start time out with
Claude Code ready, so every campaign fails its first check (G.1, S.1). The
character is easy to lose in an edit, hence this test.
"""
import os
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def prompt_re(harness):
    script = (
        '. tests/lib/lxc.sh >/dev/null 2>&1; HARNESS=%s; '
        '. tests/lib/harness.sh >/dev/null 2>&1; printf %%s "$HARNESS_PROMPT_RE"'
        % harness
    )
    env = {k: v for k, v in os.environ.items() if k != "HARNESS_PROMPT_RE"}
    return subprocess.run(["bash", "-c", script], cwd=REPO, env=env,
                          capture_output=True, text=True, check=True).stdout


def grep(regex, line):
    r = subprocess.run(["grep", "-qE", regex], input=line + "\n", text=True,
                       env=dict(os.environ, LC_ALL="C.UTF-8"))
    return r.returncode == 0


class ClaudePrompt(unittest.TestCase):
    def setUp(self):
        self.re = prompt_re("claude")

    def test_no_break_space(self):
        self.assertTrue(grep(self.re, '❯ Try "how does <filepath> work?"'))

    def test_plain_space(self):
        self.assertTrue(grep(self.re, "> hello"))
        self.assertTrue(grep(self.re, "│ ❯ "))

    def test_shortcuts_hint(self):
        self.assertTrue(grep(self.re, "  ? for shortcuts"))

    def test_rejects_text(self):
        self.assertFalse(grep(self.re, "Running unlzw baseline WP"))


if __name__ == "__main__":
    unittest.main()

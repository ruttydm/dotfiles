"""python3 -m unittest discover -s tests"""
import importlib.machinery
import importlib.util
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name, rel):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / rel))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


ntfy = load("ginger_ntfy_desktop", "ginger/.local/bin/ginger-ntfy-desktop")
menu = load("ginger_menu", "ginger/.local/bin/ginger-menu")
names = load("agent_usage_names", "omarchy/.local/bin/omarchy-agent-usage-names")


def omarchy_jsonc(text):
    """What Omarchy's MenuModel.stripJsonc + JSON.parse make of the file."""
    stripped = re.sub(r"^\s*//[^\n]*(\n|$)", "", text, flags=re.M)
    stripped = re.sub(r",(\s*[}\]])", r"\1", stripped)
    return json.loads(stripped)


class NtfyTest(unittest.TestCase):
    def test_priority_to_urgency(self):
        self.assertEqual([ntfy.urgency(p) for p in (1, 2, 3, 4, 5, None, "x")],
                         ["low", "low", "normal", "normal", "critical", "normal", "normal"])

    def test_click_url_waits_for_the_default_action(self):
        args = ntfy.notify_args({"title": "CI", "message": "a < b & c", "priority": 5,
                                 "click": "https://nomad.rz.afai.cc"})
        self.assertEqual(args, ["notify-send", "--app-name=ntfy", "--urgency=critical",
                                "--action=default=Open", "--wait", "--", "CI", "a &lt; b &amp; c"])

    def test_view_action_is_a_click_url_and_other_schemes_are_not(self):
        self.assertEqual(ntfy.click_url({"actions": [{"action": "view", "url": "https://x.test/"}]}),
                         "https://x.test/")
        self.assertEqual(ntfy.click_url({"click": "file:///etc/passwd"}), "")

    def test_no_url_no_wait(self):
        args = ntfy.notify_args({"message": "hi", "topic": "rutger"})
        self.assertNotIn("--wait", args)
        self.assertEqual(args[-2:], ["ntfy · rutger", "hi"])

    def test_since_resumes_by_id_within_the_backlog(self):
        now = 1_800_000_000
        self.assertEqual(ntfy.since_param({}, now), str(now))
        self.assertEqual(ntfy.since_param({"id": "abc", "time": now - 60}, now), "abc")
        self.assertEqual(ntfy.since_param({"id": "abc", "time": now - 86400}, now),
                         str(now - ntfy.MAX_BACKLOG))


PROJECTS = [
    {"name": "nomad", "box": "rz", "url": "https://nomad.rz.afai.cc", "stack": "laravel", "worktree_of": None},
    {"name": "nomad-wt", "box": "rz", "url": "https://nomad-wt.rz.afai.cc", "stack": "laravel",
     "worktree_of": "nomad"},
    {"name": "Helion", "box": "pi", "url": "https://helion.pi.afai.cc", "stack": "none", "worktree_of": None},
    {"name": "tools", "box": "pi", "url": "", "stack": "none", "worktree_of": None},
    {"name": "it's", "box": "tp", "url": "https://its.tp.afai.cc", "framework": "astro", "worktree_of": None},
]


class MenuTest(unittest.TestCase):
    def test_only_served_main_checkouts_sorted_by_box(self):
        self.assertEqual([(p["box"], p["name"]) for p in menu.projects(PROJECTS)],
                         [("rz", "nomad"), ("pi", "Helion"), ("tp", "it's")])

    def test_block_parses_and_is_replaced_in_place(self):
        user = '{\n  // my notes\n  "personal": {"label":"Personal","action":"xdg-open https://example.com"}\n}\n'
        once = menu.splice(user, menu.block(menu.projects(PROJECTS), 1_800_000_000))
        items = omarchy_jsonc(once)
        self.assertIn("personal", items)
        self.assertEqual(items["ginger.rz.nomad"]["action"], "xdg-open https://nomad.rz.afai.cc")
        self.assertEqual(items["ginger.tp.it-s"]["action"], "xdg-open https://its.tp.afai.cc")
        self.assertEqual(items["ginger.pi.helion"]["description"], "helion.pi.afai.cc")
        self.assertEqual(items["ginger.term-pi"]["action"], "omarchy-launch-terminal rpi")
        self.assertEqual(menu.splice(once, menu.block(menu.projects(PROJECTS), 1_800_000_000)), once)
        fewer = menu.splice(once, menu.block([], None))
        self.assertNotIn("ginger.rz.nomad", omarchy_jsonc(fewer))
        self.assertIn("personal", omarchy_jsonc(fewer))

    def test_comment_only_and_missing_files(self):
        omarchy_jsonc(menu.splice("{\n  // only comments\n}\n", menu.block([], None)))
        omarchy_jsonc(menu.splice("", menu.block([], None)))


class UsageNamesTest(unittest.TestCase):
    def test_already_short_writes_nothing(self):
        self.assertIsNone(names.patched('{"id":"claude","name":"Claude"}'))
        self.assertEqual(names.patched('{"id":"claude","name":"Claude Code"}'), '{"id":"claude","name":"Claude"}')


if __name__ == "__main__":
    unittest.main()

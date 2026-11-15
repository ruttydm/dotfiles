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


NOW = 1_800_000_000


def push(**kw):
    msg = {"event": "message", "id": kw.pop("id", "m1"), "time": NOW, "title": "CI", "message": "red", "priority": 3}
    msg.update(kw)
    return msg


class NtfyTest(unittest.TestCase):
    CONF = ntfy.parse_conf("")

    def test_only_high_priority_shows_by_default(self):
        gate = ntfy.Gate()
        self.assertEqual(gate.verdict(push(id="a", priority=3), self.CONF, NOW), "priority 3")
        self.assertEqual(gate.verdict(push(id="b", priority=4), self.CONF, NOW), "show")
        self.assertEqual(gate.verdict(push(id="c", priority=1, title="x", tags=["desktop"]), self.CONF, NOW), "show")

    def test_threshold_is_one_setting(self):
        conf = ntfy.parse_conf("# show default pushes too\nmin_priority = 3\n")
        self.assertEqual(ntfy.Gate().verdict(push(priority=3), conf, NOW), "show")
        self.assertEqual(ntfy.min_priority(ntfy.parse_conf("min_priority=9")), 5)

    def test_duplicates_replays_and_stale_pushes_are_suppressed(self):
        gate = ntfy.Gate()
        self.assertEqual(gate.verdict(push(id="a", priority=5), self.CONF, NOW), "show")
        self.assertEqual(gate.verdict(push(id="a", priority=5), self.CONF, NOW + 1), "replay")
        self.assertEqual(gate.verdict(push(id="b", priority=5), self.CONF, NOW + 300), "duplicate")
        self.assertEqual(gate.verdict(push(id="c", priority=5), self.CONF, NOW + 700), "show")
        self.assertEqual(gate.verdict(push(id="d", priority=5, title="old", time=NOW - 7200), self.CONF, NOW + 700),
                         "stale")

    def test_click_url_waits_for_the_default_action(self):
        msg = push(priority=5, message="a < b & c", click="https://nomad.rz.afai.cc")
        self.assertEqual(ntfy.notify_args(msg, wait=True),
                         ["notify-send", "--app-name=ntfy", "--urgency=critical",
                          "--action=default=Open", "--wait", "--", "CI", "a &lt; b &amp; c"])
        self.assertEqual(ntfy.click_url({"actions": [{"action": "view", "url": "https://x.test/"}]}),
                         "https://x.test/")
        self.assertEqual(ntfy.click_url({"click": "file:///etc/passwd"}), "")

    def test_since_resumes_after_the_last_message(self):
        self.assertEqual(ntfy.since_param({}, NOW), str(NOW))
        self.assertEqual(ntfy.since_param({"id": "abc", "time": NOW - 60}, NOW), "abc")
        self.assertEqual(ntfy.since_param({"id": "abc", "time": NOW - 86400}, NOW), str(NOW - ntfy.MAX_BACKLOG))


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

    def test_unreachable_box_keeps_its_cached_rows(self):
        previous = [{"name": "old", "box": "tp", "url": "https://old.tp.afai.cc"},
                    {"name": "gone", "box": "rz", "url": "https://gone.rz.afai.cc"}]
        real, menu.dev_ls = menu.dev_ls, lambda cmd, timeout: [p for p in PROJECTS if p["box"] != "tp"]
        try:
            names = sorted(p["name"] for p in menu.fetch(previous))
        finally:
            menu.dev_ls = real
        self.assertIn("old", names)
        self.assertNotIn("gone", names)

    def test_guard_is_always_true_and_names_the_refresh(self):
        g = menu.guard()
        self.assertTrue(g.rstrip().endswith("; true"))
        self.assertIn("setsid -f", g)
        self.assertIn(str(menu.STALE_SECONDS), g)

    def test_comment_only_and_missing_files(self):
        omarchy_jsonc(menu.splice("{\n  // only comments\n}\n", menu.block([], None)))
        omarchy_jsonc(menu.splice("", menu.block([], None)))


class UsageNamesTest(unittest.TestCase):
    def test_already_short_writes_nothing(self):
        self.assertIsNone(names.patched('{"id":"claude","name":"Claude"}'))
        self.assertEqual(names.patched('{"id":"claude","name":"Claude Code"}'), '{"id":"claude","name":"Claude"}')


if __name__ == "__main__":
    unittest.main()

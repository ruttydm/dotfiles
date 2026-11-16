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
names = load("agent_usage_names", "omarchy/.local/bin/omarchy-agent-usage-names")



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


class UsageNamesTest(unittest.TestCase):
    def test_already_short_writes_nothing(self):
        self.assertIsNone(names.patched('{"id":"claude","name":"Claude"}'))
        self.assertEqual(names.patched('{"id":"claude","name":"Claude Code"}'), '{"id":"claude","name":"Claude"}')


if __name__ == "__main__":
    unittest.main()

"""python3 -m unittest discover -s tests"""
import importlib.machinery
import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "omarchy/.local/bin/omarchy-tailnet-stats"
loader = importlib.machinery.SourceFileLoader("tailnet_stats", str(SCRIPT))
spec = importlib.util.spec_from_loader("tailnet_stats", loader)
ts = importlib.util.module_from_spec(spec)
loader.exec_module(ts)

GOOD = {"v": 1, "uptime_s": 60, "cpu": {"pct": 12.5, "cores": 4}, "load": [0.5, 0.4, 0.3],
        "mem": {"total": 8000, "available": 6000}, "swap": {"total": 0, "free": 0},
        "disk": {"total": 100, "used": 40}, "temp_c": 51.2}

STATUS = {
    "BackendState": "Running",
    "Self": {"HostName": "laptop", "DNSName": "laptop.tail.ts.net.", "OS": "linux",
             "TailscaleIPs": ["100.0.0.1"], "Online": False},
    "Peer": {
        "k1": {"HostName": "pi", "DNSName": "pi.tail.ts.net.", "OS": "linux", "TailscaleIPs": ["100.0.0.2"],
               "Online": True},
        "k2": {"HostName": "phone", "DNSName": "phone.tail.ts.net.", "OS": "iOS", "TailscaleIPs": ["100.0.0.3"],
               "Online": True},
        "k3": {"HostName": "Some Mac", "DNSName": "mac.tail.ts.net.", "OS": "macOS", "TailscaleIPs": ["100.0.0.4"],
               "Online": False, "LastSeen": "2026-11-09T10:00:00Z"},
        "k4": {"HostName": "se-sto-wg-001", "OS": "linux", "TailscaleIPs": ["100.0.0.5"], "Online": True,
               "Location": {"Country": "Sweden"}},
        "k5": {"HostName": "web-1", "DNSName": "web-1.tail.ts.net.", "OS": "linux", "TailscaleIPs": ["100.0.0.6"],
               "Online": True, "Tags": ["tag:server"]},
        "k6": {"HostName": "box2", "DNSName": "box2.tail.ts.net.", "OS": "linux", "TailscaleIPs": ["100.0.0.7"],
               "Online": False},
    },
}
BOXES = {"100.0.0.1": {"name": "tp", "domain": "tp.example.cc"},
         "100.0.0.2": {"name": "pi", "domain": "pi.example.cc"},
         "100.0.0.7": {"name": "b2", "domain": "b2.example.cc"}}


class CollectTests(unittest.TestCase):
    def setUp(self):
        self.fetched = []

    def fetch(self, url):
        self.fetched.append(url)
        return ts.clean_stats(GOOD), ""

    def test_devices_groups_and_fetches(self):
        out = ts.collect(STATUS, BOXES, {"tag:server"}, fetch=self.fetch, local=lambda: GOOD)
        names = [(d["group"], d["name"]) for d in out["devices"]]
        self.assertEqual(names, [("server", "web-1"), ("dev", "tp"), ("dev", "pi"), ("dev", "b2"),
                                 ("other", "Some Mac")])
        # phones and Mullvad nodes are left out; only online boxes other than this one are fetched
        self.assertEqual(self.fetched, ["https://pi.example.cc/stats.json"])
        me = out["devices"][1]
        self.assertTrue(me["self"] and me["online"])
        self.assertEqual(me["url"], "https://tp.example.cc")
        self.assertEqual(me["stats"]["cpu"], 12.5)
        mac = out["devices"][-1]
        self.assertEqual(mac["lastSeen"], 1794218400)
        self.assertNotIn("statsUrl", mac)

    def test_fetch_failure_is_reported_not_raised(self):
        def boom(url):
            raise RuntimeError("x")
        out = ts.collect(STATUS, BOXES, {"tag:server"}, fetch=boom, local=lambda: GOOD)
        pi = next(d for d in out["devices"] if d["name"] == "pi")
        self.assertIsNone(pi["stats"])
        self.assertEqual(pi["error"], "RuntimeError")


class ValidationTests(unittest.TestCase):
    def test_clean_stats_rejects_and_clamps(self):
        self.assertIsNone(ts.clean_stats({"v": 2}))
        self.assertIsNone(ts.clean_stats({**GOOD, "cpu": {"pct": "50"}}))
        self.assertIsNone(ts.clean_stats({**GOOD, "cpu": {"pct": 150}}))
        self.assertIsNone(ts.clean_stats({**GOOD, "cpu": {"pct": True}}))
        clamped = ts.clean_stats({**GOOD, "mem": {"total": 100, "available": 900}})
        self.assertEqual(clamped["memAvailable"], 100)
        self.assertEqual(ts.clean_stats({**GOOD, "load": [1, "x", float("nan"), 2]})["load"], [1])

    def test_safe_name(self):
        self.assertEqual(ts.safe_name("Rutger’s MacBook Pro"), "Rutger’s MacBook Pro")
        self.assertEqual(ts.safe_name("<b>x</b>", "device"), "device")

    def test_load_boxes(self):
        d = Path(tempfile.mkdtemp())
        f = d / "boxes.toml"
        f.write_text('[boxes.pi]\ntailscale_ip = "100.0.0.2"\ndomain = "pi.example.cc"\n'
                     '[boxes.bad]\ntailscale_ip = "100.0.0.9"\ndomain = "evil.cc/x?"\n'
                     '[boxes.nodomain]\ntailscale_ip = "100.0.0.8"\n')
        self.assertEqual(ts.load_boxes(f), {"100.0.0.2": {"name": "pi", "domain": "pi.example.cc"}})
        self.assertEqual(ts.load_boxes(None), {})

    def test_local_stats_shape(self):
        stats = ts.clean_stats(ts.local_stats(sample=0.05))
        self.assertIsNotNone(stats)
        self.assertGreater(stats["memTotal"], 0)


if __name__ == "__main__":
    unittest.main()

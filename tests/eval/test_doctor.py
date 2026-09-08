"""Exercise diagnostic failures and the boundary around command output."""
import importlib.util
import copy
import errno
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

source = pathlib.Path(__file__).parents[2] / "modules/vpn-confinement/doctor.py"
spec = importlib.util.spec_from_file_location("doctor", source)
doctor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doctor)


class DoctorTests(unittest.TestCase):
    def test_policy_comparison_ignores_handles_and_counters_but_not_verdicts(self):
        original = {"nftables": [
            {"metainfo": {"version": "1"}},
            {"chain": {"family": "inet", "table": "vpnc", "name": "output",
                        "type": "filter", "hook": "output", "policy": "drop", "handle": 1}},
            {"rule": {"chain": "output", "handle": 2,
                        "expr": [{"counter": {"packets": 5, "bytes": 300}}, {"drop": None}]}}
        ]}
        changed = copy.deepcopy(original)
        changed["nftables"][0]["metainfo"]["version"] = "2"
        changed["nftables"][1]["chain"]["handle"] = 20
        changed["nftables"][2]["rule"]["expr"][0]["counter"]["packets"] = 50
        self.assertEqual(doctor.normalized_policy(original), doctor.normalized_policy(changed))
        changed["nftables"][2]["rule"]["expr"][1] = {"accept": None}
        self.assertNotEqual(doctor.normalized_policy(original), doctor.normalized_policy(changed))
        with tempfile.TemporaryDirectory() as directory:
            snapshot = pathlib.Path(directory) / "policy.json"
            snapshot.write_text(json.dumps(original))
            self.assertTrue(doctor.policy_matches(original, snapshot))
            self.assertFalse(doctor.policy_matches(changed, snapshot))

    def test_missing_peers_and_routes_are_not_reported_as_ready(self):
        expected = {"endpointPinning": False, "services": [], "sockets": [], "interface": "wg0"}
        table = {"nftables": [{"chain": {"name": n, "policy": "drop"}}
                                for n in ("input", "output", "forward")]}
        with (
            patch.object(doctor.Path, "exists", return_value=True),
            patch.object(doctor, "json_command", side_effect=[[], [], table]),
            patch.object(doctor, "command", return_value=""),
        ):
            report = doctor.inspect("test", expected)
        self.assertFalse(report["defaultDropChainsPresent"])
        self.assertFalse(report["policyMatchesConfiguration"])
        self.assertIn("no WireGuard peers installed", report["issues"])
        self.assertIn("no usable route through the configured WireGuard interface", report["issues"])

    def test_loaded_host_activation_socket_is_reported(self):
        expected = {"endpointPinning": False, "services": ["app"], "sockets": [], "interface": "wg0"}
        def props(unit):
            if unit == "app.service":
                return {"NetworkNamespacePath": "/run/netns/test", "MainPID": "0",
                        "TriggeredBy": "packaged.socket"}
            return {"NetworkNamespacePath": ""}
        with (
            patch.object(doctor.Path, "exists", return_value=False),
            patch.object(doctor, "properties", side_effect=props),
        ):
            report = doctor.inspect("test", expected)
        self.assertIn("packaged.socket: unexpected or unreadable namespace path", report["issues"])

    def test_changed_allowed_ips_are_reported(self):
        expected = {"endpointPinning": False, "services": [], "sockets": [], "interface": "wg0",
                    "peers": [{"keyHash": doctor.hashlib.sha256(b"peer").hexdigest(),
                                "allowedIPs": ["0.0.0.0/0"]}]}
        with (
            patch.object(doctor.Path, "exists", return_value=True),
            patch.object(doctor, "json_command", side_effect=[[], [], {}]),
            patch.object(doctor, "command", side_effect=["peer 0", "peer 10.0.0.0/8"]),
        ):
            report = doctor.inspect("test", expected)
        self.assertIn("installed WireGuard allowed IPs do not match configuration", report["issues"])
        self.assertNotIn("installed WireGuard peers do not match configuration", report["issues"])

    def test_policy_rule_order_is_significant(self):
        first = {"nftables": [{"rule": {"chain": "output", "expr": [{verdict: None}]}}
                                for verdict in ("drop", "accept")]}
        second = {"nftables": list(reversed(first["nftables"]))}
        self.assertNotEqual(doctor.normalized_policy(first), doctor.normalized_policy(second))

    def test_absolute_resolver_symlinks_stay_inside_process_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory) / "root"
            (root / "etc").mkdir(parents=True)
            (root / "run").mkdir()
            (root / "run/resolver").write_text("nameserver 10.0.0.1\n")
            (root / "etc/resolv.conf").symlink_to("/run/resolver")
            self.assertEqual(doctor.read_rooted(root, "/etc/resolv.conf"), "nameserver 10.0.0.1\n")
            (root / "etc/resolv.conf").unlink()
            (root / "etc/resolv.conf").symlink_to("../../outside")
            (root / "outside").write_text("inside")
            (pathlib.Path(directory) / "outside").write_text("outside")
            self.assertEqual(doctor.read_rooted(root, "/etc/resolv.conf"), "inside")

    def test_rooted_reads_retry_only_transient_containment_races(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "resolver"
            path.write_text("inside")
            real_libc = doctor.ctypes.CDLL(None, use_errno=True)
            real_libc.syscall.restype = doctor.ctypes.c_long
            for failures, expected, calls in (
                ([errno.EAGAIN], "inside", 2),
                ([errno.EAGAIN, errno.EAGAIN], "inside", 3),
                ([errno.EAGAIN] * 3, None, 3),
                ([errno.EXDEV], None, 1),
                ([errno.ELOOP], None, 1),
                ([errno.ENOENT], None, 1),
            ):
                with self.subTest(failures=failures):
                    errors = iter(failures)
                    def syscall(*args):
                        error = next(errors, None)
                        if error is not None:
                            doctor.ctypes.set_errno(error)
                            return -1
                        return real_libc.syscall(*args)
                    with patch.object(doctor.ctypes, "CDLL") as library:
                        library.return_value.syscall.side_effect = syscall
                        self.assertEqual(doctor.read_rooted(directory, "/resolver"), expected)
                        self.assertEqual(library.return_value.syscall.call_count, calls)

    def test_process_root_reads_reject_magic_links_and_fifos(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "fifo"
            doctor.os.mkfifo(path)
            self.assertIsNone(doctor.read_rooted(directory, "fifo"))
            with tempfile.TemporaryFile() as stream:
                self.assertIsNone(doctor.read_rooted("/", f"/proc/self/fd/{stream.fileno()}"))

    def test_service_file_reads_are_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "resolv.conf"
            path.write_text("x" * 100)
            self.assertIsNone(doctor.read_text(path, limit=10))
            self.assertEqual(doctor.read_text(path, limit=100), "x" * 100)

    def test_rejected_service_files_do_not_leak_descriptors(self):
        def open_descriptors():
            # listdir closes its own directory descriptor before we inspect the entries.
            return {name for name in os.listdir("/proc/self/fd")
                    if os.path.islink(f"/proc/self/fd/{name}")}

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "directory").mkdir()
            (root / "invalid-utf8").write_bytes(b"\xff")
            (root / "oversized").write_text("x" * 100)
            os.mkfifo(root / "fifo")
            for name in ("directory", "invalid-utf8", "oversized", "fifo"):
                for rooted in (False, True):
                    with self.subTest(name=name, rooted=rooted):
                        before = open_descriptors()
                        try:
                            if rooted:
                                result = doctor.read_rooted(root, name, limit=10)
                            else:
                                result = doctor.read_text(root / name, limit=10)
                            self.assertIsNone(result)
                            self.assertEqual(open_descriptors(), before)
                        finally:
                            # Release leaks from a failing implementation so later cases stay independent.
                            for descriptor in open_descriptors() - before:
                                os.close(int(descriptor))

    def test_failed_command_does_not_return_stderr(self):
        result = subprocess.CompletedProcess([], 1, stdout="secret", stderr="private-key=secret")
        with patch.object(doctor.subprocess, "run", return_value=result):
            self.assertIsNone(doctor.command(["tool"]))

    def test_only_allowlisted_systemd_properties_are_returned(self):
        with patch.object(doctor, "command", return_value="User=app\nEnvironment=TOKEN=secret\nMainPID=0"):
            self.assertEqual(doctor.properties("app.service"), {"User": "app", "MainPID": "0"})

    def test_missing_namespace_is_not_reported_as_healthy(self):
        expected = {"endpointPinning": False, "services": [], "sockets": [], "interface": "wg0"}
        with patch.object(doctor.Path, "exists", return_value=False):
            report = doctor.inspect("missing", expected)
        self.assertFalse(report["defaultDropChainsPresent"])
        self.assertIn("namespace missing", report["issues"])
        self.assertEqual(report["reachability"], "not probed")

    def test_unexpected_route_is_reported_without_querying_secrets(self):
        expected = {"endpointPinning": False, "services": [], "sockets": [], "interface": "wg0"}
        table = {"nftables": [{"chain": {"name": n, "policy": "drop"}} for n in ("input", "output", "forward")]}
        with (
            patch.object(doctor.Path, "exists", return_value=True),
            patch.object(doctor, "json_command", side_effect=[[{"dst": "default", "dev": "eth0"}], [], table]),
            patch.object(doctor, "command", return_value="peer-public-key 0") as command,
        ):
            report = doctor.inspect("test", expected)
        self.assertIn("default route does not use the configured WireGuard interface", report["issues"])
        self.assertEqual(report["handshakeAgesSeconds"], [None])
        self.assertEqual(command.call_args.args[0][-1], "latest-handshakes")
        self.assertNotIn("peer-public-key", str(report))

    def test_missing_wireguard_interface_is_reported(self):
        expected = {"endpointPinning": False, "services": [], "sockets": [], "interface": "wg0"}
        table = {"nftables": [{"chain": {"name": n, "policy": "drop"}} for n in ("input", "output", "forward")]}
        with (
            patch.object(doctor.Path, "exists", return_value=True),
            patch.object(doctor, "json_command", side_effect=[[], [], table]),
            patch.object(doctor, "command", return_value=None),
        ):
            report = doctor.inspect("test", expected)
        self.assertIn("WireGuard interface missing or unreadable", report["issues"])


if __name__ == "__main__":
    unittest.main()

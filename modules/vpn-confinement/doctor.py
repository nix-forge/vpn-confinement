"""Local, read-only diagnostics. Never query WireGuard private keys or perform Internet probes."""
import argparse
import ctypes
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time

MANIFEST = "@manifest@"
IP, NFT, WG, SYSTEMCTL = "@ip@", "@nft@", "@wg@", "@systemctl@"
PROPERTIES = (
    "ActiveState", "SubState", "MainPID", "NetworkNamespacePath", "User",
    "DynamicUser", "CapabilityBoundingSet", "AmbientCapabilities",
    "NoNewPrivileges", "RestrictNetworkInterfaces", "RestrictAddressFamilies",
    "TriggeredBy", "Sockets",
)


def command(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    # Errors can contain paths or arbitrary provider output. Do not print them.
    return result.stdout.strip() if result.returncode == 0 else None


def json_command(args):
    output = command(args)
    try:
        return json.loads(output) if output is not None else None
    except ValueError:
        return None


def properties(unit):
    value = command([SYSTEMCTL, "show", unit, "--no-pager", *[f"--property={p}" for p in PROPERTIES]])
    if value is None:
        return {}
    allowed = set(PROPERTIES)
    return {k: v for line in value.splitlines() if "=" in line
            for k, v in [line.split("=", 1)] if k in allowed}


def read_fd(fd, limit):
    """Read a borrowed descriptor; its opener remains responsible for closing it."""
    try:
        with os.fdopen(fd, "r", closefd=False) as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                return None
            value = stream.read(limit + 1)
            return value if len(value) <= limit else None
    except (OSError, UnicodeError):
        return None


def read_text(path, limit=65536):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
        try:
            return read_fd(fd, limit)
        finally:
            os.close(fd)
    except OSError:
        return None


class OpenHow(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in ("flags", "mode", "resolve")]


def read_rooted(root, path, limit=65536):
    """Resolve absolute symlinks inside a process root, never back on the host."""
    # openat2 is syscall 437 on the supported x86_64 and aarch64 Linux ABIs.
    # Do not fall back to an ordinary open: that would use the caller's root
    # for absolute symlinks. Require Linux >= 5.6 and reject magic links.
    if sys.platform != "linux" or os.uname().machine not in ("x86_64", "aarch64") or "\0" in path:
        return None
    try:
        root_fd = os.open(root, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            how = OpenHow(os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC, 0, 0x10 | 0x02)
            libc = ctypes.CDLL(None, use_errno=True)
            libc.syscall.restype = ctypes.c_long
            fd = libc.syscall(ctypes.c_long(437), ctypes.c_int(root_fd),
                                ctypes.c_char_p(os.fsencode(path)), ctypes.byref(how),
                                ctypes.c_size_t(ctypes.sizeof(how)))
        finally:
            os.close(root_fd)
        if fd < 0:
            return None
        try:
            return read_fd(fd, limit)
        finally:
            os.close(fd)
    except OSError:
        return None


def normalized_policy(table):
    """Ignore nft bookkeeping while retaining rule order and every expression."""
    if not isinstance(table, dict) or not isinstance(table.get("nftables"), list):
        return None

    def clean(value):
        if isinstance(value, dict):
            return {k: (None if k == "counter" else clean(v))
                    for k, v in value.items() if k != "handle"}
        if isinstance(value, list):
            return [clean(v) for v in value]
        return value

    objects, rules = [], {}
    for item in table["nftables"]:
        if not isinstance(item, dict):
            return None
        if "metainfo" in item:
            continue
        item = clean(item)
        if "rule" in item:
            rules.setdefault(item["rule"].get("chain", ""), []).append(item)
        else:
            if "set" in item and isinstance(item["set"].get("elem"), list):
                item["set"]["elem"].sort(key=lambda x: json.dumps(x, sort_keys=True))
            objects.append(item)
    return {"objects": sorted(objects, key=lambda x: json.dumps(x, sort_keys=True)), "rules": rules}


def policy_matches(table, snapshot):
    if not snapshot:
        return False
    text = read_text(snapshot, limit=2 * 1024 * 1024)
    try:
        trusted = normalized_policy(json.loads(text)) if text is not None else None
    except (ValueError, TypeError):
        return False
    return trusted is not None and trusted == normalized_policy(table)


def inspect(name, expected):
    issues = []
    warnings = list(expected.get("namespaceWarnings", []))
    prefix = [IP, "netns", "exec", name]
    ns_path = Path("/run/netns") / name
    exists = ns_path.exists()
    routes = json_command(prefix + [IP, "-j", "route", "show", "table", "all"]) if exists else None
    routes6 = json_command(prefix + [IP, "-6", "-j", "route", "show", "table", "all"]) if exists else None
    table = json_command(prefix + [NFT, "--json", "--stateless", "list", "table", "inet", "vpnc"]) if exists else None
    chains = {
        entry["chain"]["name"]: entry["chain"]
        for entry in (table or {}).get("nftables", []) if "chain" in entry
    }
    drop_chains = all(chains.get(c, {}).get("policy") == "drop"
                        and chains.get(c, {}).get("hook") == c
                        and chains.get(c, {}).get("type") == "filter"
                        for c in ("input", "output", "forward"))
    policy_match = policy_matches(table, expected.get("policySnapshot"))
    if not exists:
        issues.append("namespace missing")
    if not drop_chains:
        issues.append("cannot verify installed default-drop chains")
    if not policy_match:
        issues.append("installed firewall differs from the applied configuration or its snapshot is missing")
    if routes is None or routes6 is None:
        issues.append("cannot inspect routes")
    for route in (routes or []) + (routes6 or []):
        if route.get("dst") == "default" and route.get("dev") != expected["interface"]:
            issues.append("default route does not use the configured WireGuard interface")
    if not any(r.get("dev") == expected["interface"] and r.get("type", "unicast") == "unicast"
                for r in (routes or []) + (routes6 or [])):
        issues.append("no usable route through the configured WireGuard interface")
    handshake_output = command(prefix + [WG, "show", expected["interface"], "latest-handshakes"]) if exists else None
    if handshake_output is None:
        issues.append("WireGuard interface missing or unreadable")
    ages = []
    peer_hashes = []
    for line in (handshake_output or "").splitlines():
        columns = line.split()
        if len(columns) == 2 and columns[1].isdigit():
            peer_hashes.append(hashlib.sha256(columns[0].encode()).hexdigest())
            stamp = int(columns[1])
            ages.append(max(0, int(time.time()) - stamp) if stamp else None)
    if not peer_hashes:
        issues.append("no WireGuard peers installed")
    if "peers" in expected and sorted(peer_hashes) != sorted(p["keyHash"] for p in expected["peers"]):
        issues.append("installed WireGuard peers do not match configuration")
    if "peers" in expected:
        allowed_output = command(prefix + [WG, "show", expected["interface"], "allowed-ips"]) if exists else None
        try:
            def networks(values):
                return sorted(str(ipaddress.ip_network(value, strict=False)) for value in values if value != "(none)")
            installed = {}
            for line in (allowed_output or "").splitlines():
                key, *cidrs = line.split()
                installed[hashlib.sha256(key.encode()).hexdigest()] = networks(cidrs)
            configured = {p["keyHash"]: networks(p["allowedIPs"]) for p in expected["peers"]}
            if allowed_output is None or installed != configured:
                issues.append("installed WireGuard allowed IPs do not match configuration")
        except ValueError:
            issues.append("cannot verify WireGuard allowed IPs")
    pin_installed = None
    pin_match = None
    if expected["endpointPinning"]:
        birthplace = expected["socketNamespace"]
        outer = [] if birthplace in (None, "init") else [IP, "netns", "exec", birthplace]
        pin_table = json_command(outer + [NFT, "--json", "--stateless", "list", "table", "inet", expected["endpointTable"]])
        pin_installed = pin_table is not None
        pin_match = policy_matches(pin_table, expected.get("endpointSnapshot"))
        if not pin_installed:
            issues.append("endpoint-pinning table missing or unreadable")
        if not pin_match:
            issues.append("endpoint-pinning policy differs from the applied configuration or its snapshot is missing")
    services = {}
    inherited_sockets = set()
    for service in expected["services"]:
        unit = properties(service + ".service")
        inherited_sockets.update(s for field in ("TriggeredBy", "Sockets")
                                    for s in unit.get(field, "").split() if s.endswith(".socket"))
        pid = unit.get("MainPID", "0")
        attached = None
        resolvers = None
        if pid.isdigit() and int(pid) > 0:
            try:
                attached = os.stat(f"/proc/{pid}/ns/net").st_ino == ns_path.stat().st_ino
                resolver_text = read_rooted(f"/proc/{pid}/root", "/etc/resolv.conf") or ""
                resolvers = [
                    line.split()[1] for line in resolver_text.splitlines()
                    if line.startswith("nameserver ") and len(line.split()) > 1
                ]
            except (OSError, UnicodeError):
                # Keep unknown state so the checks below report the failed inspection.
                pass
            if attached is not True:
                issues.append(f"{service}: cannot verify process namespace attachment")
            if expected["dns"]["mode"] == "strict" and resolvers != expected["dns"]["servers"]:
                issues.append(f"{service}: resolver configuration missing or unexpected")
        if unit.get("NetworkNamespacePath") != str(ns_path):
            issues.append(f"{service}: unexpected unit namespace path")
        if not unit:
            issues.append(f"{service}: cannot inspect unit")
        for warning in expected.get("serviceWarnings", {}).get(service, []):
            warnings.append(f"{service}: {warning}")
        caps = (unit.get("CapabilityBoundingSet", "") + " " + unit.get("AmbientCapabilities", "")).upper().split()
        if any(c in caps for c in ("CAP_NET_ADMIN", "CAP_SYS_ADMIN", "CAP_NET_RAW")):
            warnings.append(f"{service}: effective capabilities can bypass confinement")
        services[service] = {"unit": unit, "processAttached": attached, "resolvers": resolvers}
    socket_names = set(expected["sockets"]) | {s.removesuffix(".socket") for s in inherited_sockets}
    sockets = {s: properties(s + ".socket") for s in sorted(socket_names)}
    for socket, unit in sockets.items():
        if unit.get("NetworkNamespacePath") != str(ns_path):
            issues.append(f"{socket}.socket: unexpected or unreadable namespace path")
    if expected.get("dns", {}).get("mode") == "compat" or expected.get("dns", {}).get("allowHostResolverIPC"):
        warnings.append("DNS compatibility or host resolver access is enabled")
    return {
        "namespace": name, "configured": expected, "namespaceExists": exists,
        "defaultDropChainsPresent": drop_chains, "endpointPinningTablePresent": pin_installed,
        "policyMatchesConfiguration": policy_match, "endpointPolicyMatchesConfiguration": pin_match,
        "installedPeerCount": len(peer_hashes),
        "routesIPv4": routes, "routesIPv6": routes6, "services": services,
        "sockets": sockets,
        "handshakeAgesSeconds": ages, "reachability": "not probed",
        "issues": sorted(set(issues)),
        "warnings": sorted(set(warnings)),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("namespace", nargs="?", help="configured namespace; default: all")
    parser.add_argument("--json", action="store_true", help="print a machine-readable report")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.exit(2, "Run with sudo to inspect namespaces and confined process mounts.\n")
    configured = json.loads(Path(MANIFEST).read_text())["namespaces"]
    if args.namespace and args.namespace not in configured:
        parser.error("unknown namespace; choose one configured in services.vpnConfinement")
    selected = [args.namespace] if args.namespace else sorted(configured)
    report = [inspect(name, configured[name]) for name in selected]
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        for item in report:
            print(f"{item['namespace']}: {item['configured']['interface']}")
            print(f"  Default-drop chains present: {item['defaultDropChainsPresent']}")
            print(f"  Firewall matches applied configuration: {item['policyMatchesConfiguration']}")
            print(f"  Installed WireGuard peers: {item['installedPeerCount']}")
            print(f"  DNS: {item['configured']['dns']['mode']}; IPv6: {item['configured']['ipv6']}")
            print(f"  Host ingress TCP ports: {item['configured']['hostPorts']}")
            print(f"  Handshake ages in seconds: {item['handshakeAgesSeconds']}")
            for name, service in item["services"].items():
                print(f"  {name}: {service['unit'].get('ActiveState', 'unknown')}; process attached: {service['processAttached']}")
            for issue in item["issues"]:
                print(f"  ISSUE: {issue}")
            for warning in item["warnings"]:
                print(f"  WARNING: {warning}")
        print("Reachability was not probed. Idle handshake age is not a failure signal.")
        print("These checks do not prove the absence of all alternate host communication paths.")
    return 1 if any(item["issues"] for item in report) else 0


if __name__ == "__main__":
    sys.exit(main())

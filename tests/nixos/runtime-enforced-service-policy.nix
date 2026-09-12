{ pkgs, ... }:
let
  probe = pkgs.writeText "enforced-service-probe.py" ''
    import json, os, pathlib, socket, sys, time, urllib.request
    status = pathlib.Path("/proc/self/status").read_text()
    assert os.getuid() != 0
    assert "NoNewPrivs:\t1" in status
    assert "CapEff:\t0000000000000000" in status
    assert "CapBnd:\t0000000000000000" in status
    try:
        socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    except OSError:
        pass
    else:
        raise AssertionError("raw packet socket unexpectedly permitted")
    while True:
        try:
            with urllib.request.urlopen("http://10.71.216.232:18080", timeout=1) as response:
                assert response.status == 200
            pathlib.Path(sys.argv[1]).write_text(json.dumps({"uid": os.getuid(), "tunnel": True}))
        except OSError:
            pass
        time.sleep(0.2)
  '';
  confinedProbe = name: executable: {
    wantedBy = [ "multi-user.target" ];
    vpn = {
      enable = true;
      namespace = "vpnapps";
    };
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = name;
      ExecStartPre = "${pkgs.coreutils}/bin/true\n";
      ExecStart = "${executable} ${probe} /var/lib/${name}/ready.json\n";
    };
  };
in
{
  name = "runtime-enforced-service-policy";
  nodes.machine = {
    imports = [ ./fixtures/wireguard-peer.nix ];
    services.vpnConfinement.namespaces.vpnapps = {
      servicePolicy = "enforced";
      egress.mode = "allowAllTunnel";
    };
    systemd.services = {
      quoted-double = confinedProbe "quoted-double" "\"${pkgs.python3}/bin/python3\"";
      quoted-single = confinedProbe "quoted-single" "'${pkgs.python3}/bin/python3'";
      provider-http = {
        wantedBy = [ "multi-user.target" ];
        after = [ "test-wireguard-peer.service" ];
        requires = [ "test-wireguard-peer.service" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server 18080 --bind 10.71.216.232 --directory ${pkgs.emptyDirectory}";
        };
      };
    };
  };
  testScript = ''
    import json
    machine.wait_for_unit("provider-http.service")
    machine.wait_for_unit("wireguard-wg0.service")
    for name in ["quoted-double", "quoted-single"]:
        machine.wait_for_unit(name + ".service")
        machine.wait_until_succeeds(f"test -s /var/lib/{name}/ready.json")
        result = json.loads(machine.succeed(f"cat /var/lib/{name}/ready.json"))
        assert result["uid"] != 0 and result["tunnel"]
        pid = machine.succeed(f"systemctl show {name} -p MainPID --value").strip()
        assert machine.succeed(f"readlink /proc/{pid}/ns/net").strip() == machine.succeed("stat -Lc 'net:[%i]' /run/netns/vpnapps").strip()
    machine.wait_until_succeeds("ip netns exec vpnapps wg show wg0 latest-handshakes | awk '$2 > 0 { found = 1 } END { exit !found }'")
    report = json.loads(machine.succeed("vpn-confinement-doctor vpnapps --json"))[0]
    assert report["configured"]["servicePolicy"] == "enforced"
  '';
}

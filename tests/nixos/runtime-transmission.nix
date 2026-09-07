{ pkgs, ... }: {
  name = "runtime-transmission";
  nodes.machine = {
    imports = [
      ../../modules
      ../../examples/transmission.nix
    ];
    system.stateVersion = "26.05";
    systemd.services.test-secrets = {
      before = [
        "wireguard-wg-downloads.service"
        "transmission.service"
      ];
      requiredBy = [
        "wireguard-wg-downloads.service"
        "transmission.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        umask 077
        mkdir -p /var/lib/vpn-confinement/secrets
        if [ ! -e /var/lib/vpn-confinement/secrets/vpn-downloads.key ]; then
          ${pkgs.wireguard-tools}/bin/wg genkey > /var/lib/vpn-confinement/secrets/vpn-downloads.key
          printf '%s' '{"rpc-username":"test-user","rpc-password":"test-password"}' > /var/lib/vpn-confinement/secrets/transmission-rpc.json
        fi
      '';
    };
    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
      pkgs.iproute2
    ];
  };
  testScript = ''
    import json
    machine.wait_for_unit("transmission.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_until_succeeds("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9091/transmission/rpc | grep '^401$'")
    fingerprint = machine.succeed("sha256sum /var/lib/vpn-confinement/secrets/vpn-downloads.key")
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("transmission.service")
    machine.wait_for_unit("nginx.service")
    assert machine.succeed("sha256sum /var/lib/vpn-confinement/secrets/vpn-downloads.key") == fingerprint
    machine.succeed("test $(stat -c %a /var/lib/vpn-confinement/secrets/vpn-downloads.key) = 600")
    machine.wait_until_succeeds("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9091/transmission/rpc | grep '^401$'")
    machine.succeed("curl -s -u test-user:test-password -D /tmp/headers http://127.0.0.1:9091/transmission/rpc >/dev/null")
    machine.succeed("grep -qi X-Transmission-Session-Id /tmp/headers")
    machine.succeed("session=$(awk 'tolower($1) == \"x-transmission-session-id:\" {gsub(/\\r/, \"\"); print $2}' /tmp/headers); curl --fail -s -u test-user:test-password -H \"X-Transmission-Session-Id: $session\" -d '{\"method\":\"session-get\"}' http://127.0.0.1:9091/transmission/rpc | jq -e '.result == \"success\"'")
    report = json.loads(machine.succeed("vpn-confinement-doctor downloads --json"))[0]
    assert report["services"]["transmission"]["processAttached"] is True
    assert report["services"]["transmission"]["unit"]["User"] == "transmission"
    machine.succeed("test -d /var/lib/transmission/Downloads")
    machine.succeed("systemctl restart wireguard-wg-downloads.service")
    machine.wait_for_unit("transmission.service")
    machine.wait_until_succeeds("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9091/transmission/rpc | grep '^401$'")
  '';
}

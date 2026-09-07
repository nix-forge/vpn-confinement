_: {
  name = "runtime-wireguard-handshake";
  nodes.machine.imports = [ ./fixtures/wireguard-peer.nix ];

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("test-wireguard-peer.service")
    machine.wait_for_unit("wireguard-wg0.service")
    machine.wait_until_succeeds("ip netns list | grep -q '^vpnapps\\b'")
    machine.wait_until_succeeds("ip netns exec vpnapps ping -c 1 -W 2 10.71.216.232")
    machine.wait_until_succeeds("ip netns exec vpnapps wg show wg0 latest-handshakes | awk '$2 > 0 { found = 1 } END { exit !found }'")
    machine.wait_until_succeeds("wg show wg-test-peer latest-handshakes | awk '$2 > 0 { found = 1 } END { exit !found }'")
    machine.succeed("ip netns exec vpnapps wg show wg0 transfer | awk '$2 > 0 && $3 > 0 { found = 1 } END { exit !found }'")
  '';
}

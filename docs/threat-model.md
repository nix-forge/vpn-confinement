# Threat model

## Assets and boundaries

- Host networking for non-confined services should stay on the normal network.
- Each confinement namespace is one trust domain with one DNS and firewall
  policy surface.
- The WireGuard interface lives inside the confinement namespace, while the UDP
  socket that carries tunnel traffic is born outside that namespace unless an
  advanced socket namespace override is used.
- Service-level hardening can reduce damage from a compromised confined service,
  but the network boundary is the namespace plus nftables policy.
- `securityProfile = "highAssurance"` is the opinionated profile for users who
  want weaker compatibility paths rejected instead of merely warned about.

## Intended guarantees

- Non-confined host traffic is not redirected through the VPN just because other
  services are confined.
- Confined services fail closed when the confinement namespace or the WireGuard
  service disappears.
- Strict DNS pins common resolver behavior to namespace-local generated
  `resolv.conf` / `nsswitch.conf` and blocks classic DNS-like leak ports (`53`,
  `853`, `5353`, `5355`) except for configured resolvers.
- High assurance means strict DNS plus destination-constrained allowlisting
  (`egress.mode = "allowList"` with tightly scoped `allowedCidrs`).
- IPv6 is fail-closed by default unless explicitly tunneled.
- Listener exposure is namespace-scoped first, with optional service-level bind
  restrictions as defense in depth.

## Primary controls

- Dedicated network namespace per confinement domain.
- Namespace-local nftables default-drop rules.
- WireGuard interface placement inside the confinement namespace.
- systemd lifecycle propagation with `BindsTo=` between confined services,
  sockets, the namespace-prep unit, and the generated WireGuard dependency unit.
- Strict DNS bind mounts plus inaccessible host resolver helper paths.
- `RestrictNetworkInterfaces=` to keep confined services on `lo`, the WireGuard
  interface, and optional host-link interface only.
- Optional `vpn.restrictBind = true` to derive `SocketBindAllow` /
  `SocketBindDeny` from namespace ingress policy when ingress listeners are
  declared.

## Weaker modes and opt-outs

- `dns.mode = "compat"` disables strict DNS containment in favor of broader
  application compatibility.
- `dns.allowHostResolverIPC = true` weakens strict DNS containment by allowing
  host resolver helper IPC such as `/run/nscd` and system D-Bus.
- `hostLink.enable = true` expands the namespace attack surface by adding a host
  communication path.
- `securityProfile = "highAssurance"` rejects `dns.allowHostResolverIPC = true`,
  `wireguard.allowHostnameEndpoints = true`, and `allowedIPsAsRoutes = false`.
- `securityProfile = "highAssurance"` also requires destination-constrained
  egress (`egress.allowedCidrs` must be non-empty) and non-root service
  execution by default (unless a service sets
  `vpn.allowRootInHighAssurance = true`).
- `wireguard.socketNamespace` is advanced; `"init"` is the main supported
  override. Setting it to the same confinement namespace is rejected because the
  WireGuard UDP socket needs an uplink-capable birthplace namespace.

## Endpoint policy

- Literal WireGuard peer endpoints are the recommended default.
- Hostname endpoints require explicit opt-in with
  `wireguard.allowHostnameEndpoints = true` and effective dynamic endpoint
  refresh at the interface or peer level.
- Even with refresh enabled, hostname endpoints are weaker than literal IPs:
  resolution is performed by WireGuard management units, not the confined
  service, so it is outside the module's strict DNS guarantee.

## Threat matrix

| Threat                                                        | `dns.mode` | `egress.mode` | `hostLink` | `ipv6.mode` | Other control                                                  | Result                                    |
| ------------------------------------------------------------- | ---------- | ------------- | ---------- | ----------- | -------------------------------------------------------------- | ----------------------------------------- |
| Classic DNS leak (`resolv.conf`, `53`, `853`, `5353`, `5355`) | `strict`   | any           | any        | any         | strict bind mounts + helper blocking + nftables DNS rules      | Covered                                   |
| DoH / DoQ to arbitrary destinations                           | any        | `allowList`   | any        | any         | constrained `allowedCidrs`                                     | Covered only for allowlisted destinations |
| Route-table / host-routing leak                               | any        | any           | any        | any         | dedicated namespace + WireGuard `interfaceNamespace` ownership | Covered by default design                 |
| IPv6 leak                                                     | any        | any           | any        | `disable`   | nftables IPv6 drop + namespace sysctls                         | Covered                                   |
| Host-to-namespace ingress                                     | any        | any           | `false`    | any         | no host-link veth path                                         | Covered                                   |
| Runtime tunnel drop                                           | any        | any           | any        | any         | `BindsTo=` between namespace, WireGuard, services, and sockets | Covered                                   |

## Non-goals

- Full prevention of HTTPS-based DoH or DoQ over generic allowed egress.
- Protection against compromised root on the host.
- Strong isolation between two mutually untrusted services inside the same
  confinement namespace.
- Replacing nftables with systemd cgroup-BPF IP filters as the main enforcement
  backend.

## Caveats

- Strict DNS prevents common libc/system resolver leaks and blocks classic
  DNS-like egress, but applications can still implement their own encrypted DNS
  over generic allowed destinations unless `egress.mode = "allowList"` is used
  with constrained CIDRs.
- `dns.mode = "strict"` should be read as "common resolver leak resistance", not
  as a blanket claim that all DNS exfiltration paths are eliminated.
- Service bind restrictions are supplemental hardening only; nftables remains
  the primary enforcement layer.
- vpn-enabled services and sockets must not override namespace attachment with
  manual `NetworkNamespacePath`, `PrivateNetwork`, or `JoinsNamespaceOf`
  settings.
- Socket and service units should share the same namespace policy when both are
  vpn-enabled.
- WireGuard backend support is limited to `networking.wireguard.interfaces`.

## Endpoint pinning status

- Endpoint pinning for the WireGuard UDP socket is not currently implemented.
- Namespace-local nftables controls confined workload egress, but the WireGuard
  UDP socket itself can live in its birthplace namespace (commonly init/host).
- Robust endpoint pinning likely requires additional policy in that birthplace
  namespace and careful host-network interaction design.
- Future direction (not yet implemented): optional advanced endpoint pinning
  controls under namespace WireGuard options with literal endpoint allowlists.

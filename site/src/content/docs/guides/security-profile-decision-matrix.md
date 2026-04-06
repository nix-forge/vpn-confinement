---
title: Security Profile Decision Matrix
description: Choose balanced or highAssurance by workload type
---

Use this quick matrix to choose profile mode.

| Workload type                                                    | Recommended profile            | Why                                                                         |
| ---------------------------------------------------------------- | ------------------------------ | --------------------------------------------------------------------------- |
| Torrent clients, browsers, general outbound apps                 | `balanced`                     | These usually need broad outbound destinations and compatibility.           |
| Private APIs, fixed backup endpoints, controlled webhook targets | `highAssurance`                | Destination-constrained egress and stricter assertions are a good fit.      |
| Mixed workloads with unclear requirements                        | `balanced` first, then tighten | Start stable, then move namespaces/apps to `highAssurance` where practical. |

## Rule of thumb

- If you cannot confidently maintain narrow destination allowlists, use
  `balanced`.
- If you can maintain strict destination allowlists and non-root service
  execution, use `highAssurance`.

## Related decisions

- Endpoint pinning (`wireguard.endpointPinning.enable`) works best with literal
  endpoints and complements either profile.
- Host ingress (`publishToHost.tcp`) is operationally useful but expands attack
  surface.

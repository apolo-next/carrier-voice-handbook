# Kamailio Reference

## Routing blocks — orden canónico

```
request_route {
    # 1. Sanity checks (sanity_check)
    # 2. NAT detection (nat_uac_test)
    # 3. Record-Route + loose routing
    # 4. CANCEL handling
    # 5. Authentication (REGISTER, INVITE)
    # 6. Dispatcher / LCR
    # 7. RTPEngine offer
    # 8. t_relay
}

onreply_route { ... }      # 18x/2xx — RTPEngine answer aquí
failure_route { ... }      # 4xx/5xx — failover, redirect
branch_route { ... }       # per-branch manipulation
```

## Módulos esenciales para SBC

| Módulo | Propósito | Notas |
|---|---|---|
| `tm` | Stateful transactions | `fr_timer=30`, `fr_inv_timer=60` para IVR |
| `rr` | Record-Route | `enable_double_rr=1` para dual-interface |
| `dispatcher` | Load balancing al softswitch | `flags=2` para failover |
| `rtpengine` | Bind con RTPEngine | `rtpengine_sock="udp:127.0.0.1:2223"` |
| `auth_db` | Digest auth | usar con `subscriber` table |
| `permissions` | ACL por IP | `allow_address(group, ip, port)` |
| `htable` | In-memory rate limiting | concurrent call counters |
| `sl` | Stateless replies | para 100 Trying inicial |

## Patrón: 302 redirect a IVR

```cfg
# request_route
if (is_method("INVITE") && uri =~ "^sip:119@") {
    sl_send_reply("302", "Moved");
    append_hf("Contact: <sip:ivr@10.0.0.50:5080>\r\n");
    exit;
}
```

Pero típicamente el redirect lo emite FreeSWITCH y Kamailio solo lo relaya. Verificar con `sngrep -d eth0 port 5060`.

## Tuning timers para IVR (Apolo IVR 119 pattern)

```cfg
modparam("tm", "fr_timer", 5000)         # provisional timer 5s
modparam("tm", "fr_inv_timer", 60000)    # invite timer 60s (no 120s default)
modparam("tm", "max_inv_lifetime", 180000)
modparam("tm", "max_noninv_lifetime", 32000)
```

## RTPEngine binding

```cfg
loadmodule "rtpengine.so"
modparam("rtpengine", "rtpengine_sock", "udp:127.0.0.1:2223")
modparam("rtpengine", "extra_id_pv", "$avp(extra_id)")

# En request_route, antes de t_relay:
rtpengine_offer("replace-origin replace-session-connection ICE=remove");

# En onreply_route, para 200 OK:
if (status=~"(183)|(2[0-9][0-9])") {
    rtpengine_answer("replace-origin replace-session-connection ICE=remove");
}
```

## Concurrent call limiting (htable pattern)

```cfg
modparam("htable", "htable", "calls=>size=10;autoexpire=7200")

# En request_route, después de auth:
$sht(calls=>$fU::count) = $sht(calls=>$fU::count) + 1;
if ($sht(calls=>$fU::count) > 10) {
    sl_send_reply("486", "Busy Here - call limit");
    exit;
}
```

Para dSIPRouter, esto se gestiona vía `dsip_call_settings` table — ver `assets/configs/dsiprouter_call_limit.sql`.

## Comandos kamcmd útiles

```bash
kamcmd dispatcher.list            # estado del dispatcher
kamcmd htable.dump calls          # ver counters in-memory
kamcmd tm.stats                   # estadísticas de transacciones
kamcmd core.uptime
kamcmd sl.stats
kamcmd permissions.addressDump
```

## Air-gapped RHEL 8 deployment

- Usar el repo oficial `kamailio-repo-5.7.x.repo` mirroreado internamente.
- Dependencias críticas: `libssl-devel`, `pcre2-devel`, `mariadb-devel`, `libcurl-devel`.
- SELinux: `setsebool -P httpd_can_network_connect 1` si Kamailio queries HTTP async.
- Firewall: `firewall-cmd --add-port=5060/udp --add-port=5060/tcp --add-port=5061/tcp --permanent`.

# Architectures Reference

## Patrón 1: SBC edge clásico (Apolo IVR 119)

```
Carrier ──UDP/5060──► [Kamailio SBC] ──UDP/5080──► [FreeSWITCH IVR]
                            │
                            ▼ ng-protocol :2223
                     [RTPEngine] ◄── RTP 30000-40000 ──► Carrier
                                 ◄── RTP intra ─────────► FreeSWITCH
```

Responsabilidades:
- **Kamailio**: terminación TLS si aplica, ACL, rate limiting, dispatcher al softswitch, RTPEngine offer/answer.
- **FreeSWITCH**: IVR, prompts, DTMF collection, B2BUA para PRACK.
- **RTPEngine**: relay RTP entre carrier y FreeSWITCH, manejo NAT.

## Patrón 2: Bypass media (alta densidad, sin IVR)

```
Caller ──► [Kamailio] ──► [Kamailio] ──► Callee
              │                │
              └─── RTPEngine ──┘  (RTP relay puro, sin softswitch)
```

Cuando solo necesitas routing + relay, FreeSWITCH es overhead innecesario. Kamailio + RTPEngine soportan 10k+ concurrent en hardware modesto.

## Patrón 3: ApoloBilling integration

```
            ┌──────────────────────────┐
            │    Kamailio (auth HTTP)  │
            │     ──http_async──►      │
            └──────────┬───────────────┘
                       │ POST /auth
                       ▼
            ┌──────────────────────────┐
            │  ApoloBilling (Rust/Axum)│
            │  PostgreSQL + Redis      │
            └──────────┬───────────────┘
                       │ 200 OK / 402
                       ▼
            ┌──────────────────────────┐
            │  FreeSWITCH ESL events   │
            │  CHANNEL_HANGUP_COMPLETE │──► CDR write
            └──────────────────────────┘
```

Patrón híbrido: pre-call auth via HTTP async desde Kamailio (no bloquea), post-call CDR vía ESL desde FreeSWITCH.

## Patrón 4: Despliegue containerizado RHEL 8 air-gapped

```yaml
# docker-compose.yml (o equivalente Podman)
version: '3.8'
services:
  kamailio:
    image: registry.local/kamailio:5.7.5
    network_mode: host          # crítico para SIP/RTP
    volumes:
      - ./kamailio:/etc/kamailio:ro
      - kamailio-logs:/var/log/kamailio

  freeswitch:
    image: registry.local/freeswitch:1.10.10
    network_mode: host
    volumes:
      - ./freeswitch/conf:/etc/freeswitch:ro
      - ./freeswitch/sounds:/usr/share/freeswitch/sounds:ro
      - freeswitch-logs:/var/log/freeswitch

  rtpengine:
    image: registry.local/rtpengine:mr11.5
    network_mode: host
    cap_add:
      - NET_ADMIN
      - SYS_NICE
    volumes:
      - ./rtpengine/rtpengine.conf:/etc/rtpengine/rtpengine.conf:ro

volumes:
  kamailio-logs:
  freeswitch-logs:
```

`network_mode: host` es necesario porque la red NAT de Docker rompe RTP. En Kubernetes, esto se hace con `hostNetwork: true`.

## Anti-patrones que deberías rechazar

1. **"Pongamos solo FreeSWITCH como SBC"** — FreeSWITCH no es un SBC. Le falta rate limiting decente, ACL granular, y escala mucho peor que Kamailio en signaling.
2. **"Kamailio puede manejar el IVR"** — No. Kamailio no procesa media. Necesitas FreeSWITCH o Asterisk.
3. **"Compartamos RTPEngine entre múltiples Kamailios sin coordinación"** — RTPEngine puede ser shared, pero necesita Redis para sync de keyspace si hay HA.
4. **"Hagamos NAT con iptables MASQUERADE para RTP"** — Romperá calidad y NAT keep-alive. Usa RTPEngine con dual-interface.

## HA y escalado

- **Kamailio HA**: `dmq` para sync de htable + `keepalived` para VIP. Activo-activo posible con dispatcher cross-pointing.
- **FreeSWITCH HA**: activo-pasivo con drbd o ESL replication. Activo-activo es complejo por estado de canal.
- **RTPEngine HA**: activo-pasivo via redis sync + VIP. No hay activo-activo real.

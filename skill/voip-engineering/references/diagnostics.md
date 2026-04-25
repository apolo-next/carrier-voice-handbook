# Diagnostics & Troubleshooting

## sngrep — el primer recurso

```bash
sngrep -d eth0                          # captura interactiva en eth0
sngrep -d eth0 port 5060                # solo SIP UDP
sngrep -I trace.pcap                    # leer pcap existente
sngrep -O out.pcap port 5060            # capturar a archivo
sngrep -d any "host 200.x.x.x"          # filtro BPF
```

Dentro de sngrep:
- `F2` filtros, `F5` save, `F7` settings
- `Enter` ver call flow detallado
- `Tab` toggle entre vista de mensajes y flow

## Captura con tcpdump para post-mortem

```bash
# SIP + RTP completo, rotando archivos cada 100MB, máx 10 archivos
tcpdump -i any -s 0 -w /tmp/voip-%Y%m%d-%H%M%S.pcap \
        -W 10 -C 100 -G 3600 \
        '(udp port 5060) or (udp port 5061) or (udp portrange 30000-40000)'
```

Luego analizar con Wireshark: `Telephony → VoIP Calls`.

## Diagnóstico por capa

### Capa 1: ¿llega el SIP?

```bash
ss -lun | grep -E "5060|5061"
tcpdump -i any -n port 5060 -c 20
firewall-cmd --list-all
```

### Capa 2: ¿se procesa el SIP?

- Kamailio: `kamcmd tm.stats`, log level a 3 temporalmente
- FreeSWITCH: `fs_cli` → `sofia loglevel all 9`
- Asterisk: `pjsip set logger on`

### Capa 3: ¿se establece el media?

```bash
# RTPEngine activo?
rtpengine-ctl list numsessions

# RTP fluyendo?
tcpdump -i any -n -c 20 'udp portrange 30000-40000'

# Si no hay RTP: revisar SDP en INVITE/200OK con sngrep
```

### Capa 4: ¿la calidad es aceptable?

Métricas a revisar en logs RTPEngine y CDR FreeSWITCH:
- `rtcp_packetloss` < 1%
- `rtcp_jitter` < 30ms
- `rtcp_mos_lq` > 4.0 (MOS Listen Quality)

## Errores SIP comunes y causa raíz

| Código | Causa probable |
|---|---|
| 401 sin Auth | digest auth disparándose, falta credenciales |
| 403 Forbidden | ACL en Kamailio (`permissions`), endpoint no whitelisted |
| 404 Not Found | dialplan no encuentra destination, o registrar vacío |
| 408 Timeout | downstream no responde, revisar `fr_inv_timer` |
| 480 Temporarily Unavailable | endpoint no registrado o `Contact` expirado |
| 486 Busy Here | call limit alcanzado o canal en uso |
| 488 Not Acceptable Here | SDP/codec mismatch, revisar negotiation |
| 503 Service Unavailable | dispatcher destination caído |
| 603 Decline | rechazo explícito de aplicación |

## DTMF: las tres maneras y cómo se rompen

1. **RFC 2833 / RFC 4733** (telephone-event en RTP) — lo más común.
2. **SIP INFO** — out-of-band, en mensajes SIP.
3. **Inband** — tonos audibles en el RTP, frágil con transcoding.

Si DTMF no funciona, primer check: ¿están negociando `telephone-event/8000` en SDP de ambos legs? Si un leg lo tiene y el otro no, FreeSWITCH puede transformar pero solo si está en el path RTP (no `bypass_media`).

## Logs centralizados

Recomendación para producción: enviar logs a syslog server con facility separado:

```
# rsyslog.conf
local1.* /var/log/voip/kamailio.log
local2.* /var/log/voip/freeswitch.log
local3.* /var/log/voip/rtpengine.log
```

Y reenvío TCP/TLS a un central con loki/grafana o ELK.

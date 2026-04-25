# voip-doctor

Diagnóstico end-to-end para stacks VoIP basados en **Kamailio + FreeSWITCH + RTPEngine**.

Auto-detecta el stack en RHEL 8 (Apolo IVR 119) y Debian 12 (Apolo SBC).

## Tres modos

### `triage` — snapshot rápido on-call
Para cuando algo falla y necesitas entender el estado en menos de un minuto.

```bash
sudo ./voip-doctor.sh triage
```

Genera un `report.txt` y vuelca un resumen por stdout. Tiempo total: ~10-30s.

### `capture` — análisis post-mortem completo
Para cuando ya hay un problema y quieres una caja de evidencia transportable.

```bash
sudo ./voip-doctor.sh capture --duration 300 --iface eth0
```

Captura en paralelo:
- `report.txt` — toda la data de Kamailio/FS/RTPEngine
- `report.html` — dashboard visual con SVG de métricas + ladder diagram SIP
- `capture.pcap` — todo el SIP + RTP del rango configurado
- `kamailio.log.tail`, `freeswitch.log.tail`, `rtpengine.log.tail`
- `capture-{RUN_ID}.tar.gz` — todo lo anterior empaquetado

### `monitor` — vigilancia continua
Para correr en una sesión tmux y reaccionar a cambios.

```bash
sudo ./voip-doctor.sh monitor --interval 15 --threshold-cps 100
```

Imprime una línea por intervalo con deltas. Si supera umbrales:
- Marca la línea en rojo
- Envía a syslog vía `logger -t voip-doctor -p local1.warn`

## Requisitos

Cualquiera de estos cumple para detectar cada componente:

| Componente | Detectado si... |
|---|---|
| Kamailio | proceso activo o `kamcmd` en PATH |
| FreeSWITCH | proceso activo o `fs_cli` en PATH |
| RTPEngine | proceso activo o `rtpengine-ctl` en PATH |

Para `capture` se necesita `tcpdump` o `tshark`. Para extraer flow SIP del pcap se usa `tshark`.

Si estás en RHEL 8 air-gapped y no tienes tshark, el modo capture igual genera el pcap pero el HTML no tendrá ladder diagram (los demás componentes funcionan).

## Variables de entorno

```bash
KAMCMD=/usr/sbin/kamcmd \
FS_CLI=/usr/local/freeswitch/bin/fs_cli \
RTPENGINE_CTL=/usr/local/bin/rtpengine-ctl \
./voip-doctor.sh capture
```

## Outputs

Por default todo va a `/var/tmp/voip-doctor/{modo}-{run_id}/`. Cambiarlo con `--out-base`.

## Integración con tu workflow

**Cron diario triage:**
```
0 6 * * * /opt/apolo/voip-doctor.sh triage --out-base /var/log/voip-doctor >/dev/null 2>&1
```

**Hook en pagerduty/incident:** corre `capture` automáticamente al recibir alerta:
```bash
./voip-doctor.sh capture --duration 180 && \
    rsync -a /var/tmp/voip-doctor/capture-*/  ops-storage:/incidents/$(date +%F)/
```

**Monitor en tmux para guardia:**
```bash
tmux new -d -s voip-mon "./voip-doctor.sh monitor --interval 10"
tmux attach -t voip-mon
```

## Anatomía del HTML

El report.html incluye:

1. **Cards de métricas** — fs_calls, fs_channels, registrations, rtp_sessions, rtp_pool%, load
2. **SVG bar chart** — visualización de carga con color-coding (verde<50%, ámbar 50-80%, rojo >80%)
3. **SVG ladder diagram** — primeros 20 mensajes SIP del pcap con timeline relativa, hosts como columnas, flechas color-coded (azul=request, verde=2xx, rojo=4xx/5xx)
4. **Reporte texto completo** — colapsable, todo el output crudo de los comandos

Tema dark, sin dependencias externas (un solo archivo HTML autocontenido — funciona offline).

## Limitaciones conocidas

- El parsing de `fs_calls`/`fs_registrations` asume el formato actual de FreeSWITCH 1.10+. Si usas una build muy custom, valida con `fs_cli -x "show calls count"`.
- El ladder diagram limita a 20 mensajes y 6 hosts por simplicidad visual. Para llamadas con más legs, abrir el pcap directamente en sngrep.
- No incluye análisis RTCP — para eso usar `rtpengine-ctl get-keyspace` con grafana.

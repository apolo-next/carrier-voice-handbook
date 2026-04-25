# RTPEngine Reference

## Modelo conceptual

RTPEngine es un **media relay**. No habla SIP — recibe comandos vía protocolo `ng` (bencode sobre UDP) desde Kamailio o FreeSWITCH (`offer`, `answer`, `delete`).

Tres modos de operación:
1. **Userspace** — fácil debug, throughput limitado (~500 conc calls).
2. **In-kernel** — módulo `xt_RTPENGINE`, alto throughput (10k+ calls).
3. **Híbrido** — flujos pequeños en kernel, transcoding en userspace.

## Configuración dual-interface (NAT)

El error más común: declarar una sola interfaz cuando el host tiene IP interna y pública.

```ini
# /etc/rtpengine/rtpengine.conf
[rtpengine]
interface = internal/10.0.0.50;external/200.x.x.x
listen-ng = 127.0.0.1:2223
port-min = 30000
port-max = 40000
log-level = 6
log-facility = local1
table = 0
timeout = 60
silent-timeout = 3600
delete-delay = 30
```

Y en Kamailio, al invocar:

```cfg
rtpengine_offer("replace-origin replace-session-connection direction=internal direction=external");
```

`direction=internal direction=external` indica: "leg de entrada llega por internal, leg de salida sale por external".

## Comandos rtpengine-ctl / rtpengine-recording

```bash
rtpengine-ctl list sessions
rtpengine-ctl list numsessions
rtpengine-ctl terminate <call-id>
rtpengine-ctl debug <call-id> on

# Estadísticas
rtpengine-ctl get-keyspaces
rtpengine-ctl ksrm <keyspace>
```

## In-kernel module

```bash
# Cargar módulo
modprobe xt_RTPENGINE

# Verificar
ls /proc/rtpengine/0/
cat /proc/rtpengine/0/list      # sesiones activas en kernel
cat /proc/rtpengine/0/control   # control interface
```

Si `cat /proc/rtpengine/0/list` está vacío pero `rtpengine-ctl list numsessions` muestra activas → el módulo no está enlazando, probablemente `table=` no coincide entre config y módulo.

## Transcoding

```ini
[rtpengine]
codec = transcode-PCMU
codec = transcode-PCMA
codec = transcode-G729
```

Requiere libs externas (`libbcg729`, `libopus`). En air-gapped RHEL hay que mirrorearlas.

## Permisos en RHEL/Debian

Issue común: RTPEngine corre como `rtpengine` user pero no puede abrir puertos < 1024 ni escribir en `/var/log/rtpengine/`.

```bash
# Capability para puertos privilegiados (raro pero ocurre con TURN)
setcap 'cap_net_bind_service=+ep' /usr/bin/rtpengine

# Logs
chown -R rtpengine:rtpengine /var/log/rtpengine
chmod 755 /var/log/rtpengine
```

En el caso documentado en sbc-core-01 Debian 12: el fix fue ajustar `/var/log/rtpengine` ownership y reiniciar.

## Recording

```ini
[rtpengine]
recording-method = pcap        # o "proc"
recording-format = eth
recording-dir = /var/spool/rtpengine
```

Y en Kamailio:
```cfg
rtpengine_offer("record-call=yes");
```

Cuidado: `recording-method=proc` requiere kernel module + tools especiales para reconstruir.

## Troubleshooting checklist

1. `rtpengine-ctl list numsessions` — ¿hay sesiones?
2. `tcpdump -i any -n udp port 2223` — ¿llegan ng-protocol commands?
3. `ss -lun | grep rtpengine` — ¿está escuchando en los rangos RTP?
4. Logs en `/var/log/rtpengine/rtpengine.log` con `log-level=7` para tracing.
5. Si "no port available" → port-min/port-max muy estrecho, expandir a 30000-40000.

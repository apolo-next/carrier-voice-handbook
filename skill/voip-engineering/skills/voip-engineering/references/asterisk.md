# Asterisk Reference

## Cuándo Asterisk vs FreeSWITCH

| Caso | Recomendación |
|---|---|
| IVR con muchos prompts dinámicos, conferencias grandes | FreeSWITCH |
| PBX corporativa con queues, voicemail visual, FAX | Asterisk |
| SBC + media relay alto throughput | Kamailio + RTPEngine |
| Migración de Asterisk → FS | FreeSWITCH B2BUA en paralelo, luego cutover |

## chan_pjsip vs chan_sip (legacy)

`chan_sip` está deprecado desde Asterisk 17. Todo nuevo va con `chan_pjsip` (`pjsip.conf`).

```ini
; /etc/asterisk/pjsip.conf

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060

[my_endpoint]
type=endpoint
context=from-internal
disallow=all
allow=ulaw,alaw
auth=my_auth
aors=my_aor

[my_auth]
type=auth
auth_type=userpass
username=user1
password=secret123      ; placeholder — usar realtime/ARI en prod

[my_aor]
type=aor
max_contacts=1
```

## Dialplan básico

```ini
; extensions.conf
[from-internal]
exten => _X.,1,NoOp(Llamada saliente: ${EXTEN})
 same => n,Set(CALLERID(num)=${CALLERID(num)})
 same => n,Dial(PJSIP/${EXTEN}@trunk_carrier,30)
 same => n,Hangup()
```

## AGI / AMI / ARI — cuál usar

| Interfaz | Caso de uso | Lenguaje típico |
|---|---|---|
| AGI | Lógica de dialplan extendida síncrona | Python, Perl |
| AMI | Eventos + comandos legacy | Cualquiera con TCP |
| ARI | REST + WebSocket eventos, control de canales | Modern stacks (Rust, Node) |

ARI es lo que querrías para integraciones nuevas con ApoloBilling.

## Migración Asterisk → FreeSWITCH (Apolo IVR 119 pattern)

Estrategia recomendada:

1. **Inventario**: dump de `pjsip show endpoints`, dialplan grep, sounds custom.
2. **Mapeo**:
   - `Dial()` → `bridge`
   - `Playback()` → `playback`
   - `Background() + WaitExten()` → `play_and_get_digits` o IVR XML
   - `Queue()` → `mod_callcenter` o `mod_fifo`
3. **Paralelo**: Kamailio reparte tráfico por % vía `dispatcher`.
4. **Cutover por DID**: mover destination_numbers uno por uno.
5. **Decommission**: dejar Asterisk standby 1-2 semanas para rollback.

## Comandos asterisk -rx útiles

```bash
asterisk -rx "pjsip show endpoints"
asterisk -rx "pjsip show registrations"
asterisk -rx "core show channels"
asterisk -rx "sip set debug on"          # solo si todavía usas chan_sip
asterisk -rx "pjsip set logger on"
asterisk -rx "dialplan reload"
```

## Logs

`/var/log/asterisk/full` y `/var/log/asterisk/messages`. Configurar verbose en `logger.conf`:

```
[logfiles]
console => warning,notice,error
messages => notice,warning,error
full => notice,warning,error,debug,verbose,dtmf
```

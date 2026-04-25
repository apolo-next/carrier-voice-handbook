# FreeSWITCH Reference

## Arquitectura mental

FreeSWITCH es un **softswitch B2BUA**. A diferencia de Kamailio (proxy stateful), FreeSWITCH:
- Termina y re-origina el SIP en cada lado.
- Puede manipular SDP libremente (transcoding, transformaciones de PRACK).
- Mantiene una FSM por canal (`channel_state`).

Esto lo hace ideal para IVR, conferencias, transcoding y para arreglar interworking que Kamailio no puede.

## SIP profiles — internal vs external

```
conf/sip_profiles/internal.xml   # extensiones registradas, puerto 5060
conf/sip_profiles/external.xml   # gateways/trunks, puerto 5080
```

Para Apolo IVR 119, típicamente Kamailio escucha en 5060 (cara al carrier) y FreeSWITCH escucha en 5080 (interno). El profile relevante es `external` con `inbound-bypass-media` controlado por dialplan.

## bypass_media — cuándo SÍ y cuándo NO

`bypass_media=true` saca a FreeSWITCH del path RTP. Los endpoints hablan RTP directamente.

**Usar SÍ cuando:**
- FreeSWITCH solo hace señalización (auth, routing).
- No necesitas DTMF detection, recording, ni transcoding.
- Quieres reducir latencia y carga CPU.

**NO usar cuando:**
- Necesitas reproducir prompts (IVR).
- Necesitas detectar DTMF inband o RFC 2833 transformación.
- Hay transcoding entre legs (G.729 ↔ G.711).
- Hay grabación.

```xml
<action application="set" data="bypass_media=true"/>
<action application="bridge" data="sofia/external/${destination_number}@${gateway}"/>
```

## 100rel / PRACK interworking

Patrón clásico: el carrier exige PRACK (RFC 3262), pero el endpoint legacy no lo soporta. FreeSWITCH como B2BUA resuelve esto:

```xml
<!-- Leg hacia el carrier (requiere PRACK) -->
<action application="set" data="sip_require_100rel=true"/>
<action application="set" data="sip_send_pranswer=true"/>

<!-- Leg hacia el endpoint legacy (sin PRACK) -->
<action application="export" data="nolocal:sip_require_100rel=false"/>
```

La clave es `export nolocal:` — aplica la variable solo al leg-B, no al leg-A.

## Dialplan IVR pattern (119)

```xml
<extension name="apolo_ivr_119">
  <condition field="destination_number" expression="^119$">
    <action application="answer"/>
    <action application="sleep" data="500"/>
    <action application="set" data="playback_terminators=#"/>
    <action application="ivr" data="apolo_main_menu"/>
  </condition>
</extension>
```

Y en `conf/ivr_menus/apolo_main_menu.xml`:

```xml
<menu name="apolo_main_menu"
      greet-long="ivr/apolo/welcome.wav"
      greet-short="ivr/apolo/welcome_short.wav"
      invalid-sound="ivr/ivr-that_was_an_invalid_entry.wav"
      timeout="5000"
      max-failures="3"
      digit-len="1">
  <entry action="menu-exec-app" digits="1" param="transfer 119001 XML default"/>
  <entry action="menu-exec-app" digits="2" param="transfer 119002 XML default"/>
</menu>
```

## ESL (Event Socket Library) — para ApoloBilling

```rust
// Patrón Rust con tokio
use tokio::net::TcpStream;

let mut stream = TcpStream::connect("127.0.0.1:8021").await?;
// auth ClueCon
// events plain CHANNEL_CREATE CHANNEL_DESTROY CHANNEL_ANSWER
```

Eventos críticos para billing:
- `CHANNEL_CREATE` — start del attempt
- `CHANNEL_ANSWER` — billable start (típicamente)
- `CHANNEL_HANGUP_COMPLETE` — CDR completo con `variable_billsec`, `variable_hangup_cause`

## fs_cli comandos esenciales

```bash
fs_cli -x "show channels"
fs_cli -x "sofia status"
fs_cli -x "sofia status profile external"
fs_cli -x "sofia status gateway my_gateway"
fs_cli -x "sofia loglevel all 9"        # debug intenso, cuidado en prod
fs_cli -x "uuid_kill <uuid>"
fs_cli -x "reloadxml"
fs_cli -x "console loglevel debug"
```

## RTPEngine integration vía mod_rtp

FreeSWITCH puede usar RTPEngine como media relay externo, pero típicamente solo se hace cuando FreeSWITCH está detrás de NAT complejo. En la mayoría de despliegues, FreeSWITCH maneja su propio RTP y RTPEngine vive del lado de Kamailio.

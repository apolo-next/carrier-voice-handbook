# Billing Integration Reference

## Tres approaches comparados

| Approach | Pros | Contras | Cuándo |
|---|---|---|---|
| **CGRateS** | Listo, rating engine completo, soporta SIP/Diameter | Complejo, Go stack, learning curve | Operadores con tariff plans complejos |
| **Custom (Rust/Axum)** | Control total, latencia mínima | Reinventar prepaid, fraud detection | Productos verticales con lógica custom (ApoloBilling) |
| **HTTP async desde Kamailio** | Simplísimo de integrar | Solo pre-call auth, no rating | MVP o cuando billing vive en otro sistema |

## Patrón Kamailio HTTP async auth

```cfg
loadmodule "http_async_client.so"

route[AUTH_BILLING] {
    $http_req(suspend) = 1;
    $http_req(method) = "POST";
    $http_req(body) = "{\"caller\":\"$fU\",\"callee\":\"$rU\"}";
    $http_req(hdr) = "Content-Type: application/json";
    http_async_query("http://billing.local/auth", "AUTH_REPLY");
    exit;
}

route[AUTH_REPLY] {
    if ($http_rs == 200) {
        route(RELAY);
    } else {
        sl_send_reply("402", "Payment Required");
    }
}
```

`$http_req(suspend) = 1` es la magia: suspende la transacción SIP y la reanuda al recibir la respuesta HTTP, sin bloquear workers.

## Patrón ESL para CDR (ApoloBilling Rust)

```rust
use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt, BufReader};

async fn handle_freeswitch_events() -> anyhow::Result<()> {
    let stream = TcpStream::connect("127.0.0.1:8021").await?;
    let (read_half, mut write_half) = stream.into_split();
    let mut reader = BufReader::new(read_half);

    write_half.write_all(b"auth ClueCon\n\n").await?;
    write_half.write_all(b"events plain CHANNEL_HANGUP_COMPLETE\n\n").await?;

    loop {
        let event = read_event(&mut reader).await?;
        if event.name == "CHANNEL_HANGUP_COMPLETE" {
            persist_cdr(&event).await?;
        }
    }
}
```

Variables clave en el evento:
- `Caller-Caller-ID-Number`
- `Caller-Destination-Number`
- `variable_billsec`
- `variable_hangup_cause`
- `variable_uuid`
- `Event-Date-Timestamp` (microsegundos epoch)

## Concurrent call limiting via dSIPRouter

```sql
-- Tabla dsip_call_settings
INSERT INTO dsip_call_settings
(gwgroupid, name, limit_calls, time_period, mode)
VALUES
(1001, 'customer_a', 50, 0, 1);  -- 50 conc, mode=1 (block on limit)
```

dSIPRouter inyecta esto en Kamailio htable automáticamente. Verificar con:

```bash
kamcmd htable.dump call_limits
```

## Validación 98.93% reconciliation pattern (Telcordia OAP)

Para reconciliar CDRs propios contra OAP del carrier:

```sql
WITH our_cdrs AS (
    SELECT DATE_TRUNC('hour', start_time) AS h,
           COUNT(*) AS n,
           SUM(billsec) AS total_sec
    FROM cdr WHERE start_time::date = CURRENT_DATE - 1
    GROUP BY 1
),
oap_cdrs AS (
    SELECT DATE_TRUNC('hour', start_time) AS h,
           COUNT(*) AS n,
           SUM(billsec) AS total_sec
    FROM oap_import WHERE start_time::date = CURRENT_DATE - 1
    GROUP BY 1
)
SELECT o.h,
       o.n AS our_n,
       op.n AS oap_n,
       ROUND(100.0 * LEAST(o.n, op.n) / GREATEST(o.n, op.n), 2) AS match_pct
FROM our_cdrs o
JOIN oap_cdrs op USING (h)
ORDER BY o.h;
```

Targets típicos:
- > 99% en CDR count → excelente
- 98-99% → aceptable, investigar gaps
- < 98% → problema sistémico (timezone, lost CDRs, double counting)

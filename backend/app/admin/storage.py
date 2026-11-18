"""One database round trip per priority batch, with transactional daily quotas."""
import json
from collections import defaultdict
from sqlalchemy import text


WRITE_BATCH=text("""
 WITH input AS (
   SELECT * FROM jsonb_to_recordset(CAST(:records AS jsonb))
     AS incoming(id text,kind text,at timestamptz,environment text,payload jsonb)
 ), fresh AS MATERIALIZED (
   SELECT * FROM input WHERE NOT EXISTS(SELECT 1 FROM monitoring.events e WHERE e.id=input.id)
 ), budget AS (
   INSERT INTO monitoring.event_quotas(environment,kind,day,event_count,byte_count)
   SELECT :environment,:kind,CAST(:day AS date),count(*),coalesce(sum(octet_length(payload::text)),0) FROM fresh
   ON CONFLICT(environment,kind,day) DO UPDATE
     SET event_count=monitoring.event_quotas.event_count+EXCLUDED.event_count,
         byte_count=monitoring.event_quotas.byte_count+EXCLUDED.byte_count
     WHERE monitoring.event_quotas.event_count+EXCLUDED.event_count<=:count_limit
       AND monitoring.event_quotas.byte_count+EXCLUDED.byte_count<=:byte_limit
   RETURNING environment
 ), written AS (
   INSERT INTO monitoring.events(id,kind,at,environment,payload)
   SELECT id,kind,at,environment,payload FROM fresh WHERE EXISTS(SELECT 1 FROM budget)
   ON CONFLICT(id) DO NOTHING RETURNING id
 ) SELECT (SELECT count(*) FROM fresh)-(SELECT count(*) FROM written) AS dropped
""")


async def persist_events(connection,batch):
    groups=defaultdict(list)
    for row in batch:
        priority=0 if row["payload"].get("level") in {"ERROR","CRITICAL","WARNING"} or (row["payload"].get("status") or 0)>=400 else 1
        groups[(priority,row["environment"],row["kind"],row["at"].date())].append({**row,"at":row["at"].isoformat()})
    dropped=0
    for (_,environment,kind,day),rows in sorted(groups.items()):
        count_limit,byte_limit=(25000,32*1024*1024) if kind=="runtime" else (50000,64*1024*1024)
        dropped+=await connection.scalar(WRITE_BATCH,{"environment":environment,"kind":kind,"day":day,
            "records":json.dumps(rows),"count_limit":count_limit,"byte_limit":byte_limit})
    return dropped

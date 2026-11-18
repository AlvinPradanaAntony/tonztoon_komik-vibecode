"""Start API as a child and persist sanitized logs outside its lifecycle.

python -m scripts.admin_supervisor
The independent probe worker must also run separately.
"""
import asyncio
import json
import os
import sys
import uuid
from collections import deque
from datetime import datetime
from app.admin.telemetry import utcnow
from app.admin.storage import persist_events
from app.database import engine
from app.config import settings


async def main():
    environment={**os.environ,"ADMIN_CONSOLE_ENABLED":"true","ADMIN_EXTERNAL_COLLECTOR":"1"}
    child=await asyncio.create_subprocess_exec(sys.executable,"-m","scripts.run_admin_api",stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.STDOUT,env=environment)
    pending=deque(maxlen=1000)
    dropped=0

    async def flush():
        nonlocal dropped
        if not pending:return
        rows=[pending.popleft() for _ in range(min(len(pending),250))]
        try:
            async with asyncio.timeout(4):
                async with engine.begin() as conn:
                    dropped+=await persist_events(conn,rows)
        except Exception:
            for row in reversed(rows):
                if len(pending)<pending.maxlen:pending.appendleft(row)
                else:dropped+=1

    async def collect():
        nonlocal dropped
        while True:
            line=await child.stdout.readline()
            if not line:break
            try:
                item=json.loads(line).get("tt_runtime")
                if not isinstance(item,dict):raise ValueError()
            except (ValueError,UnicodeError,AttributeError):
                # Unstructured output may contain source lines, SQL or credentials.
                # Preserve a bounded signal, never the original text.
                item={"id":str(uuid.uuid4()),"at":utcnow().isoformat(),"logger":"process.output","level":"WARNING",
                      "message":"Output proses tidak terstruktur diterima; teks mentah tidak disimpan.","request_id":None,
                      "environment":settings.APP_ENV,"instance_id":"supervised-api"}
            if len(pending)==pending.maxlen:dropped+=1
            pending.append({"id":item["id"],"kind":"runtime","at":datetime.fromisoformat(item["at"]),"environment":settings.APP_ENV,"payload":item})

    task=asyncio.create_task(collect())
    print("Admin supervisor active on http://127.0.0.1:8000; sanitized log collector enabled.",flush=True)
    try:
        while not task.done():
            await flush();await asyncio.sleep(1)
        await task
        code=await child.wait()
        item={"id":str(uuid.uuid4()),"at":utcnow().isoformat(),"logger":"process.lifecycle","level":"ERROR" if code else "INFO",
              "message":f"Proses API berhenti dengan exit code {code}.","request_id":None,"environment":settings.APP_ENV,"collector_dropped":dropped}
        pending.append({"id":item["id"],"kind":"runtime","at":utcnow(),"environment":settings.APP_ENV,"payload":item})
        await flush()
        print("API exited; collector saved available events. Probe worker remains independent.",flush=True)
    finally:
        if child.returncode is None:
            child.terminate()
            await child.wait()
        await engine.dispose()


if __name__=="__main__":
    try:asyncio.run(main())
    except KeyboardInterrupt:pass

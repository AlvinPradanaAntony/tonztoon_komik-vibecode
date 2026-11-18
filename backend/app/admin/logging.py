"""Structured stdout for an external supervisor. Formatting arguments are excluded."""
import json
import logging
import sys
import uuid
from app.admin.telemetry import sanitize,utcnow,request_id_context
from app.config import settings


class StructuredHandler(logging.Handler):
    def emit(self,record):
        if record.name.startswith(("sqlalchemy","httpx","httpcore","uvicorn.access")):
            return
        frames=[]
        if record.exc_info and record.exc_info[2]:
            trace=record.exc_info[2]
            while trace and len(frames)<20:
                frames.append({"function":trace.tb_frame.f_code.co_name[:120],"line":trace.tb_lineno})
                trace=trace.tb_next
        item={"id":str(uuid.uuid4()),"at":utcnow().isoformat(),"logger":record.name[:120],"level":record.levelname,
              "message":sanitize(record.msg),"exception":record.exc_info[0].__name__ if record.exc_info else None,
              "frames":frames,"request_id":request_id_context.get(),"environment":settings.APP_ENV,"instance_id":"supervised-api"}
        try:
            sys.stdout.write(json.dumps({"tt_runtime":item},ensure_ascii=True)+"\n");sys.stdout.flush()
        except Exception:
            pass

"""Local single-worker API with the admin feature enabled; no .env edits."""
import os
os.environ["ADMIN_CONSOLE_ENABLED"]="true"

if __name__=="__main__":
    import uvicorn
    log_config=None
    if os.environ.get("ADMIN_EXTERNAL_COLLECTOR")=="1":
        log_config={"version":1,"disable_existing_loggers":False,"handlers":{"structured":{"class":"app.admin.logging.StructuredHandler","level":"INFO"}},
                    "root":{"handlers":["structured"],"level":"INFO"},"loggers":{"uvicorn":{"handlers":["structured"],"level":"INFO","propagate":False},"uvicorn.error":{"handlers":["structured"],"level":"INFO","propagate":False},"uvicorn.access":{"handlers":[],"propagate":False}}}
    uvicorn.run("app.main:app",host="127.0.0.1",port=8000,workers=1,log_config=log_config if log_config else uvicorn.config.LOGGING_CONFIG)

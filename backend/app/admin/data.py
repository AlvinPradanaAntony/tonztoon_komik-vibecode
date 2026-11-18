from __future__ import annotations
import hashlib
import json
import uuid
from datetime import datetime
from typing import Literal
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import select, func, text, update, delete
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.admin.security import permissions_for, require
from app.admin.tables import editorial, audit, operations, outbox
from app.admin.telemetry import utcnow, request_id_context
from app.database import get_db, Base
from app.models import Comic, Chapter, Genre, comic_genre
from scraper.sources.registry import get_all_source_metadata, get_source_metadata

router = APIRouter()
FIELDS = {"comics": ("title", "alternative_titles", "synopsis", "author", "artist", "status", "type", "cover_image_url", "genre_ids"),
          "chapters": ("title", "release_date"), "genres": ("name",)}
MODELS = {"comics": Comic, "chapters": Chapter, "genres": Genre}


class ComicPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str | None = Field(None, min_length=1, max_length=500)
    alternative_titles: str | None = Field(None, max_length=10000)
    synopsis: str | None = Field(None, max_length=50000)
    author: str | None = Field(None, max_length=300)
    artist: str | None = Field(None, max_length=300)
    status: Literal["ongoing", "completed", "hiatus"] | None = None
    type: Literal["manga", "manhwa", "manhua"] | None = None
    cover_image_url: str | None = Field(None, max_length=1000)
    genre_ids: list[int] = Field(default_factory=list,max_length=100)

    @field_validator("title")
    @classmethod
    def valid_title(cls, value):
        if value is None or not value.strip():
            raise ValueError("Judul wajib diisi.")
        return value.strip()

    @field_validator("cover_image_url")
    @classmethod
    def valid_cover(cls, value):
        if value:
            from app.services.image_service import validate_proxy_image_url
            return validate_proxy_image_url(value)
        return value


class ComicCreate(ComicPatch):
    title: str = Field(min_length=1, max_length=500)
    slug: str = Field(min_length=1, max_length=600, pattern=r"^[a-z0-9][a-z0-9-]*$")
    source_name: str = Field(max_length=100)
    source_url: str = Field(max_length=1000)


class ChapterPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str | None = Field(None, max_length=500)
    release_date: datetime | None = None


class ChapterCreate(ChapterPatch):
    chapter_number: float = Field(ge=0, allow_inf_nan=False)
    source_url: str = Field(max_length=1000)


class GenreCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=1, max_length=100)
    slug: str = Field(min_length=1, max_length=120, pattern=r"^[a-z0-9][a-z0-9-]*$")


class GenrePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=1, max_length=100)


def serialize(value):
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def fingerprint(value):
    return '"'+hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()+'"'


async def resource(db, kind, identifier, lock=False):
    model = MODELS[kind]
    query = select(model).where(model.id==identifier).execution_options(include_archived=True)
    if lock:
        query = query.with_for_update()
    obj = (await db.execute(query)).scalars().first()
    if obj is None:
        raise HTTPException(404, "Resource tidak ditemukan.")
    state = (await db.execute(select(editorial).where(editorial.c.kind==kind,
                          editorial.c.resource_id==identifier))).mappings().first()
    source = {name: serialize(getattr(obj, "_source_"+name, getattr(obj,name))) for name in FIELDS[kind] if name!="genre_ids"}
    if kind=="comics":
        source["genre_ids"]=list((await db.execute(select(comic_genre.c.genre_id).where(comic_genre.c.comic_id==identifier).order_by(comic_genre.c.genre_id))).scalars())
    overrides = dict(state["overrides"]) if state else {}
    effective = {**source, **overrides}
    base = {"id": obj.id, "source": source, "overrides": overrides, "effective": effective,
            "revision": state["revision"] if state else 0, "archived": state["archived"] if state else False}
    if kind=="comics":
        base.update(source_name=obj.source_name, slug=obj.slug, source_url=obj.source_url,
                    genres=[{"id":g.id,"name":g.name,"slug":g.slug} for g in obj.genres],
                    chapter_count=await db.scalar(select(func.count(Chapter.id)).where(Chapter.comic_id==identifier).execution_options(include_archived=True)))
    elif kind=="chapters":
        base.update(comic_id=obj.comic_id, chapter_number=obj.chapter_number, source_url=obj.source_url,
                    image_count=len(obj.images or []), images_are_invalid=obj.images_are_invalid)
    else:
        base["slug"] = obj.slug
    base["etag"] = fingerprint(base)
    return obj, base


async def idempotency(db, request, user, payload):
    key = request.headers.get("idempotency-key", "")
    if not 8 <= len(key) <= 128:
        raise HTTPException(428, "Idempotency-Key wajib disertakan (8–128 karakter).")
    identity = hashlib.sha256(f"{user.user_id}:{key}".encode()).hexdigest()
    await db.execute(text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"), {"key": identity})
    signature = fingerprint({"method": request.method, "path": request.url.path, "payload": payload})
    previous = (await db.execute(select(operations).where(operations.c.key==identity))).mappings().first()
    if previous:
        if previous["fingerprint"] != signature:
            raise HTTPException(409, "Kunci tindakan sudah digunakan untuk payload lain.")
        if previous["response"] is None:
            raise HTTPException(409, "Tindakan memerlukan rekonsiliasi; jangan mengulang otomatis.")
        return identity, previous["response"]
    await db.execute(insert(operations).values(key=identity, actor=str(user.user_id), fingerprint=signature))
    return identity, None


async def finish(db, request, user, kind, identifier, action, fields, operation, response):
    await db.execute(insert(audit).values(id=str(uuid.uuid4()), actor=str(user.user_id), permission="catalog:write",
        resource=f"{kind}/{identifier}", action=action, fields=fields,
        request_id=request_id_context.get(), operation_id=operation))
    await db.execute(insert(outbox).values(payload={"type":"resource_changed","resource":f"{kind}/{identifier}","action":action}))
    await db.execute(update(operations).where(operations.c.key==operation).values(response=response, status="succeeded"))
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, "Identitas atau nilai unik sudah digunakan.")
    from app.admin.telemetry import telemetry
    telemetry.resource_changed(f"{kind}/{identifier}",response.get("revision"))
    return response


@router.get("/stream")
async def resource_stream(request:Request,user=Depends(require("data:read"))):
    import asyncio,time
    from fastapi.responses import StreamingResponse
    from app.admin.telemetry import telemetry
    identity=str(user.user_id)
    if telemetry.streams[identity]>=2 or sum(telemetry.streams.values())>=20:
        raise HTTPException(429,"Batas stream tercapai.")
    async def generate():
        telemetry.streams[identity]+=1
        last=None;checked=0
        try:
            yield 'event: reset\ndata: {"schema_version":1,"reason":"resource_snapshot"}\n\n'
            while not await request.is_disconnected():
                if time.time()-checked>=30:
                    from app.services.auth_service import validate_supabase_jwt
                    try:
                        current=await validate_supabase_jwt(request.headers.get("authorization","").removeprefix("Bearer "))
                        if "data:read" not in permissions_for(current):break
                    except Exception:break
                    checked=time.time()
                changes=list(telemetry.resource_changes)
                if last:
                    index=next((i for i,event in enumerate(changes) if event["id"]==last),None)
                    changes=changes[index+1:] if index is not None else changes
                if changes:
                    last=changes[-1]["id"]
                    for event in changes:
                        yield f'id: {event["id"]}\nevent: resource_changed\ndata: {json.dumps(event)}\n\n'
                else:yield 'event: heartbeat\ndata: {}\n\n'
                await asyncio.sleep(1)
        finally:telemetry.streams[identity]-=1
    return StreamingResponse(generate(),media_type="text/event-stream",headers={"Cache-Control":"private, no-store","X-Accel-Buffering":"no"})


def validate_source_url(source_name, value):
    source = get_source_metadata(source_name)
    if not source:
        raise HTTPException(422, "Source tidak terdaftar.")
    target, base = urlparse(value), urlparse(source["base_url"])
    if target.scheme not in {"http","https"} or target.hostname != base.hostname or target.username or target.password or target.port not in {None,80,443}:
        raise HTTPException(422, "URL harus berasal dari source yang dipilih.")


@router.get("/capabilities")
async def capabilities(user=Depends(require("data:read"))):
    return {"permissions": sorted(permissions_for(user)), "editable_fields":FIELDS,
            "features":{"editorial":True,"archive":True,"genre_mapping":True}}


@router.get("/comics")
async def comics(q: str = Query("",max_length=150), source: str = "", archived: bool = False,
                 status: str = "", page: int = Query(1,ge=1), limit: int = Query(50,ge=1,le=100),
                 _=Depends(require("data:read")), db: AsyncSession=Depends(get_db)):
    from app.admin.editorial import active
    query = select(Comic).execution_options(include_archived=True)
    query = query.where(active("comics",Comic.id) if not archived else ~active("comics",Comic.id))
    if q:
        query = query.where(Comic.title.ilike(f"%{q}%"))
    if source:
        query = query.where(Comic.source_name==source)
    if status:
        query = query.where(Comic.status==status)
    total = await db.scalar(select(func.count()).select_from(query.subquery()).execution_options(include_archived=True))
    rows = (await db.execute(query.order_by(Comic.id.desc()).offset((page-1)*limit).limit(limit))).scalars().all()
    return {"items":[{"id":c.id,"title":c.title,"source_name":c.source_name,"slug":c.slug,"status":c.status,"type":c.type} for c in rows],
            "total":total,"page":page,"limit":limit}


@router.get("/sources")
async def sources(_=Depends(require("data:read")), db:AsyncSession=Depends(get_db)):
    counts = dict((await db.execute(select(Comic.source_name,func.count()).group_by(Comic.source_name))).all())
    return {"items":[{**s,"db_comic_count":counts.get(s["id"],0)} for s in get_all_source_metadata()]}


@router.get("/genres")
async def genres(_=Depends(require("data:read")), db:AsyncSession=Depends(get_db)):
    return {"items":[{"id":g.id,"name":g.name,"slug":g.slug} for g in (await db.execute(select(Genre).order_by(Genre.name))).scalars()]}


@router.get("/audit")
async def audit_list(cursor: str | None=None, limit:int=Query(50,ge=1,le=100),
                     _=Depends(require("audit:read")), db:AsyncSession=Depends(get_db)):
    query = select(audit)
    if cursor:
        try:
            stamp, identifier = cursor.split("|",1)
            from sqlalchemy import or_, and_
            at = datetime.fromisoformat(stamp)
            query = query.where(or_(audit.c.at<at,and_(audit.c.at==at,audit.c.id<identifier)))
        except ValueError:
            raise HTTPException(422,"Cursor tidak valid.")
    rows = (await db.execute(query.order_by(audit.c.at.desc(),audit.c.id.desc()).limit(limit+1))).mappings().all()
    items = [{**dict(r),"at":r["at"].isoformat()} for r in rows[:limit]]
    return {"items":items,"next_cursor":f'{items[-1]["at"]}|{items[-1]["id"]}' if len(rows)>limit else None}


@router.get("/schema")
async def schema(_=Depends(require("data:read")),db:AsyncSession=Depends(get_db)):
    from app.admin.tables import metadata
    names=[t.name for t in [*Base.metadata.tables.values(),*metadata.tables.values()]]
    query=text("""
      SELECT ns.nspname AS schema_name,cl.relname AS table_name,a.attname AS name,
        format_type(a.atttypid,a.atttypmod) AS type,NOT a.attnotnull AS nullable,
        EXISTS(SELECT 1 FROM pg_index ix WHERE ix.indrelid=cl.oid AND ix.indisprimary AND a.attnum=ANY(ix.indkey)) AS primary_key,
        ARRAY(SELECT target_ns.nspname||'.'||target.relname||'.'||target_col.attname
          FROM pg_constraint fk CROSS JOIN LATERAL unnest(fk.conkey,fk.confkey) AS keys(source_num,target_num)
          JOIN pg_class target ON target.oid=fk.confrelid
          JOIN pg_namespace target_ns ON target_ns.oid=target.relnamespace
          JOIN pg_attribute target_col ON target_col.attrelid=target.oid AND target_col.attnum=keys.target_num
          WHERE fk.conrelid=cl.oid AND fk.contype='f' AND keys.source_num=a.attnum) AS "references"
      FROM pg_class cl JOIN pg_namespace ns ON ns.oid=cl.relnamespace
      JOIN pg_attribute a ON a.attrelid=cl.oid
      WHERE ns.nspname IN ('public','monitoring') AND cl.relkind IN ('r','p')
        AND cl.relname=ANY(CAST(:names AS text[])) AND a.attnum>0 AND NOT a.attisdropped
      ORDER BY ns.nspname,cl.relname,a.attnum
    """)
    rows=(await db.execute(query,{"names":names})).mappings().all()
    tables={}
    for row in rows:
        identifier=f'{row["schema_name"]}.{row["table_name"]}'
        table=tables.setdefault(identifier,{"id":identifier,"columns":[]})
        table["columns"].append({key:row[key] for key in ("name","type","nullable","primary_key","references")})
    return {"source":"Introspeksi PostgreSQL pada tabel aplikasi yang diizinkan","observed_at":utcnow().isoformat(),"tables":list(tables.values())}


@router.get("/comics/{identifier}/chapters")
async def chapters(identifier:int, page:int=Query(1,ge=1),limit:int=Query(50,ge=1,le=100),
                   _=Depends(require("data:read")), db:AsyncSession=Depends(get_db)):
    total=await db.scalar(select(func.count(Chapter.id)).where(Chapter.comic_id==identifier).execution_options(include_archived=True))
    rows=(await db.execute(select(Chapter.id,Chapter.chapter_number,Chapter.title,Chapter.release_date,Chapter.images_are_invalid)
        .where(Chapter.comic_id==identifier).order_by(Chapter.chapter_number.desc(),Chapter.id).offset((page-1)*limit).limit(limit)
        .execution_options(include_archived=True))).mappings().all()
    return {"items":[dict(r) for r in rows],"total":total,"page":page,"limit":limit}


@router.get("/{kind}/{identifier}")
async def detail(kind:Literal["comics","chapters","genres"],identifier:int,response:Response,
                 _=Depends(require("data:read")),db:AsyncSession=Depends(get_db)):
    _, value=await resource(db,kind,identifier)
    response.headers["ETag"]=value["etag"]
    return value


@router.patch("/{kind}/{identifier}")
async def patch(kind:Literal["comics","chapters","genres"],identifier:int,payload:dict,request:Request,
                user=Depends(require("catalog:write")),db:AsyncSession=Depends(get_db)):
    from pydantic import ValidationError
    try:
        data={"comics":ComicPatch,"chapters":ChapterPatch,"genres":GenrePatch}[kind].model_validate(payload).model_dump(exclude_unset=True,mode="json")
    except ValidationError as exc:
        raise HTTPException(422, json.loads(exc.json(include_context=False)))
    if "genre_ids" in data:
        await validate_genres(db,data["genre_ids"])
    operation,previous=await idempotency(db,request,user,data)
    if previous is not None:
        return previous
    obj,before=await resource(db,kind,identifier,True)
    require_match(request,before)
    if kind=="genres":
        obj.name=data["name"]
        await db.flush()
    else:
        values={**before["overrides"],**data}
        await db.execute(insert(editorial).values(kind=kind,resource_id=identifier,overrides=values,
            revision=before["revision"]+1,archived=before["archived"]).on_conflict_do_update(
                index_elements=[editorial.c.kind,editorial.c.resource_id],set_={"overrides":values,"revision":before["revision"]+1,"updated_at":utcnow()}))
    db.expire_all()
    _,after=await resource(db,kind,identifier)
    changes={name:{"before":before["effective"].get(name),"after":after["effective"].get(name)} for name in data}
    return await finish(db,request,user,kind,identifier,"update",changes,operation,after)


def require_match(request,before):
    if not request.headers.get("if-match"):
        raise HTTPException(428,"Muat detail terbaru sebelum menyimpan (If-Match wajib).")
    if request.headers["if-match"]!=before["etag"]:
        raise HTTPException(412,{"message":"Data berubah. Muat ulang dan periksa draft Anda.","current":before})


@router.post("/{kind}/{identifier}/archive-preview")
async def archive_preview(kind:Literal["comics","chapters"],identifier:int,
        _=Depends(require("catalog:write")),db:AsyncSession=Depends(get_db)):
    _,value=await resource(db,kind,identifier)
    return {"resource":value,"affected_chapters":value.get("chapter_count",0),"effect":"Konten disembunyikan dari pembaca; relasi dan progress dipertahankan."}


async def archive(kind:Literal["comics","chapters"],identifier:int,action:Literal["archive","restore"],request:Request,
                  user=Depends(require("catalog:write")),db:AsyncSession=Depends(get_db)):
    operation,previous=await idempotency(db,request,user,{"action":action})
    if previous is not None:
        return previous
    _,before=await resource(db,kind,identifier,True)
    require_match(request,before)
    await db.execute(insert(editorial).values(kind=kind,resource_id=identifier,archived=action=="archive",revision=before["revision"]+1)
        .on_conflict_do_update(index_elements=[editorial.c.kind,editorial.c.resource_id],set_={"archived":action=="archive","revision":before["revision"]+1,"updated_at":utcnow()}))
    _,after=await resource(db,kind,identifier)
    return await finish(db,request,user,kind,identifier,action,{},operation,after)


@router.delete("/{kind}/{identifier}/overrides/{field}")
async def reset(kind:Literal["comics","chapters"],identifier:int,field:str,request:Request,
                user=Depends(require("catalog:write")),db:AsyncSession=Depends(get_db)):
    if field not in FIELDS[kind]:
        raise HTTPException(422,"Field tidak dapat direset.")
    operation,previous=await idempotency(db,request,user,{"field":field})
    if previous is not None:
        return previous
    _,before=await resource(db,kind,identifier,True)
    require_match(request,before)
    values={k:v for k,v in before["overrides"].items() if k!=field}
    await db.execute(update(editorial).where(editorial.c.kind==kind,editorial.c.resource_id==identifier)
        .values(overrides=values,revision=before["revision"]+1,updated_at=utcnow()))
    db.expire_all()
    _,after=await resource(db,kind,identifier)
    return await finish(db,request,user,kind,identifier,"reset_override",{field:{"reset":True}},operation,after)


@router.post("/comics")
async def create_comic(payload:ComicCreate,request:Request,user=Depends(require("catalog:write")),db:AsyncSession=Depends(get_db)):
    data=payload.model_dump(mode="json")
    validate_source_url(payload.source_name,payload.source_url)
    operation,previous=await idempotency(db,request,user,data)
    if previous is not None:
        return previous
    selected=data.pop("genre_ids",[])
    await validate_genres(db,selected)
    obj=Comic(**data)
    db.add(obj)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409,"Komik dengan source dan slug ini sudah ada.")
    identifier=obj.id
    if selected:
        await db.execute(insert(editorial).values(kind="comics",resource_id=identifier,overrides={"genre_ids":selected},revision=1))
        db.expire_all()
    _,after=await resource(db,"comics",identifier)
    return await finish(db,request,user,"comics",identifier,"create",{k:{"after":v} for k,v in data.items() if k in FIELDS["comics"]},operation,after)


@router.post("/comics/{identifier}/chapters")
async def create_chapter(identifier:int,payload:ChapterCreate,request:Request,user=Depends(require("catalog:write")),db:AsyncSession=Depends(get_db)):
    _,comic=await resource(db,"comics",identifier)
    validate_source_url(comic["source_name"],payload.source_url)
    operation,previous=await idempotency(db,request,user,payload.model_dump(mode="json"))
    if previous is not None:
        return previous
    obj=Chapter(comic_id=identifier,**payload.model_dump(),images=[])
    db.add(obj)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409,"Nomor chapter sudah ada pada komik ini.")
    _,after=await resource(db,"chapters",obj.id)
    return await finish(db,request,user,"chapters",obj.id,"create",{},operation,after)


@router.post("/genres")
async def create_genre(payload:GenreCreate,request:Request,user=Depends(require("catalog:write")),db:AsyncSession=Depends(get_db)):
    operation,previous=await idempotency(db,request,user,payload.model_dump())
    if previous is not None:
        return previous
    obj=Genre(**payload.model_dump())
    db.add(obj)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409,"Nama atau slug genre sudah digunakan.")
    _,after=await resource(db,"genres",obj.id)
    return await finish(db,request,user,"genres",obj.id,"create",{"name":{"after":obj.name}},operation,after)


router.add_api_route("/{kind}/{identifier}/{action}", archive, methods=["POST"])


async def validate_genres(db, identifiers):
    if len(set(identifiers))!=len(identifiers) or any(identifier<=0 for identifier in identifiers):
        raise HTTPException(422,"ID genre harus unik dan positif.")
    found=set((await db.execute(select(Genre.id).where(Genre.id.in_(identifiers)))).scalars())
    if found!=set(identifiers):
        raise HTTPException(422,"Sebagian genre tidak ditemukan. Muat ulang daftar genre.")

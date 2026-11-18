"""SQL and instance values share one editorial overlay; scraper setters keep raw values."""
from sqlalchemy import case, select, exists, event, and_
from sqlalchemy.ext.hybrid import hybrid_property
from sqlalchemy.orm import column_property, Session, with_loader_criteria
from app.config import settings
from app.admin.tables import editorial


def install_fields(model, kind, fields):
    model._admin_overrides = column_property(
        select(editorial.c.overrides).where(editorial.c.kind==kind, editorial.c.resource_id==model.id)
        .correlate_except(editorial).scalar_subquery(), deferred=not settings.ADMIN_CONSOLE_ENABLED)
    for name in fields:
        def getter(self, field=name):
            raw = getattr(self, "_source_"+field)
            if not settings.ADMIN_CONSOLE_ENABLED:
                return raw
            value = (self._admin_overrides or {}).get(field, raw)
            if field == "release_date" and isinstance(value, str):
                from datetime import datetime
                return datetime.fromisoformat(value)
            return value

        def setter(self, value, field=name):
            setattr(self, "_source_"+field, value)

        def expression(cls, field=name):
            raw = getattr(cls, "_source_"+field)
            if not settings.ADMIN_CONSOLE_ENABLED:
                return raw.label(field)
            override = select(editorial.c.overrides[field].astext).where(
                editorial.c.kind==kind, editorial.c.resource_id==cls.id,
                editorial.c.overrides.has_key(field)).correlate_except(editorial).scalar_subquery()
            has_override = exists(select(1).where(editorial.c.kind==kind,
                editorial.c.resource_id==cls.id, editorial.c.overrides.has_key(field)))
            return case((has_override, override.cast(raw.type)), else_=raw).label(field)

        def update_expression(cls, value, field=name):
            return [(getattr(cls, "_source_"+field), value)]

        prop = hybrid_property(getter, setter).expression(expression).update_expression(update_expression)
        getter.__name__ = name
        setattr(model, name, prop)


def active(kind, identifier):
    return ~exists(select(1).where(editorial.c.kind==kind, editorial.c.resource_id==identifier,
                                  editorial.c.archived.is_(True)))


@event.listens_for(Session, "do_orm_execute")
def filter_archived(state):
    if not settings.ADMIN_CONSOLE_ENABLED or not state.is_select or state.execution_options.get("include_archived"):
        return
    from app.models import Comic, Chapter
    state.statement = state.statement.options(
        with_loader_criteria(Comic, active("comics", Comic.id), include_aliases=True),
        with_loader_criteria(Chapter, and_(active("chapters", Chapter.id), active("comics", Chapter.comic_id)), include_aliases=True),
    )

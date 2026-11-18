"""Additive admin schema; no changes to business-table columns."""
from sqlalchemy import (
    MetaData, Table, Column, Text, Integer, BigInteger, DateTime, Boolean,
    Index, ForeignKey, Float, Date, func,
)
from sqlalchemy.dialects.postgresql import JSONB

metadata = MetaData(schema="monitoring")
sessions = Table("admin_sessions", metadata,
    Column("id_hash", Text, primary_key=True), Column("user_id", Text, nullable=False),
    Column("encrypted_tokens", Text, nullable=False), Column("expires_at", DateTime(timezone=True), nullable=False),
    Column("created_at", DateTime(timezone=True), server_default=func.now()),
)
editorial = Table("editorial", metadata,
    Column("kind", Text, primary_key=True), Column("resource_id", Integer, primary_key=True),
    Column("revision", Integer, nullable=False, server_default="0"),
    Column("overrides", JSONB, nullable=False, server_default="{}"),
    Column("archived", Boolean, nullable=False, server_default="false"),
    Column("updated_at", DateTime(timezone=True), server_default=func.now()),
)
audit = Table("audit", metadata,
    Column("id", Text, primary_key=True), Column("at", DateTime(timezone=True), server_default=func.now(), index=True),
    Column("actor", Text, nullable=False), Column("permission", Text, nullable=False),
    Column("resource", Text, nullable=False), Column("action", Text, nullable=False),
    Column("fields", JSONB, nullable=False), Column("request_id", Text), Column("operation_id", Text),
    Column("result", Text, nullable=False, server_default="succeeded"),
)
operations = Table("operations", metadata,
    Column("key", Text, primary_key=True), Column("actor", Text, nullable=False),
    Column("fingerprint", Text, nullable=False), Column("response", JSONB),
    Column("status", Text, nullable=False, server_default="pending"),
    Column("created_at", DateTime(timezone=True), server_default=func.now(), index=True),
)
outbox = Table("outbox", metadata,
    Column("id", BigInteger, primary_key=True, autoincrement=True),
    Column("at", DateTime(timezone=True), server_default=func.now(), index=True),
    Column("payload", JSONB, nullable=False),
)
events = Table("events", metadata,
    Column("id", Text, primary_key=True), Column("kind", Text, nullable=False, index=True),
    Column("at", DateTime(timezone=True), nullable=False, index=True),
    Column("environment", Text, nullable=False), Column("payload", JSONB, nullable=False),
)
buckets = Table("buckets", metadata,
    Column("id", Text, primary_key=True), Column("at", DateTime(timezone=True), nullable=False, index=True),
    Column("environment", Text, nullable=False), Column("payload", JSONB, nullable=False),
)
probes = Table("probes", metadata,
    Column("id", BigInteger, primary_key=True, autoincrement=True),
    Column("at", DateTime(timezone=True), nullable=False, index=True),
    Column("environment", Text, nullable=False), Column("success", Boolean, nullable=False),
    Column("duration_ms", Float),
)
incidents = Table("incidents", metadata,
    Column("id", Text, primary_key=True), Column("rule", Text, nullable=False),
    Column("environment", Text, nullable=False), Column("state", Text, nullable=False),
    Column("started_at", DateTime(timezone=True), nullable=False),
    Column("updated_at", DateTime(timezone=True), nullable=False),
    Column("resolved_at", DateTime(timezone=True)), Column("value", Float),
    Column("healthy_since", DateTime(timezone=True)), Column("condition_since", DateTime(timezone=True)),
)
Index("ix_incidents_environment_rule", incidents.c.environment, incidents.c.rule)
quotas=Table("event_quotas",metadata,
    Column("environment",Text,primary_key=True),Column("kind",Text,primary_key=True),Column("day",Date,primary_key=True),
    Column("event_count",Integer,nullable=False,server_default="0"),Column("byte_count",BigInteger,nullable=False,server_default="0"))
security_events=Table("security_events",metadata,
    Column("id",Text,primary_key=True),Column("at",DateTime(timezone=True),server_default=func.now(),index=True),
    Column("action",Text,nullable=False),Column("outcome",Text,nullable=False),Column("user_id",Text),Column("environment",Text,nullable=False))

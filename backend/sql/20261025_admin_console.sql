CREATE SCHEMA IF NOT EXISTS monitoring;
CREATE TABLE IF NOT EXISTS monitoring.admin_sessions (
  id_hash text PRIMARY KEY, user_id text NOT NULL, encrypted_tokens text NOT NULL,
  expires_at timestamptz NOT NULL, created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS monitoring.editorial (
  kind text NOT NULL, resource_id integer NOT NULL, revision integer NOT NULL DEFAULT 0,
  overrides jsonb NOT NULL DEFAULT '{}', archived boolean NOT NULL DEFAULT false,
  updated_at timestamptz DEFAULT now(), PRIMARY KEY(kind,resource_id)
);
CREATE TABLE IF NOT EXISTS monitoring.audit (
  id text PRIMARY KEY, at timestamptz DEFAULT now(), actor text NOT NULL,
  permission text NOT NULL, resource text NOT NULL, action text NOT NULL,
  fields jsonb NOT NULL, request_id text, operation_id text, result text NOT NULL DEFAULT 'succeeded'
);
CREATE TABLE IF NOT EXISTS monitoring.operations (
  key text PRIMARY KEY, actor text NOT NULL, fingerprint text NOT NULL, response jsonb,
  status text NOT NULL DEFAULT 'pending', created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS monitoring.outbox (
  id bigserial PRIMARY KEY, at timestamptz DEFAULT now(), payload jsonb NOT NULL
);
CREATE TABLE IF NOT EXISTS monitoring.events (
  id text PRIMARY KEY, kind text NOT NULL, at timestamptz NOT NULL,
  environment text NOT NULL, payload jsonb NOT NULL
);
CREATE TABLE IF NOT EXISTS monitoring.buckets (
  id text PRIMARY KEY, at timestamptz NOT NULL, environment text NOT NULL, payload jsonb NOT NULL
);
CREATE TABLE IF NOT EXISTS monitoring.probes (
  id bigserial PRIMARY KEY, at timestamptz NOT NULL, environment text NOT NULL,
  success boolean NOT NULL, duration_ms double precision
);
CREATE TABLE IF NOT EXISTS monitoring.incidents (
  id text PRIMARY KEY, rule text NOT NULL, environment text NOT NULL, state text NOT NULL,
  started_at timestamptz NOT NULL, updated_at timestamptz NOT NULL, resolved_at timestamptz,
  value double precision, healthy_since timestamptz, condition_since timestamptz
);
CREATE TABLE IF NOT EXISTS monitoring.event_quotas (
  environment text NOT NULL, kind text NOT NULL, day date NOT NULL,
  event_count integer NOT NULL DEFAULT 0, byte_count bigint NOT NULL DEFAULT 0,
  PRIMARY KEY(environment,kind,day)
);
CREATE TABLE IF NOT EXISTS monitoring.security_events (
  id text PRIMARY KEY, at timestamptz DEFAULT now(), action text NOT NULL,
  outcome text NOT NULL, user_id text, environment text NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_monitoring_audit_at ON monitoring.audit(at);
CREATE INDEX IF NOT EXISTS ix_monitoring_operations_created_at ON monitoring.operations(created_at);
CREATE INDEX IF NOT EXISTS ix_monitoring_outbox_at ON monitoring.outbox(at);
CREATE INDEX IF NOT EXISTS ix_monitoring_events_kind_at ON monitoring.events(kind,at);
CREATE INDEX IF NOT EXISTS ix_monitoring_buckets_at ON monitoring.buckets(at);
CREATE INDEX IF NOT EXISTS ix_monitoring_probes_at ON monitoring.probes(at);
CREATE INDEX IF NOT EXISTS ix_monitoring_incidents_environment_rule ON monitoring.incidents(environment,rule);
CREATE INDEX IF NOT EXISTS ix_monitoring_security_events_at ON monitoring.security_events(at);

-- ほいくつなぐ 初期スキーマ
-- 時刻はすべてミリ秒の UNIX 時刻

CREATE TABLE facilities (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  login_id TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'staff')),
  password_hash TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
CREATE INDEX users_facility ON users(facility_id);

CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX sessions_user ON sessions(user_id);
CREATE INDEX sessions_facility ON sessions(facility_id);

CREATE TABLE login_failures (
  login_id TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX login_failures_login ON login_failures(login_id, at);

CREATE TABLE classes (
  id TEXT PRIMARY KEY,
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  name TEXT NOT NULL,
  age INTEGER NOT NULL CHECK (age BETWEEN 0 AND 6),
  interval_min INTEGER NOT NULL CHECK (interval_min BETWEEN 1 AND 30),
  sort INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX classes_facility ON classes(facility_id);

CREATE TABLE children (
  id TEXT PRIMARY KEY,
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  class_id TEXT NOT NULL REFERENCES classes(id),
  name TEXT NOT NULL,
  sort INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
CREATE INDEX children_facility ON children(facility_id);

CREATE TABLE naps (
  id TEXT PRIMARY KEY,
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  child_id TEXT NOT NULL REFERENCES children(id),
  day TEXT NOT NULL,
  start_at INTEGER NOT NULL,
  end_at INTEGER,
  started_by TEXT NOT NULL REFERENCES users(id),
  ended_by TEXT REFERENCES users(id)
);
CREATE INDEX naps_facility_day ON naps(facility_id, day);
CREATE INDEX naps_child_open ON naps(child_id, end_at);

CREATE TABLE nap_checks (
  id TEXT PRIMARY KEY,
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  nap_id TEXT NOT NULL REFERENCES naps(id),
  t INTEGER NOT NULL,
  posture TEXT NOT NULL CHECK (posture IN ('supine', 'right', 'left', 'prone')),
  fixed INTEGER NOT NULL DEFAULT 0,
  recorder_id TEXT NOT NULL REFERENCES users(id),
  entered_by TEXT NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  deleted_by TEXT REFERENCES users(id)
);
CREATE INDEX nap_checks_nap ON nap_checks(nap_id);

CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  facility_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  action TEXT NOT NULL,
  detail TEXT,
  at INTEGER NOT NULL
);
CREATE INDEX audit_log_facility ON audit_log(facility_id, at);

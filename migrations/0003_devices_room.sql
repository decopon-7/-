-- 「名前を選ぶだけ」にするための変更と、室温・湿度の記録
--
-- ・ログインは「園の端末の登録」だけにする（管理者のIDとパスワードで登録）
--   職員は端末で名前を選ぶだけ。職員の users 行はログインしない（password_hash = '!'）
-- ・設定の変更は、管理者がパスワードを入れて「管理者モード」にした時だけ（10分で自動で戻る）

ALTER TABLE sessions ADD COLUMN device_name TEXT NOT NULL DEFAULT '';
ALTER TABLE sessions ADD COLUMN admin_user_id TEXT REFERENCES users(id);
ALTER TABLE sessions ADD COLUMN admin_until INTEGER;

-- どの端末から入力したかも残す
ALTER TABLE nap_checks ADD COLUMN device_name TEXT;

-- 確認間隔は年齢で決める（0歳は5分、それ以外は10分）
UPDATE classes SET interval_min = CASE WHEN age = 0 THEN 5 ELSE 10 END;

-- 室温・湿度
CREATE TABLE room_readings (
  id TEXT PRIMARY KEY,
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  class_id TEXT NOT NULL REFERENCES classes(id),
  day TEXT NOT NULL,
  t INTEGER NOT NULL,
  temp_c10 INTEGER NOT NULL CHECK (temp_c10 BETWEEN 50 AND 450), -- 0.1℃単位
  humidity INTEGER NOT NULL CHECK (humidity BETWEEN 0 AND 100),  -- %
  recorder_id TEXT NOT NULL REFERENCES users(id),
  device_name TEXT,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE INDEX room_readings_facility_day ON room_readings(facility_id, day);

-- これまでの職員のパスワードは使わなくなるので無効にし、登録済みの端末は登録し直してもらう
UPDATE users SET password_hash = '!' WHERE role = 'staff';
DELETE FROM sessions;

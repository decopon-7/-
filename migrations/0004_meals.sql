-- 給食の未経験食材チェック（docs/meal-check-design.md）

-- 食材（園の食材チェック表の項目）
CREATE TABLE foods (
  id TEXT PRIMARY KEY,
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '',
  sort INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX foods_facility_name ON foods(facility_id, name);

-- 子ども×食材の今の状態（行がない = 未）
CREATE TABLE child_foods (
  child_id TEXT NOT NULL REFERENCES children(id),
  food_id TEXT NOT NULL REFERENCES foods(id),
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  status TEXT NOT NULL CHECK (status IN ('ok', 'ng')), -- ok: 家庭で食べた / ng: 除去
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (child_id, food_id)
);
CREATE INDEX child_foods_facility ON child_foods(facility_id);

-- 状態を変えた履歴（上書きで消さない）
CREATE TABLE child_food_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  facility_id TEXT NOT NULL,
  child_id TEXT NOT NULL,
  food_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('none', 'ok', 'ng')),
  recorder_id TEXT NOT NULL REFERENCES users(id),
  device_name TEXT,
  at INTEGER NOT NULL
);
CREATE INDEX child_food_log_child ON child_food_log(child_id, at);

-- クラス×日の献立
CREATE TABLE menu_items (
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  class_id TEXT NOT NULL REFERENCES classes(id),
  day TEXT NOT NULL,
  food_id TEXT NOT NULL REFERENCES foods(id),
  PRIMARY KEY (class_id, day, food_id)
);
CREATE INDEX menu_items_facility_day ON menu_items(facility_id, day);

CREATE TABLE menus (
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  class_id TEXT NOT NULL REFERENCES classes(id),
  day TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  recorder_id TEXT NOT NULL REFERENCES users(id),
  device_name TEXT,
  PRIMARY KEY (class_id, day)
);

-- 配膳前の確認（2名）。snapshot に確認時点の献立と対象の子・食材を残す
CREATE TABLE meal_checks (
  id TEXT PRIMARY KEY,
  facility_id TEXT NOT NULL REFERENCES facilities(id),
  class_id TEXT NOT NULL REFERENCES classes(id),
  day TEXT NOT NULL,
  t INTEGER NOT NULL,
  checker1_id TEXT NOT NULL REFERENCES users(id),
  checker2_id TEXT NOT NULL REFERENCES users(id),
  device_name TEXT,
  snapshot TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX meal_checks_facility_day ON meal_checks(facility_id, day);

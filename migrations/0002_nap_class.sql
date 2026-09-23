-- 午睡を始めた時点のクラスと確認間隔を残す
-- （あとでクラス替えや間隔の変更をしても、過去の記録表が変わらないように）
ALTER TABLE naps ADD COLUMN class_id TEXT REFERENCES classes(id);
ALTER TABLE naps ADD COLUMN interval_min INTEGER;

UPDATE naps SET
  class_id = (SELECT class_id FROM children WHERE children.id = naps.child_id),
  interval_min = (SELECT c.interval_min FROM children k JOIN classes c ON c.id = k.class_id WHERE k.id = naps.child_id)
WHERE class_id IS NULL;

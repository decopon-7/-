// 給食の未経験食材チェック：献立と「家庭で食べた食材」の照らし合わせ
// 画面とサーバー（worker/api.js）の両方で同じものを使う

export const FOOD_STATUS = {
  none: { label: '未', short: '未' },
  ok: { label: '家庭で食べた', short: '済' },
  ng: { label: '除去', short: '除' },
};

// タップするたびに 未 → 家庭で食べた → 除去 → 未
export function nextStatus(status) {
  return { none: 'ok', ok: 'ng', ng: 'none' }[status || 'none'];
}

// childFoods: [{ childId, foodId, status }] → (childId, foodId) で引ける形
export function statusLookup(childFoods) {
  const m = new Map(childFoods.map((c) => [`${c.childId}:${c.foodId}`, c.status]));
  return (childId, foodId) => m.get(`${childId}:${foodId}`) || 'none';
}

// 今日の献立に、未経験（untried）・除去（excluded）の食材がある子だけを返す（children の順）
export function mealFlags(children, childFoods, menuFoodIds) {
  const statusOf = statusLookup(childFoods);
  const out = [];
  for (const ch of children) {
    const untried = [];
    const excluded = [];
    for (const f of menuFoodIds) {
      const s = statusOf(ch.id, f);
      if (s === 'ng') excluded.push(f);
      else if (s === 'none') untried.push(f);
    }
    if (untried.length || excluded.length) out.push({ childId: ch.id, untried, excluded });
  }
  return out;
}

// 確認の記録に残す内容（確認時点の献立と、対象の子・食材）
export function checkSnapshot(children, childFoods, menuFoodIds) {
  return {
    menu: [...menuFoodIds].sort(),
    children: children.map((c) => c.id).sort(),
    flagged: mealFlags([...children].sort((a, b) => (a.id < b.id ? -1 : 1)), childFoods, [...menuFoodIds].sort()),
  };
}

// 確認のあとで、献立・子ども・食べた食材の記録が変わったか
export function isStale(savedSnapshot, currentSnapshot) {
  return JSON.stringify(savedSnapshot) !== JSON.stringify(currentSnapshot);
}

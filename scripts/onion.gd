# 刻まれる半分の玉ねぎ。
#
# 工程:
#   1. LENGTHWISE  縦に切り込みを入れる（ローカルX方向の位置に切れ目）
#   2. CROSSWISE   90°回して横に刻む（ローカルZ方向の位置に切れ目）→ サイコロ状になる
#   3. MINCE       かき集めた山をトントン刻んで細かくする
#
# 1・2 の見た目は「半楕円体を切れ目で区切ったブロック」を毎回メッシュとして組み立てる。
# 3 は小さな立方体（MultiMesh）の集まりで、包丁が当たったかけらを2つに割っていく。
class_name Onion
extends Node3D

signal phase_changed(phase: int)

enum Phase { LENGTHWISE, CROSSWISE, MINCE, DONE }

const SHADER := preload("res://shaders/onion.gdshader")
## この幅より広い切れ目の間隔があると次の工程に進めない
const GAP_MAX := 0.024
## みじん切りの完成とみなすかけらの大きさ
const TARGET_SIZE := 0.006
## 目標サイズ以下のかけらがこの割合になったら完成
const FINENESS_DONE := 0.9
const MAX_CHUNKS := 3000
## 切れ目のすき間（見た目用）
const SPREAD := 0.0018

var phase := Phase.LENGTHWISE
var grams := 100
var rx := 0.08   # 幅の半分
var rz := 0.072  # 根元〜先端の半分
var h := 0.07    # 高さ

var cuts_x: Array[float] = []
var cuts_z: Array[float] = []

var _body: Node3D
var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _busy := false

# メッシュ組み立て用の作業領域
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()
var _offset := Vector3.ZERO

var _pile: MultiMeshInstance3D
var _chunk_pos := PackedVector3Array()
var _chunk_target := PackedVector3Array()
var _chunk_size := PackedFloat32Array()
var _chunk_rot := PackedFloat32Array()
var _chunk_color := PackedColorArray()
var _pile_dirty := false
var _pile_settling := 0.0


## 大きさをランダムにする。add_child の前に呼ぶ。
func randomize_shape(rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.9, 1.1)
	rx = 0.08 * s * rng.randf_range(0.95, 1.05)
	rz = 0.072 * s * rng.randf_range(0.95, 1.05)
	h = 0.07 * s * rng.randf_range(0.92, 1.05)
	grams = int(round(100.0 * s * s * s))


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("radii", Vector3(rx, h, rz))
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = _material
	_body.add_child(_mesh_instance)
	_rebuild_mesh()

	var chunk_mat := StandardMaterial3D.new()
	chunk_mat.vertex_color_use_as_albedo = true
	chunk_mat.roughness = 0.25
	chunk_mat.rim_enabled = true
	chunk_mat.rim = 0.4
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	cube.material = chunk_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cube
	mm.instance_count = MAX_CHUNKS
	mm.visible_instance_count = 0
	_pile = MultiMeshInstance3D.new()
	_pile.multimesh = mm
	add_child(_pile)


func _process(delta: float) -> void:
	if _pile_settling > 0.0:
		_pile_settling -= delta
		var k := minf(1.0, delta * 9.0)
		for i in _chunk_pos.size():
			_chunk_pos[i] = _chunk_pos[i].lerp(_chunk_target[i], k)
		_pile_dirty = true
	if _pile_dirty:
		_pile_dirty = false
		_update_pile()


func is_busy() -> bool:
	return _busy


## 今の工程の進み具合 0〜1
func get_progress() -> float:
	match phase:
		Phase.LENGTHWISE:
			return _gap_progress(cuts_x, rx)
		Phase.CROSSWISE:
			return _gap_progress(cuts_z, rz)
		Phase.MINCE:
			return clampf(get_fineness() / FINENESS_DONE, 0.0, 1.0)
	return 1.0


## 包丁をワールド座標 x の位置に振り下ろす。何か切れたら true。
func chop(world_x: float, reach: float) -> bool:
	if _busy:
		return false
	match phase:
		Phase.LENGTHWISE:
			var lx := _world_x_to_body(world_x).x
			if not _insert_cut(cuts_x, lx, rx):
				return false
			_rebuild_mesh()
			if _max_gap(cuts_x, rx) <= GAP_MAX:
				_to_crosswise()
			return true
		Phase.CROSSWISE:
			var lz := _world_x_to_body(world_x).z
			if not _insert_cut(cuts_z, lz, rz):
				return false
			_rebuild_mesh()
			if _max_gap(cuts_z, rz) <= GAP_MAX:
				_to_mince()
			return true
		Phase.MINCE:
			var hit := _chop_pile(world_x - global_position.x, reach)
			if hit and get_fineness() >= FINENESS_DONE:
				_set_phase(Phase.DONE)
			return hit
	return false


## 目標サイズ以下になった量の割合
func get_fineness() -> float:
	var total := 0.0
	var fine := 0.0
	for s in _chunk_size:
		var v := s * s * s
		total += v
		if s <= TARGET_SIZE:
			fine += v
	return fine / total if total > 0.0 else 0.0


## 間隔が広すぎる箇所（ワールド座標 x の [始点, 終点]）。赤い目印の表示用。
func get_wide_gaps_world() -> Array:
	var result := []
	if _busy or phase > Phase.CROSSWISE:
		return result
	var cuts := cuts_x if phase == Phase.LENGTHWISE else cuts_z
	var r := rx if phase == Phase.LENGTHWISE else rz
	var pts := _points(cuts, r)
	for i in pts.size() - 1:
		if pts[i + 1] - pts[i] > GAP_MAX:
			var a := _body_axis_to_world_x(pts[i])
			var b := _body_axis_to_world_x(pts[i + 1])
			result.append([minf(a, b), maxf(a, b)])
	return result


## 盛り付け先へ移すための見た目上の大きさ（手前方向の半径）
func front_extent() -> float:
	return rz if phase == Phase.LENGTHWISE else rx


# ================================================================ 工程の切り替え

func _set_phase(p: Phase) -> void:
	phase = p
	phase_changed.emit(p)


func _to_crosswise() -> void:
	_set_phase(Phase.CROSSWISE)
	_busy = true
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(_body, "rotation:y", -PI / 2, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _busy = false)


func _to_mince() -> void:
	_set_phase(Phase.MINCE)
	# ブロックを小さな立方体に置き換え、中央にかき集める
	var xs := _points(cuts_x, rx)
	var zs := _points(cuts_z, rz)
	var rng := RandomNumberGenerator.new()
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var cx := (xs[i] + xs[i + 1]) * 0.5
			var cz := (zs[j] + zs[j + 1]) * 0.5
			var ch := _height(cx, cz)
			if ch < 0.004:
				continue
			var vol := (xs[i + 1] - xs[i]) * (zs[j + 1] - zs[j]) * ch * 0.75
			var start := _body.transform * Vector3(cx, ch * 0.5, cz)
			_add_chunk(start, pow(vol, 1.0 / 3.0), rng)
	_mesh_instance.visible = false
	_scatter_targets(rng)


# ================================================================ みじん切り

func _add_chunk(pos: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	_chunk_pos.append(pos)
	_chunk_target.append(pos)
	_chunk_size.append(size)
	_chunk_rot.append(rng.randf_range(-PI, PI))
	var c := Color(0.95, 0.93, 0.82).lerp(Color(0.86, 0.87, 0.7), rng.randf())
	_chunk_color.append(c)


## かけらをこんもりした山の形に並べ直す
func _scatter_targets(rng: RandomNumberGenerator) -> void:
	var radius := 0.075
	for i in _chunk_pos.size():
		var a := rng.randf_range(0.0, TAU)
		var r := sqrt(rng.randf()) * radius
		var mound := (1.0 - r / radius) * 0.03
		_chunk_target[i] = Vector3(cos(a) * r, _chunk_size[i] * 0.5 + mound * rng.randf(), sin(a) * r * 0.8)
	_pile_settling = 0.8


func _chop_pile(local_x: float, reach: float) -> bool:
	var rng := RandomNumberGenerator.new()
	var hit := false
	var n := _chunk_pos.size()
	for i in n:
		var s := _chunk_size[i]
		var p := _chunk_target[i]
		if absf(p.x - local_x) > s * 0.5 + reach or s <= TARGET_SIZE * 0.6:
			continue
		hit = true
		var ns := s * 0.79
		_chunk_size[i] = ns
		# 包丁に押されて左右に少し分かれる
		var side := signf(p.x - local_x) if p.x != local_x else 1.0
		_chunk_target[i] = Vector3(p.x + side * ns * 0.35, maxf(ns * 0.5, p.y - s * 0.2), p.z + rng.randf_range(-0.002, 0.002))
		if _chunk_pos.size() < MAX_CHUNKS:
			_add_chunk(_chunk_pos[i], ns, rng)
			var j := _chunk_pos.size() - 1
			_chunk_target[j] = Vector3(p.x - side * ns * 0.35, maxf(ns * 0.5, p.y - s * 0.2), p.z + rng.randf_range(-0.003, 0.003))
	if hit:
		_pile_settling = 0.4
	return hit


func _update_pile() -> void:
	var mm := _pile.multimesh
	var n := _chunk_pos.size()
	mm.visible_instance_count = n
	for i in n:
		var s := _chunk_size[i]
		var b := Basis(Vector3.UP, _chunk_rot[i]).scaled(Vector3(s, s * 0.8, s))
		mm.set_instance_transform(i, Transform3D(b, _chunk_pos[i]))
		mm.set_instance_color(i, _chunk_color[i])


# ================================================================ 切れ目

func _world_x_to_body(world_x: float) -> Vector3:
	return _body.global_transform.affine_inverse() * Vector3(world_x, global_position.y, global_position.z)


## 今の工程の切る軸（ローカル）上の値をワールド x に変換
func _body_axis_to_world_x(v: float) -> float:
	var local := Vector3(v, 0, 0) if phase == Phase.LENGTHWISE else Vector3(0, 0, v)
	return (_body.global_transform * local).x


func _insert_cut(cuts: Array[float], v: float, r: float) -> bool:
	if absf(v) >= r * 0.97:
		return false
	for c in cuts:
		if absf(c - v) < 0.0025:
			return false
	cuts.append(v)
	cuts.sort()
	return true


func _points(cuts: Array[float], r: float) -> PackedFloat32Array:
	var pts := PackedFloat32Array([-r])
	pts.append_array(PackedFloat32Array(cuts))
	pts.append(r)
	return pts


func _max_gap(cuts: Array[float], r: float) -> float:
	var pts := _points(cuts, r)
	var m := 0.0
	for i in pts.size() - 1:
		m = maxf(m, pts[i + 1] - pts[i])
	return m


func _gap_progress(cuts: Array[float], r: float) -> float:
	var pts := _points(cuts, r)
	var excess := 0.0
	for i in pts.size() - 1:
		excess += maxf(0.0, pts[i + 1] - pts[i] - GAP_MAX)
	return clampf(1.0 - excess / (2.0 * r - GAP_MAX), 0.0, 1.0)


# ================================================================ メッシュ生成

func _height(x: float, z: float) -> float:
	var q := 1.0 - (x / rx) * (x / rx) - (z / rz) * (z / rz)
	return h * sqrt(q) if q > 0.0 else 0.0


func _rebuild_mesh() -> void:
	_verts = PackedVector3Array()
	_normals = PackedVector3Array()
	_uvs = PackedVector2Array()
	_uv2s = PackedVector2Array()
	var xs := _points(cuts_x, rx)
	var zs := _points(cuts_z, rz)
	var ncol := xs.size() - 1
	var nrow := zs.size() - 1
	for i in ncol:
		for j in nrow:
			_offset = Vector3((i - (ncol - 1) * 0.5) * SPREAD, 0, (j - (nrow - 1) * 0.5) * SPREAD)
			_add_cell(xs[i], xs[i + 1], zs[j], zs[j + 1])
	var mesh := ArrayMesh.new()
	if _verts.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance.mesh = mesh


## 切れ目で区切られた1ブロック分（上面＋4つの切り口）を追加
func _add_cell(x0: float, x1: float, z0: float, z1: float) -> void:
	var nx := maxi(1, int(ceil((x1 - x0) / 0.007)))
	var nz := maxi(1, int(ceil((z1 - z0) / 0.007)))
	var grid := []
	var any := false
	for a in nx + 1:
		var col := []
		var x := lerpf(x0, x1, float(a) / nx)
		for b in nz + 1:
			var z := lerpf(z0, z1, float(b) / nz)
			var y := _height(x, z)
			any = any or y > 0.0005
			col.append(Vector3(x, y, z))
		grid.append(col)
	if not any:
		return

	# 上面（楕円体の表面）
	for a in nx:
		for b in nz:
			var p00: Vector3 = grid[a][b]
			var p10: Vector3 = grid[a + 1][b]
			var p01: Vector3 = grid[a][b + 1]
			var p11: Vector3 = grid[a + 1][b + 1]
			if p00.y + p10.y + p01.y + p11.y < 0.0005:
				continue
			_tri(p00, p10, p11, _surface_normal(p00), _surface_normal(p10), _surface_normal(p11), Vector3.UP)
			_tri(p00, p11, p01, _surface_normal(p00), _surface_normal(p11), _surface_normal(p01), Vector3.UP)

	# 切り口（4辺）
	var left := []
	var right := []
	var front := []
	var back := []
	for t in nz + 1:
		left.append(grid[0][t])
		right.append(grid[nx][t])
	for t in nx + 1:
		back.append(grid[t][0])
		front.append(grid[t][nz])
	_wall(left, Vector3.LEFT)
	_wall(right, Vector3.RIGHT)
	_wall(back, Vector3.FORWARD)
	_wall(front, Vector3.BACK)


func _wall(tops: Array, n: Vector3) -> void:
	for t in tops.size() - 1:
		var top0: Vector3 = tops[t]
		var top1: Vector3 = tops[t + 1]
		if top0.y + top1.y < 0.0005:
			continue
		var bot0 := Vector3(top0.x, 0.0, top0.z)
		var bot1 := Vector3(top1.x, 0.0, top1.z)
		_tri(bot0, top0, top1, n, n, n, n)
		_tri(bot0, top1, bot1, n, n, n, n)


## 三角形を追加。facing 側から見たときに表になるよう、必要なら頂点の並びを入れ替える。
func _tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, facing: Vector3) -> void:
	if (b - a).cross(c - a).dot(facing) < 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	for pair in [[a, na], [b, nb], [c, nc]]:
		var p: Vector3 = pair[0]
		_verts.append(p + _offset)
		_normals.append(pair[1])
		_uvs.append(Vector2(p.x, p.z))
		_uv2s.append(Vector2(p.y, 0.0))


func _surface_normal(p: Vector3) -> Vector3:
	if p.y <= 0.0005:
		return Vector3(p.x / rx, 0.2, p.z / rz).normalized()
	return Vector3(p.x / (rx * rx), p.y / (h * h), p.z / (rz * rz)).normalized()

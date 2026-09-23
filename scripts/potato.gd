# 皮をむけるジャガイモ。
#
# しくみ:
#   ・見た目は SphereMesh を楕円体に拡大縮小し、シェーダーで凸凹させたもの。
#   ・「どこがむけたか」は球面座標 (経度, 緯度) の低解像度マスク画像で管理する。
#   ・マウスのレイと楕円体の交点を解析的に求め、その方向を中心にマスクを塗る。
class_name Potato
extends Node3D

const SHADER := preload("res://shaders/potato.gdshader")
const MASK_W := 256
const MASK_H := 128

var shape_scale := Vector3(1.0, 0.72, 0.68)
var seed_value := 0.0

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _mask_image: Image
var _mask_texture: ImageTexture
var _mask := PackedByteArray()
var _row_weight := PackedFloat32Array()
var _total_weight := 0.0
var _peeled_weight := 0.0
var _dirty := false


## 大きさと模様をランダムにする。add_child の前に呼ぶ。
func randomize_shape(rng: RandomNumberGenerator) -> void:
	shape_scale = Vector3(
		rng.randf_range(0.95, 1.15),
		rng.randf_range(0.64, 0.76),
		rng.randf_range(0.60, 0.72))
	seed_value = rng.randf_range(0.0, 100.0)


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48

	_mask.resize(MASK_W * MASK_H)
	_mask.fill(0)
	_mask_image = Image.create_from_data(MASK_W, MASK_H, false, Image.FORMAT_L8, _mask)
	_mask_texture = ImageTexture.create_from_image(_mask_image)

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("peel_mask", _mask_texture)
	_material.set_shader_parameter("seed", seed_value)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = sphere
	_mesh_instance.scale = shape_scale
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)

	# 緯度ごとの面積の重み（極付近のピクセルは面積が小さい）
	_row_weight.resize(MASK_H)
	for y in MASK_H:
		var w := sin((y + 0.5) / MASK_H * PI)
		_row_weight[y] = w
		_total_weight += w * MASK_W


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_mask_image.set_data(MASK_W, MASK_H, false, Image.FORMAT_L8, _mask)
		_mask_texture.update(_mask_image)


func get_peel_ratio() -> float:
	return _peeled_weight / _total_weight


## ワールド座標のレイとの交点。当たらなければ空の Dictionary。
## 戻り値: {"position": ワールド座標, "normal": ワールド法線, "dir": 単位球上の方向}
func intersect_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	var xf := _mesh_instance.global_transform
	var inv := xf.affine_inverse()
	var o := inv * origin
	var d := inv.basis * direction
	var a := d.dot(d)
	var b := 2.0 * o.dot(d)
	var c := o.dot(o) - 1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return {}
	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t < 0.0:
		return {}
	var p := o + d * t
	return {
		"position": xf * p,
		"normal": (xf.basis.inverse().transposed() * p).normalized(),
		"dir": p.normalized(),
	}


## from_dir から to_dir までの線に沿って皮をむく。新たにむけた面積の割合を返す。
func peel_stroke(from_dir: Vector3, to_dir: Vector3, radius: float) -> float:
	var before := _peeled_weight
	var angle := from_dir.angle_to(to_dir)
	var steps := maxi(1, int(ceil(angle / (radius * 0.35))))
	for i in steps + 1:
		_stamp(from_dir.slerp(to_dir, float(i) / steps).normalized(), radius)
	return (_peeled_weight - before) / _total_weight


## 残りを一気にむく（完成演出用）
func peel_all() -> void:
	_mask.fill(255)
	_peeled_weight = _total_weight
	_dirty = true


func _stamp(center: Vector3, radius: float) -> void:
	var theta_c := acos(clampf(center.y, -1.0, 1.0))
	var phi_c := atan2(center.x, center.z)
	var cos_r := cos(radius)
	var y0 := maxi(0, int(floor((theta_c - radius) / PI * MASK_H)))
	var y1 := mini(MASK_H - 1, int(ceil((theta_c + radius) / PI * MASK_H)))
	var x_center := int((phi_c / TAU + 0.5) * MASK_W)
	for y in range(y0, y1 + 1):
		var theta := (y + 0.5) / MASK_H * PI
		var st := sin(theta)
		var ct := cos(theta)
		var half := MASK_W / 2
		if st > sin(radius):
			half = mini(half, int(ceil(radius / st / TAU * MASK_W)) + 1)
		var row := y * MASK_W
		for i in range(-half, half):
			var x := posmod(x_center + i, MASK_W)
			var idx := row + x
			if _mask[idx] != 0:
				continue
			var phi := ((x + 0.5) / MASK_W - 0.5) * TAU
			if Vector3(st * sin(phi), ct, st * cos(phi)).dot(center) >= cos_r:
				_mask[idx] = 255
				_peeled_weight += _row_weight[y]
				_dirty = true

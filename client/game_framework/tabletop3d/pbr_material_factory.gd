extends RefCounted
class_name XbdPbrMaterialFactory
## XbdPbrMaterialFactory（小板凳PBR材质工厂）
## 统一创建桌面游戏使用的 StandardMaterial3D（标准PBR材质）。
## 后续美术资源可把颜色参数替换为 Albedo/Normal/Roughness/Metallic/ORM 纹理，
## 业务场景无需修改材质调用方式。


static func create_material(
	base_color: Color,
	roughness_value: float = 0.45,
	metallic_value: float = 0.0
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = base_color
	material.roughness = clampf(roughness_value, 0.0, 1.0)
	material.metallic = clampf(metallic_value, 0.0, 1.0)
	return material


static func create_emissive_material(
	base_color: Color,
	emission_color: Color,
	emission_energy: float = 1.0,
	roughness_value: float = 0.35
) -> StandardMaterial3D:
	var material := create_material(base_color, roughness_value, 0.0)
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = maxf(emission_energy, 0.0)
	return material

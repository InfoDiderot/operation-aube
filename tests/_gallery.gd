extends Node3D
func _ready() -> void:
	var cam := Camera3D.new(); cam.position = Vector3(0, 3, 16); cam.rotation_degrees.x = -6; cam.fov = 60; add_child(cam); cam.current = true
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 40, 0); sun.shadow_enabled = true; add_child(sun)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.6,0.7,0.8); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.55,0.55,0.55); add_child(env)
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(80, 80); g.mesh = pm; g.material_override = Mats.ground(); add_child(g)
	var nat := Nature.new()
	var names := ["NormalTree_1","NormalTree_3","BirchTree_1","DeadTree_1","Bush_Large","Bush_Flowers","Rock_1","Grass_Large","Flower_3_Clump","Plant_1"]
	var x := -18.0
	for n in names:
		nat.add_at(n, Vector3(x, 0, 0), 1.0, 0.0)
		var aabb := Nature.mesh(n).get_aabb()
		print(n, " aabb size=", aabb.size, " pos=", aabb.position, " tris~", Nature.mesh(n).get_faces().size() / 3)
		x += 4.0
	for i in 300:
		nat.add_at("Grass_Large" if i % 5 else "Flower_2_Clump", Vector3(randf_range(-20, 20), 0, randf_range(2, 12)), randf_range(0.8, 1.5), randf() * TAU)
	nat.flush(self)
	var wall := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(6, 4, 0.5); wall.mesh = bm; wall.material_override = Mats.stone(Color(0.74, 0.68, 0.57)); wall.position = Vector3(-10, 2, -6); add_child(wall)
	var wall2 := MeshInstance3D.new(); wall2.mesh = bm; wall2.material_override = Mats.plaster(Color(0.86, 0.8, 0.68)); wall2.position = Vector3(-3, 2, -6); add_child(wall2)
	var roof := MeshInstance3D.new(); var pr := PrismMesh.new(); pr.size = Vector3(6, 2.5, 6); roof.mesh = pr; roof.material_override = Mats.roof(Color(0.47,0.23,0.16), Color(0.86,0.8,0.68)); roof.position = Vector3(4, 1.25, -6); roof.rotation_degrees.y = 30; add_child(roof)
	var cob := MeshInstance3D.new(); var pm2 := PlaneMesh.new(); pm2.size = Vector2(6, 6); cob.mesh = pm2; cob.material_override = Mats.cobble(); cob.position = Vector3(11, 0.02, -4); add_child(cob)
	for i in 40:
		await get_tree().process_frame
		if i % 10 == 0: print("frame ", i, " t=", Time.get_ticks_msec())
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/gallery.png")
	get_tree().quit()

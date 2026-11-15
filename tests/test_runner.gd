extends Node
## Tests automatisés (sans écran). Lancer depuis la racine du projet :
##   godot --headless --path . --fixed-fps 60 res://tests/test_scene.tscn
## (scène plutôt que --script : les autoloads Game/Sfx/Fx sont ainsi chargés avant compilation)
## --fixed-fps 60 rend la simulation déterministe et plus rapide que le temps réel.
## Code de sortie : 0 si tout passe, 1 sinon.

var passed := 0
var failed := 0
var mission: Node3D


var _flow_done := false
var _errors := ErrorCounter.new()


## Compte les erreurs de script/moteur : une erreur pendant les tests = échec,
## même si les assertions passent (une fonction interrompue peut ne rien casser de visible).
class ErrorCounter extends Logger:
	var count := 0
	var first := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		if code.begins_with("ÉCHEC") or rationale.begins_with("ÉCHEC"):
			return
		count += 1
		if first == "":
			first = "%s %s (%s:%d)" % [code, rationale, file.get_file(), line]
	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	OS.add_logger(_errors)
	await get_tree().process_frame
	test_weapon_table()
	test_sounds()
	Game.checkpoint = 0
	await test_mission_flow()
	# Un test qui plante en route n'atteint pas sa dernière ligne : on le compte en échec.
	check(_flow_done, "déroulé de mission exécuté jusqu'au bout")
	_flow_done = false
	await test_checkpoint_and_squad()
	check(_flow_done, "test point de contrôle + escouade exécuté jusqu'au bout")
	check(_errors.count == 0, "aucune erreur de script ou du moteur (%d ; première : %s)" % [_errors.count, _errors.first])
	print("\nRésultat : %d réussis, %d échoués" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  OK   ", label)
	else:
		failed += 1
		print("  ÉCHEC ", label)
		push_error("ÉCHEC " + label)


func wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await get_tree().physics_frame


# --- Équilibrage des armes ----------------------------------------------------------

func test_weapon_table() -> void:
	print("\n[Armes] Table TTK contre 100 PV (cible : 0,15 – 0,6 s au corps à 10 m)")
	for w in WeaponData.make_all():
		var body := w.ttk(100.0, 10.0)
		var head := w.ttk(100.0, 10.0, w.head_mult)
		var far := w.ttk(100.0, 50.0)
		print("  %-24s corps %d coups / %.2f s · tête %d / %.2f s · à 50 m %d / %.2f s" % [
			w.display_name, body.x, body.y, head.x, head.y, far.x, far.y])
		check(body.y >= 0.15 and body.y <= 0.6, "%s : TTK au corps dans la plage" % w.id)
		check(head.x <= body.x, "%s : la tête tue au moins aussi vite" % w.id)


func test_sounds() -> void:
	print("\n[Sons] Enregistrements CC0")
	var streams: Dictionary = Sfx.get("_streams")
	for sound: String in ["step_grass", "step_stone", "impact", "body_hit", "hurt", "click", "reload", "bounce"]:
		var v: Variant = streams.get(sound)
		check(v is Array and (v as Array).size() == 5, "%s : 5 variantes enregistrées" % sound)
	check(LevelBuilder.is_paved(Vector3(0, 0, 50)) and not LevelBuilder.is_paved(Vector3(-20, 0, 90)),
		"surface : route pavée / champ en herbe")


# --- Mission complète --------------------------------------------------------------

func test_mission_flow() -> void:
	print("\n[Mission] Déroulé complet")
	mission = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(mission)
	get_tree().current_scene = mission
	await wait(0.2)
	var player: Player = mission.get("player")
	var builder: LevelBuilder = mission.get("builder")
	player.health = 100000.0   # invulnérable pour le test
	# Coéquipiers figés : ce déroulé teste la mission seule, de façon déterministe
	for a in mission.get("allies"):
		(a as Ally).set_physics_process(false)
	check((mission.get("allies") as Array).size() == 2, "2 coéquipiers déployés")
	check(Game.checkpoint == 0, "départ sans point de contrôle")

	# Navmesh
	var polys := builder.nav.navigation_mesh.get_polygon_count()
	check(polys > 100, "navmesh cuite (%d polygones)" % polys)
	var map := builder.nav.get_navigation_map()
	for pair: Array in [[Vector3(0, 0, 95), Vector3(0, 0, -2)], [Vector3(6, 0, -80), Vector3(50, 0, -8)],
			[Vector3(0, 0, -2), Vector3(-25, 0, -10)], [Vector3(-2, 0, -2), Vector3(-58, 0, -2)]]:
		var path := NavigationServer3D.map_get_path(map, pair[0], pair[1], true)
		var ok := path.size() > 1 and path[path.size() - 1].distance_to(pair[1]) < 2.5
		check(ok, "chemin IA %s -> %s" % [pair[0], pair[1]])

	# Cadence de tir indépendante du framerate (Thompson, 1 s de tir continu)
	player.global_position = Vector3(0, 0.1, 100)
	player.rotation.y = 0.0
	player.head.rotation.x = deg_to_rad(60.0)   # vise le ciel
	player.switch_to(1)
	await wait(0.6)
	var shots_before: int = Game.stats["shots"]
	player.test_trigger = true
	await wait(1.0)
	player.test_trigger = false
	var fired: int = Game.stats["shots"] - shots_before
	check(absi(fired - 11) <= 1, "Thompson : %d tirs en 1 s (attendu 11 ± 1)" % fired)

	# Un tir sur un mur laisse un impact
	player.switch_to(0)
	player.global_position = Vector3(-4, 0.1, 20)
	player.rotation.y = PI * 0.5            # regarde vers l'ouest (maison)
	player.head.rotation.x = 0.0
	await wait(0.7)
	var holes := (Fx.get("_holes") as Array).size()
	player.test_trigger = true
	await wait(0.1)
	player.test_trigger = false
	check((Fx.get("_holes") as Array).size() > holes, "un tir sur un mur crée un impact")

	# Les ennemis du bocage repèrent et touchent le joueur
	player.global_position = Vector3(0, 0.1, 84)
	player.rotation.y = 0.0
	var dmg_before: float = Game.stats["damage_taken"]
	await wait(8.0)
	check(Game.stats["damage_taken"] > dmg_before, "les ennemis du bocage engagent le joueur (%.0f dégâts)" % (Game.stats["damage_taken"] - dmg_before))

	# Tir du joueur sur un ennemi : dégâts + tête
	var target: Enemy = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Enemy).zone == "bocage" and not (e as Enemy).is_dead():
			target = e
			break
	var res := target.take_bullet(52.0, target.global_position + Vector3.UP * 1.65, 2.6)
	check(res.get("headshot", false) and res.get("killed", false), "tir à la tête au Garand : mort en 1 balle")

	# Objectif 1 -> 2 : entrée du village
	player.global_position = Vector3(0, 0.1, 43)
	await wait(0.3)
	player.global_position = Vector3(0, 0.1, 38)
	await wait(0.3)
	check(mission.get("obj") == 1, "entrée du village -> objectif « place »")
	check(Game.checkpoint == 1, "point de contrôle 1 enregistré")

	# Objectif 2 -> 3 : place nettoyée
	var square := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		var en := e as Enemy
		if en.zone == "square" and not en.is_dead():
			en.take_bullet(999.0, en.global_position + Vector3.UP, 1.0)
			square += 1
	await wait(0.2)
	check(square == 7, "7 défenseurs sur la place")
	check(mission.get("obj") == 2, "place nettoyée -> objectif « charge »")
	var charge: Interactable = mission.get("charge")
	check(charge.enabled, "la charge devient disponible")
	check(Game.checkpoint == 2, "point de contrôle 2 enregistré")

	# Objectif 3 -> 4 : poser la charge en maintenant E
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Enemy).zone == "flak":
			(e as Enemy).take_bullet(999.0, (e as Enemy).global_position + Vector3.UP, 1.0)
	player.global_position = Vector3(46.5, 0.1, -2)
	player.rotation.y = -PI * 0.5           # regarde vers l'est (canon)
	await wait(0.3)
	check(player.can_interact(), "le joueur peut interagir avec le canon")
	Input.action_press("interact")
	await wait(3.3)
	Input.action_release("interact")
	check(mission.get("obj") == 3, "charge posée -> compte à rebours")

	# Explosion puis contre-attaque
	player.global_position = Vector3(10, 0.1, -2)
	await wait(10.5)
	check(mission.get("obj") == 6, "canon détruit")
	await wait(3.5)
	check(mission.get("obj") == 4, "contre-attaque lancée")
	var wave: Array[Enemy] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Enemy).zone == "counter":
			wave.append(e)
	check(wave.size() == 7, "7 assaillants")
	var d0 := 0.0
	for e in wave:
		d0 += e.global_position.distance_to(player.global_position)
	await wait(6.0)
	var d1 := 0.0
	for e in wave:
		d1 += e.global_position.distance_to(player.global_position)
	check(d1 < d0 - 40.0, "les assaillants convergent vers le joueur (%.0f m -> %.0f m cumulés)" % [d0, d1])
	for e in wave:
		if not e.is_dead():
			e.take_bullet(999.0, e.global_position + Vector3.UP, 1.0)
	await wait(0.2)
	check(mission.get("obj") == 5, "contre-attaque repoussée -> ralliement")

	# Ralliement -> victoire
	player.global_position = Vector3(-58, 0.1, -2)
	await wait(3.5)
	check(mission.get("ended") == true, "mission terminée")
	check(Game.last_result.get("victory", false), "victoire enregistrée")
	get_tree().paused = false
	_flow_done = true


# --- Point de contrôle + escouade ---------------------------------------------------

func test_checkpoint_and_squad() -> void:
	print("\n[Point de contrôle + escouade]")
	mission.queue_free()
	await get_tree().process_frame
	Game.checkpoint = 2
	mission = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(mission)
	get_tree().current_scene = mission
	await wait(0.3)
	var player: Player = mission.get("player")
	player.health = 100000.0
	check(mission.get("obj") == 2, "reprise au point 2 -> objectif « charge »")
	check(player.global_position.distance_to(Vector3(0, 0, 4)) < 2.0, "joueur replacé sur la place")
	check(mission.call("total_in", "square") == 0 and mission.call("total_in", "bocage") == 0,
		"zones déjà prises non repeuplées")
	check(mission.call("alive_in", "flak") == 3, "gardes du canon présents")
	var allies: Array = mission.get("allies")
	for a in allies:
		check((a as Ally).global_position.distance_to(player.global_position) < 6.0, "%s placé près du joueur" % (a as Ally).callsign)

	# Les coéquipiers suivent le joueur et engagent les gardes du canon
	player.global_position = Vector3(28, 0.1, -2)
	player.rotation.y = -PI * 0.5
	var guards: Array[Enemy] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Enemy).zone == "flak":
			guards.append(e)
	await wait(12.0)
	var follow_ok := true
	for a in allies:
		follow_ok = follow_ok and (a as Ally).global_position.distance_to(player.global_position) < 12.0
	check(follow_ok, "les coéquipiers ont suivi le joueur (%s)" % ", ".join(allies.map(func(a: Node) -> String: return "%.1f m" % (a as Ally).global_position.distance_to(player.global_position))))
	var hurt := 0
	for g in guards:
		if g.is_dead() or g.health < 100.0:
			hurt += 1
	check(hurt > 0, "les coéquipiers touchent l'ennemi (%d garde(s) touché(s))" % hurt)

	# Écran de fin après une mort : reprise proposée
	var screen := EndScreen.new()
	mission.add_child(screen)
	screen.show_result({"victory": false, "difficulty": 1})
	var labels: Array = screen.find_children("*", "Button", true, false).map(func(b: Node) -> String: return (b as Button).text)
	check(labels.has("Reprendre au point de contrôle"), "écran de mort : bouton de reprise")
	get_tree().paused = false
	Game.checkpoint = 0
	_flow_done = true

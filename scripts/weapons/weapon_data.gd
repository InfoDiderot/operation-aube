class_name WeaponData
extends RefCounted
## Données d'une arme. Tout l'équilibrage se règle ici ; tests/test_runner.gd imprime la table TTK.

var id := ""
var display_name := ""
var automatic := false
var damage := 30.0          # dégâts d'une balle au corps
var head_mult := 2.0        # multiplicateur tête
var falloff_start := 30.0   # m : dégâts pleins jusqu'ici
var falloff_end := 70.0     # m : plancher atteint ici
var falloff_min := 0.7      # fraction des dégâts au plancher
var fire_rate := 5.0        # coups par seconde
var mag_size := 8
var reserve := 40
var reserve_max := 120
var reload_time := 2.0
var hip_spread := 2.0       # degrés (demi-angle du cône) en tir à la hanche
var ads_spread := 0.15      # idem en visée
var bloom := 0.4            # degrés ajoutés par tir enchaîné
var bloom_max := 3.0
var recoil_v := 1.5         # degrés vers le haut par tir
var recoil_h := 0.4         # degrés latéraux max par tir
var recovery := 8.0         # vitesse de retour de la visée après recul
var ads_fov := 55.0
var ads_time := 0.2         # secondes pour passer en visée
var move_mult := 1.0        # multiplicateur de vitesse de déplacement
var sound := "rifle"
var max_range := 300.0
var noise_radius := 55.0    # rayon où l'IA entend le tir


func damage_at(dist: float) -> float:
	if dist <= falloff_start:
		return damage
	var t := clampf((dist - falloff_start) / (falloff_end - falloff_start), 0.0, 1.0)
	return damage * lerpf(1.0, falloff_min, t)


## Coups nécessaires et temps pour tuer (1er tir à t = 0).
func ttk(hp: float, dist := 10.0, mult := 1.0) -> Vector2:
	var shots := ceili(hp / (damage_at(dist) * mult))
	return Vector2(shots, (shots - 1) / fire_rate)


static func make_all() -> Array[WeaponData]:
	var garand := WeaponData.new()
	garand.id = "garand"
	garand.display_name = "Fusil M1 Garand"
	garand.damage = 52.0
	garand.head_mult = 2.6
	garand.falloff_start = 60.0
	garand.falloff_end = 120.0
	garand.falloff_min = 0.8
	garand.fire_rate = 4.5
	garand.mag_size = 8
	garand.reserve = 64
	garand.reserve_max = 96
	garand.reload_time = 2.3
	garand.hip_spread = 2.2
	garand.ads_spread = 0.1
	garand.bloom = 0.6
	garand.bloom_max = 2.5
	garand.recoil_v = 2.6
	garand.recoil_h = 0.5
	garand.recovery = 7.0
	garand.ads_fov = 50.0
	garand.ads_time = 0.22
	garand.move_mult = 0.95
	garand.sound = "rifle"
	garand.noise_radius = 60.0

	var thompson := WeaponData.new()
	thompson.id = "thompson"
	thompson.display_name = "Mitraillette Thompson"
	thompson.automatic = true
	thompson.damage = 22.0
	thompson.head_mult = 1.8
	thompson.falloff_start = 15.0
	thompson.falloff_end = 40.0
	thompson.falloff_min = 0.55
	thompson.fire_rate = 11.0
	thompson.mag_size = 30
	thompson.reserve = 120
	thompson.reserve_max = 180
	thompson.reload_time = 2.6
	thompson.hip_spread = 2.8
	thompson.ads_spread = 0.6
	thompson.bloom = 0.25
	thompson.bloom_max = 2.5
	thompson.recoil_v = 0.75
	thompson.recoil_h = 0.45
	thompson.recovery = 9.0
	thompson.ads_fov = 60.0
	thompson.ads_time = 0.18
	thompson.sound = "smg"
	thompson.noise_radius = 45.0

	var colt := WeaponData.new()
	colt.id = "colt"
	colt.display_name = "Pistolet M1911"
	colt.damage = 34.0
	colt.head_mult = 2.0
	colt.falloff_start = 12.0
	colt.falloff_end = 35.0
	colt.falloff_min = 0.6
	colt.fire_rate = 6.0
	colt.mag_size = 7
	colt.reserve = 42
	colt.reserve_max = 70
	colt.reload_time = 1.6
	colt.hip_spread = 1.8
	colt.ads_spread = 0.35
	colt.bloom = 0.5
	colt.bloom_max = 2.0
	colt.recoil_v = 1.8
	colt.recoil_h = 0.6
	colt.recovery = 10.0
	colt.ads_fov = 65.0
	colt.ads_time = 0.14
	colt.move_mult = 1.08
	colt.sound = "pistol"
	colt.noise_radius = 40.0

	var list: Array[WeaponData] = [garand, thompson, colt]
	return list

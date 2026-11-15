# Opération Aube — prototype FPS (Godot 4.7)

FPS solo original situé en Normandie, en juin 1944, avec un rendu low-poly stylisé.
Le jeu se compose d'une mission complète d'environ 8 à 12 minutes, jouée avec deux
coéquipiers IA et trois points de contrôle. Le décor et les armes sont générés par le
code ; les personnages et une partie des sons viennent de packs CC0 (voir Crédits).

## Lancer le jeu

1. Installez [Godot 4.7](https://godotengine.org/download), version standard (pas la
   version .NET).
2. Ouvrez Godot, cliquez sur **Importer** et choisissez `project.godot`.
3. Appuyez sur **F5**.

Vous pouvez aussi utiliser l'exécutable Windows du dossier `export/`, s'il est fourni.

## La mission

| # | Objectif | Ce qui le déclenche |
|---|----------|------------------------|
| 1 | Franchir le bocage | Entrer dans la zone à l'entrée du village |
| 2 | Nettoyer la place | Les 7 défenseurs de la zone `square` sont morts |
| 3 | Poser la charge sur le canon de 88 | Maintenir **E** pendant 3 s près du canon |
| 4 | S'éloigner | Compte à rebours de 10 s, explosion mortelle à moins de 14 m |
| 5 | Repousser la contre-attaque | Les 7 assaillants « chasseurs » sont morts |
| 6 | Rejoindre le point de ralliement | Entrer dans la zone de la fumée verte, à l'ouest |

Points de contrôle : entrée du village, place prise, canon détruit. Après une mort,
l'écran de fin propose **Reprendre au point de contrôle**. Les zones déjà prises ne
sont pas repeuplées et les statistiques sont conservées, morts comprises.

Escouade : le Sgt Miller et le Sdt Novak suivent le joueur en formation et tirent sur les
ennemis visibles. Leur précision est volontairement faible pour que le joueur garde
l'essentiel du travail. Les ennemis peuvent les prendre pour cible. Ils sont
invulnérables, comme dans la plupart des FPS à escouade, ce qui évite un échec de
mission injuste.

## Commandes

ZQSD ou WASD (touches physiques, donc AZERTY et QWERTY fonctionnent tous les deux) ·
Souris · Clic gauche tirer · Clic droit viser · R recharger · 1/2/3 ou molette pour
changer d'arme · G grenade · E interagir · Maj sprint · C/Ctrl s'accroupir ·
Espace sauter · Échap pause.

## Architecture

```
scripts/
  autoload/game.gd       état global, entrées, difficulté, statistiques, bruit (IA)
  autoload/sfx.gd        sons : enregistrements CC0 (variantes) + synthèse (tirs, explosions, UI)
  autoload/fx.gd         particules, traçantes, impacts, fumées
  weapons/weapon_data.gd armes définies comme données (TTK, recul, dispersion…)
  weapons/grenade.gd     grenade physique, dégâts dégressifs, réduits derrière un mur
  player/player.gd       déplacement, tir hitscan, recul, visée, santé régénérante
  player/weapon_view.gd  arme en vue subjective animée par code
  enemy/enemy.gd         IA : vue, ouïe, états, couverture, grenades, rafales, choix de cible
  ally/ally.gd           coéquipier : formation, acquisition de cible, tir, rattrapage
  characters/soldier_model.gd  mannequin KayKit animé (AnimationTree), proportions corrigées
  level/level_builder.gd génération du village, des couvertures et du navmesh
  level/mission.gd       objectifs, apparitions, contre-attaque, fin de partie
  ui/                    HUD, menu principal, pause, écran de fin
tests/
  test_scene.tscn        52 tests automatisés (armes, sons, mission complète, reprise, escouade)
  capture.tscn           captures d'écran de points de vue fixes (outil de dev)
```

Principes retenus :
- **L'équilibrage vit dans les données.** Les valeurs se modifient dans `WeaponData.make_all()` et `Enemy.KINDS`.
- **L'IA ne triche pas.** Un ennemi a un temps de réaction avant son premier tir, rate volontairement ses premières balles et ne voit le joueur que s'il a une ligne de vue dégagée. Seuls les assaillants de la contre-attaque connaissent la position du joueur.
- **La cadence de tir ne dépend pas du framerate.** Les tirs sont planifiés sur une horloge, ce qui est vérifié par les tests.

## Tests

```bash
godot --headless --path . --fixed-fps 60 res://tests/test_scene.tscn
```

Le code de sortie vaut 0 si tout passe. Les tests vérifient la table TTK des armes,
la navmesh et les chemins de l'IA, la cadence de tir, les impacts, la détection du
joueur par les ennemis et l'enchaînement complet des 6 objectifs jusqu'à la victoire.

## Crédits (CC0, domaine public)

- Personnages et animations : **KayKit Character Animations 1.1**, Kay Lousberg
  (kaylousberg.com). Fichiers dans `assets/characters/`, licence incluse.
- Bruitages (pas, impacts, blessures, métal) : **Kenney Impact Sounds** (kenney.nl).
  Fichiers dans `assets/sounds/`, licence incluse.

## Limites connues (prototype)

- Les personnages KayKit gardent un style trapu, même avec la tête réduite et les jambes
  allongées par code (`ProportionModifier`). La pose de visée du pack est faite pour une
  arbalète : le fusil est donc fixé au corps et ne suit pas exactement les mains.
- Les détonations et les explosions sont toujours synthétisées : aucun pack CC0 de
  tirs n'était accessible depuis l'environnement de développement. Pour les remplacer,
  placez des `.ogg` dans `assets/sounds/` et ajoutez-les à `Sfx.RECORDED`.
- Une seule hitbox par soldat : la tête est détectée par la hauteur du cou.
- L'arme peut traverser les murs quand on s'y colle (pas de caméra séparée pour la vue
  subjective).
- Il n'y a pas d'escalier : le personnage ne monte pas les marches, d'où un village
  sans étage accessible.

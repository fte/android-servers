# Trouver l'interrupteur de charge avec `acc -t` — SM-G386F (Android 4.2.2)

Objectif : identifier un fichier sysfs + un couple de valeurs (ON/OFF) qui **coupe** et
**rétablit** de façon fiable la charge du G386F, pour qu'ACC puisse appliquer ses paliers.

Rappels du fonctionnement (doc ACC) :

- `acc -t` teste chaque ligne de la base de switches connue : il écrit la valeur **OFF**,
  vérifie la chute du courant / le passage en « Not charging », puis réécrit **ON**.
  Format d'une ligne : `chemin_valeur_ON valeur_OFF`.
- **Exit 15** = switch valide **et** idle mode natif supporté (le meilleur résultat).
- **Exit 10** = aucun switch de la base ne fonctionne.
- **Exit 16** = échec de *ré*activation → vérifier immédiatement la charge (§6).
- `acc -t p` = génère les candidats depuis le log power_supply, les teste tous et
  **ajoute les bons à la base connue** ; active le log détaillé (`-x` implicite).
- Samsung : `battery/batt_slate_mode 0 1` est le switch de référence (l'installateur
  d'ACC le sélectionne d'office sur Samsung/Exynos). Préférer `slate_mode` à
  `store_mode` : ce dernier cause le bug connu « charge bloquée à 70 % ».

Contexte kernel : driver Samsung `sec_battery` (2013-2014), tout se passe sous
`/sys/class/power_supply/battery/`. Le SoC du G386F est documenté tantôt Broadcom
BCM21664T, tantôt Snapdragon 400 selon les sources — d'où l'importance du dump de
l'étape 1 : personne n'a publié la liste exacte des nœuds de ce kernel.

---

## 0. Préconditions

1. ACC installé et initialisé :
   `su -c 'test -f /dev/.vr25/acc/acca || /data/adb/vr25/acc/service.sh'`
2. BusyBox disponible : `su -c 'which busybox'` (sinon pousser `payload/busybox` du repo
   vers `/system/xbin/busybox` — Android 4.2.2 n'a qu'un toolbox minimal).
3. Batterie entre **20 et 70 %** (hors zone des seuils par défaut d'ACC), chargeur sur
   secteur, et `su -c 'acc -i'` montre `STATUS=Charging`, `CURRENT_NOW ≠ 0`.
4. Session SSH stable (cf. §6 du README à la racine du repo). Garde un **second shell** ouvert pour
   l'observation en direct.

## 1. État des lieux du power_supply

```sh
su
busybox ls -l /sys/class/power_supply/
for f in $(busybox find /sys/class/power_supply -type f); do
  echo "== $f"; busybox cat "$f" 2>/dev/null
done > /sdcard/ps-dump.txt
```

Rapatrier le dump pour archivage : `scp -P 2222 <user>@<ip>:/sdcard/ps-dump.txt .`

À repérer dans le dump : fichiers `*enabled*`, `*_mode`, `*charging*`, `*suspend*`,
`*disable*` sous `battery/`, `fuelgauge/`, `charger/` (ou équivalents). Note : ACC a
déjà généré `/data/adb/vr25/acc-data/logs/power_supply-*.log` à l'installation — c'est
son propre inventaire des nœuds, utilisé par `-p`.

## 2. Test automatique (essayer en premier)

```sh
su -c 'acc -t p'
```

- Laisse tourner : chaque candidat prend quelques secondes (OFF → mesure → ON).
- À la fin, les switches qui marchent sont listés **et ajoutés à la base connue**.
- Si au moins un fonctionne → passer à l'étape 5.
- Sinon, noter `echo $?` (10 = aucun, cf. §6) et lire
  `/sdcard/Download/acc-*.log` (log `-x` implicite) pour voir ce qui a été testé.

## 3. Tests ciblés Samsung (si l'étape 2 a renvoyé 10)

La base intégrée ne connaît pas forcément les nœuds de ce kernel. Tester à la main,
dans cet ordre (du plus sûr au plus exotique) :

| # | Commande | Pourquoi |
|---|---|---|
| a | `su -c 'acc -t battery/batt_slate_mode 0 1'` | switch Samsung officiel (« slate mode »), sans danger, réinitialisé au boot |
| b | `su -c 'acc -t battery/charging_enabled 1 0'` | générique `sec_battery` |
| c | `su -c 'acc -t battery/op_disable_charge 0 1'` | variante du même driver |
| d | `su -c 'acc -t battery_ext/smart_charging_interruption 0 1'` | variante Samsung |
| e | `su -c 'acc -t battery/batt_charging_source 0 2'` | variantes SEC_VIA ; si échec, tester l'orientation inverse `2 0` |
| f | `su -c 'acc -t battery/batt_store_mode 0 1'` | dernier recours — fonctionne mais évite-le au final (bug « 70 % ») |
| g | `su -c 'acc -t battery/restricted_charging 0 1'` | très dernier recours : bride au lieu de couper |

Pendant chaque test, observer en direct dans le second shell :

```sh
su -c 'acc -w1'   # STATUS / CURRENT_NOW / VOLTAGE_NOW rafraîchis chaque seconde
```

Un switch « marche » quand, OFF appliqué : `CURRENT_NOW` tombe à ~0 (± la valeur
d'idle) et/ou `STATUS` passe à `Not charging`/`Idle` — puis **revient** en charge après
le ON.

## 4. Méthode manuelle (si rien ne marche)

1. Générer les candidats depuis l'inventaire d'ACC :
   `su -c 'acc -p'` → liste des switches potentiels **absents** de la base.
2. Les placer dans `/sdcard/experimental_switches.txt` (une ligne `chemin ON OFF`,
   cf. annexe A) puis tester ce fichier :
   `su -c 'acc -t /sdcard/experimental_switches.txt'`.
3. Sonde 100 % manuelle sur un fichier suspect (un seul à la fois, valeur d'origine
   affichée avant d'écrire) :
   ```sh
   f=/sys/class/power_supply/battery/batt_slate_mode
   su -c "cat $f; echo 1 > $f; sleep 5; \
     cat /sys/class/power_supply/battery/current_now; \
     cat /sys/class/power_supply/battery/status; echo 0 > $f"
   ```
   Courant ~0 + `Not charging` → c'est un switch : l'ajouter au fichier d'expérimentation.
4. Statut incohérent (annonce `Discharging` alors que ça charge) : régler
   `batt_status_workaround` (défaut : `true`) et, si besoin, `discharge_polarity` dans
   la config — cf. « default configuration » du README d'ACC.
5. **Aucun** fichier ne coupe la charge : ce kernel n'expose pas de switch → les paliers
   d'ACC sont impossibles, mais la **limitation de courant** peut rester disponible si
   des fichiers comme `constant_charge_current*`, `current_max`, `input_current*` ou
   `batt_tune_*_charge_current` existent et sont inscriptibles (`acc -s c 500`).
   Limiter le courant est universellement sans danger quand les fichiers sont
   inscriptibles.

## 5. Consolider le switch trouvé

1. Forcer ce switch (empêche ACC d'en changer) : `su -c 'acc -ss'`
   → écrit `chargingSwitch=(... --)` dans la config.
2. Re-test : `su -c 'acc -t'` → doit repartir sur ce switch et sortir en 0.
3. Vérifier l'idle sur chargeur : `su -c 'acc -w1'` → après la pause, `STATUS=Idle` et
   `CURRENT_NOW ≈ 0` = idle mode natif (idéal). Sinon l'alternance charge/pause
   (`off_mid`) reste un comportement normal.
4. Seuils : `su -c 'acc 75 70'` (pause à 75 %, reprise à 70 %).
5. Persistance : le switch vit dans `/data/adb/vr25/acc-data/config.txt` ; vérifier que
   `install-recovery.sh` lance bien `service.sh` au boot, puis rebooter et contrôler
   `su -c 'accd,'` (= running).
6. Journal des fichiers qui provoquent reboots/blacklist :
   `/data/adb/vr25/acc-data/logs/write.log` (lignes préfixées `#`).

## 6. Codes de sortie utiles

| Code | Signification | Action |
|---|---|---|
| 0 | switch valide | étape 5 |
| 15 | switch valide + idle natif | étape 5 (cas idéal) |
| 10 | aucun switch valide | étape 3 puis 4 |
| 16 | réactivation échouée | vérifier la charge tout de suite : `acc -i`, débrancher/rebrancher, `acc -e`, ou reboot |
| 7 | impossible de couper (daemon) | cf. troubleshooting ACC |
| 3 / 4 | busybox absent / pas root | prérequis §0 |

## 7. Sécurité

- Un seul fichier à la fois, toujours vérifier le retour à la valeur d'origine
  (d'où le `cat` avant chaque écriture manuelle).
- `batt_slate_mode` est sans danger : c'est le mécanisme du mode économie d'énergie stock.
- Charge bloquée : `su -c 'acc -e'`, rebrancher le chargeur, ou rebooter — le sysfs
  revient à son défaut au boot.
- Reboot spontané pendant un test = fichier fautif, blacklisté automatiquement
  par ACC (`write.log`) : ne pas insister.
- Dépannage général : `su -c 'acc -T'` (tail du log daemon), `su -c 'acc -le'`
  (export complet des logs), `su -c 'acc -sr'` (reset config usine).

---

## Annexe A — `/sdcard/experimental_switches.txt` de départ

Chemins relatifs à `/sys/class/power_supply/`, convention `chemin ON OFF` :

```
battery/batt_slate_mode 0 1
battery/charging_enabled 1 0
battery/op_disable_charge 0 1
battery_ext/smart_charging_interruption 0 1
battery/batt_charging_source 0 2
battery/batt_charging_source 2 0
battery/charging_enabled 0 0 battery/op_disable_charge 0 1 battery/charging_enabled 1 1
battery/batt_store_mode 0 1
battery/restricted_charging 0 1
```

La ligne à trois fichiers est un « switch groupe » repris tel quel de la base officielle
ACC (`install/ctrl-files.sh`) — elle enchaîne plusieurs écritures pour les drivers
récalcitrants. Les deux lignes `batt_charging_source` couvrent les deux orientations de
sémantique observées selon les firmwares : ne garde que celle qui marche.

## Annexe B — fichiers de contrôle de courant à surveiller (pour `acc -s c`)

Liste des motifs qu'ACC considère comme contrôleurs de courant
(`install/ctrl-files.sh`) : `*/constant_charge_current*`, `*/current_max`,
`*/input_current*`, `*/batt_tune_*_charge_current`. Sur ce device, croiser avec le
dump de l'étape 1 et tester une valeur basse (500 mA) puis `acc -s c -` pour restaurer.

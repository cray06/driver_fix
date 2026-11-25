# Contribuer à driver-fix

Merci de prendre le temps d'aider ! Ce guide a deux parties :

- [**Signaler un problème**](#signaler-un-problème) : le script n'a pas réparé ton PC, et tu veux qu'il soit adapté à ta configuration. Aucune connaissance technique n'est nécessaire.
- [**Corriger le script**](#corriger-le-script) : tu veux écrire le correctif toi-même, ou tu traites une issue.

---

## Signaler un problème

### 1. Avant d'ouvrir une issue

Vérifie ces points, ils règlent une bonne partie des cas :

- [ ] Tu as lancé le script **puis redémarré** le PC (rien ne change avant le redémarrage).
- [ ] Tu as relancé le script une seconde fois après ce redémarrage.
- [ ] Le câble HDMI était branché **avant** d'allumer le PC, et tu as essayé une autre entrée sur l'écran.
- [ ] Tu as lu la section [« Ça ne marche toujours pas ? »](README.md#ça-ne-marche-toujours-pas-) du README.
- [ ] Personne n'a déjà ouvert une [issue](https://github.com/cray06/driver_fix/issues?q=is%3Aissue) pour le même modèle de PC. Si c'est le cas, ajoute ton rapport en commentaire plutôt que d'ouvrir une nouvelle issue.

### 2. Créer le rapport de debug

Ouvre un terminal (`Ctrl` + `Alt` + `T`), colle cette commande et appuie sur Entrée :

```bash
wget -qO- https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh | sudo bash -s -- --debug
```

<details>
<summary>Avec <code>curl</code>, ou depuis une copie locale du dépôt</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh | sudo bash -s -- --debug
sudo bash fix.sh --debug
```
</details>

La commande :

- **ne modifie rien** sur ton PC ;
- affiche le rapport complet dans le terminal ;
- l'enregistre dans ton **dossier personnel** sous le nom `driver-fix-debug-AAAAMMJJ-HHMMSS.txt` ;
- affiche à la fin un **lien** qui ouvre une issue déjà pré-remplie (modèle du PC, carte graphique, distribution, noyau, version du script).

> Lance-la **avec `sudo`** : sans les droits administrateur, le journal du noyau (la partie la plus utile) est souvent illisible.

### 3. Ouvrir l'issue

1. Si tu n'en as pas, crée un compte gratuit sur [github.com](https://github.com/signup) et connecte-toi.
2. Dans le terminal, fais **`Ctrl` + clic** sur le lien affiché en dernier. Sinon, va dans l'onglet [**Issues**](https://github.com/cray06/driver_fix/issues), clique sur **New issue** puis choisis **« Le script n'a pas réparé mon PC »**.
3. Vérifie les champs déjà remplis : modèle, carte graphique, distribution, noyau.
4. Choisis ce que tu vois dans **« Que se passe-t-il ? »**, puis décris-le avec tes mots (quel écran est noir, à quel moment, ce que tu as branché…).
5. Dans **« Rapport --debug »**, **glisse-dépose le fichier** `driver-fix-debug-….txt` depuis ton dossier personnel. GitHub l'envoie et insère un lien tout seul.
   - Tu peux aussi cliquer dans le champ et coller le contenu (`Ctrl` + `V`) si le fichier est petit.
6. Coche les deux cases de vérification, puis clique sur **Create**.

### 4. Ce qu'on te demande, et pourquoi

| Champ | Pourquoi c'est utile |
|---|---|
| **Modèle du PC** | Le câblage HDMI (sur la carte NVIDIA, ou derrière un MUX) dépend du modèle exact. |
| **Carte(s) graphique(s)** | L'ID PCI (`10de:xxxx`) décide de la variante du pilote (open ou propriétaire). |
| **Distribution et noyau** | Les paquets disponibles changent d'une version d'Ubuntu à l'autre. |
| **Que se passe-t-il ?** | « Pas de signal » et « écran noir au démarrage » n'ont pas du tout la même cause. |
| **Ce que tu as essayé** | Pour éviter de te proposer ce qui n'a déjà pas marché (BIOS, `prime-select`, autre câble…). |
| **Rapport `--debug`** | Il contient tout le reste : sans lui, on ne peut pas écrire de correctif. |

### 5. Et ensuite ?

- Garde un œil sur tes notifications GitHub : on peut te poser une question ou te demander une capture du BIOS.
- Quand un correctif est prêt, on te demande de le **tester avant qu'il soit publié**. La commande ressemble à celle-ci (le nom de la branche est donné dans l'issue) :

  ```bash
  wget -qO- https://raw.githubusercontent.com/cray06/driver_fix/NOM-DE-LA-BRANCHE/fix.sh | sudo bash
  ```

  Redémarre, puis réponds dans l'issue : ça marche, ou voici le nouveau rapport `--debug`.

### Ce que contient le rapport (et ce qu'il ne contient pas)

Le rapport est un simple fichier texte : **relis-le avant de l'envoyer**, il sera public.

| Contenu | Détail |
|---|---|
| État détecté par driver-fix | Ce que le script a compris de ta machine, et son diagnostic. |
| Machine | Fabricant, modèle, version du BIOS, processeur, quantité de RAM. |
| Système | Distribution, noyau, paramètres de démarrage, type de session (Wayland / X11). |
| Cartes graphiques et écrans | `lspci`, état d'alimentation des cartes, état des sorties HDMI / DisplayPort. |
| Pilote NVIDIA | Module chargé, `modinfo` pour chaque noyau, `nvidia-smi`, firmware GSP. |
| Paquets | Paquets NVIDIA et noyaux installés, dépôts APT, DKMS, `ubuntu-drivers`. |
| Configuration | `modprobe.d`, GRUB, Xorg, GDM, PRIME, Secure Boot. |
| Journaux | Lignes du journal noyau liées au GPU (démarrage actuel et précédent), erreurs système, Xorg. |
| Historique driver-fix | Ce que le script a déjà fait sur ta machine. |

Retirés automatiquement : ton **nom d'utilisateur**, le **nom du PC**, les **UUID** (disques, GPU) et le mot de passe MOK temporaire. Le script ne collecte jamais les numéros de série, les adresses MAC ou IP, ni le contenu de tes fichiers.

---

## Proposer une amélioration

Une distribution à supporter, un message peu clair, une idée ? Ouvre une issue avec le modèle **« Idée ou amélioration »**. Pour une nouvelle distribution, joins aussi un rapport `--debug` lancé sur cette distribution.

---

## Corriger le script

### Organisation du dépôt

```
fix.sh                      le script, en un seul fichier
tests/run_tests.sh          les scénarios de test
tests/stubs/                fausses commandes (apt-get, dpkg, modinfo, nvidia-smi, journalctl…)
.github/workflows/ci.yml    tests lancés à chaque push et pull request
.github/workflows/release.yml   publication d'une version à partir d'un tag
.github/ISSUE_TEMPLATE/     formulaires d'issue
CHANGELOG.md                changements de chaque version
```

### Du rapport au correctif

Chaque correctif part d'un rapport `--debug` et suit toujours le même chemin :

1. **Lire le rapport.** La section « État détecté par driver-fix » montre ce que le script a compris. Compare-la aux journaux et aux paquets pour trouver ce qu'il a mal compris ou n'a pas su faire.
2. **Reproduire le cas dans un scénario de test** (voir le tableau ci-dessous) et vérifier que le test **échoue** avec le script actuel.
3. **Corriger `fix.sh`**, jusqu'à ce que le nouveau test passe sans casser les autres.
4. **Lancer les vérifications** : `bash tests/run_tests.sh` puis `shellcheck -S warning fix.sh tests/run_tests.sh tests/stubs/*`.
5. **Ajouter une ligne** dans la section « Non publié » du [CHANGELOG](CHANGELOG.md).
6. **Ouvrir une pull request** qui contient `Fixes #<numéro de l'issue>`, puis demander à la personne qui a ouvert l'issue de tester la branche (commande dans la partie [« Et ensuite ? »](#5-et-ensuite-)).

La CI doit être verte avant la fusion.

### Traduire un rapport en scénario

Les tests ne demandent ni GPU ni droits root : chaque scénario construit un faux `/sys`, `/proc` et `/lib/modules` dans un dossier temporaire, et remplace les commandes système par les stubs de `tests/stubs/`.

| Dans le rapport | Dans le scénario |
|---|---|
| `NVIDIA 10de:2d59 @ 0000:01:00.0`, sortie de `lspci` | `add_gpu 0000:01:00.0 0x10de 0x2d59 "NVIDIA Corporation …"` |
| Machine (DMI) | `set_dmi LENOVO 82JW "Legion 5 15ACH6H"` |
| Noyau actuel | `echo 6.8.0-50-generic >"$FAKE/kernel"` (ou garder `$K`) |
| Paquets installés (dpkg) | `installed nvidia-driver-595 nvidia-utils-595 …` |
| Pilotes proposés (`ubuntu-drivers`) | texte dans `"$FAKE/ubuntu_drivers"` + `available <paquets>` |
| `modinfo nvidia (<noyau>)` | `set_module "<licence>" <version> <fichier> [<signataire>]` |
| Version du pilote chargé | `set_loaded open\|proprietary <version>` |
| `nvidia-smi` | `nvsmi "<sortie>" <code retour>`, ou `nvsmi_ok` / `nvsmi_nodev` |
| Journal noyau | lignes ajoutées à `"$FAKE/klog"` |
| Firmware NVIDIA | `add_firmware <version>` |
| Secure Boot activé | `echo "SecureBoot enabled" >"$FAKE/sb_state"` |
| `/boot libre` | `echo <Ko> >"$FAKE/boot_free"` |
| Commande absente | `remove_stub <commande>` |

Pour simuler l'effet d'une installation (par exemple un nouveau module qui apparaît), écris un petit script dans `"$FAKE/effects/<paquet>"` : le faux `apt-get` l'exécute quand il « installe » ce paquet (voir `effect_open_prebuilt`). Les fichiers `"$FAKE/apt_sim"`, `"$FAKE/apt_fail"` et `"$FAKE/apt_sim_rc"` simulent les retraits prévus par APT, un échec d'installation ou un conflit.

Vérifications disponibles :

| Fonction | Vérifie que… |
|---|---|
| `expect_out` / `refute_out "texte"` | la sortie du script contient / ne contient pas ce texte |
| `expect_call` / `refute_call "regex"` | une commande a été / n'a pas été appelée (journal `"$FAKE/calls"`) |
| `expect_rc 0`, `expect_rc_nonzero` | le code retour est celui attendu |
| `expect_file` / `refute_file <chemin>` | un fichier a été / n'a pas été créé |
| `no_crash` | aucune erreur bash (`unbound variable`, `command not found`…) |
| `safety` | aucune purge, aucun redémarrage, aucun `sudo`, aucun `pacman -Rdd` |

Exemple complet :

```bash
t_legion_rtx4060_nouveau_loaded() {
  scenario legion_rtx4060_nouveau_loaded
  add_gpu 0000:01:00.0 0x10de 0x28e0 "NVIDIA Corporation AD107M [GeForce RTX 4060 Max-Q / Mobile]"
  set_dmi LENOVO 82RG "Legion Slim 5 16APH8"
  mkdir -p "$FR/sys/module/nouveau"
  installed linux-image-generic
  printf 'driver   : nvidia-driver-580 - distro non-free recommended\n' >"$FAKE/ubuntu_drivers"
  available nvidia-driver-580 "linux-modules-nvidia-580-$K" nvidia-utils-580
  run_fix --yes
  expect_out "Pilote choisi par ubuntu-drivers pour ce GPU : nvidia-driver-580"
  expect_call "install -y nvidia-driver-580$"
  no_crash; safety
}
```

Toute fonction dont le nom commence par `t_` est lancée automatiquement.

### Lancer les tests

```bash
bash tests/run_tests.sh              # tous les scénarios
bash tests/run_tests.sh debug        # seulement ceux dont le nom contient « debug »
VERBOSE=1 bash tests/run_tests.sh    # affiche la sortie et les appels des scénarios en échec
```

Ils tournent sous Linux, et sous Windows avec WSL (bien plus rapide que Git Bash). Il faut `bash` 4.4 ou plus récent et `shellcheck` (`sudo apt install shellcheck`).

### Règles du projet

- **Un seul fichier bash, sans dépendance** : `fix.sh` doit pouvoir tourner via `wget … | sudo bash` sur une installation neuve.
- **Pas de commentaires dans le code** : des noms de fonctions et de variables clairs, et les scénarios de test servent de documentation.
- **Messages en français**, courts, compréhensibles par quelqu'un qui débute sous Linux.
- **Sécurité d'abord** : ne jamais purger, ne jamais retirer un paquet non NVIDIA (passer par `apt_safe_install` / `apt_check_removals`, qui simulent l'opération avant), ne jamais redémarrer à la place de l'utilisateur, ne jamais conseiller de désactiver Secure Boot.
- **Toute action passe par `run`** : elle est alors journalisée et respecte `--dry-run`. Une modification durable s'enregistre avec `history_add`, accompagnée de la commande pour l'annuler.
- **Idempotent** : relancer le script ne doit refaire que ce qui manque.
- **Un nouveau cas géré = un nouveau scénario de test.**

### Publier une version

1. Mets à jour `VERSION` dans `fix.sh` ([versionnage sémantique](https://semver.org/lang/fr/) : correctif `2.1.1`, nouveau cas géré `2.2.0`).
2. Dans `CHANGELOG.md`, renomme « Non publié » en `## [2.1.1] - AAAA-MM-JJ`.
3. Fusionne sur `main`, puis pousse le tag :

   ```bash
   git tag v2.1.1
   git push origin v2.1.1
   ```

4. Le workflow `release.yml` relance tous les tests, vérifie que le tag, `VERSION` et le CHANGELOG correspondent, puis publie la release avec `fix.sh` et les notes du CHANGELOG.

La commande du README pointe toujours sur `main` : un correctif fusionné est disponible pour tout le monde immédiatement.

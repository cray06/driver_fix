<div align="center">

```
░█▀▄░█▀▄░▀█▀░█░█░█▀▀░█▀▄░░░█▀▀░▀█▀░█░█
░█░█░█▀▄░░█░░▀▄▀░█▀▀░█▀▄░░░█▀▀░░█░░▄▀▄
░▀▀░░▀░▀░▀▀▀░░▀░░▀▀▀░▀░▀░░░▀░░░▀▀▀░▀░▀
```

**Ton écran HDMI ne marche pas sous Linux ? Une commande, un redémarrage, et dans la plupart des cas c'est réglé.**

![Bash](https://img.shields.io/badge/bash-script-4EAA25?logo=gnubash&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-support%20complet-E95420?logo=ubuntu&logoColor=white)
![NVIDIA](https://img.shields.io/badge/NVIDIA-GeForce%20%2F%20RTX-76B900?logo=nvidia&logoColor=white)
![Licence](https://img.shields.io/badge/licence-MIT-blue)

</div>

---

## Lancement rapide

Ouvre un terminal (`Ctrl` + `Alt` + `T`), colle cette commande et appuie sur Entrée :

```bash
wget -qO- https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh | sudo bash
```

<details>
<summary>Tu préfères <code>curl</code> ?</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh | sudo bash
```
</details>

Le script demande ton mot de passe, puis **fait tout seul, sans question** : il analyse ton PC, choisit le bon pilote et l'installe.

**À la fin : redémarre ton PC, c'est fini.** Le script ne redémarre jamais à ta place.

Tu veux juste voir ce qui ne va pas, sans rien modifier ? Ajoute `-s -- --diagnose` après `sudo bash`.

---

## Prérequis

- Ubuntu 22.04 ou plus récent (ou une dérivée : Mint, Pop!\_OS, Zorin…) pour le support complet.
- Une connexion Internet (téléchargement des paquets).
- Les droits administrateur (`sudo`).
- Un peu de place dans `/boot` (le script prévient s'il reste moins de 150 Mo).
- Avec Secure Boot, dans de rares cas : taper une fois un mot de passe affiché par le script, au redémarrage (voir plus bas).

---

## Pourquoi l'HDMI ne marche pas ?

Sur la plupart des PC portables « gaming », **le port HDMI est câblé directement sur la carte NVIDIA**. Si le pilote NVIDIA ne fonctionne pas, l'écran externe reste noir, même si l'écran du portable marche très bien (lui passe par la puce Intel/AMD).

Les causes que le script sait détecter :

| Cause | Ce qui se passe |
|---|---|
| **Mauvaise variante du pilote** | Les cartes **RTX 50 (Blackwell)** n'acceptent que les modules noyau NVIDIA **open**. Avec le module propriétaire, le noyau affiche `requires use of the NVIDIA open kernel modules` puis `RmInitAdapter failed`, et `nvidia-smi` répond `No devices were found`. |
| **Restes d'un ancien pilote** | Un paquet `linux-modules-nvidia-XXX-…` propriétaire, ou un module DKMS ancien, continue de fournir le mauvais module au démarrage. |
| **Mise à jour du noyau** | Ubuntu installe un nouveau noyau, mais pas le pilote NVIDIA qui va avec. |
| **Pilote jamais installé** | Linux utilise `nouveau`, le pilote libre, qui gère mal les cartes récentes. |
| **Secure Boot** | Le module est installé mais le firmware refuse de le charger car sa signature n'est pas reconnue. |
| **Firmware GSP manquant** | Les modules open ont besoin des fichiers `/lib/firmware/nvidia/<version>/gsp_*.bin`. |
| **Mode PRIME « intel »** | La carte NVIDIA est éteinte pour économiser la batterie… et le port HDMI avec. |
| **Pas redémarré** | Le nouveau module est sur le disque mais l'ancien tourne encore en mémoire. |
| **Installation interrompue** | Une mise à jour coupée en plein milieu a laissé des paquets à moitié installés. |

---

## Ce que fait le script

```
  ━━ 2/5 · Carte graphique ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ● NVIDIA Corporation GB206M [GeForce RTX 5060 Max-Q / Mobile]
  ● Advanced Micro Devices, Inc. [AMD/ATI] Rembrandt
  Type             portable hybride (iGPU + NVIDIA)
  ID PCI NVIDIA    10de:2d59
  Pilote chargé    595.99.02 (propriétaire)
  Module sur disque propriétaire 595.99.02
  Variante requise open
  nvidia-smi       No devices were found

  ━━ 3/5 · Diagnostic ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✖ Le module installé pour 7.0.0-42-generic est propriétaire alors que ce GPU exige les modules open
  ✖ Le paquet nvidia-driver-595 installe la variante propriétaire, incompatible avec ce GPU
  ✖ Modules noyau de la mauvaise variante encore installés : linux-modules-nvidia-595-7.0.0-42-generic linux-modules-nvidia-595-generic
  ✖ Le module chargé en mémoire est propriétaire alors que ce GPU exige les modules open
  ✖ Le pilote est chargé mais n'arrive pas à initialiser le GPU (RmInitAdapter failed (0x22:0x56:1017))
  ⚠ Le noyau indique que ce GPU exige les modules NVIDIA open (confirmé par les logs)
  ➜ Cause identifiée : module propriétaire chargé sur un GPU qui exige les modules open

  ━━ 4/5 · Réparation ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✔ Même version, variante open : nvidia-driver-595-open
  ➜ Remplacement prévu : nvidia-driver-595 → nvidia-driver-595-open
  ⚠ Cette installation remplace : nvidia-driver-595 libnvidia-gl-595
  ✔ Installation du pilote nvidia-driver-595-open
  ✔ Retrait des modules propriétaires incompatibles
  ✔ Module NVIDIA pré-compilé et signé pour 7.0.0-42-generic
  ✔ Reconstruction de l'initramfs (tous les noyaux)

  ━━ 5/5 · Vérification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✔ 7.0.0-42-generic   module open (Dual MIT/GPL) · actuel · démarrage par défaut
  ➜ Le nouveau pilote sera actif au prochain démarrage.
```

*(Sortie produite par les tests automatisés avec un faux système, pas sur une vraie machine.)*

En détail :

1. **Détecte** la distribution et sa version, les noyaux installés, les cartes graphiques (ID PCI), la variante du module NVIDIA **sur le disque** (licence `Dual MIT/GPL` = open, `NVIDIA` = propriétaire) et **en mémoire** (`/proc/driver/nvidia/version`), les paquets NVIDIA installés, l'état DKMS, Secure Boot, PRIME, les sorties HDMI/DisplayPort et le journal du noyau.
2. **Diagnostique** : `RmInitAdapter`, modules open requis, firmware GSP, *fallen off the bus*, signature refusée, `nvidia-smi` absent ou en échec, version mismatch, `/boot` presque plein…
3. **Répare** (Ubuntu) :
   - répare les paquets interrompus (`dpkg --configure -a`) ;
   - choisit le pilote : garde celui installé s'il est de la bonne variante, sinon prend **la même version en open**, sinon **la recommandation d'`ubuntu-drivers`** (qui se base sur l'ID PCI de ta carte) ;
   - **simule chaque opération APT d'abord** (`apt-get -s`) et refuse si elle retirerait autre chose que des paquets NVIDIA ;
   - retire les paquets de modules de la mauvaise variante (désinstallation simple, jamais de purge) ;
   - installe le module **pré-compilé et signé** pour chaque noyau, sinon le compile avec DKMS, puis **vérifie la variante obtenue** ;
   - installe le paquet qui suit automatiquement les futurs noyaux ;
   - désactive `nouveau` et active `nvidia-drm modeset=1`, **seulement si un module NVIDIA utilisable est présent** (sinon risque d'écran noir) ;
   - repasse le mode PRIME de `intel` à `on-demand` sur les portables hybrides ;
   - avec Secure Boot, prépare l'enregistrement de la clé MOK si le module a été compilé localement.
4. **Vérifie** que chaque noyau a bien le bon module, puis te dit de redémarrer.
5. **Garde une trace** : journal `/var/log/driver-fix.log`, historique des changements `/var/lib/driver-fix/history.log`.

Au lancement suivant, le script sait si le PC a redémarré depuis la dernière réparation : si le GPU ne répond toujours pas, il le dit au lieu de répéter la même correction.

> Le script est **idempotent** : tu peux le relancer autant de fois que tu veux, il ne refait que ce qui manque. Deux exécutions simultanées sont bloquées.

---

## Cartes RTX 50 (Blackwell) et modules « open »

NVIDIA publie deux variantes du module noyau : **propriétaire** et **open**. Les cartes Blackwell (GeForce RTX 50xx) ne fonctionnent qu'avec la variante **open**. Sous Ubuntu, ce sont les paquets qui finissent par `-open` (`nvidia-driver-595-open`, `linux-modules-nvidia-595-open-…`).

Le script considère que la variante open est obligatoire :
- **avec certitude** si le noyau affiche `requires use of the NVIDIA open kernel modules` ;
- **par déduction** si l'ID PCI de la carte est `10de:2900` ou plus (Blackwell et après). Le diagnostic précise toujours laquelle des deux sources a été utilisée.

Pour les cartes plus anciennes (RTX 20/30/40, GTX 16), le pilote déjà installé est conservé, quelle que soit sa variante.

**Vérifier à la main** quelle variante tourne :

```bash
cat /proc/driver/nvidia/version          # « Open Kernel Module » = open
modinfo -F license nvidia                # « Dual MIT/GPL » = open, « NVIDIA » = propriétaire
modinfo -F filename nvidia               # fichier utilisé (updates/dkms = compilé par DKMS)
sudo journalctl -k -b | grep -Ei 'nvrm|nvidia'
nvidia-smi
```

---

## Secure Boot : l'écran bleu au redémarrage

Il n'est **pas nécessaire de désactiver Secure Boot**. Sur Ubuntu, les modules pré-compilés (`linux-modules-nvidia-…`) sont déjà signés et se chargent directement.

Si le module a dû être compilé sur ta machine (DKMS), il est signé avec une clé locale (MOK) qu'il faut enregistrer une fois. Le script s'en occupe tout seul et **t'affiche un mot de passe à 8 chiffres** à la fin. Au redémarrage, un **écran bleu « MOK management »** apparaît :

1. Appuie sur une touche → **Enroll MOK**
2. **Continue** → **Yes**
3. Tape le mot de passe affiché par le script
4. **Reboot**

Cette étape au démarrage ne peut pas être automatisée : c'est la protection de Secure Boot (sinon un logiciel malveillant pourrait faire pareil). Le mot de passe est aussi enregistré dans `/var/lib/driver-fix/mok-password` (lisible par root seulement). Si tu as raté l'écran (il disparaît après 10 s), relance simplement le script.

---

## Options

| Option | Effet |
|---|---|
| `-d`, `--diagnose` | Analyse seulement, ne modifie rien |
| `-n`, `--dry-run` | Affiche tout ce qui serait fait, sans rien modifier |
| `-i`, `--interactive` | Pose les questions au lieu de tout faire automatiquement |
| `-p`, `--prime MODE` | Force le mode PRIME : `on-demand`, `nvidia` ou `intel` |
| `--undo` | Retire les réglages ajoutés par le script (voir plus bas) |
| `--no-color` | Désactive les couleurs |
| `-h`, `--help` | Affiche l'aide |

Ou en local :

```bash
git clone https://github.com/cray06/driver_fix.git
cd driver_fix
sudo ./fix.sh --diagnose
sudo ./fix.sh
```

---

## Distributions supportées

| Distribution | Support |
|---|---|
| Ubuntu 22.04 / 24.04 / 26.04 et + (et variantes Kubuntu, Xubuntu…) | Complet |
| Linux Mint, Pop!\_OS, Zorin OS, elementary OS | Complet (basées sur Ubuntu) |
| Debian 12 / 13 | Expérimental (dépôts `non-free` nécessaires ; RTX 50 seulement si `nvidia-open-kernel-dkms` est disponible) |
| Fedora | Expérimental (active RPM Fusion après accord) |
| Arch Linux, EndeavourOS | Expérimental (`nvidia-open-dkms`, cartes RTX 20xx / GTX 16xx et +) |
| Manjaro | Le script t'indique la commande `mhwd` à lancer |

Cartes **AMD** et **Intel** seules : leurs pilotes sont déjà dans le noyau, le script te donne quelques pistes et peut mettre à jour `linux-firmware`. Sur un portable hybride AMD + NVIDIA, le script ne touche jamais aux paquets du GPU AMD.

---

## Limites

Le script ne peut pas tout corriger. Il le dit quand il rencontre :

- **`fallen off the bus`** : la carte disparaît du bus PCI. C'est souvent lié au BIOS, à l'alimentation ou à la gestion d'énergie PCIe, pas aux paquets.
- **`RmInitAdapter failed` sans cause identifiée** : firmware GSP, BIOS trop ancien, mode graphique du BIOS… Le script affiche le code d'erreur pour une recherche ou une issue.
- **Pilote trop ancien pour la carte** : si aucun pilote proposé par `ubuntu-drivers` ne gère ta carte, il faut attendre une version plus récente dans les dépôts.
- **Câblage HDMI** : sur certains portables, le port HDMI dépend du MUX du BIOS (« Hybrid / Discrete »). Le script ne modifie pas le BIOS.
- **Vérification réelle** : le nouveau module n'est chargé qu'au redémarrage. Le script ne peut donc pas confirmer que le GPU fonctionne avant ce redémarrage : relance `--diagnose` après.

---

## Ça ne marche toujours pas ?

1. **As-tu bien redémarré ?** Rien ne change avant le redémarrage.
2. **Relance le diagnostic** : `sudo bash fix.sh --diagnose`. Il signale si le PC a redémarré depuis la réparation sans amélioration.
3. **Force la carte NVIDIA** pour tout l'affichage (consomme plus de batterie) :
   ```bash
   sudo prime-select nvidia
   ```
   puis redémarre. Pour revenir : `sudo prime-select on-demand`.
4. **Teste un autre câble / une autre entrée** sur l'écran, et branche le câble *avant* d'allumer le PC.
5. **BIOS** : sur certains portables (Lenovo Legion, ASUS ROG, MSI…), une option « Hybrid Graphics / MUX / Discrete GPU » peut aider. Mets aussi le BIOS à jour.
6. **Ouvre une issue** avec la sortie de `--diagnose` et le fichier `/var/log/driver-fix.log` (il contient les lignes NVIDIA du journal noyau, les modules par noyau et les paquets installés).

---

## Annuler les changements

```bash
sudo bash fix.sh --undo
```

Cette commande retire les fichiers `/etc/modprobe.d/driver-fix-*.conf`, restaure `/etc/default/grub` si le script l'avait modifié, puis reconstruit l'initramfs.

Les **paquets** ne sont pas désinstallés automatiquement (ce serait risqué pour l'affichage). L'historique `/var/lib/driver-fix/history.log` indique, pour chaque changement, la commande exacte pour revenir en arrière, par exemple :

```
2026-10-29 14:02:11  pilote nvidia-driver-595 -> nvidia-driver-595-open (annuler : sudo apt-get install nvidia-driver-595)
```

---

## Sécurité

Lancer un script trouvé sur Internet avec `sudo` lui donne tous les droits. Ce dépôt est public : **lis [`fix.sh`](fix.sh) avant de le lancer** si tu as un doute, et teste d'abord avec `--diagnose` ou `--dry-run`.

Ce que le script s'interdit :
- purger des paquets ou supprimer « tous les paquets NVIDIA » ;
- retirer un paquet non NVIDIA (toute opération APT est simulée avant, et annulée si elle en retire un) ;
- désactiver `nouveau` tant qu'aucun module NVIDIA utilisable n'est installé ;
- redémarrer le PC à ta place ;
- conseiller de désactiver Secure Boot.

Ce qu'il modifie de façon durable (tout est listé dans l'historique) : paquets NVIDIA, deux fichiers dans `/etc/modprobe.d/`, l'initramfs, le mode PRIME, et éventuellement le noyau par défaut de GRUB (avec sauvegarde). Tout s'annule avec `--undo`, et l'option `--interactive` permet de valider chaque étape.

---

## Tests

Les tests tournent **sans carte graphique** : chaque scénario crée un faux `/sys`, `/proc`, `/lib/modules`… et remplace `apt-get`, `dpkg`, `dkms`, `modinfo`, `lspci`, `nvidia-smi`, `journalctl` par des simulations.

```bash
bash tests/run_tests.sh            # tous les scénarios
bash tests/run_tests.sh blackwell  # filtre par nom
VERBOSE=1 bash tests/run_tests.sh  # affiche la sortie des scénarios en échec
```

Scénarios couverts : RTX 5060 avec module propriétaire et `RmInitAdapter` (diagnostic, réparation, simulation), module open sur le disque mais propriétaire en mémoire, restes de modules propriétaires, compilation DKMS qui donne encore la mauvaise variante, pilote open fonctionnel, pilote absent, GPU AMD seul, RTX 40 propriétaire (non forcée en open), `nvidia-smi` absent ou en échec, Secure Boot qui refuse le module, APT absent, installation APT en échec, conflit APT, retrait non souhaité refusé, firmware GSP manquant, échec persistant après redémarrage, `/boot` presque plein, mode automatique par défaut, enregistrement Secure Boot automatique (et repli si mokutil est trop ancien), `--undo`.

Ces tests vérifient la logique du script, **pas le comportement sur un vrai matériel**.

---

## Contribuer

Une distribution, un modèle de PC ou un cas qui ne marche pas ? Les issues et pull requests sont les bienvenues.

- Le script doit rester en **un seul fichier bash**, sans dépendance.
- Vérifie ton code avec [`shellcheck`](https://www.shellcheck.net/) et lance `bash tests/run_tests.sh` (les deux tournent automatiquement sur chaque PR).
- Ajoute un scénario de test pour chaque nouveau cas géré.

## Licence

[MIT](LICENSE) — libre d'utilisation, de modification et de partage.

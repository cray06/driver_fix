<div align="center">

```
░█▀▄░█▀▄░▀█▀░█░█░█▀▀░█▀▄░░░█▀▀░▀█▀░█░█
░█░█░█▀▄░░█░░▀▄▀░█▀▀░█▀▄░░░█▀▀░░█░░▄▀▄
░▀▀░░▀░▀░▀▀▀░░▀░░▀▀▀░▀░▀░░░▀░░░▀▀▀░▀░▀
```

**Ton écran HDMI ne marche pas sous Linux ? Une commande, un redémarrage, c'est réglé.**

![Bash](https://img.shields.io/badge/bash-script-4EAA25?logo=gnubash&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-support%20complet-E95420?logo=ubuntu&logoColor=white)
![NVIDIA](https://img.shields.io/badge/NVIDIA-GeForce%20%2F%20RTX-76B900?logo=nvidia&logoColor=white)
![Licence](https://img.shields.io/badge/licence-MIT-blue)

</div>

---

## Lancement rapide

Ouvre un terminal (`Ctrl` + `Alt` + `T`), colle **une** de ces commandes et appuie sur Entrée :

```bash
wget -qO- https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh | sudo bash
```

<details>
<summary>Tu préfères <code>curl</code> ?</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh | sudo bash
```
</details>

Le script te demande ton mot de passe, analyse ton PC, te montre ce qui ne va pas, puis te demande la permission avant de réparer.

**À la fin : redémarre ton PC, branche ton câble HDMI, c'est fini.**

---

## Pourquoi l'HDMI ne marche pas ?

Sur la plupart des PC portables « gaming » ou avec une carte NVIDIA, **le port HDMI est câblé directement sur la carte NVIDIA**. Si le pilote NVIDIA ne se charge pas, l'écran externe reste noir, même si l'écran du portable marche très bien (lui passe par la puce Intel/AMD).

Les causes les plus fréquentes :

| Cause | Ce qui se passe |
|---|---|
| **Mise à jour du noyau** | Ubuntu installe un nouveau noyau Linux, mais pas le pilote NVIDIA qui va avec. Au redémarrage, plus de pilote. |
| **Pilote jamais installé** | Linux utilise `nouveau`, le pilote libre, qui gère mal les cartes récentes. |
| **Secure Boot** | Le pilote est installé mais le BIOS refuse de le charger car il n'est pas signé. |
| **Mode PRIME « intel »** | La carte NVIDIA est éteinte pour économiser la batterie… et le port HDMI avec. |
| **Pas redémarré** | Le pilote a été mis à jour mais l'ancien tourne encore (*version mismatch*). |
| **Installation interrompue** | Une mise à jour coupée en plein milieu a laissé des paquets à moitié installés. |

---

## Ce que fait le script

```
  ━━ 1/5 · Analyse du système ━━━━━━━━━━━━━━━━━━━━━━━━━━
  Distribution     Ubuntu 24.04.5 LTS
  Noyau actuel     7.0.0-38-generic
  Secure Boot      désactivé

  ━━ 2/5 · Carte graphique ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ● Intel Corporation Alder Lake-P GT1 [UHD Graphics]
  ● NVIDIA Corporation AD107M [GeForce RTX 4060 Max-Q / Mobile]
  Type             portable hybride (iGPU + NVIDIA)

  ━━ 3/5 · Diagnostic ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✖ Pas de module NVIDIA pour le noyau actuel (7.0.0-38-generic)

  ━━ 4/5 · Réparation ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✔ Pilote recommandé pour ta carte : nvidia-driver-595-open
  ✔ Module NVIDIA pré-compilé pour 7.0.0-38-generic
  ✔ Suivi automatique des futures mises à jour du noyau
  ✔ Activation de nvidia-drm modeset (nécessaire pour l'HDMI)
  ✔ Reconstruction de l'initramfs (tous les noyaux)

  ━━ 5/5 · Vérification ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✔ 7.0.0-38-generic   pilote NVIDIA prêt · actuel · démarrage par défaut

  ╭─────────────────────────────────────────────╮
  │  ✔ C'est réparé !                           │
  │                                             │
  │  ➜ Redémarre ton PC pour appliquer le fix,  │
  │    puis branche ton câble HDMI.             │
  ╰─────────────────────────────────────────────╯
```

En détail :

1. **Détecte** ta distribution, tes noyaux installés, ta (tes) carte(s) graphique(s) et le pilote utilisé, l'état de Secure Boot et du mode PRIME.
2. **Diagnostique** ce qui bloque (liste ci-dessus).
3. **Répare** :
   - répare les paquets cassés (`dpkg --configure -a`) si besoin ;
   - choisit le **bon pilote pour ton modèle exact** (celui recommandé par `ubuntu-drivers`, ou garde celui déjà installé) ;
   - installe le module NVIDIA **pour chaque noyau installé** : d'abord la version pré-compilée et signée par Ubuntu, sinon il le compile (DKMS) ;
   - installe le paquet qui **suit automatiquement les futures mises à jour du noyau** → le problème ne revient pas ;
   - désactive `nouveau` et active `nvidia-drm modeset=1` ;
   - repasse le mode PRIME de `intel` à `on-demand` sur les portables hybrides ;
   - avec Secure Boot, prépare l'enregistrement de la clé de signature (voir plus bas) ;
   - si le noyau par défaut ne peut vraiment pas avoir le pilote, propose de démarrer sur un noyau qui l'a.
4. **Vérifie** que chaque noyau a bien son pilote.
5. Te dit de **redémarrer** (et peut le faire pour toi).

> Le script est **idempotent** : tu peux le relancer autant de fois que tu veux, il ne refait que ce qui manque.

---

## Secure Boot : l'écran bleu au redémarrage

Si Secure Boot est activé et que le pilote a dû être compilé, le script te demande de **choisir un mot de passe** (ex : `12345678`).

Au redémarrage, un **écran bleu « MOK management »** apparaît :

1. Appuie sur une touche → **Enroll MOK**
2. **Continue** → **Yes**
3. Tape le mot de passe choisi
4. **Reboot**

Si tu as raté l'écran (il disparaît après 10 s), relance simplement le script.

---

## Options

```bash
# Juste analyser, sans rien modifier
wget -qO- https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh | sudo bash -s -- --diagnose
```

| Option | Effet |
|---|---|
| `-d`, `--diagnose` | Analyse seulement, ne modifie rien |
| `-n`, `--dry-run` | Affiche tout ce qui serait fait, sans rien modifier |
| `-y`, `--yes` | Répond « oui » à toutes les questions (sauf le redémarrage) |
| `-p`, `--prime MODE` | Force le mode PRIME : `on-demand`, `nvidia` ou `intel` |
| `--no-color` | Désactive les couleurs |
| `-h`, `--help` | Affiche l'aide |

Ou en local :

```bash
git clone https://github.com/cray06/driver_fix.git
cd driver_fix
sudo ./fix.sh
```

---

## Distributions supportées

| Distribution | Support |
|---|---|
| Ubuntu 22.04 / 24.04 et + (et variantes Kubuntu, Xubuntu…) | Complet |
| Linux Mint, Pop!\_OS, Zorin OS, elementary OS | Complet (basées sur Ubuntu) |
| Debian 12 / 13 | Expérimental (nécessite les dépôts `non-free`) |
| Fedora | Expérimental (active RPM Fusion) |
| Arch Linux, EndeavourOS | Expérimental (`nvidia-open-dkms`, cartes RTX 20xx / GTX 16xx et +) |
| Manjaro | Le script t'indique la commande `mhwd` à lancer |

Cartes **AMD** et **Intel** seules : leurs pilotes sont déjà dans le noyau, le script te donne quelques pistes et peut mettre à jour `linux-firmware`.

---

## Ça ne marche toujours pas ?

1. **As-tu bien redémarré ?** Rien ne change avant le redémarrage.
2. **Force la carte NVIDIA** pour tout l'affichage (consomme plus de batterie) :
   ```bash
   sudo prime-select nvidia
   ```
   puis redémarre. Pour revenir : `sudo prime-select on-demand`.
3. **Teste un autre câble / une autre entrée** sur l'écran, et branche le câble *avant* d'allumer le PC.
4. **BIOS** : sur certains portables (Lenovo Legion, ASUS ROG, MSI…), une option « Hybrid Graphics / MUX / Discrete GPU » peut aider. Essaie « Discrete ».
5. **Ouvre une issue** avec le résultat de `--diagnose` et le fichier `/var/log/driver-fix.log`.

---

## Annuler les changements

Le script n'ajoute que des choses standard (pilotes officiels) et deux petits fichiers de configuration :

```bash
sudo rm /etc/modprobe.d/driver-fix-*.conf
sudo update-initramfs -u -k all
```

S'il a changé le noyau de démarrage par défaut, une sauvegarde existe :

```bash
sudo cp /etc/default/grub.driver-fix.bak /etc/default/grub
sudo update-grub
```

Le journal complet de tout ce qui a été fait est dans `/var/log/driver-fix.log`.

---

## Sécurité

Lancer un script trouvé sur Internet avec `sudo` donne tous les droits à ce script. Ce dépôt est public : **lis [`fix.sh`](fix.sh) avant de le lancer** si tu as un doute, et teste d'abord avec `--diagnose` ou `--dry-run`.

---

## Contribuer

Une distribution, un modèle de PC ou un cas qui ne marche pas ? Les issues et pull requests sont les bienvenues.

- Le script doit rester en **un seul fichier bash**, sans dépendance.
- Vérifie ton code avec [`shellcheck`](https://www.shellcheck.net/) (lancé automatiquement sur chaque PR).
- Teste avec `--dry-run` avant de proposer une modification.

## Licence

[MIT](LICENSE) — libre d'utilisation, de modification et de partage.

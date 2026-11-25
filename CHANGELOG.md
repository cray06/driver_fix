# Changelog

Toutes les évolutions notables de driver-fix sont listées ici.
Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les versions suivent le [versionnage sémantique](https://semver.org/lang/fr/).

## [Non publié]

## [2.1.0] - 2026-11-25

### Ajouté

- Option `--debug` : crée un rapport complet (machine, cartes graphiques, pilote, paquets, configuration, journaux, historique) dans le dossier personnel, sans rien modifier. Les noms d'utilisateur et de machine, les UUID et le mot de passe MOK sont retirés.
- Lien d'issue pré-rempli (modèle, GPU, distribution, noyau, version) affiché à la fin de `--debug`.
- Modèle du PC (DMI) affiché dans l'analyse du système.
- Détection de WSL : le script explique que le pilote est celui de Windows au lieu de proposer une réparation.
- Formulaires d'issue, modèle de pull request, `CONTRIBUTING.md` et ce changelog.
- CI : tests sur Ubuntu 22.04 et 24.04, exécution réelle de `--diagnose`, `--dry-run` et `--debug`, rapport gardé comme artefact.
- Workflow de release : un tag `vX.Y.Z` relance les tests, vérifie la cohérence avec `VERSION` et le changelog, puis publie la release.
- Tests : rapport `--debug` (contenu et anonymisation), WSL, distribution inconnue, numérotation des étapes, cohérence README / `--help` et changelog / `VERSION`.

### Modifié

- Les messages d'échec renvoient vers `--debug` au lieu de `--diagnose` et du journal brut.
- La numérotation des étapes correspond au mode lancé (`1/3` en diagnostic au lieu de `1/5`).
- Alignement des colonnes correct avec les libellés accentués.

## [2.0.0] - 2026-10-29

### Ajouté

- Prise en charge des cartes Blackwell (RTX 50) : détection des modules open obligatoires (journal noyau ou ID PCI) et passage à la variante `-open` du même pilote.
- Simulation de chaque opération APT avant de l'appliquer, avec refus si un paquet non NVIDIA serait retiré.
- Secure Boot : enregistrement automatique de la clé MOK avec mot de passe affiché.
- Détection : `RmInitAdapter`, firmware GSP, *fallen off the bus*, version mismatch, `/boot` presque plein, paquets interrompus, échec persistant après redémarrage.
- Options `--dry-run`, `--interactive`, `--prime`, `--undo`.
- Historique des changements avec la commande pour les annuler.
- Scénarios de test sans GPU et CI ShellCheck.

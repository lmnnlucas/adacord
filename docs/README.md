# Documentation de l’API

Adacord utilise les commentaires présents dans les spécifications Ada (`.ads`)
comme source de documentation. Les blocs `--` placés après une déclaration
décrivent l’entité précédente ; les balises `@param`, `@return`, `@exception`,
`@field` et `@enum` structurent les informations pour GNATdoc.

La référence lisible est disponible dans [`api.md`](api.md). Elle est générée
à partir des spécifications publiques actuelles et sert aussi de version
consultable dans GitHub.

## Génération HTML avec GNATdoc

GNATdoc est l’outil Ada équivalent à Javadoc. Il lit le projet GPR et produit
des pages HTML avec liens croisés entre packages et déclarations. Il est
distribué avec GNAT Studio. La version à choisir doit correspondre au
compilateur GNAT utilisé pour le projet ; GNATdoc 25.2 est limité à GNAT < 15,
alors que ce crate utilise actuellement GNAT 15 avec AWS 25.

Depuis un environnement où `gnatdoc` est dans le `PATH` :

```sh
gnatdoc -P adacord.gpr --backend=html --generate=public \
  --style=gnat --warnings -O docs/generated
```

La même configuration est enregistrée dans `adacord.gpr` via le package
`Documentation`. Le dossier `docs/generated/` contient la sortie générée et ne
doit pas être modifié à la main. Il est ignoré par Git pour éviter de mélanger
les fichiers dérivés et les sources.

GNATdoc n’est pas installé automatiquement par ce dépôt. GNATdoc 25.2 doit
être exécuté dans un environnement GNAT antérieur à 15 ; GNATdoc 26 demande la
pile de dépendances 26. Installer une version compatible via GNAT Studio ou
un environnement Ada séparé, puis relancer la commande ci-dessus.

La pipeline GitHub Actions utilise la distribution binaire `gnatdoc_bin` 26
dans un job Ubuntu dédié. Elle reconstruit les dépendances avec le toolchain
du projet, génère les pages HTML et publie `docs/generated/` comme artifact
`adacord-api-docs` pour chaque push et chaque pull request.

## Conventions de documentation

- Les API publiques sont documentées dans les `.ads`, jamais uniquement dans
  les corps `.adb`.
- Les secrets, tokens et identifiants d’interaction sont décrits comme
  confidentiels et ne doivent pas apparaître dans les journaux.
- Les limites d’entrée et exceptions sont indiquées au niveau de l’opération
  qui les applique.
- Les packages et types internes restent exclus de la sortie publique de
  GNATdoc avec `--generate=public`.

Pour vérifier la couverture pendant une modification, ajouter `--warnings` à
la génération et traiter toute nouvelle déclaration publique sans commentaire.

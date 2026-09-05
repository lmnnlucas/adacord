# Documentation de l’API

Adacord utilise les commentaires présents dans les spécifications Ada (`.ads`)
comme source de documentation. Les blocs `--` placés après une déclaration
décrivent l’entité précédente ; les balises `@param`, `@return`, `@exception`,
`@field` et `@enum` structurent les informations pour GNATdoc.

La synthèse lisible est disponible dans [`api.md`](api.md). Elle est maintenue
manuellement à partir des spécifications publiques et reste consultable dans
GitHub. La génération GNATdoc ne met pas à jour ce fichier.

## Génération HTML avec GNATdoc

GNATdoc est l’outil Ada équivalent à Javadoc. Il lit le projet GPR et produit
des pages HTML avec liens croisés entre packages et déclarations. Il est
disponible sous forme de distribution binaire Alire `gnatdoc_bin=26.0.0`,
utilisée par la CI avec GNAT 15 et AWS 25.

Depuis un environnement où `gnatdoc` est dans le `PATH` :

```sh
alr -n exec -- gnatdoc -P adacord.gpr --backend=html --generate=public \
  --style=gnat --warnings -O docs/generated
```

`alr exec` fournit les chemins des projets AWS/GNATCOLL et du compilateur.
Un appel direct à GNATdoc hors de cet environnement peut échouer à charger
les dépendances. Le script `tools/generate-docs.ps1` utilise aussi `alr exec`.

La même configuration est enregistrée dans `adacord.gpr` via le package
`Documentation`. Le dossier `docs/generated/` contient la sortie générée et ne
doit pas être modifié à la main. Il est ignoré par Git pour éviter de mélanger
les fichiers dérivés et les sources.

Pour une installation locale, installer `gnatdoc_bin=26.0.0` avec `alr install`
et ajouter le dossier `bin` du préfixe d’installation au `PATH`. Cette
distribution évite de compiler les dépendances du générateur dans le projet.

La pipeline GitHub Actions utilise la distribution binaire `gnatdoc_bin` 26
dans un job Ubuntu dédié. Elle reconstruit les dépendances avec le toolchain
du projet, génère les pages HTML et publie `docs/generated/` comme artifact
`adacord-api-docs` pour chaque push et chaque pull request. Pour un push sur
`main`, un second job déploie la même sortie sur GitHub Pages, à l’adresse
`https://lmnnlucas.github.io/adacord/`.

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

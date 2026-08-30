# Adacord

Adacord est une bibliothèque Ada pour créer et exécuter des bots Discord. La
version `0.1.0-dev` fournit un noyau fonctionnel autour de l’API Discord v10 :

- connexion sécurisée à la Gateway par WebSocket (`wss://`) ;
- identification, heartbeat, ACK, reconnexion et reprise de session ;
- événements typés `READY`, `MESSAGE_CREATE` et `INTERACTION_CREATE` ;
- envoi de messages texte avec gestion des réponses HTTP `429` ;
- enregistrement de commandes slash globales et réponses publiques ou
  éphémères aux interactions ;
- snowflakes Discord sur 64 bits et ensemble complet d’intents ;
- tâche réseau séparée des handlers pour ne pas bloquer le heartbeat.

La bibliothèque utilise [Ada Web Server (AWS)](https://github.com/AdaCore/aws)
pour HTTPS et WebSocket, et se construit avec
[Alire](https://alire.ada.dev/).

## Démarrage rapide

Il faut Alire 2.x et un compilateur GNAT récent. Depuis ce dépôt :

```sh
alr build
alr test
```

La commande `alr test` construit et exécute les 39 assertions hors ligne. Pour
lancer directement le binaire déjà construit :

```sh
# Linux/macOS
./bin/adacord_tests

# Windows PowerShell
.\bin\adacord_tests.exe
```

Pour utiliser la copie locale depuis un autre crate Alire :

```sh
alr with adacord --use=../adacord
```

Le projet GPR de l’application doit importer `adacord` :

```ada
with "adacord";
project My_Bot is
   --  ...
end My_Bot;
```

Après publication dans l’index Alire, la dépendance locale pourra devenir
simplement `alr with adacord`.

## Configurer le bot dans Discord

1. Créer une application puis un bot dans le
   [Discord Developer Portal](https://discord.com/developers/applications).
2. Dans **OAuth2 > URL Generator**, sélectionner les scopes `bot` et
   `applications.commands`, puis inviter le bot sur le serveur de test.
3. Aucun intent privilégié n’est nécessaire pour l’exemple `/ping`.
4. Copier `.env.example` vers `.env`, puis placer le token dans ce fichier. Ne
   jamais ajouter le token au code, aux logs ou au dépôt Git.

```powershell
Copy-Item .env.example .env
# Modifier ensuite .env : DISCORD_BOT_TOKEN=votre-token
alr exec -- gprbuild -P examples/ping_bot.gpr
alr exec -- .\bin\ping_bot.exe
```

Sous Linux ou macOS :

```sh
cp .env.example .env
# Modifier ensuite .env : DISCORD_BOT_TOKEN=votre-token
alr exec -- gprbuild -P examples/ping_bot.gpr
alr exec -- ./bin/ping_bot
```

Le bot charge automatiquement `.env` depuis le dossier courant. Une variable
`DISCORD_BOT_TOKEN` déjà définie dans l’environnement reste prioritaire, ce qui
permet d’utiliser les secrets du système en production et dans la CI. Le fichier
`.env` est ignoré par Git ; seul `.env.example`, sans secret, est versionné.
Le lancement via `alr exec` rend également les bibliothèques TLS disponibles
sur toutes les plateformes. Adacord recherche automatiquement le magasin de
certificats d’Alire et les emplacements système usuels. Si nécessaire, un
fichier de certificats personnalisé peut être indiqué avec
`ADACORD_CA_BUNDLE`.

Au démarrage, le bot crée ou met à jour la commande globale `/ping`, puis
répond `pong` à chaque invocation. Une commande globale peut demander un peu
de temps avant d’apparaître dans tous les serveurs. Le code complet est dans
[`examples/ping_bot.adb`](examples/ping_bot.adb).

## Modèle de programmation

Un handler Ada dérive de `Adacord.Clients.Event_Handler` et redéfinit seulement
les événements utiles :

```ada
type My_Handler is new Adacord.Clients.Event_Handler with null record;

overriding procedure On_Ready
  (Self  : in out My_Handler;
   Bot   : in out Adacord.Clients.Client;
   Event : Adacord.Types.Ready)
is
   pragma Unreferenced (Self);
begin
   Adacord.Clients.Register_Global_Command
     (Bot,
      Application_ID => Event.Application_ID,
      Name           => "ping",
      Description    => "Repond avec pong");
end On_Ready;

overriding procedure On_Interaction_Create
  (Self  : in out My_Handler;
   Bot   : in out Adacord.Clients.Client;
   Event : Adacord.Types.Interaction)
is
   pragma Unreferenced (Self);
   use type Adacord.Types.Interaction_Kind;
begin
   if Event.Kind = Adacord.Types.Application_Command_Interaction
     and then Event.Command_Name.Present
     and then To_String (Event.Command_Name.Value) = "ping"
   then
      Adacord.Clients.Respond_To_Interaction
        (Bot, Event, "pong");
   end if;
end On_Interaction_Create;
```

Initialisation et boucle principale :

```ada
Adacord.Clients.Initialize
  (Bot,
   Token           => Token,
   Gateway_Intents => Adacord.Intents.Guilds);

Adacord.Clients.Run (Bot, Callbacks);
```

`Run` est bloquant. Un handler ou une autre tâche peut appeler
`Adacord.Clients.Stop (Bot)` pour demander un arrêt propre. Les handlers sont
exécutés dans la tâche appelante ; la Gateway conserve sa propre tâche pour les
heartbeats et les reconnexions.

## API actuelle

- `Adacord.Clients` : client haut niveau, cycle de vie, handlers, messages,
  commandes globales et réponses aux interactions.
- `Adacord.Config` : chargement portable des fichiers `.env` et paramètres
  obligatoires.
- `Adacord.Intents` : masques d’intents, dont le raccourci `Message_Bot`.
- `Adacord.Types` : `Snowflake`, `User`, `Message`, `Ready`, `Interaction` et
  `Application_Command`.
- `Adacord.REST` : accès REST bas niveau à `/gateway/bot`, création de
  messages, commandes globales et callbacks d’interaction.
- `Adacord.Events` : conversion stricte du JSON Discord vers les types Ada.

Les mentions automatiques sont désactivées lors d’un envoi (`allowed_mentions`
vide), ce qui évite qu’un contenu réutilisé déclenche accidentellement
`@everyone` ou une autre mention.

## Limites de la version 0.1

La première prise en charge des commandes slash couvre les commandes globales
sans option et leur réponse initiale en texte. Les options, sous-commandes,
réponses différées, suivis, embeds, pièces jointes, composants, réactions,
commandes vocales, compression Gateway et sharding automatique ne sont pas
encore gérés. Le client récupère toutefois le nombre de shards recommandé dans
`Adacord.REST.Gateway_Info` pour une future extension.

Les tests sont entièrement hors ligne : aucun token Discord n’est nécessaire
et aucun message réel n’est envoyé.

## Ressources Discord

- [Référence de l’API](https://docs.discord.com/developers/reference)
- [Gateway](https://docs.discord.com/developers/events/gateway)
- [Gateway events](https://docs.discord.com/developers/events/gateway-events)
- [Application commands](https://docs.discord.com/developers/interactions/application-commands)
- [Receiving and responding](https://docs.discord.com/developers/interactions/receiving-and-responding)
- [Créer un message](https://docs.discord.com/developers/resources/message#create-message)
- [Rate limits](https://docs.discord.com/developers/topics/rate-limits)

## Licence

Adacord est distribué sous licence MIT. Voir [`LICENSE`](LICENSE).

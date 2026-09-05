# Adacord API

Cette référence est dérivée des commentaires GNATdoc présents dans les
spécifications `src/*.ads`. La sortie HTML complète peut être régénérée avec
[`docs/README.md`](README.md) dès que GNATdoc est installé.

## `Adacord`

Bibliothèque de bots Discord. La version est exposée par `Version`.

Les exceptions communes sont :

- `Configuration_Error` : configuration locale, entrée invalide ou mauvais
  état du cycle de vie ;
- `Transport_Error` : échec du transport HTTP, sans exposer les en-têtes ;
- `Protocol_Error` : réponse Discord inattendue ou JSON malformé ;
- `Authentication_Error` : réponse HTTP 401 ou 403 ;
- `Rate_Limit_Error` : limite HTTP 429 impossible à résorber ;
- `Invalid_Event` : événement incomplet, mal typé ou identifiant invalide.

## `Adacord.Clients`

Client haut niveau qui possède les identifiants, le client REST et l’état
synchronisé du cycle de vie. Les callbacks sont exécutés séquentiellement par
la tâche appelant `Run`.

`Initialize` configure le client sans ouvrir la Gateway. Il faut appeler cette
opération avant de partager le client entre tâches et sérialiser toute
réinitialisation avec les autres opérations.

`Run` est bloquant : il connecte la Gateway, lance le worker réseau et appelle
les méthodes de `Event_Handler`. La file contient au plus 1 024 événements.
Lorsqu’elle déborde, le worker s’arrête, les événements déjà acceptés sont
traités et `On_Error` reçoit `Fatal=True`.

`Stop` demande un arrêt coopératif. Les appels AWS bloquants peuvent retarder
le retour ; aucune durée maximale n’est garantie. `Is_Running` reste vrai
jusqu’à la fin du worker et des callbacks.

Les callbacks disponibles sont `On_Ready`, `On_Message_Create`,
`On_Interaction_Create` et `On_Error`. Les implémentations par défaut ne font
rien. Une exception d’un callback applicatif est convertie en erreur générique
et ne termine pas la distribution normale.

`Send_Message` accepte du texte UTF-8 non vide de 2 000 caractères Unicode au
maximum. `Register_Global_Command` crée une commande globale de type 1 sans
options et contrôle le nom sur 32 caractères et la description sur 100.
`Respond_To_Interaction` envoie la réponse initiale de type 4 ; l’option
`Ephemeral` active le drapeau 64. Les réponses différées et les suivis ne sont
pas encore pris en charge.

## `Adacord.REST`

Client HTTP synchrone de l’API Discord v10. `Initialize` exige une URL absolue
HTTP(S), sans identifiants, requête ni fragment. Les tokens et User-Agent sont
validés comme valeurs ASCII imprimables. En production, utiliser HTTPS et
configurer `ADACORD_CA_BUNDLE` avant la première initialisation HTTPS.

`Get_Gateway_Info` lit `/gateway/bot` et retourne l’URL Gateway, le nombre de
shards conseillé et le quota d’identification observé.

`Send_Message` et `Respond_To_Interaction` désactivent les mentions
automatiques. Les tokens d’interaction sont encodés comme un segment d’URL et
ne sont jamais envoyés dans l’en-tête `Authorization`.

Les réponses HTTP 429 sont retentées au plus deux fois, avec `retry_after`
borné à 60 secondes par attente. Les délais négatifs, malformés ou plus longs
provoquent `Rate_Limit_Error`. Les POST utilisent une connexion non persistante
avec `Retry => 0` afin d’éviter de rejouer une opération non idempotente après
une réponse réseau ambiguë.

## `Adacord.Events`

Les fonctions `Parse_Ready`, `Parse_Message`, `Parse_Message_Create` et
`Parse_Interaction_Create` prennent le champ `d` de l’enveloppe Gateway, jamais
l’enveloppe complète. Elles vérifient les champs obligatoires, les types JSON,
les plages numériques et les snowflakes. Un champ optionnel absent ou `null`
produit une valeur optionnelle absente. Les erreurs lèvent `Invalid_Event`.

Les interactions de type commande remplissent `Command_ID`, `Command_Name` et
`Command_Type`. Les codes de type inconnus sont conservés dans `Type_Code` et
représentés par `Unknown_Interaction`.

## `Adacord.Types`

`Snowflake` est un identifiant Discord opaque non signé sur 64 bits. Utiliser
`Parse_Snowflake` pour accepter uniquement les décimaux canoniques compris
entre 1 et `2**64-1`; `Image` reformate l’identifiant et `Is_Valid` teste la
validité sans propager l’exception. `Snowflake_List` conserve l’ordre
d’insertion.

Les enregistrements `User`, `Message`, `Interaction`, `Application_Command` et
`Ready` contiennent le sous-ensemble actuellement pris en charge. Les champs
`Optional_Snowflake` et `Optional_Text` distinguent une valeur absente d’une
valeur présente.

## `Adacord.Intents`

`Intent_Set` est un masque sur 64 bits. Combiner les constantes nommées avec
`or` et vérifier un sous-ensemble avec `Contains`. `Privileged` comprend
`Guild_Members`, `Guild_Presences` et `Message_Content`; ces intents doivent
également être activés dans le portail développeur Discord. `Message_Bot`,
`All_Non_Privileged` et `All_Intents` sont des raccourcis prédéfinis.

## `Adacord.Config`

`Load_Dotenv` charge `NAME=VALUE` depuis `.env`, accepte le BOM UTF-8, les
tabulations, `export`, les guillemets simples/doubles et les commentaires.
Les substitutions et échappements ne sont pas interprétés. Les variables
déjà présentes sont conservées sauf avec `Override => True`.

`Required_Value` retourne une valeur non vide et tente de charger le fichier
dotenv uniquement lorsque le nom n’existe pas déjà dans l’environnement. Les
diagnostics ne contiennent jamais la valeur secrète.

## `Adacord.Gateway`

Package interne de la machine d’état Gateway : identification, heartbeats,
ACK, reconnexion et reprise de session. `Adacord.Clients` fournit son sink
non bloquant. Les heartbeats sollicités ne décalent pas l’échéance périodique.
Une fermeture de reconnexion conserve la session, alors qu’un arrêt explicite
invalide normalement la connexion.

## `Adacord.Bounded_Queues`

Package générique interne fournissant une FIFO protégée à capacité fixe. Les
producteurs ne bloquent pas : `Push` indique si l’élément a été accepté.
`Pop` attend un élément ou `Finish`; `Overflowed` devient vrai de façon
persistante lorsqu’une saturation survient.

## `AWS.Net.WebSocket.Buffered_Client_Fix`

Adaptateur de compatibilité pour les octets que `AWS.Client` peut lire au-delà
de la réponse HTTP 101. `Recover_Buffered_Message` traite au plus un message
par appel, complète une trame partielle depuis le transport réel, conserve les
trames suivantes et envoie les réponses de contrôle sur le vrai transport.
L’appel doit être sérialisé avec les autres lectures et écritures du socket.

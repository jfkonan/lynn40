# Dictée pour Windows

Dictez au lieu de taper, dans n'importe quelle application : Word, Outlook, navigateur, Teams…
Maintenez **Ctrl droit**, parlez, relâchez : le texte apparaît là où se trouve le curseur.

Dictée utilise **votre propre clé API OpenAI**. L'audio n'est envoyé qu'à OpenAI, puis supprimé de votre ordinateur.
Aucune télémétrie, aucun autre serveur.

## Installation

1. Téléchargez `Dictee.exe` (un seul fichier, rien à installer).
2. Rangez-le où vous voulez, par exemple dans `Documents\Dictée`, puis double-cliquez dessus.
3. Au premier lancement, Windows peut afficher « Windows a protégé votre ordinateur » (SmartScreen) :
   cliquez sur **Informations complémentaires**, puis **Exécuter quand même**. Ce message s'affiche pour toute
   application qui n'est pas signée par un éditeur payant.
4. Une icône de micro apparaît dans la zone de notification, près de l'horloge (dans la flèche « ^ » si elle est masquée).
   La fenêtre des réglages s'ouvre : collez votre clé API OpenAI (créée sur <https://platform.openai.com/api-keys>), puis **Enregistrer**.

## Utilisation

| Action | Effet |
|---|---|
| Maintenir **Ctrl droit** et parler | Enregistrement (pastille « Écoute… » en bas de l'écran) |
| Relâcher **Ctrl droit** | Transcription, puis insertion du texte au curseur |
| **Échap** pendant l'enregistrement | Annule la dictée |
| Ctrl droit + une autre touche (Ctrl+C…) | Le raccourci habituel fonctionne ; aucune dictée |

Couleur de l'icône : gris = prête, rouge = écoute, bleu = transcription, orange = erreur (le message s'affiche 4 s dans la pastille).

Clic droit sur l'icône :
- **Dernière transcription** : la recopie dans le presse-papiers (utile si l'insertion a échoué) ;
- **Réglages…** (aussi par double-clic sur l'icône) ;
- **Quitter**.

## Réglages

| Réglage | Par défaut | Remarque |
|---|---|---|
| Modèle | `gpt-4o-transcribe` | `gpt-4o-mini-transcribe` est moins cher ; `whisper-1` est l'ancien modèle. Saisie libre possible. |
| Langue | `fr` | Vide = détection automatique. |
| Vocabulaire | termes OHADA et droit des sociétés | Mots à bien orthographier (noms propres, sigles), séparés par des virgules. |
| Nettoyer le texte | non | Second appel qui ponctue et retire les « euh », sans reformuler. |
| Raccourci | Ctrl droit | Aussi : Alt droit, F8, Ctrl+Maj+Espace. |
| Mode | maintenir pour parler | Ou : appuyer pour démarrer, appuyer pour arrêter. Ctrl+Maj+Espace fonctionne toujours ainsi. |
| Sons | oui | Deux notes brèves au début et à la fin. |
| Restaurer le presse-papiers | oui | Dictée passe par le presse-papiers pour coller, puis remet votre contenu précédent. |
| Lancer au démarrage | non | Lance Dictée à l'ouverture de votre session Windows. |

**Clavier AZERTY** : Alt droit y est la touche **AltGr** (@, #, €…). Préférez Ctrl droit ou F8.

## Bon à savoir

- **Applications lancées en administrateur** : Windows interdit à Dictée d'y simuler Ctrl+V. Le texte est alors laissé
  dans le presse-papiers et la pastille affiche « Texte copié : collez-le avec Ctrl+V ».
- **Durée** : jusqu'à 12 minutes par dictée ; au-delà, l'enregistrement s'arrête et la transcription part automatiquement.
  Une pression de moins de 0,3 s est ignorée.
- **Micro** : si rien n'est capté, vérifiez *Paramètres > Confidentialité et sécurité > Microphone* et l'option
  « Autoriser les applications de bureau à accéder au microphone ».
- **Coût** : facturé par OpenAI sur votre compte, à la minute d'audio (quelques centimes pour plusieurs minutes de dictée).

## Confidentialité

- La clé API est chiffrée par Windows (DPAPI) pour votre seul compte, dans `%APPDATA%\Dictee\apikey.bin`.
- Les réglages sont dans `%APPDATA%\Dictee\settings.json` (sans la clé).
- L'enregistrement est un fichier temporaire dans `%TEMP%`, supprimé juste après la transcription, en cas d'erreur ou d'annulation.
- Le texte dicté n'est jamais envoyé au presse-papiers cloud de Windows ; quand le presse-papiers est restauré,
  il n'entre pas non plus dans l'historique Win+V.

## Désinstallation

Quittez Dictée (clic droit sur l'icône > Quitter), décochez d'abord « Lancer au démarrage » si vous l'aviez activé,
puis supprimez `Dictee.exe` et le dossier `%APPDATA%\Dictee`.

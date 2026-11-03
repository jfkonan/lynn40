# Dictée pour Windows

Dictez au lieu de taper, dans n'importe quelle application : Word, Outlook, navigateur, Teams…
Maintenez **Ctrl droit**, parlez, relâchez : le texte apparaît là où se trouve le curseur.

Dictée utilise **votre propre clé API**, chez le fournisseur de transcription de votre choix :

| Fournisseur | Remarque |
|---|---|
| **OpenAI** (par défaut) | Clé sur <https://platform.openai.com/api-keys>. |
| **Mistral** (Voxtral) | Hébergé dans l'UE. Clé sur <https://console.mistral.ai/api-keys>. |
| **Microsoft** (Azure AI Speech, MAI-Transcribe-2) | Preview, prix promotionnel jusqu'au 31/12/2026. Clé et région d'une ressource Speech du portail Azure. |

L'audio n'est envoyé qu'au fournisseur choisi, puis supprimé de votre ordinateur. Le nettoyage optionnel du texte passe
toujours par OpenAI (il est simplement sauté si vous n'avez pas de clé OpenAI). Aucune télémétrie, aucun autre serveur.

## Installation

1. Téléchargez `Dictee.exe` (un seul fichier, rien à installer).
2. Rangez-le où vous voulez, par exemple dans `Documents\Dictée`, puis double-cliquez dessus.
3. Au premier lancement, Windows peut afficher « Windows a protégé votre ordinateur » (SmartScreen) :
   cliquez sur **Informations complémentaires**, puis **Exécuter quand même**. Ce message s'affiche pour toute
   application qui n'est pas signée par un éditeur payant.
4. Une icône de micro apparaît dans la zone de notification, près de l'horloge (dans la flèche « ^ » si elle est masquée).
   La fenêtre des réglages s'ouvre : choisissez le **Fournisseur** (OpenAI par défaut), collez la clé API de ce fournisseur
   dans « Clés API » (pour Microsoft, indiquez aussi la **Région Azure** de votre ressource), puis **Enregistrer**.

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
| Fournisseur | OpenAI | Ou Mistral (hébergé dans l'UE), ou Microsoft (preview, prix promotionnel jusqu'au 31/12/2026). |
| Modèle (OpenAI) | `gpt-transcribe` | Aussi `gpt-4o-transcribe`, `gpt-4o-mini-transcribe` (moins cher), `whisper-1` (ancien). Saisie libre possible. |
| Modèle (Mistral) | `voxtral-small-transcribe-3` | Aussi `voxtral-mini-transcribe-3`. Saisie libre possible. |
| Modèle (Microsoft) | `mai-transcribe-2` | Saisie libre. |
| Région Azure | `eastus` | Microsoft seulement : région de votre ressource Speech (ex. `westeurope`, `swedencentral`). |
| Langue | `fr` | Vide = détection automatique. |
| Vocabulaire | termes OHADA et droit des sociétés | Mots à bien orthographier (noms propres, sigles), séparés par des virgules, points-virgules ou retours à la ligne (100 termes au maximum pour Mistral et Microsoft). |
| Nettoyer le texte | non | Second appel à OpenAI qui ponctue et retire les « euh », sans reformuler (clé OpenAI requise, sinon sauté). |
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
- **Coût** : facturé par le fournisseur choisi sur votre compte, à la minute d'audio (quelques centimes pour plusieurs minutes de dictée).
- **Noms de modèles** : ils évoluent vite. Si le fournisseur refuse un modèle (« Erreur Mistral (400) : … »), saisissez le nom
  qu'il documente dans la liste « Modèle » des réglages.

## Confidentialité

- Chaque clé API est chiffrée par Windows (DPAPI) pour votre seul compte, dans `%APPDATA%\Dictee\` :
  `apikey.bin` (OpenAI), `apikey-mistral.bin` (Mistral), `apikey-microsoft.bin` (Microsoft).
- Les réglages sont dans `%APPDATA%\Dictee\settings.json` (sans aucune clé).
- L'enregistrement est un fichier temporaire dans `%TEMP%`, supprimé juste après la transcription, en cas d'erreur ou d'annulation.
- Le texte dicté n'est jamais envoyé au presse-papiers cloud de Windows ; quand le presse-papiers est restauré,
  il n'entre pas non plus dans l'historique Win+V.

## Désinstallation

Quittez Dictée (clic droit sur l'icône > Quitter), décochez d'abord « Lancer au démarrage » si vous l'aviez activé,
puis supprimez `Dictee.exe` et le dossier `%APPDATA%\Dictee`.

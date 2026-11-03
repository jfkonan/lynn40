# Dictée

Dictée transcrit votre voix avec **votre propre clé API**, sur le principe de Wispr Flow, et insère le texte
là où se trouve le curseur. Trois fournisseurs de transcription au choix : **OpenAI** (par défaut), **Mistral**
(hébergé dans l'UE) ou **Microsoft** (Azure, MAI-Transcribe-2, en preview). Ce dossier contient deux versions :
- **iPhone** : un clavier AZERTY complet avec une barre de dictée (ci-dessous) ;
- **Mac** : une app de barre des menus (voir « Sur Mac » plus bas).

Le comportement commun est décrit dans [`../SPEC.md`](../SPEC.md).

## Comment ça marche

iOS interdit aux claviers d'utiliser le micro. Dictée est donc composée de deux éléments :
- **l'app Dictée**, qui écoute, envoie l'audio au fournisseur choisi et garde vos clés ;
- **le clavier Dictée**, un clavier AZERTY complet surmonté d'une barre de dictée, qui insère le texte.

Le principe est celui de Wispr Flow : vous démarrez une « session » une fois, puis vous dictez dans n'importe quelle app sans la quitter.

## Utilisation

1. **Première fois** : ouvrez l'app Dictée, choisissez le fournisseur et collez sa clé API (`sk-…` pour OpenAI).
2. **Installez le clavier** : Réglages > Général > Clavier > Claviers > Ajouter > Dictée, puis activez « Autoriser l'accès complet ». Cet accès sert à communiquer avec l'app ; le clavier n'envoie rien lui-même sur Internet.
3. **Pour dicter** :
   - Passez au clavier Dictée avec le globe 🌐 et touchez le micro.
   - Si aucune session n'est active, l'app s'ouvre. Revenez à votre app avec « ‹ » en haut à gauche.
   - Touchez le micro, parlez, puis retouchez-le : le texte s'insère au curseur.
4. La session s'arrête seule après 10 minutes sans dictée. Ce délai est réglable.

## Le clavier

- **Barre supérieure** : ☰ ouvre le panneau rapide ; la pastille blanche affiche le style d'écriture (« Brut. »,
  « Formel. »…) et, pendant la dictée, « Écoute… » puis « Transcription… » ; le micro (cercle noir) démarre et arrête
  la dictée. Il devient rouge pendant l'écoute ; un appui long l'annule.
- **Touches AZERTY** comme sur iOS : majuscule (double toucher = verrouillage), majuscule automatique, double espace = « . »,
  effacement répété, accents par appui long (é è ê ë, à â æ, ç, ù û ü, î ï, ô œ, ÿ), claviers `123` et `#+=`.
  La barre d'espace affiche « Dictée ».
- **Panneau rapide** : réinsérer une des 10 dernières transcriptions, effacer l'historique, changer le style,
  le fournisseur ou la langue, ouvrir l'app.

## Styles d'écriture

| Style | Effet |
|---|---|
| Brut (défaut) | Texte tel que transcrit (nettoyé seulement si « Nettoyer le texte » est activé) |
| Formel | Registre soutenu et professionnel, sans changer le sens |
| Courriel | Paragraphes courts, ton courtois ; formule de politesse seulement si elle est dictée |
| Décontracté | Phrases simples, ton direct |

Un style autre que « Brut » passe par le nettoyage chez OpenAI, avec la clé OpenAI (même si le fournisseur de
transcription est Mistral ou Microsoft). Sans clé OpenAI, le texte brut est inséré.

## Réglages

| Réglage | Par défaut | Rôle |
|---|---|---|
| Fournisseur | OpenAI | OpenAI, Mistral (hébergé dans l'UE) ou Microsoft (preview, prix promotionnel jusqu'au 31/12/2026) |
| Modèle OpenAI | `gpt-transcribe` | Aussi `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1` ou saisie libre |
| Modèle Mistral | `voxtral-small-transcribe-3` | Aussi `voxtral-mini-transcribe-3` ou saisie libre |
| Modèle Microsoft | `mai-transcribe-2` | Saisie libre |
| Région Azure | `eastus` | Région de votre ressource Azure Speech (ex. `westeurope`, `swedencentral`) |
| Langue | `fr` | Code ISO de la langue parlée |
| Vocabulaire | sigles OHADA, termes de droit des sociétés | Aide le modèle à bien orthographier vos termes (Mistral et Microsoft : 100 termes au maximum) |
| Nettoyer le texte | désactivé | Ponctue et retire les « euh » sans reformuler (second appel, `gpt-4o-mini`, toujours chez OpenAI avec la clé OpenAI ; sauté sans clé OpenAI) |
| Style d'écriture | Brut | Brut, Formel, Courriel ou Décontracté ; se règle dans l'app ou depuis le clavier |

Chaque fournisseur a sa propre clé, rangée dans le Trousseau. Les noms de modèles et le format de l'API Azure
sont à confirmer lors des premiers essais (voir [HANDOFF.md](HANDOFF.md)).

## Confidentialité

- Vos clés API restent dans le Trousseau de l'iPhone.
- L'audio est envoyé uniquement au fournisseur choisi (OpenAI, Mistral ou Microsoft), avec votre clé. Il est supprimé
  du téléphone juste après la transcription. Le texte n'est envoyé à OpenAI que si le nettoyage est activé ou si un style autre que « Brut » est choisi.
- Les 10 dernières transcriptions restent sur l'iPhone (espace partagé entre l'app et le clavier) ; « Effacer l'historique »,
  dans l'app ou le panneau du clavier, les supprime.
- Pendant une session, iOS affiche le point orange du micro.

## Sur Mac

Dictée vit dans la barre des menus (icône micro), sans icône dans le Dock.

1. **Première fois** : la fenêtre de réglages s'ouvre. Choisissez le fournisseur, collez sa clé API, puis accordez les autorisations :
   - **Micro**, pour enregistrer votre voix ;
   - **Accessibilité** (Réglages Système > Confidentialité et sécurité > Accessibilité), pour écouter la touche Fn
     et coller le texte dans l'app au premier plan.
2. **Touche 🌐** : dans Réglages Système > Clavier, réglez « Appuyer sur la touche 🌐 pour » sur **« Ne rien faire »**.
3. **Pour dicter** : placez le curseur où vous voulez écrire, **maintenez Fn**, parlez, relâchez.
   Le texte s'insère au curseur. **Échap** annule.
   - Autre raccourci possible : **⌥Espace**, qui fonctionne même sans l'autorisation Accessibilité.
   - Mode « basculer » : un appui démarre, un appui arrête.
4. Une pastille en bas de l'écran indique « Écoute… » puis « Transcription… ». Un son discret marque le début et la fin.
5. Le menu de l'icône permet de recopier la dernière transcription et d'ouvrir les réglages.

| Réglage propre au Mac | Par défaut | Rôle |
|---|---|---|
| Raccourci | Fn | Fn ou ⌥Espace |
| Mode | Maintenir pour parler | Ou « appuyer pour démarrer, appuyer pour arrêter » |
| Sons de début et de fin | activé | « Tink » et « Pop » |
| Restaurer le presse-papiers | activé | Remet votre ancien presse-papiers environ 1 s après le collage |
| Lancer à l'ouverture de session | désactivé | Démarre Dictée avec votre Mac |

Sur Mac, les clés restent dans le Trousseau du Mac. Le texte passe un court instant par le presse-papiers pour être collé.
Sans l'autorisation Accessibilité, il est seulement copié : collez-le avec ⌘V.

## Compiler le projet

Voir [HANDOFF.md](HANDOFF.md). Il faut un Mac, Xcode et XcodeGen. Schéma `Dictee` pour l'iPhone,
schéma `DicteeMac` pour le Mac (macOS 13 ou plus récent).

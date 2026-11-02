# Dictée

Dictée transcrit votre voix avec **votre propre clé API OpenAI**, sur le principe de Wispr Flow, et insère le texte
là où se trouve le curseur. Ce dossier contient deux versions :
- **iPhone** : un clavier de dictée (ci-dessous) ;
- **Mac** : une app de barre des menus (voir « Sur Mac » plus bas).

Le comportement commun est décrit dans [`../SPEC.md`](../SPEC.md).

## Comment ça marche

iOS interdit aux claviers d'utiliser le micro. Dictée est donc composée de deux éléments :
- **l'app Dictée**, qui écoute, envoie l'audio à OpenAI et garde votre clé ;
- **le clavier Dictée**, qui affiche un gros bouton micro et insère le texte.

Le principe est celui de Wispr Flow : vous démarrez une « session » une fois, puis vous dictez dans n'importe quelle app sans la quitter.

## Utilisation

1. **Première fois** : ouvrez l'app Dictée et collez votre clé OpenAI (`sk-…`).
2. **Installez le clavier** : Réglages > Général > Clavier > Claviers > Ajouter > Dictée, puis activez « Autoriser l'accès complet ». Cet accès sert à communiquer avec l'app ; le clavier n'envoie rien lui-même sur Internet.
3. **Pour dicter** :
   - Passez au clavier Dictée avec le globe 🌐 et touchez le micro.
   - Si aucune session n'est active, l'app s'ouvre. Revenez à votre app avec « ‹ » en haut à gauche.
   - Touchez le micro, parlez, puis retouchez-le : le texte s'insère au curseur.
4. La session s'arrête seule après 10 minutes sans dictée. Ce délai est réglable.

## Réglages

| Réglage | Par défaut | Rôle |
|---|---|---|
| Modèle | `gpt-4o-transcribe` | `gpt-4o-mini-transcribe` coûte moitié moins cher |
| Langue | `fr` | Code ISO de la langue parlée |
| Vocabulaire | sigles OHADA, termes de droit des sociétés | Aide le modèle à bien orthographier vos termes |
| Nettoyer le texte | désactivé | Ponctue et retire les « euh » sans reformuler (second appel, `gpt-4o-mini`) |

## Confidentialité

- Votre clé API reste dans le Trousseau de l'iPhone.
- L'audio est envoyé uniquement à OpenAI, avec votre clé. Il est supprimé du téléphone juste après la transcription.
- Pendant une session, iOS affiche le point orange du micro.

## Sur Mac

Dictée vit dans la barre des menus (icône micro), sans icône dans le Dock.

1. **Première fois** : la fenêtre de réglages s'ouvre. Collez votre clé OpenAI, puis accordez les autorisations :
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

Sur Mac, la clé reste dans le Trousseau du Mac. Le texte passe un court instant par le presse-papiers pour être collé.
Sans l'autorisation Accessibilité, il est seulement copié : collez-le avec ⌘V.

## Compiler le projet

Voir [HANDOFF.md](HANDOFF.md). Il faut un Mac, Xcode et XcodeGen. Schéma `Dictee` pour l'iPhone,
schéma `DicteeMac` pour le Mac (macOS 13 ou plus récent).

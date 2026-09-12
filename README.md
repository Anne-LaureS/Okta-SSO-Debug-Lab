# 🔑 SSO Debug Lab — OIDC & SAML (Okta)

[![OIDC client_credentials demo](https://github.com/Anne-LaureS/Okta-SSO-Debug-Lab/actions/workflows/oidc-demo.yml/badge.svg)](https://github.com/Anne-LaureS/Okta-SSO-Debug-Lab/actions/workflows/oidc-demo.yml)

Boîte à outils pour diagnostiquer un échec de connexion SSO en isolant chaque
maillon de la chaîne (IdP → token/assertion → application), plutôt qu'en
devinant à partir des symptômes côté utilisateur.

Construit et testé de bout en bout sur un tenant Okta réel (Integrator Free
Plan), avec une collection [Bruno](https://www.usebruno.com/) qui automatise
chaque étape de vérification.

## 🎯 Ce que ça démontre

- Compréhension des protocoles **OIDC** (`client_credentials`, JWT, JWKS) et
  **SAML 2.0** (assertions, bindings Redirect/POST, signature XML)
- Démarche de debug structurée : à chaque étape, un résultat attendu, une
  cause probable si ça échoue, une correction — pas juste une suite de
  commandes
- Capacité à automatiser des vérifications manuelles (décodage JWT/SAML,
  appels aux endpoints IdP) dans un outil réutilisable en équipe
- Gestion propre des secrets dans une collection partagée (aucune valeur
  réelle committée, voir plus bas)

## 📁 Structure du repo

```
procedure-debug-sso.md   Runbook détaillé, étape par étape (OIDC + SAML)
iam-debug/                Collection Bruno
├── oidc/                 Discovery, obtention de token, introspection
├── saml/                 Métadonnées IdP, rejeu d'une assertion capturée
├── auth0-demo/           Démo OIDC sur Auth0 (preuve de fonctionnement
                          hors des limites du plan gratuit Okta)
└── environments/         demo / uat / ope — variables par environnement
```

Le détail de chaque étape, les commandes PowerShell équivalentes et les
diagnostics associés sont dans [`procedure-debug-sso.md`](procedure-debug-sso.md).

## 🛠️ Reproduire ce lab

Les étapes de création des apps Okta (OIDC et SAML, sur un tenant Okta
Developer gratuit) sont détaillées dans [`setup-okta.md`](setup-okta.md).

## 🧪 Utiliser la collection

Sans installer d'extension : la collection est exécutable en ligne de
commande avec le [CLI Bruno](https://www.usebruno.com/) (`npm install -g
@usebruno/cli`), ce que fait justement la démo automatisée ci-dessous.

```bash
cd iam-debug
bru run auth0-demo --env auth0-demo \
  --env-var client_id=<ton-client-id> \
  --env-var client_secret=<ton-client-secret>
```

Elle reste aussi ouvrable dans l'app desktop Bruno (ou son extension VSCode,
si installée) pour suivre le détail des requêtes :

1. Ouvrir `iam-debug/` dans Bruno
2. Sélectionner un environnement, renseigner ses propres identifiants de
   test (jamais dans le fichier partagé — voir ci-dessous)
3. Suivre l'ordre des requêtes dans `oidc/` ou `saml/`

## ✅ Preuve de fonctionnement automatisée

Le flow OIDC `client_credentials` (démo Auth0, voir plus bas) est rejoué à
chaque push et chaque semaine par [ce workflow
GitHub Actions](.github/workflows/oidc-demo.yml) : obtention d'un token,
vérification qu'il s'agit bien d'un JWT valide, non expiré, avec l'audience
attendue. Le badge en haut de ce README reflète l'état du dernier run — ce
n'est pas une affirmation, c'est un test qui échoue si le flow casse.

## 🔐 Secrets

Les fichiers d'environnement ne contiennent que des placeholders. Chaque
utilisateur renseigne ses propres `client_id` / `client_secret` /
`saml_response` localement, marqués **Secret** dans Bruno — jamais commités.

## 💻 Stack

Okta (IdP de test) · Auth0 (démo comparative) · Bruno · PowerShell

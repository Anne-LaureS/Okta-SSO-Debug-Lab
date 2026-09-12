# Captures à fournir

Liste dans l'ordre de `setup-okta.md`. Envoyez-les une par une (ou par lot)
dans la conversation, je les enregistre sous le nom indiqué et je les
intègre au bon endroit avec une légende.

## OIDC

- [X] `01-create-app-oidc.png` — écran **Create App Integration**, avec
  **API Services** sélectionné (Étape 2.2 de `setup-okta.md`)
- [X] `02-client-id.png` — onglet **General** de l'app, `Client ID` visible
- [X] `03-public-key-jwk.png` — section **Public Keys**, la clé JWK ajoutée
  avec son `kid` visible dans la liste
- [X] `04-api-scopes.png` — onglet **Okta API Scopes**, `okta.users.read`
  accordé
- [X] `05-token-response.png` — terminal après `get-token-pkjwt.sh`, avec
  un `access_token` reçu

## SAML

- [X] `06-saml-app-assignments.png` — app `iam-debug-saml`, Actif,
  assignation à Anne-Laure S.
- [X] `07-saml-configure.png` — onglet **Configure SAML**, avec les champs
  Single sign-on URL / Audience URI / Name ID format remplis
- [X] `08-saml-setup-instructions.png` — page **View SAML setup
  instructions**, avec l'App ID (préfixe `exk`) visible
- [X] `09-saml-tracer-capture.png` — **fournie** (SAML-tracer, POST vers
  httpbin.org/post avec badge SAML)

## Preuve automatisée

- [X] `10-github-actions-success.png` — page Actions du repo, run vert
- [X] `11-readme-badges.png` — README avec les badges en haut, tel qu'affiché sur GitHub

---

Format : PNG ou JPG, pas besoin de flouter votre nom (déjà visible dans
plusieurs captures existantes), mais floutez tout ce qui serait un vrai
secret (`client_secret`, contenu de clé privée) si jamais ça apparaît à
l'écran.

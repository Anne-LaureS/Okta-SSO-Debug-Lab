# Reproduire le lab — création des apps Okta

Étapes pour recréer, depuis zéro, les apps Okta utilisées par ce lab (tenant
Okta Developer / Integrator Free Plan). Une fois faites, reporter les valeurs
obtenues dans `iam-debug/environments/demo.bru`.

## Prérequis

- Un compte [Okta Developer](https://developer.okta.com/signup/) (gratuit)
- Accès à la console admin de ce tenant

## App OIDC (client_credentials)

1. **Okta Admin** → Applications → **Create App Integration**
2. Sign-in method : **API Services** (c'est ce type qui active le grant
   `client_credentials`)
3. Nommer l'app (ex: `lab-oidc-client-credentials`) → **Save**
4. Onglet **General** → noter le `Client ID` et générer/copier le
   `Client secret`
5. Onglet **Okta API Scopes** (ou, pour un scope custom, créer d'abord un
   Authorization Server custom sous **Security → API**) : autoriser le scope
   utilisé par `oidc/client-credentials-token.bru` (ex: `test.read`)
6. Reporter dans `environments/demo.bru` :
   - `issuer` = `https://<ton-tenant>.okta.com/oauth2/default`
   - `client_id` / `client_secret` (en Secret dans l'éditeur Bruno, jamais
     dans le fichier committé)
   - `scope`

Valider avec `oidc/discovery.bru` puis `oidc/client-credentials-token.bru`.

**Note** : sur un tenant Okta Integrator Free Plan, ce grant échoue avec
`invalid_grant` / "The NHI Authentication Tokens SKU is not enabled" — le
Custom Authorization Server (`/oauth2/default`) bride `client_credentials`
derrière un SKU payant. Le contournement gratuit et fonctionnel est
`private_key_jwt` contre l'Org Authorization Server (`/oauth2/v1/token`),
voir plus bas.

## Client_credentials qui marche vraiment (private_key_jwt + Org Auth Server)

Sur l'app `iam-debug-m2m` :

1. **General** → Edit → **Client authentication** → **Public key / Private key**
2. Section **Public Keys** → ajoute la clé publique générée dans
   `iam-debug/oidc/.keys-lab/` (voir ce dossier, ignoré par git — la clé
   privée n'y quitte jamais la machine)
3. Onglet **Okta API Scopes** → accorde le scope `okta.users.read`

Puis lance :

```bash
CLIENT_ID=<ton-client-id> iam-debug/oidc/.keys-lab/get-token-pkjwt.sh
```

Ce script construit et signe le JWT `private_key_jwt` en bash/openssl pur
et obtient un vrai token. **Ce n'est volontairement pas un fichier
`.bru`** : le bac à sable de script de Bruno (QuickJS) n'a pas accès au
module `crypto` natif, donc signer un JWT RS256 depuis Bruno n'est pas
possible avec cette version de l'outil — `oidc/client-credentials-pkjwt.bru`
documente le flow mais renvoie vers ce script pour l'exécution réelle.

## App SAML

1. **Okta Admin** → Applications → **Create App Integration** → **SAML 2.0**
2. Général :
   - **Single sign-on URL (ACS)** : une URL qui reçoit vraiment le POST pour
     pouvoir le rejouer ensuite — utiliser un endpoint d'écho public le temps
     du lab, ex. une URL générée sur [webhook.site](https://webhook.site) ou
     `https://httpbin.org/post`
   - **Audience URI (SP Entity ID)** : une valeur arbitraire, ex.
     `urn:portfolio-lab:sp`
   - **Name ID format** : `EmailAddress`
3. Onglet **Assignments** → assigner son propre utilisateur Okta
4. Noter l'**App ID** : visible dans l'URL admin de la page de l'app
   (`.../admin/app/.../instance/<APP_ID>#tab-general`)
5. Reporter dans `environments/demo.bru` :
   - `acs_url` = l'URL ACS choisie à l'étape 2
   - `okta_app_id` = l'App ID noté à l'étape 4

Valider avec `saml/idp-metadata.bru`.

## Capturer un vrai SAMLResponse

1. Ouvrir SAML-tracer, le laisser ouvert
2. Depuis le tableau des apps Okta, lancer le SSO vers l'app SAML créée
   ci-dessus
3. Dans SAML-tracer, repérer le POST vers l'URL ACS (webhook.site/httpbin) et
   copier la valeur de `SAMLResponse`
4. Coller cette valeur dans la variable `saml_response` de l'environnement
   (en local uniquement, jamais committée)

Valider avec `saml/acs-replay.bru`.

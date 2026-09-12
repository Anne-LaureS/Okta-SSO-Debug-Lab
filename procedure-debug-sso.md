# Procédure de débug SSO (OIDC / SAML)

Document à suivre pas à pas quand un utilisateur ne peut pas se connecter via SSO. Toutes les commandes sont en PowerShell (`pwsh`).

## Prérequis (à faire une fois)

- [ ] `pwsh` installé
- [ ] Extension navigateur **SAML-tracer** installée (Firefox ou Chrome)
- [ ] Bruno installé (voir Partie 3 ci-dessous si pas encore fait)
- [ ] Vous avez : le `client_id`/`client_secret` d'une app de test dans votre org Okta

## Étape 0 — Identifier le protocole en cause

Regardez l'URL au moment où la connexion échoue :

| Vous voyez dans l'URL... | Protocole | Aller à |
|---|---|---|
| `response_type=code`, `client_id=...`, redirection vers `/authorize` | OIDC | Partie 1 |
| `SAMLRequest=...` ou `SAMLResponse=...` | SAML | Partie 2 |
| Vous ne savez pas | — | Ouvrez SAML-tracer et relancez la connexion : s'il capture quelque chose, c'est du SAML |

---

## Notre IdP : Okta

- `issuer` = `https://votre-org.okta.com/oauth2/default` (serveur d'autorisation par défaut) ou `https://votre-org.okta.com/oauth2/{authServerId}` pour un serveur custom
- Token endpoint = `{issuer}/v1/token`
- Introspection endpoint = `{issuer}/v1/introspect`
- Authentification du client = **Basic Auth** (`client_id`/`client_secret` dans l'en-tête `Authorization`) par défaut, pas dans le corps de la requête
- Le `scope` doit être un scope défini sur ce serveur d'autorisation dans la console Okta

Toutes les commandes et la collection Bruno (`iam-debug/`) ci-dessous suivent ces conventions.

## Démonstration : preuve de fonctionnement

Cette procédure et la collection Bruno sont conçues pour Okta. Pour prouver que la méthode fonctionne de bout en bout sans dépendre du réseau ou des identifiants de l'entreprise, un environnement de démonstration a été mis en place à part, dans `iam-debug/auth0-demo/`.

Il tourne sur **Auth0** (et non Okta) : sur le plan gratuit "Integrator Free" d'Okta, le grant `client_credentials` contre un serveur d'autorisation personnalisé est bridé derrière un SKU payant ("NHI Authentication Tokens"), ce qui empêche de démontrer ce flow gratuitement sur un tenant Okta de test. Auth0 propose ce même grant sans restriction sur son offre gratuite, et suit un protocole équivalent (OIDC / `client_credentials`) — seuls les endpoints et le format du corps de requête diffèrent (JSON avec `client_secret` dans le corps, au lieu de Basic Auth sur `/v1/token`).

Cette démo reste isolée du reste de la collection : `auth0-demo/get-token.bru` et `auth0-demo/decode-token.bru`, avec son propre environnement `auth0-demo`. Elle illustre la méthode (obtenir un token, décoder son contenu), pas la procédure Okta elle-même, qui reste la référence pour un débug réel en entreprise.

## Partie 1 — Procédure OIDC

### Étape 1.1 — Le discovery répond-il ?

```powershell
Invoke-RestMethod https://votre-org.okta.com/oauth2/default/.well-known/openid-configuration |
  Select-Object issuer, authorization_endpoint, token_endpoint, jwks_uri
```

- **Ça échoue (timeout, 404, 500)** → l'IdP est injoignable ou l'URL de config est fausse. **Stop, remontez côté infra/IdP**, inutile d'aller plus loin.
- **Ça répond** → notez la valeur `issuer` et passez à 1.2.

### Étape 1.2 — Un token peut-il être obtenu en direct ?

La méthode dépend du plan Okta de l'organisation.

**Sur un tenant Okta payant** (Workforce/Customer Identity avec le SKU
M2M activé), le client s'authentifie en `client_secret_basic` contre un
Authorization Server custom :

```powershell
$pair = "$($env:CLIENT_ID):$($env:CLIENT_SECRET)"
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))

Invoke-RestMethod -Method Post `
  -Uri https://votre-org.okta.com/oauth2/default/v1/token `
  -Headers @{ Authorization = "Basic $basic" } `
  -Body @{
    grant_type = 'client_credentials'
    scope      = 'votre.scope.custom'
  }
```

- **Erreur `unauthorized_client` ou `invalid_scope`** → le client n'a pas la permission/le scope demandé côté IdP. **Corrigez l'enregistrement du client**, puis relancez cette étape.
- **Erreur `invalid_client`** → `client_id`/`client_secret` faux ou expiré. **Vérifiez le secret**, relancez.
- **Erreur `invalid_grant` avec "NHI Authentication Tokens SKU is not enabled"** → le tenant est en réalité sur un plan **Integrator Free**, pas payant : passez à la méthode gratuite ci-dessous.
- **Ça répond avec un `access_token`** → l'IdP fonctionne, le problème n'est pas côté serveur d'identité. Passez à 1.3.

**Sur un tenant Okta gratuit** (Integrator Free Plan), ce grant est bridé
derrière ce même SKU payant sur un Authorization Server custom, quelle
que soit la configuration du client — inutile de chercher une erreur de
config. Le contournement gratuit et fonctionnel est `client_credentials`
via **`private_key_jwt`** contre l'**Org Authorization Server**
(`/oauth2/v1/token`, et non `/oauth2/default/v1/token`) :

```bash
OKTA_DOMAIN=votre-org.okta.com CLIENT_ID=... KID=... \
  iam-debug/oidc/.keys-lab/get-token-pkjwt.sh
```

Setup complet (génération de la clé, configuration de l'app) dans
`setup-okta.md`. Une fois un token obtenu par l'une ou l'autre méthode,
passez à 1.3.

### Étape 1.3 — Le contenu du token est-il correct ?

```powershell
function Decode-JwtPart($Token, $Part) {
  $seg = $Token.Split('.')[$Part].Replace('-','+').Replace('_','/')
  $seg += '=' * ((4 - $seg.Length % 4) % 4)
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($seg)) | ConvertFrom-Json
}
Decode-JwtPart $env:ACCESS_TOKEN 1   # payload
```

- **`aud` ne correspond pas à l'API ciblée** → mauvaise audience configurée côté client. **Corrigez la config de l'app**, retestez depuis 1.2.
- **`exp` déjà dépassé ou `nbf` dans le futur** → suspectez un décalage d'horloge. Passez à 1.5.
- **Tout est cohérent** → passez à 1.4.

### Étape 1.4 — La clé de signature est-elle bien publiée ?

```powershell
(Invoke-RestMethod https://votre-org.okta.com/oauth2/default/v1/keys).keys |
  Select-Object kid, alg

# à comparer avec l'en-tête du token :
Decode-JwtPart $env:ACCESS_TOKEN 0
```

- **Le `kid` du token n'apparaît pas dans le JWKS** → l'IdP a fait tourner ses clés et le cache côté application (ou côté SP) est périmé. **Forcez un rafraîchissement du cache JWKS côté app.**
- **Le `kid` correspond** → le token est valide de bout en bout. Si l'appli échoue quand même, passez à 1.6.

### Étape 1.5 — Vérifier l'horloge

```powershell
Get-Date -AsUTC
```

Comparez avec l'heure UTC du serveur IdP. Un écart de plus de quelques minutes casse la validation `exp`/`nbf`. **Resynchronisez le NTP** sur la machine en tort.

### Étape 1.6 — Le token est bon mais l'appli échoue quand même

À ce stade, le problème n'est plus le protocole mais l'intégration :
- Comparez le `redirect_uri` **exact** enregistré côté IdP et celui envoyé par l'app (slash final, http/https, port).
- Vérifiez que l'app envoie bien le header `Authorization: Bearer <token>` sur le bon appel.

---

## Partie 2 — Procédure SAML

### Étape 2.1 — Capturer l'échange

Ouvrez **SAML-tracer**, relancez la connexion, gardez la fenêtre ouverte pendant tout le flux.

- **Rien n'est capturé** → ce n'est probablement pas du SAML, revenez à l'Étape 0.
- **Une requête `SAMLRequest` ou une réponse `SAMLResponse` apparaît** → copiez sa valeur, passez à 2.2.

### Étape 2.2 — Décoder ce qui a été capturé

**Si c'est une `SAMLRequest`** (binding Redirect, dans l'URL) :

```powershell
$bytes = [Convert]::FromBase64String($env:SAMLRequest)
$ms = [IO.MemoryStream]::new(,$bytes)
$ds = [IO.Compression.DeflateStream]::new($ms, [IO.Compression.CompressionMode]::Decompress)
[IO.StreamReader]::new($ds).ReadToEnd()
```

**Si c'est une `SAMLResponse`** (binding POST, dans le corps) :

```powershell
$xml = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:SAMLResponse))
$doc = [xml]$xml
$sw = [IO.StringWriter]::new()
$w = [Xml.XmlTextWriter]::new($sw)
$w.Formatting = 'Indented'
$doc.WriteTo($w)
$sw.ToString()
```

Passez à 2.3 avec le XML en clair sous les yeux.

### Étape 2.3 — Vérifier les champs de l'assertion

Dans le XML décodé, cherchez :

- `Destination` → doit être **exactement** l'URL ACS de votre SP. **Différent ?** → corrigez la config ACS côté IdP.
- `Audience` → doit être l'entity ID exact de votre SP. **Différent ?** → corrigez l'entity ID enregistré.
- `NotBefore` / `NotOnOrAfter` → comparez à l'heure actuelle (`Get-Date -AsUTC`). **Hors fenêtre ?** → décalage d'horloge, resynchronisez le NTP.

Tout est correct → passez à 2.4.

### Étape 2.4 — Vérifier la signature

```powershell
$cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new("okta-cert.pem")
$cert | Select-Object Thumbprint, NotBefore, NotAfter
```

Le certificat Okta se télécharge depuis la console d'admin : **Applications → (votre app) → Sign On → SAML Signing Certificates** — ou directement via `saml/idp-metadata.bru` dans la collection Bruno (Étape 3.6).

- **Le `Thumbprint` ne correspond pas** à celui des métadonnées publiées par l'IdP → **l'IdP a renouvelé son certificat**, mettez à jour le certificat de confiance côté SP.
- **Le certificat correspond mais est expiré** (`NotAfter` dépassé) → il faut le renouveler des deux côtés.
- **Tout correspond** → l'assertion est valide. Si la connexion échoue quand même, passez à 2.5.

### Étape 2.5 — Tout est valide mais boucle de connexion

Le SSO aboutit côté IdP mais l'utilisateur repart en boucle : suspectez un **cookie de session bloqué** (attribut `SameSite`, domaine du cookie, ou blocage tiers du navigateur). Vérifiez les attributs du cookie de session dans les devtools réseau du navigateur.

---

## Partie 3 — Utiliser la collection Bruno

La collection existe déjà dans `iam-debug/` (dossiers `oidc/`, `saml/`, `environments/`) — pas besoin de la recréer, seulement de la brancher sur votre org Okta.

### 3.1 — Ouvrir la collection

En ligne de commande, avec le [CLI Bruno](https://www.usebruno.com/) (`npm install -g @usebruno/cli`) :

```bash
cd iam-debug
bru run oidc/discovery.bru --env uat
```

Ou dans l'app desktop Bruno (**Open Collection** → dossier `SSO-DEBUG/iam-debug`) si vous préférez l'interface graphique.

### 3.2 — Choisir et remplir l'environnement

1. Ouvrez une requête, par exemple `oidc/discovery.bru`
2. En haut de cet onglet de requête, à côté du bouton **Send**, sélectionnez l'environnement `uat` (ou `ope` selon le contexte)
3. Cliquez sur l'icône engrenage à côté du nom de l'environnement pour ouvrir l'éditeur de variables, et renseignez :

| Champ | Valeur à mettre |
|---|---|
| `issuer` | `https://<votre-domaine-okta>.okta.com/oauth2/default` |
| `client_id` | L'ID de l'app de test Okta (console Okta → Applications → votre app) |
| `client_secret` | Le secret de cette même app |
| `scope` | Le scope custom défini sur le serveur d'autorisation Okta |
| `acs_url` | L'URL ACS de votre SP (nécessaire uniquement pour la partie SAML) |
| `saml_response` | À laisser vide, à coller uniquement lors d'un test SAML (Étape 3.7) |
| `okta_app_id` | L'ID de l'app SAML Okta, à récupérer sur l'onglet **Sign On** de l'app → lien **View SAML setup instructions** (pas l'ID visible dans l'URL générale d'administration, qui pointe vers l'instance d'app et non vers l'endpoint SAML) — nécessaire uniquement pour l'Étape 3.6 |

4. Enregistrez

### 3.3 — Tester le discovery

Ouvrez `oidc/discovery.bru` → **Send**. Vous devez récupérer le JSON de configuration Okta (`token_endpoint` en `/v1/token`, etc.) — voir Étape 1.1 de la procédure.

### 3.4 — Obtenir un token

**Tenant payant** : ouvrez `oidc/client-credentials-token.bru` → **Send**.
Cette requête est déjà configurée en Basic Auth (`client_id`/`client_secret`
dans l'en-tête, pas dans le corps — c'est ce qu'Okta attend par défaut) et
son script post-réponse range automatiquement le résultat dans la variable
`access_token`.

**Tenant gratuit (Integrator Free Plan)** : cette requête échoue avec
`invalid_grant` (voir Étape 1.2 de la procédure) — c'est attendu, pas une
erreur de config. `oidc/client-credentials-pkjwt.bru` documente le flow
`private_key_jwt` équivalent, mais renvoie vers `get-token-pkjwt.sh`
(documenté dans `setup-okta.md`) pour l'exécution réelle : le bac à sable
JS de Bruno ne peut pas signer un JWT RS256 nativement.

### 3.5 — Inspecter le token obtenu

Ouvrez `oidc/introspect.bru` → **Send**. Elle réutilise `{{access_token}}` posé à l'étape précédente et affiche le payload décodé dans la console Bruno — correspond aux Étapes 1.3/1.4 de la procédure.

### 3.6 — Récupérer le certificat et les métadonnées de l'IdP

Ouvrez `saml/idp-metadata.bru` → **Send**. Automatise l'Étape 2.4 (vérifier la signature) : renvoie le XML de métadonnées Okta (certificat de signature, SSO URL, entity ID) sans passer par le téléchargement manuel dans la console Okta. Nécessite `okta_app_id` renseigné dans l'environnement.

### 3.7 — Rejouer une assertion SAML capturée

Dans `saml/acs-replay.bru` : collez dans la variable d'environnement `saml_response` la valeur base64 capturée avec SAML-tracer (Étape 2.1), renseignez `acs_url`, puis **Send** — utile pour rejouer un cas précis sans repasser par tout le flux navigateur. Le script pre-request décode automatiquement le XML dans la console Bruno (Étape 2.2), à vérifier ensuite manuellement selon l'Étape 2.3.

### 3.8 — Gestion des secrets

Les fichiers `environments/uat.bru`, `environments/ope.bru`, `environments/demo.bru` et `environments/auth0-demo.bru` ne doivent contenir aucune valeur réelle — ni domaine, ni `client_id`, ni `client_secret`. Conservez les placeholders (`votre-org`, `à-remplir-localement...`) ; chaque utilisateur renseigne ses propres identifiants localement, en les marquant **Secret** dans l'éditeur Bruno, sans les enregistrer dans le fichier partagé.

---

*Ajoutez une section à ce document chaque fois qu'un nouveau cas de panne apparaît — c'est un document vivant, pas une référence figée.*

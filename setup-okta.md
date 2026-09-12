# Reproduire le lab — création des apps Okta

Étapes pour recréer, depuis zéro, les apps Okta utilisées par ce lab (tenant
Okta Developer / Integrator Free Plan). Suivies dans l'ordre, elles mènent à
un flow OIDC et un flow SAML fonctionnels dès la première tentative.

## Prérequis

- Un compte [Okta Developer](https://developer.okta.com/signup/) (gratuit)
- Accès à la console admin de ce tenant
- `openssl` et `python3` installés en local (pour générer la clé RSA)

## 1. Générer la paire de clés RSA (OIDC)

Dans `iam-debug/oidc/.keys-lab/` :

```bash
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -pubout -out public.pem
```

Ces deux fichiers restent en local (`.gitignore` les exclut) : la clé
privée ne doit jamais être committée.

Convertir la clé publique au format JWK, avec un identifiant (`kid`) que tu
choisis toi-même (ex: `iam-debug-lab-key-1`) :

```bash
python3 -c "
import base64, subprocess, json

hex_mod = subprocess.check_output(
    ['openssl', 'rsa', '-pubin', '-in', 'public.pem', '-noout', '-modulus']
).decode().split('=')[1]
n = base64.urlsafe_b64encode(bytes.fromhex(hex_mod)).rstrip(b'=').decode()
e = base64.urlsafe_b64encode((65537).to_bytes(3, 'big')).rstrip(b'=').decode()

print(json.dumps({
    'kty': 'RSA', 'use': 'sig', 'alg': 'RS256',
    'kid': 'iam-debug-lab-key-1',
    'n': n, 'e': e,
}, indent=2))
"
```

Garde le JSON affiché sous la main pour l'étape 3, et retiens le `kid` que
tu as choisi : c'est cette même valeur qui ira dans `KID=` à l'étape 4.

## 2. Créer l'app OIDC (API Services)

1. **Okta Admin** → Applications → **Create App Integration**
2. Sign-in method : **API Services**
3. Nommer l'app (ex: `iam-debug-m2m`) → **Save**
4. Onglet **General** → noter le **Client ID**

## 3. Configurer l'authentification par clé publique

1. Toujours sur l'app `iam-debug-m2m`, onglet **General** → **Edit** sur
   **Client Credentials**
2. **Client authentication** → **Public key / Private key**
3. Section **Public Keys** → **Add Key** → coller le JSON JWK généré à
   l'étape 1 (celui avec `"kid": "iam-debug-lab-key-1"`)
4. Onglet **Okta API Scopes** → **Grant** sur `okta.users.read`

## 4. Obtenir un token

```bash
cd iam-debug/oidc/.keys-lab
OKTA_DOMAIN=<ton-tenant>.okta.com \
CLIENT_ID=<le-client-id-note-a-l-etape-2> \
KID=iam-debug-lab-key-1 \
./get-token-pkjwt.sh
```

Une réponse avec un `access_token` confirme que le flow `client_credentials`
via `private_key_jwt` fonctionne — c'est la méthode qui marche sans
dépendre d'un SKU payant, contrairement au grant `client_credentials`
classique contre un Authorization Server custom (`/oauth2/default`), qui
échoue sur le plan Integrator Free avec `invalid_grant` ("NHI
Authentication Tokens SKU not enabled").

Valider ensuite avec `oidc/discovery.bru` (`bru run oidc/discovery.bru`).

## 5. Créer l'app SAML

1. **Okta Admin** → Applications → **Create App Integration** → choisir
   **SAML 2.0**
2. Nommer l'app (ex: `iam-debug-saml`) → **Next**
3. Onglet **Configure SAML**, dans **Single sign-on URL**, **Recipient URL**
   et **Destination URL** (si affichés séparément), coller exactement,
   sans rien autour :

   ```
   https://httpbin.org/post
   ```

   (endpoint public qui accepte n'importe quel POST et en renvoie le
   contenu — suffisant pour rejouer une assertion sans monter de vrai SP)
4. **Audience URI (SP Entity ID)** :
   ```
   urn:portfolio-lab:sp
   ```
5. **Name ID format** : `EmailAddress`
6. **Next** puis **Finish**
7. Onglet **Assignments** → **Assign** → assigner ton propre utilisateur Okta

## 6. Récupérer les métadonnées SAML

1. Sur la page de l'app, onglet **Sign On** → lien **View SAML setup
   instructions** (ou **View Setup Instructions**)
2. Cette page donne l'URL exacte des métadonnées IdP, de la forme
   `https://<tenant>.okta.com/app/<id>/sso/saml/metadata` — c'est cet
   `<id>` (préfixe `exk`) qu'il faut utiliser, pas l'ID visible dans l'URL
   générale d'administration de l'app (préfixe `0oa`, qui pointe vers
   l'instance d'app et non vers l'endpoint SAML)
3. Reporter dans `iam-debug/environments/demo.bru` :
   - `acs_url` = `https://httpbin.org/post`
   - `okta_app_id` = l'`<id>` (préfixe `exk`) relevé à l'étape 2

Valider avec `bru run saml/idp-metadata.bru` — la réponse contient le
certificat de signature X.509 réel de l'IdP.

## 7. Capturer un vrai SAMLResponse

1. Installer et ouvrir l'extension **SAML-tracer** dans le navigateur, la
   laisser active
2. Depuis le tableau des apps Okta (page d'accueil utilisateur), lancer le
   SSO vers `iam-debug-saml`
3. Dans SAML-tracer, repérer la requête POST vers `httpbin.org/post` et
   copier la valeur du champ `SAMLResponse`
4. Coller cette valeur dans la variable `saml_response` de l'environnement
   Bruno (en local uniquement, jamais committée)

Valider avec `bru run saml/acs-replay.bru`.

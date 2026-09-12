#!/usr/bin/env bash
# Obtient un token client_credentials via private_key_jwt (Org Authorization
# Server Okta).
# Usage : OKTA_DOMAIN=ton-tenant.okta.com CLIENT_ID=0oa... KID=un-id-de-ton-choix \
#         ./get-token-pkjwt.sh
# KID doit être exactement l'identifiant que tu as saisi dans Okta au moment
# d'ajouter la clé publique (General > Public Keys > Add key), pas une valeur
# à retrouver après coup.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OKTA_DOMAIN="${OKTA_DOMAIN:?Definis OKTA_DOMAIN=ton-tenant.okta.com avant de lancer ce script}"
TOKEN_ENDPOINT="https://${OKTA_DOMAIN}/oauth2/v1/token"
KID="${KID:?Definis KID=un-id-de-ton-choix, le meme que celui saisi dans Okta}"
CLIENT_ID="${CLIENT_ID:?Definis CLIENT_ID=0oa... avant de lancer ce script}"
SCOPE="${SCOPE:-okta.users.read}"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

NOW=$(date +%s)
EXP=$((NOW + 300))
JTI=$(openssl rand -hex 16)

HEADER=$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$KID" | tr -d '\n' | b64url)
PAYLOAD=$(printf '{"iss":"%s","sub":"%s","aud":"%s","jti":"%s","exp":%d,"iat":%d}' \
  "$CLIENT_ID" "$CLIENT_ID" "$TOKEN_ENDPOINT" "$JTI" "$EXP" "$NOW" | tr -d '\n' | b64url)

SIGNING_INPUT="${HEADER}.${PAYLOAD}"
SIGNATURE=$(printf '%s' "$SIGNING_INPUT" | openssl dgst -sha256 -sign "$DIR/private.pem" | b64url)

CLIENT_ASSERTION="${SIGNING_INPUT}.${SIGNATURE}"

curl -s -X POST "$TOKEN_ENDPOINT" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "scope=${SCOPE}" \
  --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  --data-urlencode "client_assertion=${CLIENT_ASSERTION}"
echo

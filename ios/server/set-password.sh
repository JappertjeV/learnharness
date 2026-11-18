#!/bin/bash
# Set or replace the LearnHarness login (user "learner" unless you pass a name).
#
#   ./set-password.sh [username]
#
# Generates a random password, writes its argon2 hash to authelia/users_database.yml and shows
# the password once. Save it in your password manager. Lost it? Run this again.
set -euo pipefail
cd "$(dirname "$0")"
user=${1:-learner}
[[ $user =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || { echo "Invalid username: $user" >&2; exit 2; }

hash_of() {
  # Via stdin, not as an argument, so the password doesn't show up in the process list.
  printf '%s' "$1" | docker compose run --rm -T --no-deps --entrypoint sh authelia \
    -c 'read -r p; authelia crypto hash generate argon2 --password "$p"' 2>/dev/null | sed -n 's/^Digest: //p'
}

pw=$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-32)
hash=$(hash_of "$pw")
[[ $hash == '$argon2'* ]] || { echo "Creating the hash failed (is Docker running?)." >&2; exit 1; }

umask 077
mkdir -p authelia
cat > authelia/users_database.yml.new <<YAML
users:
  $user:
    disabled: false
    displayname: "$user"
    password: "$hash"
    email: $user@localhost
    groups: []
YAML
mv authelia/users_database.yml.new authelia/users_database.yml
docker compose restart authelia >/dev/null 2>&1 || true

cat <<MSG

Username: $user
Password (shown only once): $pw

Save it in your password manager for https://${LH_DOMAIN:-your domain}, then sign in.
MSG
unset pw

#!/bin/sh
# Build step: disable admin 2FA (and every module that depends on it, e.g. MageOS_PasskeyAuth)
# so the admin of this test install logs in with just a username and password.
set -eu
MODS="$(grep -oE "'(Magento_AdminAdobeImsTwoFactorAuth|Magento_TwoFactorAuth|MageOS_PasskeyAuth)'" app/etc/config.php | tr -d "'" | tr '\n' ' ')"
[ -n "$MODS" ] || exit 0

i=0
while [ $i -lt 6 ]; do
  if OUT="$(bin/magento module:disable $MODS 2>&1)"; then
    echo "$OUT"
    exit 0
  fi
  echo "$OUT"
  # Lines look like "MageOS_PasskeyAuth: MageOS_PasskeyAuth->Magento_TwoFactorAuth": add the dependents.
  DEPS="$(echo "$OUT" | grep -oE '^[A-Za-z0-9]+_[A-Za-z0-9]+:' | tr -d ':' | tr '\n' ' ')"
  [ -n "$DEPS" ] || exit 1
  MODS="$MODS $DEPS"
  i=$((i + 1))
done
exit 1

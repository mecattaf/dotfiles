# The NAS owns all three Google logins; the original HOME and project cwd stay.
case ${0##*/} in
  agy) account=1 ;;
  agy2) account=2 ;;
  agy3) account=3 ;;
  *) echo 'Use agy, agy2 or agy3.' >&2; exit 2 ;;
esac
account_root="${XDG_DATA_HOME:-$HOME/.local/share}/antigravity-cli/accounts/$account"
umask 077
mkdir -p "$account_root"
chmod 700 "$account_root"

# Google OAuth normally uses a single shared keyring entry. The vendor's
# composite store falls back to each account's token file when D-Bus is disabled
# for this child. No shared keyring or user-session service is changed.
# NAS's kernel already blacklists broken RDRAND on its Zen+ CPU; BoringSSL
# independently detects it, so clear that single capability and keep OS entropy.
exec env \
  -u GEMINI_CLI_HOME -u GEMINI_CLI_AUTH_OVERRIDE -u GEMINI_CLI_SYSTEM_SETTINGS_PATH \
  -u GEMINI_API_KEY -u GOOGLE_API_KEY -u GOOGLE_APPLICATION_CREDENTIALS \
  -u GOOGLE_CLOUD_ACCESS_TOKEN -u AGY_ADC_AUTH -u AGY_ACCOUNT \
  -u ANTIGRAVITY_CONFIG_REL_DIR -u ANTIGRAVITY_CREDENTIAL_SCOPE \
  DBUS_SESSION_BUS_ADDRESS=disabled: \
  OPENSSL_ia32cap='~0x4000000000000000' \
  AGY_CLI_DISABLE_AUTO_UPDATE=true \
  ANTIGRAVITY_GEMINI_DIR="$account_root" \
  ANTIGRAVITY_APP_DATA_DIR=antigravity-cli \
  "$AGY_EXECUTABLE" --gemini_dir "$account_root" --app_data_dir antigravity-cli "$@"

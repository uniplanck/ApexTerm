#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_APP="$ROOT_DIR/.artifacts/ApexTerm.app"
SYSTEM_DESTINATION="/Applications/ApexTerm.app"
USER_DESTINATION="$HOME/Applications/ApexTerm.app"

"$ROOT_DIR/scripts/build-app.zsh" >/dev/null

pkill -x ApexTerm 2>/dev/null || true
sleep 0.3

if [[ -w /Applications ]]; then
    DESTINATION="$SYSTEM_DESTINATION"
else
    mkdir -p "$HOME/Applications"
    DESTINATION="$USER_DESTINATION"
fi

rm -rf "$DESTINATION"
ditto "$SOURCE_APP" "$DESTINATION"

LAUNCH_SERVICES="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LAUNCH_SERVICES" -f "$DESTINATION"

CLI_DIRECTORY="$HOME/.local/bin"
CLI_LINK="$CLI_DIRECTORY/gag"
mkdir -p "$CLI_DIRECTORY"
if [[ -e "$CLI_LINK" && ! -L "$CLI_LINK" ]]; then
    print -u2 -r -- "Refusing to replace existing non-symlink: $CLI_LINK"
    exit 2
fi
ln -sfn "$DESTINATION/Contents/Resources/bin/gag" "$CLI_LINK"

open "$DESTINATION"

printf 'INSTALLED_APP=%s\n' "$DESTINATION"
printf 'INSTALLED_GAG_CLI=%s\n' "$CLI_LINK"

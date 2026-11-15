#!/bin/zsh
# Builds Rick, installs him to ~/Applications (findable with Spotlight, stable for
# Start at Login), and adds the `rick` command to your PATH.
set -e
cd "$(dirname "$0")"
./build.sh

pgrep -x Rick >/dev/null && { osascript -e 'tell application "Rick" to quit' >/dev/null 2>&1 || pkill -x Rick; sleep 1; }
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Rick.app"
cp -R Rick.app "$HOME/Applications/Rick.app"
echo "Installed ~/Applications/Rick.app"

# Put `rick` on the PATH: first writable directory from this list that's on PATH.
for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  if [[ ":$PATH:" == *":$dir:"* && -w "$dir" ]]; then
    ln -sf "$PWD/bin/rick" "$dir/rick"
    echo "Added the 'rick' command ($dir/rick)"
    break
  fi
done
command -v rick >/dev/null || echo "Couldn't find a writable PATH folder; run $PWD/bin/rick directly."

open "$HOME/Applications/Rick.app"

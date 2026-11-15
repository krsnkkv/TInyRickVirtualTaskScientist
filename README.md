# Mochi — a desktop pet that chats with Claude 🌱

A small pastel creature that wanders along the bottom of your Mac screen. Click it and a chat window opens where you can ask Claude anything.

## Build & run

```bash
./build.sh && open Mochi.app
```

## Using it
- **Click Mochi** to open/close the chat. **Drag** it anywhere and it falls back to the floor.
- Hover and it waves; leave it alone and it wanders, naps and offers help.
- **🌱 menu-bar icon**: New Conversation, Hide/Show, Set API Key…, Quit.

## API key
Saved to `~/Library/Application Support/MochiPet/api_key` (chmod 600); `ANTHROPIC_API_KEY` takes precedence.

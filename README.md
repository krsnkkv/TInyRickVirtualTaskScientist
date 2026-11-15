# Mochi — a pixel desktop pet that keeps your priorities 🌱

A small striped, pixel-art creature that wanders along the bottom of your Mac screen. Click it to open your **Urgent / Important list**: four coloured boxes you type straight into. Everything is saved as you type, so it's always remembered.

## Build & run

```bash
./build.sh && open Mochi.app
```

Needs only the Xcode command-line tools (native Swift/AppKit, no other dependencies).

## Using it
- **Click Mochi** to open or close your list. Click inside a box and start typing; **Enter** starts a new `>>` item, and pressing Enter on an empty item removes the bullet.
- Mochi sometimes reminds you of things in **Urgent & Important** ("Don't forget: …").
- **Drag Mochi** anywhere and it falls back to the floor. Hover and it waves; leave it alone and it wanders or naps.
- **🌱 menu-bar icon** (or right-click Mochi): Open My List, Hide/Show Mochi, Show List File in Finder, Quit.

## Where your list lives
`~/Library/Application Support/MochiPet/matrix.json` is plain JSON, which makes it easy to sync elsewhere later. It's kept outside this repo, so git doesn't track your personal list.

## Code
- `Sources/Pet.swift`: pixel-art character, animations and wandering behaviour (`pixelSize` controls how chunky it looks)
- `Sources/Matrix.swift`: the four-box list window and saving
- `Sources/main.swift`: app setup and menu

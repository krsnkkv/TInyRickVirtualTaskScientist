# Rick — a pixel desktop pet that keeps your priorities 🧪

A small pixel-art pet (the built-in look is a striped creature; load any sprite you like) that wanders along the bottom of your Mac screen. Click it to open your **Urgent / Important list**: four coloured boxes you type straight into. Everything is saved as you type, so it's always remembered.

## Build & run

```bash
./build.sh && open Rick.app
```

Needs only the Xcode command-line tools (native Swift/AppKit, no other dependencies).

## Using it
- **Click Rick** to open or close your list. Click inside a box and start typing; **Enter** starts a new `>>` item, and pressing Enter on an empty item removes the bullet.
- **Due dates are picked up automatically** from what you write: `today`, `tomorrow`, a weekday (`Thursday`, `this thu` = the coming one, today counts), `next thursday` (the week after), or a date like `20 Nov`. A weekday is fixed to a real date when you write it, so "Thursday" written on Sunday doesn't roll over to next week.
- Items due soon are coloured (red = overdue, orange = today, amber = within 2 days), and each box shows its next due date.
- **Reminders:** every 15–25 minutes Rick brings up something overdue or due within 3 days, waking up if it's napping. **What's Due Soon?** in the menu asks right away.
- **Drag Rick** anywhere and it falls back to the floor. Hover and it waves; leave it alone and it wanders or naps.
- **🧪 menu-bar icon** (or right-click Rick): Open My List, What's Due Soon?, Hide/Show Rick, Choose Sprite…, Use Built-in Look, Show List File in Finder, Quit.

## Custom sprite
**Choose Sprite…** takes a PNG/JPG: either a single image or a whole **sprite sheet**. Sprites should face **right**; Rick flips them when walking left.
- A solid background colour (taken from the top-left pixel, e.g. white) is removed.
- On a sheet, the frame grid is detected automatically, and loose bits smaller than a full figure are skipped.
- **Row 1 is the standing animation and row 2 the walk cycle** (if row 2 has fewer than two frames, row 1 is used for both).
- The sprite is copied to `~/Library/Application Support/MochiPet/sprite.png`, outside this repo. Sprites ripped from games or shows are copyrighted, so keep them out of git; credit doesn't make them free to redistribute.

## Where your list lives
`~/Library/Application Support/MochiPet/matrix.json` is plain JSON, which makes it easy to sync elsewhere later. It's kept outside this repo, so git doesn't track your personal list.

## Code
- `Sources/Pet.swift`: pixel-art character, animations and wandering behaviour (`pixelSize` controls how chunky it looks)
- `Sources/Matrix.swift`: the four-box list window and saving
- `Sources/DueDates.swift`: finding due dates in items and wording reminders
- `Sources/Sprite.swift`: loading custom sprites
- `Sources/main.swift`: app setup and menu

# Rick — a pixel desktop pet that keeps your priorities 🧪

A small pixel-art pet (the built-in look is a striped creature; load any sprite you like) that wanders along the bottom of your Mac screen. Click it to open your **Urgent / Important list**: four coloured boxes you type straight into. Everything is saved as you type, so it's always remembered.

## Build & run

```bash
./install.sh
```
Builds Rick, installs him to `~/Applications` (so Spotlight finds him and **Start at Login** works), adds the `rick` terminal command, and starts him. For a quick dev run without installing: `./build.sh && open Rick.app`.

## Shortcuts & commands
- **⌃⌘C**: open/close your list (works from any app)
- **⌃⌘R**: send Rick away / bring him back (while away he does no work at all)
- **⌃⌘P**: pop up the modes list next to the pet (↑ ↓ to move, Return to pick, Esc to close)
- `rick` / `rick stop` / `rick restart` / `rick status` in the terminal
- **Start at Login** in the 🧪 menu keeps him around after a reboot
- **Options** submenu: sprite, list background, show list file, Start at Login, and **Restart Rick**, which quits and reopens him (re-reads Personality.md and the sprite)

Needs only the Xcode command-line tools (native Swift/AppKit, no other dependencies).

## Using it
- **Click Rick** to open or close your list. Click inside a box and start typing; **Enter** starts a new `>>` item, and pressing Enter on an empty item removes the bullet.
- **Due dates are picked up automatically** from what you write: `today`, `tomorrow`, a weekday (`Thursday`, `this thu` = the coming one, today counts), `next thursday` (the week after), or a date like `20 Nov`. A weekday is fixed to a real date when you write it, so "Thursday" written on Sunday doesn't roll over to next week.
- **Mark things done with ⌘⇧X:** select one or more items and press ⌘⇧X to strike them through (again to undo). Done items stay in the list, greyed out, and Rick stops nagging about them. ⌘C/⌘V/⌘Z work in the list too.
- **Or just write DONE:** "Pay fees DONE", "done: email Akila" or "Read papers – done ✓" strikes it through too ("get it done by Friday" doesn't count). Delete the word and it's open again.
- **Date words stay true:** "by tomorrow" becomes "by today" after midnight, then "by yesterday", then the actual date ("by Mon 16 Nov"). A weekday that has passed turns into its date as well.
- Items due soon are coloured (red = overdue, orange = today, amber = within 2 days), and each box shows its next due date.
- **Reminders:** every 15–25 minutes Rick brings up something overdue or due within 3 days, waking up if it's napping. **What's Due Soon?** in the menu makes Rick read out your whole list, one bubble per item: Urgent & Important first, then Urgent & Not Important, Not Urgent & Important, Not Urgent & Not Important. Each box is sorted by due date, and done items are skipped.
- **Drag Rick** anywhere and it falls back to the floor. Hover and it waves; leave it alone and it wanders or naps.
- **🧪 menu-bar icon** (or right-click Rick): Open My List, What's Due Soon?, Hide/Show Rick, the options below, Choose Sprite…, Use Built-in Look, Show List File in Finder, Quit.

## Options (🧪 menu, remembered between launches)
- **Mute Rick**: no speech bubbles.
- **Stay Still**: he hangs around in one spot (guitar, naps, waves) instead of walking off.
- **Anti-Gravity**: he stays wherever you drop him instead of falling to the floor.
- **ADHD Mode**: hops and zooms around and never naps.

**Loner Rick** (next to ADHD Mode) shows this right away: if you leave Rick alone for 10 minutes he gets sad, nags you about your to-do list, and stays slumped until you hover, click or drag him.

**You Cryin?** shows up in the menu when the profile's sprite has a `cryin` animation (e.g. `"cryin": "2:1-3"` in `sprite.json`). While it's on, the pet stays put and plays that animation over and over.

**Profile modes:** a sprite can bring its own set of modes, which replace Stay Still / ADHD / Loner in the menu (as "<Name> Modes"). In `sprite.json`:

```json
"modes": [
  { "name": "Normal", "idle": 1, "walk": 4, "extras": [2, 3, 5] },
  { "name": "Hyper", "behaviour": "hyper", "extras": [1, 2, 3, 5, 6] },
  { "name": "Party", "behaviour": "still", "idle": 8, "extras": [8, 9] }
]
```

Each mode can set any of the usual rows (`idle`, `walk`, `sad`, …); `extras` are rows played as random moves; `behaviour` is `normal`, `still` (never walks) or `hyper` (like ADHD). A row can also be a list, e.g. `"idle": [1, "3:1-2"]`. Sheets whose frames aren't on an even grid can add `"layout": "rows"`: each strip of figures becomes a row and each figure a frame.

Reminders leave out the date words you wrote ("Cross check MLS by tomorrow!" → "Tomorrow: Cross check MLS…").

## Tasks | Calendar views
The list window has a **☑︎ Tasks | 📅 Calendar** switch at the top (⌘1 / ⌘2, or 🧪 ▸ Open Calendar View). It reopens on whichever you used last.
- **Schedule:** scrolls day by day for the next 30 days: overdue tasks first, then each day's events and the tasks due that day (with their box: U&I, U&NI…).
- **Month:** a month grid with dots (events in their calendar colour, tasks in their box colour); ‹ › and Today to move around; click a day to see its list underneath.
- Tick a task's box in either view to mark it done; it's struck through in your list too.

## Calendar
**🧪 ▸ Calendar ▸ Connect Calendar…** asks macOS for calendar access. It reads the Calendar app, so **Google calendars work too** once your Google account is added in System Settings ▸ Internet Accounts.
- **Today strip** above the boxes: today's events with calendar colours; finished meetings fade.
- **Heads-up** about 10 minutes before a meeting, and again when it starts (in your pet's voice). Off while the pet is hidden.
- **Add to Calendar** (⌘⇧E, right-click, or the Calendar menu) puts the task under the cursor in your calendar. All-day, or timed if you wrote a time ("Interview tomorrow at 3pm").
- **Two-way:** change the task's date words and the event moves; move the event in Calendar and the task's date and words follow ("by Thursday" → "by Friday"). Deleting either side just unlinks them; nothing is ever deleted from your calendar.
- Choose which calendars to show, and which one new tasks go into.

## List background
**Options ▸ List Background** picks a theme painted by the app: **Space** (deep purple sky, nebulas, stars; the default for Rick/Grumpy Genius), **Garden** (cream and mint with floating leaves; Mochi's default) or **Plain**. Each profile remembers its own. **Choose Picture…** puts any picture behind the four boxes (they turn slightly see-through with wider gaps). It's copied to `~/Library/Application Support/MochiPet/list-background.png`, outside this repo. **Remove List Background** goes back to plain.

## Profiles (alter egos)
The pet can be different characters. **🧪 menu ▸ Profile** switches between them; each keeps its own look, voice and settings (Mute, ADHD…).
- Built in: **Mochi** 🌱 (cute and encouraging) and **Grumpy Genius** 🧪 (sarcastic, never mean), in [`Profiles/`](Profiles).
- Your own live in `~/Library/Application Support/MochiPet/profiles/<name>/` (e.g. your local **Rick** with his sprite sheet); they're never committed.
- **New Profile…** asks for a name and emoji and starts from Mochi's personality. **Edit Personality…** opens that profile's `Personality.md`; editing a built-in makes your own copy first.
- A profile folder is `profile.json` (`{"name": …, "icon": …}`), `Personality.md`, and optionally `sprite.png` + `sprite.json`.

## Personality
Everything a character says lives in its `Personality.md`. Each `## section` is a moment (greeting, reminders, being dragged…) and each bullet is a line it might say, with `{item}` and `{when}` filled in. After editing, use **Options ▸ Restart** to hear the changes.

## Custom sprite
**Profile ▸ Choose Sprite…** (for the active profile) takes a PNG/JPG: either a single image or a whole **sprite sheet**. Sprites should face **right**; Rick flips them when walking left.
- A solid background colour (taken from the top-left pixel, e.g. white) is removed.
- On a sheet, the frame grid is detected automatically, and loose bits smaller than a full figure are skipped.
- **Row 1 is the standing animation and row 2 the walk cycle** (if row 2 has fewer than two frames, row 1 is used for both).
- The sprite is copied into the profile's folder in `~/Library/Application Support/MochiPet/profiles/`, outside this repo. Sprites ripped from games or shows are copyrighted, so keep them out of git; credit doesn't make them free to redistribute.

## Where your list lives
`~/Library/Application Support/MochiPet/matrix.json` is plain JSON, which makes it easy to sync elsewhere later. It's kept outside this repo, so git doesn't track your personal list.

## Tests
`./test.sh` runs the checks in `Tests/` (dates, rolling words, list migration, task identity, profiles).

## Code
- `Sources/Pet.swift`: pixel-art character, animations and wandering behaviour (`pixelSize` controls how chunky it looks)
- `Sources/Matrix.swift`: the four-box list window and saving
- `Sources/DueDates.swift`: finding due dates in items and wording reminders
- `Sources/Sprite.swift`: loading custom sprites
- `Sources/Tasks.swift`: tasks with stable IDs behind the typed lines, migration, done/cleanup
- `Sources/CalendarPane.swift`: the Calendar side of the list window (Schedule and Month views)
- `Sources/Themes.swift`: Space / Garden / Plain list backgrounds
- `Sources/Calendar.swift`, `Sources/CalendarLink.swift`: EventKit access, Today strip data, task↔event sync rules
- `Sources/Profiles.swift`: profile folders, switching, migration from the single-character setup
- `Sources/main.swift`: app setup and menu

# Roadmap 🧪

From a desktop pet with a priority list → a real app that keeps your life organised:
**profiles (alter egos) → calendar sync (grounding) → clean button → mail**.

Tick things off as they land (`- [x]`). Each phase should ship something usable on its own.

---

## ✅ Done so far
- [x] Desktop pet that wanders, naps, gets dragged around (native Swift/AppKit)
- [x] Eisenhower list (U&I / U&NI / NU&I / NU&NI), saved as you type
- [x] Due dates from plain words ("by Thursday", "tomorrow", "18th"), rolled forward each day
- [x] Reminders, "What's Due Soon?" rundown, ⌘⇧X to mark done
- [x] Sprite sheets with row-mapped animations; Rick personality in `Personality.md`
- [x] Modes: Mute, Stay Still, Anti-Gravity, ADHD, Loner
- [x] ⌃⌘C / ⌃⌘R shortcuts, `rick` command, Start at Login, list backgrounds

---

## Phase 0: Foundations (do first; everything below depends on it)
Right now each task is just a line of text, and its due date / done state are looked up *by that text*. Syncing with a calendar needs every task to have a stable identity.

- [ ] **Task model:** each task becomes a record: `id`, `title`, `box`, `due`, `done`, `createdAt`, `source` (typed / calendar / mail), `externalID` (calendar event or email it came from)
- [ ] Migrate `matrix.json` automatically from the current text format (keep a backup)
- [ ] Keep the typing experience (still type `>>` lines), but map lines ↔ task records behind the scenes
- [ ] Move to a Swift Package (or Xcode project) with unit tests for date parsing, rolling words, migration
- [ ] Settings window (instead of everything living in the 🧪 menu)
- [ ] **Clean up done tasks:** button to clear struck-through items (optionally archive them to a "Done" log)

## Phase 1: Profiles / alter egos (start here) 🎭
A profile = a whole character: look, voice and behaviour.

- [ ] Profile folder format: `profiles/<name>/` with `sprite.png`, `sprite.json` (row mapping), `Personality.md`, `profile.json` (name, menu icon, speed, chattiness)
- [ ] Profile switcher in the menu (🧪 → Profile ▸ Rick / Mochi / …), remembered between launches
- [ ] Built-in profiles that ship with the app: **Mochi** (original sprout blob) and a blank template
- [ ] Your local profiles: **Rick** (your sprite sheet + current personality), stays out of git
- [ ] "New Profile…": pick a sprite sheet, map rows with a little preview, start from a personality template
- [ ] Per-profile settings (mute, ADHD, etc. can differ per character)
- [ ] Import/export a profile as a single `.zip` (share with friends; only share art you're allowed to share)
- [ ] Ideas: profiles with different nag styles (gentle coach, drill sergeant, grumpy genius)

## Phase 2: Calendar sync (the grounding part) 📅
**Plan:** use Apple's **EventKit** first. It reads macOS Calendar, which already includes your Google Calendar if your Google account is added in System Settings ▸ Internet Accounts. One integration covers both. Direct Google API comes later only if needed.

- [ ] Ask for Calendar (and Reminders) permission with a clear explanation
- [ ] **Read:** show today's events in the list window (a "Today" strip above the boxes)
- [ ] Rick reminds you before meetings ("Stand-up in 10 minutes. Try to look awake.")
- [ ] **Write:** "Add to Calendar" on a task with a due date → creates an all-day event (or timed, if a time was written: "at 3pm")
- [ ] Two-way: moving/deleting the calendar event updates the task, and vice versa (uses `externalID` from Phase 0)
- [ ] Choose which calendars to read and which one to write to
- [ ] Optional: sync tasks with **Apple Reminders** lists (shows up on iPhone too)
- [ ] Later: direct **Google Calendar API** (OAuth) for people who don't add Google to macOS
- [ ] Understand times, not just days ("Thursday 3pm", "in 2 hours")

## Phase 3: Clean button 🧹
"Go through the junk and let me swipe it away."

- [ ] Decide the first target: **mail inbox** (most value) — see Phase 4 for the mail connection
- [ ] Card-stack UI: one email per card (sender, subject, first line, how many similar ones)
- [ ] Swipe ← archive/trash · swipe → keep · ↑ unsubscribe (opens the unsubscribe link for you to confirm) · ↓ turn into a task
- [ ] Group by sender ("37 emails from ShopCo: swipe them all at once")
- [ ] **Safety:** nothing is permanently deleted. Trash/archive only, with an Undo for the whole session
- [ ] Rick comments as you go ("Another newsletter you never read? Bold.")
- [ ] Also a list-side clean: clear done tasks, flag stale ones ("This has been here 3 weeks. Still a thing?")

## Phase 4: Mail → tasks (last) ✉️
- [ ] Connect mail: **Gmail API** (OAuth) first; generic IMAP or Outlook later. Read-only to start
- [ ] Scan new emails for action items and deadlines ("please submit by Friday") → suggested tasks
- [ ] Suggest which box (U&I etc.) and a due date; **you approve** each one before it's added
- [ ] Link the task back to the email (open it from the list)
- [ ] Probably uses an AI model (e.g. Claude) to read emails: needs an API key, and a clear privacy note about what gets sent
- [ ] Daily digest: "3 new things from your inbox"

## Later / maybe
- [ ] iCloud sync of the list across Macs; iPhone companion app / widget
- [ ] Proper app icon, signed + notarised build so others can install it
- [ ] Onboarding: first launch walks through profile → calendar → mail
- [ ] Focus timer (Pomodoro) with the pet

---

### Notes
- **Copyright:** Rick (and any character from a show/game) stays a *local* profile. The public app ships only original characters like Mochi.
- **Privacy:** calendar and mail data stay on this Mac unless a feature clearly says otherwise.

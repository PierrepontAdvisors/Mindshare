# Mindshare

A tiny macOS menu bar app that shows how much of your Mac's memory each app is using, warns you when one crosses a limit you set, and lets you quit it.

- Live memory use per app, with helper processes added together
- A menu bar pie that turns into a warning when something needs attention
- Optional per-app limits, with a notification when an app goes over
- One-click quit, using a normal quit so apps can still ask you to save. Option-click forces a frozen app to quit, which loses anything unsaved
- Sort by any column, and choose how often it refreshes

Everything stays on your Mac. Mindshare makes no network connections.

## Install

You need macOS 14 or later, on an Apple Silicon or Intel Mac.

1. Download `Mindshare.zip` from the [latest release](../../releases/latest).
2. Unzip it and drag **Mindshare** into your Applications folder.
3. Open it. macOS will say it can't verify the app, because Mindshare isn't signed with a paid Apple developer account. Close the message.
4. Open **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to Mindshare.
5. Allow notifications when asked, so limit warnings can reach you.

Mindshare lives in the menu bar, not the Dock. Look for a small green pie at the top of your screen.

## Using it

| Menu bar | Meaning |
|---|---|
| Green pie | All fine. The fill shows how much memory is in use |
| Amber triangle | Memory pressure is elevated, or an app is over its limit |
| Red octagon | Memory pressure is critical |

Click it to open the panel. Hover over anything for more detail, and click a column heading to sort. **Show all** adds small helper apps and larger background processes you can't quit. The refresh menu is also where you turn on **Open at login**.

macOS has no supported way to cap an app's memory, so limits warn you and leave the decision to you.

## Build from source

You only need Apple's Command Line Tools (`xcode-select --install`).

```bash
./build-app.sh
```

This runs the logic checks and creates `build/Mindshare.app` and `build/Mindshare.zip`.

Grouping helper processes under their app uses a private macOS function. If a future macOS removes it, helpers show up as background rows instead.

## License

MIT. See [LICENSE](LICENSE).

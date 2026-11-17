# Contributing

Thank you for taking the time to contribute! ❤️

These guidelines help streamline the contribution process for everyone involved. By following them, you'll make it easier for maintainers to review your work and collaborate with you effectively.

You can contribute in many ways: writing code, improving documentation, reporting bugs, requesting features, or creating tutorials and blog posts. Every contribution, large or small, helps make Boring Notch better.

## Table of Contents

- [Working on T3 Isle](#working-on-t3-isle)
  - [Debug builds](#debug-builds)
  - [Debug commands](#debug-commands)
  - [How it talks to T3 Code](#how-it-talks-to-t3-code)
  - [Syncing from boring.notch](#syncing-from-boringnotch)
- [Localizations](#localizations)
- [Contributing Code](#contributing-code)
  - [Before You Start](#before-you-start)
  - [Setting Up Your Environment](#setting-up-your-environment)
  - [Making Changes](#making-changes)
  - [Pull Requests](#pull-requests)
<!-- - [Code Style Guidelines](#code-style-guidelines) -->
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)
- [Getting Help](#getting-help)
- [Cutting a release](#cutting-a-release)

## Working on T3 Isle

The T3 Code integration lives in two places. `T3IsleCore/` is a Swift package with the models, the T3 server client and the derived state, and it never imports SwiftUI or AppKit. The views are in `boringNotch/T3Isle/`.

Run the package tests with:

```sh
swift test --package-path T3IsleCore
```

To work on the views without live agents, launch the app with `--demo`. Demo mode plays the recorded `showcase` scenario (see [Replay a scenario](#replay-a-scenario)) and never contacts T3.

### Debug builds

The Debug configuration is its own app: bundle id `dev.t3isle.app.debug`, shown as "T3 Isle Debug". It keeps its own settings (`defaults read dev.t3isle.app.debug`), its own T3 session (`~/Library/Application Support/T3 Isle Debug/session.json`, issued under the label "T3 Isle Debug") and its own shelf (`~/Library/Application Support/T3 Isle Debug/Shelf`), so a dev build never touches the installed app. Debug builds never launch at login. Release builds keep `dev.t3isle.app`.

A fresh Debug identity starts with onboarding. To skip it:

```sh
defaults write dev.t3isle.app.debug firstLaunch -bool false
```

On a Mac without a notch whose menu bar hides itself, the closed notch has no height, so closed-notch activities (headphones, T3) are invisible. Give it one:

```sh
defaults write dev.t3isle.app.debug nonNotchHeightMode -string "Custom height"
```

### Debug commands

Debug builds accept commands from the shell, so you can drive the app without clicking. They are compiled out of Release builds. Send one through the `t3isle-debug://` URL scheme. Naming the app with `-a` targets that exact build and launches it if needed:

```sh
APP="$HOME/Library/Developer/Xcode/DerivedData/<your build>/Build/Products/Debug/T3 Isle.app"
open -g -a "$APP" "t3isle-debug://open-settings/t3"
```

Or pass commands at launch, each after `--debug`:

```sh
open -a "$APP" --args --debug open-settings appearance --debug replay question
```

| Command | What it does | Reverse | Example |
| --- | --- | --- | --- |
| `open-settings [pane]` | Opens Settings, on a pane if given (`general`, `t3`, `appearance`, `media`, `calendar`, `hud`, `battery`, `shelf`, `shortcuts`, `advanced`, `about`) | `close-settings` | `open -g -a "$APP" "t3isle-debug://open-settings/t3"` |
| `close-settings` | Closes Settings | `open-settings` | `open -g -a "$APP" "t3isle-debug://close-settings"` |
| `open-notch` | Opens the notch | `close-notch` | `open -g -a "$APP" "t3isle-debug://open-notch"` |
| `close-notch` | Closes the notch | `open-notch` | `open -g -a "$APP" "t3isle-debug://close-notch"` |
| `tab home\|t3\|shelf` | Opens the notch on a tab | `close-notch` | `open -g -a "$APP" "t3isle-debug://tab/t3"` |
| `demo on\|off` | Relaunches with or without demo data | `demo off`, `demo on` | `open -g -a "$APP" "t3isle-debug://demo/on"` |
| `replay <scenario>\|off` | Replays a recorded T3 scenario in place of the real T3 data, or goes back to it with `off` | `replay off` | `open -g -a "$APP" "t3isle-debug://replay/question"` |
| `state` | Writes what the app shows as JSON to the state file | None, it changes nothing | `open -g -a "$APP" "t3isle-debug://state"` |
| `airpods-connect [name] [battery]` | Shows the headphones activity as if they just connected (default `AirPods Pro`, battery 0 to 100) | `airpods-disconnect` | `open -g -a "$APP" "t3isle-debug://airpods-connect/AirPods%20Max/64"` |
| `airpods-disconnect` | Hides the headphones activity | `airpods-connect` | `open -g -a "$APP" "t3isle-debug://airpods-disconnect"` |

In a URL, arguments are path segments, so encode spaces as `%20`. The command ignores a query or fragment, so a script can add `?n=4` to tell its commands apart. The event log keeps the full URL.

To tear down, run the reverse of each command you ran, last first. A reverse with nothing to undo does nothing and still succeeds: `replay off` without a replay, or `demo off` outside demo mode. Each `command.ran` event names its reverse.

#### Replay a scenario

`replay <scenario>` swaps the T3 data for a recording, which the app reads through the same decoders as the live connection. Answering a replayed question or approving a replayed request works like the real thing. `replay` needs the T3 integration turned on in Settings, but not T3 Code itself. `replay off` goes back to the real T3 data, or to `showcase` in demo mode.

| Scenario | What it shows |
| --- | --- |
| `showcase` | Six threads in three projects: two approvals, a two-question request, a snoozed thread, a failed thread and two providers. Over 12 seconds a plan finishes. Demo mode plays it too. |
| `busy-session` | Four threads working in two projects, with no questions or approvals |
| `question` | One thread asks one question, which shows the attention border |
| `plan-done` | One thread finishes its three-step plan after 1.5 seconds, which shows the "Plan complete" banner |
| `quota-low` | Two threads, with both providers at 95 and 92 percent of their session window |

Recordings live in `T3IsleCore/Sources/T3IsleCore/Scenarios/<name>.ndjson`. Line 1 names the scenario: `{"scenario":"question","summary":"One thread asks one question"}`. Every other line is one step: `afterMs`, the delay since the previous step (default 0), and exactly one payload in T3's own wire JSON:

- `shell`: one `orchestration.subscribeShell` item, such as `{"kind":"thread.updated","thread":{...}}`.
- `detail`: a `/api/orchestration/threads/<id>/bounded` response body, `{"projection":{...}}`.
- `provider`: `{"id":"claudeAgent","file":{...}}`, where `file` is the content of `~/.t3/caches/claudeAgent.json`.

```json
{"afterMs":1500,"shell":{"kind":"thread.updated","thread":{"id":"plan-thread","title":"Finish the three-step plan","status":"completed","updatedAt":"2026-01-01T00:00:01.500Z"}}}
```

Dates count from `2026-01-01T00:00:00.000Z`, which stands for the moment the replay starts, so "running for 5m" labels come out the same every run. The app fetches a thread's details when the thread changes, so put a `detail` step before the `shell` step that announces or updates its thread. `swift test --package-path T3IsleCore` fails on any recording line that does not decode, and names the file and line.

#### Read the state

`state` writes `~/Library/Logs/T3 Isle Debug/state.json`. It writes a temporary file and renames it, so a reader never sees half a file. The file has no timestamps, so the same scenario gives the same bytes every run. Every key is always present, with `null` for nothing. After `replay question`, it reads (arrays folded onto one line here):

```json
{
  "closedActivity" : "t3",
  "headphones" : null,
  "notch" : "open",
  "settingsOpen" : false,
  "t3" : {
    "agents" : [ { "id" : "question-thread", "state" : "needsYou" } ],
    "banner" : null,
    "connection" : "live",
    "enabled" : true,
    "presence" : "alert",
    "prompts" : [ { "id" : "question-request#border", "kind" : "question", "threadId" : "question-thread", "title" : "Border" } ],
    "providers" : [ ],
    "replay" : { "finished" : true, "scenario" : "question" },
    "source" : "replay",
    "threads" : [ { "id" : "question-thread", "mood" : "needsYou", "project" : "web", "snoozed" : false, "title" : "Check the attention border" } ]
  },
  "tab" : "t3"
}
```

`notch` is `open` or `closed`. `tab` is `home`, `shelf` or `t3`. `closedActivity` is `none`, `t3`, `nowPlaying` or `headphones`. `t3.source` is `live`, `demo` or `replay`, and `t3.connection` is `connecting`, `live` or `offline`. Each entry in `t3.providers` reads `{"id":"claudeAgent","windows":[{"kind":"session","usedPercent":95}]}`. `state` waits until any replay has finished, the app has taken in every update the replay sent, and it has fetched the thread details it was waiting for, up to 30 seconds, then writes the file, so `replay plan-done` followed by `state` gives the same file every run. Its `state.written` event says `settled` `true`, or `false` when it gave up waiting.

Things outside the replay carry over between scenarios: whether the notch is open, the tab, Settings, and the headphones activity. Start from a known place by sending `close-notch` (and the reverse of anything else you ran) before `replay`. A question or a finished plan may open the notch on its own, the same way live T3 does.

To read the state from a script, remove the old file, ask for a new one, and wait for it:

```sh
STATE="$HOME/Library/Logs/T3 Isle Debug/state.json"
rm -f "$STATE"
open -g -a "$APP" "t3isle-debug://state"
for _ in $(seq 350); do [ -f "$STATE" ] && break; sleep 0.1; done
jq . "$STATE"
```

#### Read the event log

Debug builds append one JSON object per line to `~/Library/Logs/T3 Isle Debug/events.ndjson`:

```json
{"time":"2026-11-16T10:00:00.123Z","event":"command.ran","attributes":{"command":"replay question","input":"t3isle-debug://replay/question?n=4","reverse":"replay off"}}
```

| Event | Attributes |
| --- | --- |
| `app.launched` | `pid`, `version`, `source` (`live` or `demo`) |
| `command.ran` | `input`, `command`, `reverse` (missing for `state`) |
| `command.failed` | `input`, `message` |
| `replay.started` | `scenario`, `steps` |
| `replay.finished` | `scenario` |
| `connection.changed` | `state` |
| `notch.opened`, `notch.closed` | None |
| `tab.changed` | `tab` |
| `activity.changed` | `closedActivity` |
| `prompts.changed` | `count` |
| `banner.shown` | `threadId` |
| `state.written` | `path`, `settled` |
| `state.failed` | `message` |

When the log is over 5 MB at launch, the app moves it to `events.1.ndjson` and starts a new one. To summarize the last 10 minutes (counts per event, failed commands, and the last 20 events), run:

```sh
scripts/debug-log.sh
```

It takes the number of minutes and the log file as optional arguments, needs only `jq`, and exits with 2 when the log file is missing.

#### Add a command

The commands and their parsing live in `T3IsleCore/Sources/T3IsleCore/DebugCommand.swift`. To add one:

1. Add a case to `DebugCommand`, with its `tokens` and its `reverse`. Only a command that changes nothing has no reverse.
2. Add an entry to `DebugCommand.specs`.
3. Handle the case in `boringNotch/T3Isle/T3DebugCommands.swift`.
4. Add a row to the table in this section.

The compiler flags a case with no tokens, reverse or handler, and `swift test` flags a spec with no row here.

#### A state folder per copy

Launch a Debug build with `--state-dir <path>` and it keeps all of its state in that folder, so two copies running side by side share nothing:

| In the state folder | Holds | Without `--state-dir` |
| --- | --- | --- |
| `defaults.plist` | Settings | `defaults read dev.t3isle.app.debug` |
| `session.json` | T3 session (file `0600`, folder `0700`) | `~/Library/Application Support/T3 Isle Debug/session.json` |
| `Shelf/` | Shelf items | `~/Library/Application Support/T3 Isle Debug/Shelf` |
| `logs/` | `events.ndjson` and `state.json` | `~/Library/Logs/T3 Isle Debug/` |

```sh
open -n -a "$APP" --args --state-dir "$PWD/.build/debug-state" --demo
defaults read "$PWD/.build/debug-state/defaults"
defaults write "$PWD/.build/debug-state/defaults" nonNotchHeightMode -string "Custom height"
```

Pass an absolute path, since `open` starts the app from `/`. `demo on|off` keeps the folder when it relaunches, but Restart T3 Isle in the menu does not, so quit and launch again instead. Release builds ignore the flag. The folders are resolved in `T3IsleCore/Sources/T3IsleCore/StateFolders.swift`.

#### Scripts

These scripts build, launch, screenshot and stop a Debug copy with its own state folder. They print results on stdout and progress on stderr.

`scripts/run-debug.sh` builds the Debug app into `.build/DerivedData` with the CI flags (log in `.build/run-debug-build.log`), launches it with `--state-dir .build/debug-state` plus any arguments you pass, waits for its first window, and prints one JSON line:

```sh
scripts/run-debug.sh --demo
scripts/run-debug.sh --no-build --state-dir /tmp/t3isle-b --debug tab t3
```

```json
{"app":"…/.build/DerivedData/Build/Products/Debug/T3 Isle.app","pid":4242,"log":"…/.build/debug-state/logs/events.ndjson","state":"…/.build/debug-state/logs/state.json","stateDir":"…/.build/debug-state"}
```

On failure the line also has an `error` field, and the script exits with 2 when the build or signing failed and 3 when the app did not launch. A new state folder starts past onboarding. The script refuses to start a second copy on a state folder that is already in use.

To keep macOS permissions across builds, set a signing identity (a certificate's SHA-1 or name) in your shell, never in the repo. Without one, the app keeps its build signature.

```sh
export T3ISLE_SIGN_IDENTITY=<certificate SHA-1 or name>
export T3ISLE_SIGN_KEYCHAIN=<path to the keychain that holds it>
```

`scripts/capture.sh <label>` saves the windows of the last launched copy to `.build/debug-state/captures/<NN>-<label>.png`, counting `NN` up from `01`, and prints the path. `--pid`, `--out` and `--state-dir` pick another copy or folder. A copy with one window is captured on its own, so other apps don't show up in the image.

```sh
APP=$(plutil -extract app raw -o - .build/debug-state/run.json)
open -g -a "$APP" "t3isle-debug://open-notch"
scripts/capture.sh notch-open
```

`scripts/stop-debug.sh [pid]` quits the last launched copy, or the PID you give, with SIGTERM, waits for it to exit, and refuses any process that isn't a T3 Isle build outside `/Applications`.

```sh
scripts/stop-debug.sh
scripts/stop-debug.sh --state-dir /tmp/t3isle-b
```

`scripts/check-changed.sh [base-ref]` lints the Swift files changed since the merge base with `origin/main` (or the ref you give), untracked files included, and runs the `T3IsleCore` test classes for them: `Foo.swift` runs `FooTests`, a changed test file runs itself, a changed fixture runs the tests that name it, and a `Package.swift` change runs the whole suite. It ends with a pass/FAIL summary and exits non-zero on a failure. CI still runs everything.

```sh
scripts/check-changed.sh
```

#### Hazards

- Quit only the PID you launched. `app.launched` names it. Other checkouts may be running their own copies, and `killall "T3 Isle"` also quits the installed app.
- Never touch the installed app's settings (`dev.t3isle.app`) or session (`~/Library/Application Support/T3 Isle/session.json`).
- Never reinstall the T3 service (`t3 service install` or `uninstall`).
- When two copies run from the same build, `open -a "$APP" "t3isle-debug://…"` reaches only one of them. Pass commands at launch with `--debug` instead.

### How it talks to T3 Code

T3 Isle uses T3 Code's local server on this Mac. It finds the server in `~/.t3/userdata/server-runtime.json` (falling back to `http://127.0.0.1:3773`) and signs in with T3's own command-line tool (`t3 auth session issue`), asking only for the `orchestration:read` and `orchestration:operate` scopes. The session token is stored in `T3 Isle/session.json` (`T3 Isle Debug/session.json` for Debug builds) in the app's Application Support folder, readable only by your account (file `0600`, folder `0700`).

- Threads, questions and approvals stream live over T3's WebSocket API (`orchestration.subscribeShell`). Thread details (plan, activity, question text) come from `/api/orchestration/threads/<id>/bounded`.
- Answers, approvals, interrupts, snooze and settle are sent as T3 orchestration commands (`runtime-request.respond`, `thread.stop`, `thread.snooze`, `thread.settle`, …).
- Usage limits come from `~/.t3/caches/<provider>.json`.
- Clicking a thread opens `t3code://threads/<environment-id>/<thread-id>`.

Set `T3CODE_HOME` to use a different T3 data directory.

### Syncing from boring.notch

The upstream `cicd.yml`, `base_ref_check.yml` and `base_ref_check_comment.yml` workflows were removed on purpose. If an upstream merge hits a modify/delete conflict on them, resolve it with `git rm`.

## Localizations

Please submit all translations to [Crowdin](https://crowdin.com/project/boring-notch). New strings added to the `dev` branch from code changes will sync automatically to Crowdin, and Crowdin will automatically open a new PR with translations to allow us to integrate them.

## Contributing Code

### Before You Start

- **Check existing issues**: Before creating a new issue or starting work, search existing issues to avoid duplicates.
- **Discuss major changes**: For significant features or major changes, please open an issue first to discuss your approach with maintainers and the community.
<!-- - **Review the code style**: Familiarize yourself with our code style guidelines below to ensure consistency. -->

> [!IMPORTANT]
> All code contributions must be based on the `dev` branch, not `main`. Documentation changes should be based on `main` instead.

### Setting Up Your Environment

1. **Fork the repository**: Click the "Fork" button at the top of the repository page to create your own copy.

2. **Clone your fork**:
   ```bash
   git clone https://github.com/{your-username}/boring.notch.git
   cd boring.notch
   ```
   Replace `{your-username}` with your GitHub username.

3. **Switch to the `dev` branch**:
   ```bash
   git checkout dev
   ```
   All code contributions must be based on the `dev` branch, not `main`. Documentation changes should be based on `main` instead.

5. **Create a new feature branch**:
   ```bash
   git checkout -b feature/{your-feature-name}
   ```
   Replace `{your-feature-name}` with a descriptive name. Use lowercase letters, numbers, and hyphens only (e.g., `feature/add-dark-mode` or `fix/notification-crash`).

### Making Changes

1. **Make your changes**: Implement your feature or bug fix. Write clean, well-documented code <!-- following the project's style guidelines. -->

2. **Test your changes**: Ensure your changes work as expected and don't break existing functionality.

3. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Add descriptive commit message"
   ```
   Write clear, concise commit messages that explain what your changes do and why.

4. **Keep your branch up to date**:
   Regularly sync your branch with the latest changes from the `dev` branch to avoid conflicts.

5. **Push to your fork**:
   ```bash
   git push origin feature/{your-feature-name}
   ```

### Pull Requests

1. **Create a pull request**: Go to the original repository and click "New Pull Request." Select your feature branch and set the base branch to `dev`.

2. **Write a detailed description**: Your PR should include:
   - A clear title summarizing the changes
   - A detailed description of what was changed and why
   - Reference to any related issues (e.g., "Fixes #123" or "Relates to #456")
   - Screenshots or screen recordings for UI changes

3. **Respond to feedback**: Maintainers may request changes.

4. **Be patient**: Reviews take time. Maintainers will get to your PR as soon as they can.

<!-- ## Code Style Guidelines

- Follow the existing code style and conventions used in the project
- Write clear, self-documenting code with meaningful variable and function names
- Add comments for complex logic or non-obvious implementations
- Ensure your code is properly formatted before committing
- Remove any debugging code, console logs, or commented-out code before submitting -->

## Reporting Bugs

When reporting bugs, please include:

- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs. actual behavior
- Screenshots or error messages if applicable
- Your environment details (OS version, app version, etc.)

## Feature Requests

Feature requests are welcome! Please:

- Check if the feature has already been requested
- Clearly describe the feature and its use case
- Explain why this feature would be valuable to users
- Be open to discussion and alternative approaches

## Getting Help

If you need help or have questions:

- Check the project documentation
- Search existing issues for similar questions
- Open a new issue with the "question" label
- Join our [community Discord server](https://discord.com/servers/boring-notch-1269588937320566815)

## Cutting a release

T3 Isle ships through GitHub Releases only. There is no nightly channel and no in-app updater.

1. Make sure `main` has what you want to ship and its checks are green.
2. Tag that commit and push the tag:
   ```bash
   git fetch origin
   git tag v0.2.0 origin/main
   git push origin v0.2.0
   ```
3. The **T3 Isle release** workflow builds the app with the tag's version (`0.2.0`), packages `T3-Isle.dmg`, and publishes a GitHub Release with the DMG and generated notes.

Tags must look like `vX.Y.Z`. Any other `v*` tag fails the build, and no release is created.

To build a test DMG without releasing, open the workflow in the Actions tab, click **Run workflow**, and download `T3-Isle.dmg` from the run's artifacts. Pull requests that change the workflow or `Configuration/dmg/` build one the same way.

Release builds are signed with a stable self-signed certificate but not notarized, so macOS blocks the first launch until the user clicks **Open Anyway** in System Settings → Privacy & Security. Developer ID signing and notarization need a paid Apple Developer account and are not set up yet.

---

Thank you for contributing to Boring Notch! Your efforts help make this project better for everyone. 🎉

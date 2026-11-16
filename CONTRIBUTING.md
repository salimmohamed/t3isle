# Contributing

Thank you for taking the time to contribute! ❤️

These guidelines help streamline the contribution process for everyone involved. By following them, you'll make it easier for maintainers to review your work and collaborate with you effectively.

You can contribute in many ways: writing code, improving documentation, reporting bugs, requesting features, or creating tutorials and blog posts. Every contribution, large or small, helps make Boring Notch better.

## Table of Contents

- [Working on T3 Isle](#working-on-t3-isle)
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

To work on the views without live agents, launch the app with `--demo`. Demo mode uses made-up agents, questions, plans and quota, and never contacts T3.

### How it talks to T3 Code

T3 Isle uses T3 Code's local server on this Mac. It finds the server in `~/.t3/userdata/server-runtime.json` (falling back to `http://127.0.0.1:3773`) and signs in with T3's own command-line tool (`t3 auth session issue`), asking only for the `orchestration:read` and `orchestration:operate` scopes. The session token is stored in `~/Library/Application Support/T3 Isle/session.json`, readable only by your account (file `0600`, folder `0700`).

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

The app is ad-hoc signed and not notarized, so macOS blocks the first launch until the user clicks **Open Anyway** in System Settings → Privacy & Security. Developer ID signing and notarization need a paid Apple Developer account and are not set up yet.

---

Thank you for contributing to Boring Notch! Your efforts help make this project better for everyone. 🎉

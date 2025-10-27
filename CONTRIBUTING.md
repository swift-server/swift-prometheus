## Legal

By submitting a pull request, you represent that you have the right to license
your contribution to Apple and the community, and agree by submitting the patch
that your contributions are licensed under the Apache 2.0 license (see
`LICENSE.txt`).

## How to Contribute

Contributions to this project are welcome. You can help by opening an issue to report a bug or suggest a feature, or by submitting a pull request with code changes.

For security concerns, please follow the private disclosure process outlined in the [SECURITY.md](SECURITY.md) file instead of opening a public issue.

### Reporting Bugs or Requesting Features

A great bug report or feature request is specific and actionable. Before submitting a new issue, please check if a similar one already exists.

When you create a bug report, please provide the following:

- **swift-prometheus commit hash** you are using.
- **Context**: What were you trying to achieve?
- **Steps to Reproduce**: Provide the simplest possible steps. A pull request with a failing test case is ideal.
- **Environment Details**:
    - Swift version (`swift --version`)
    - OS version (`uname -a`)
    - Any other relevant configuration.

#### Example

```
swift-prometheus commit hash: 22ec043dc9d24bb011b47ece4f9ee97ee5be2757

Context:
While load testing my program written with swift-prometheus, I noticed
that one file descriptor is leaked per request.

Steps to reproduce:
1. ...
2. ...
3. ...
4. ...

$ swift --version
Swift version 4.0.2 (swift-4.0.2-RELEASE)
Target: x86_64-unknown-linux-gnu

Operating system: Ubuntu Linux 16.04 64-bit

$ uname -a
Linux beefy.machine 4.4.0-101-generic #124-Ubuntu SMP Fri Nov 10 18:29:59 UTC 2017 x86_64 x86_64 x86_64 GNU/Linux

My system has IPv6 disabled.
```

### Submitting Code Contributions

#### The Development Workflow

1.  **Fork & Clone**: Fork the repository and clone it to your local machine.

    ```bash
    git clone https://github.com/YOUR_USERNAME/swift-prometheus.git
    cd swift-prometheus
    ```

2.  **Create a Branch**: Create a descriptive branch for your changes (e.g., `fix/counter-overflow` or `feature/new-exporter`).

    ```bash
    git checkout -b fix/counter-overflow
    ```

3.  **Write Code & Tests**: Make your changes. All new code must be accompanied by tests to prevent regressions. For changes that are performance-critical or security-sensitive, we also strongly encourage adding new benchmarks or fuzz tests.

4.  **Run Checks Locally**: Before pushing, validate your changes by running the project's automated checks on your local machine.
    - **Run Unit Tests**: This is the most fundamental check to ensure your changes haven't broken existing functionality.

        ```bash
        swift test
        ```

    - **Check Code Formatting**: We use `swift-format` to maintain a consistent code style. Run the following command to verify your code is formatted correctly.

        ```bash
        curl -s --retry 3 https://raw.githubusercontent.com/swiftlang/github-workflows/refs/heads/main/.github/workflows/scripts/check-swift-format.sh | bash
        ```

    - **Simulate CI Workflows (Optional)**: For a more comprehensive check, you can run the full GitHub Actions workflows locally using [act](https://github.com/nektos/act). This is useful for catching issues that only appear in the CI environment.
        - For detailed setup instructions, see the Swift project's guide on [Running Workflows Locally](https://github.com/swiftlang/github-workflows?tab=readme-ov-file#running-workflows-locally).
        - You can run an entire workflow or target a specific job. For example, to run only the `soundness` check:
            ```bash
            act pull_request --job soundness
            ```
        - You can find the names of all available jobs to target in our [pull_request.yml](.github/workflows/pull_request.yml) file.

5.  **Commit & Push**: Write a clear commit message following the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) standard, then push your branch to your fork.

6.  **Open a Pull Request**: Open a PR against the `main` branch. Link any relevant issues in your PR description (e.g., `Fixes #123`).

#### Pull Request Guidelines

For a smooth review process, your PR should be:

- **Atomic**: Address a single, focused issue or feature.
- **Tested**: Include tests that prove your change works.
- **Documented**: Add DocC comments for any new public APIs.

Once submitted, a maintainer will review your code, provide feedback, and merge it once it's approved. Thank you for your contribution!

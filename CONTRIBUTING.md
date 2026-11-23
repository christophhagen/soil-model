# Contributing to SoilModel

Thank you for considering a contribution! Contributions of all sizes are welcome,
from typo fixes in the documentation to new features.

Please note that this project follows a [Code of Conduct](CODE_OF_CONDUCT.md).

## How to contribute

1. **Small changes**: Open a pull request directly for documentation fixes, small bug fixes, or clarifications.
2. **Larger or behavioral changes**: Please open an issue first to discuss the proposal.
   This avoids duplicated work and ensures that the change fits the design of the library.
3. **Questions**: Use the issue tracker, so that the answers are searchable for others.

Security issues should not be reported publicly, see the [Security Policy](SECURITY.md).

## Setting up locally

```sh
swift build   # Compile the library
swift test    # Run the test suite
```

## Opening a pull request

- Keep the change focused, with one logical change per pull request.
- Add or update tests to cover the change.
- Update the [Readme](Readme.md) if the change affects the public API or usage examples.
- Document public API additions with DocC-style comments.
- Add an entry to the [CHANGELOG](CHANGELOG.md) for user-facing changes.
- Describe **what** changed and **why** in the pull request.

## License

By contributing to this repository, you agree that your contributions are licensed under the [MIT License](LICENSE).

# Contributing

We welcome contributions from everyone. By participating in this project, you agree to follow our [code of conduct](./CODE_OF_CONDUCT.md).

## Getting Started

1. **Fork the repository** and clone it locally:
   ```
   git clone git@github.com:your-username/discourse-segment-CDP.git
   ```

2. **Create a branch** for your changes:
   ```
   git checkout -b your-feature-branch
   ```

3. **Make your changes**, ideally in alignment with existing coding style.

4. **Test your work**. We prefer contributions that come with clear test coverage where applicable.

5. **Commit with a clear message**:
   Refer to [this guide](http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html) for good commit message practices.

6. **Push to your fork** and submit a pull request:
   [Submit PR](https://github.com/islegendary/discourse-segment-CDP/compare/)

## Development Guidelines

### Plugin Structure
- Keep plugin disabled by default
- Ensure settings are properly initialized
- Use friendly names for page tracking
- Handle errors gracefully
- Add appropriate logging
- Follow Segment's latest specifications for context objects

### Testing
- Test with missing writeKey
- Test with various user ID strategies
- Test page tracking with different controllers
- Test error conditions
- Verify context object structure matches Segment spec
- Check for duplicate event calls

### Documentation
- Update README.md with new features
- Add entries to CHANGELOG.md
- Document any new settings
- Include examples where helpful

## Tips for a Smooth Review

- Focus PRs on a single change or set of related changes.
- Reference any relevant GitHub issues in your PR description.
- Be open to feedback. We aim to respond to PRs within 1–3 business days.
- If adding new configuration settings, update the `README.md` and `settings.yml` accordingly.
- If the plugin behavior changes, update `CHANGELOG.md`.
- Ensure all Segment event calls follow the latest specifications.

Thank you for helping improve the Discourse Segment CDP Plugin.

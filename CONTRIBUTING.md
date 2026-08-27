# Contributing to Jido Browser

Thank you for your interest in contributing to Jido Browser!

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/agentjido/jido_browser.git
   cd jido_browser
   ```

2. Install dependencies:
   ```bash
   mix setup
   ```

3. Run tests:
   ```bash
   mix test
   ```

4. Run quality checks:
   ```bash
   mix quality
   ```

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Make your changes
4. Ensure `mix quality` passes
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/)
6. Give the pull request a Conventional Commit title
7. Push to your fork and submit a PR

Pull requests are squash merged. The Conventional Commit title of the pull request becomes the squash commit and the source for the generated changelog entry. Do not edit generated changelog entries by hand.

## Code Style

- Follow existing code patterns
- Add `@moduledoc` and `@doc` for public modules/functions
- Include typespecs for public functions
- Use Zoi for struct schemas
- Use Splode for error types

## Testing

- Add tests for new functionality
- Ensure existing tests pass
- Use Mimic for mocking external dependencies

`mix coveralls` enforces the coverage floor in
`coveralls.json` at `coverage_options.minimum_coverage`. When a feature or bug fix
raises the coverage baseline, raise this floor in the same pull request.

## Commit Messages

Use Conventional Commits:

```
feat(scope): add new feature
fix(scope): fix a bug
docs: update documentation
test: add tests
chore: maintenance tasks
```

## Questions?

Open an issue or reach out to the maintainers.

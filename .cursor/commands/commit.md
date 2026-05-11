Using git to commit current changes with the Commit Rule following the these steps, and as fast as possible without any explanations.

# Steps
1. According to the staged changes existing or not,
   -. If there are staged changes, read the staged changes using `git --no-pager diff --cached`
   -. If there are not staged changes, read the changes in the current branch using `git --no-pager diff`
2. According to the changes content, the changes may be committed with one or more commits.
3. For each commit, generate a commit message using the Commit Rule
4. Commit the changes with the generated commit message

# Commit Rule

Follow the commit message format: `[type](scope): <message>`

## Format Structure
- **type**: Required type indicating the type of change
- **scope**: Optional scope in square brackets (e.g., [macos], [backend], [api])
- **message**: Descriptive commit message

## Examples
- `feat(backend) Add new user authentication feature`
- `fix(macos) Fix login form validation`
- `docs(README) Update README documentation`


## Rules
1. Always start with an appropriate type
2. Use scope in square brackets when the change affects a specific part of the codebase
3. Keep the message concise but descriptive
4. Use present tense ("Add feature" not "Added feature")

# Homebrew tap

`Casks/portside.rb` is the cask for a personal tap, so people can run:

```sh
brew install springmusk026/tap/portside
```

That also links the `portside` command into your PATH.

## Set up the tap (once)

```sh
gh repo create springmusk026/homebrew-tap --public --description "Homebrew casks for my Mac apps"
git clone https://github.com/springmusk026/homebrew-tap.git
mkdir -p homebrew-tap/Casks
```

## For each release

```sh
./build.sh --release        # prints the zip's SHA-256
gh release create v1.1.0 build/Portside.zip --title "Portside 1.1.0" --notes-file <(...)
```

Copy `Casks/portside.rb` into the tap's `Casks/`, set `version` and `sha256` to the release's,
then commit and push the tap. Check it with `brew audit --cask --strict springmusk026/tap/portside`.

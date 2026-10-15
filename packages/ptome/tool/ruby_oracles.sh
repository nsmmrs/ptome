#!/usr/bin/env bash
# The checks against Asciidoctor itself, run by hand when retargeting or
# moving a pin (they test outside software, which changes on its own
# schedule, not ptome's code; what the tests need of it is frozen in the
# corpus's goldens):
#
#   tool/ruby_oracles.sh e2e            the CLI's bats suite on the gem
#   tool/ruby_oracles.sh differential   the differential harness's self-check
#   tool/ruby_oracles.sh epub           EPUB parity with asciidoctor-epub3
#                                       2.3.0, every book through EPUBCheck
#   tool/ruby_oracles.sh goldens        the corpus's goldens made again from
#                                       their pinned bundle: the same files
#   tool/ruby_oracles.sh all
#
# Everything is installed into the work folder (WORK, by default
# ~/.cache/asciidart-work/ruby-oracles), never the system's: the gem from
# upstream main at the pin tool/vendor.sh follows (2.1.0.alpha.0) with
# asciimath, asciidoctor-epub3 on it, EPUBCheck 5.4.0. Needs Ruby 3.4,
# bats, Java and git.
set -euo pipefail
cd "$(dirname "$0")/.."
work="${WORK:-$HOME/.cache/asciidart-work/ruby-oracles}"
export GEM_HOME="$work/gems" GEM_PATH="$work/gems"
export PATH="$GEM_HOME/bin:$PATH"
# (The goldens were made in UTC: a book's date is in its zone.)
export TZ=UTC
mkdir -p "$work"

gem_main() {
  [ -x "$GEM_HOME/bin/asciidoctor" ] && asciidoctor --version >/dev/null 2>&1 &&
    return
  local src="$work/asciidoctor"
  [ -d "$src/.git" ] ||
    git clone -q https://github.com/asciidoctor/asciidoctor.git "$src"
  git -C "$src" checkout -q 30fb8cd5f7145c57274b04524ceaa99812f830e0
  (cd "$src" && gem build -q asciidoctor.gemspec &&
    gem install --no-document asciidoctor-*.gem)
  # (logger: a bundled gem from Ruby 4.0 on, no longer a default one.)
  gem install --no-document asciimath:2.0.6 logger
}

exe() {
  [ -x "$work/ptome" ] && [ "$work/ptome" -nt bin/ptome.dart ] && return
  dart compile exe -o "$work/ptome" bin/ptome.dart >/dev/null
}

e2e() {
  gem_main
  ASCIIDOCTOR_EXE=test/e2e/bin/asciidoctor-ruby bats test/e2e/
}

differential() {
  gem_main
  bats test/differential/
}

epub() {
  gem_main
  exe
  if ! command -v asciidoctor-epub3 >/dev/null; then
    gem install --no-document gepub -v 1.0.17
    gem install --no-document mime-types sass
    gem install --no-document --ignore-dependencies asciidoctor-epub3 -v 2.3.0
  fi
  asciidoctor-epub3 -v | grep -q 'using Asciidoctor 2.1.0'
  local jar="$work/epubcheck-5.4.0/epubcheck.jar"
  if [ ! -f "$jar" ]; then
    curl -sSLo "$work/epubcheck.zip" \
      https://github.com/w3c/epubcheck/releases/download/v5.4.0/epubcheck-5.4.0.zip
    unzip -q -o "$work/epubcheck.zip" -d "$work"
  fi
  dart run tool/epub_parity.dart \
    --exe-a "$(command -v asciidoctor-epub3)" --exe-b "$work/ptome" \
    --epubcheck "$jar" \
    $(find vendor/asciidoctor-epub3/test/fixtures -name '*.adoc' | sort)
}

goldens() {
  local dir=../ptome_corpus_tools/goldens copy="$work/corpus"
  rm -rf "$copy"
  cp -r test/corpus "$copy"
  (cd "$dir" &&
    BUNDLE_GEMFILE="$PWD/asciidoctor-2.0.26/Gemfile" bundle install --quiet &&
    BUNDLE_GEMFILE="$PWD/asciidoctor-2.0.26/Gemfile" \
      bundle exec ruby generate.rb --replace -j 4 "$copy")
  local status=0 a b
  for case in test/corpus/*/; do
    [ -d "$case/expected" ] || continue
    while read -r a b; do
      # (A book by the files in it: a ZIP's bytes carry its entries' dates
      # and the zlib that wrote it.)
      if [[ "$a" == *.epub ]] && same_entries "$a" "$b"; then continue; fi
      echo "differs: $a"
      status=1
    done < <(diff -rq "$case/expected" "$copy/$(basename "$case")/expected" |
      sed -nE 's/^Files (.*) and (.*) differ$/\1 \2/p')
  done
  return $status
}

# Whether the ZIP files $1 and $2 hold the same entries, byte for byte.
same_entries() {
  local name
  [ "$(unzip -Z1 "$1" | sort)" = "$(unzip -Z1 "$2" | sort)" ] || return 1
  while read -r name; do
    cmp -s <(unzip -p "$1" "$name") <(unzip -p "$2" "$name") || return 1
  done < <(unzip -Z1 "$1")
}

case "${1:-}" in
  e2e | differential | epub | goldens) "$1" ;;
  all) e2e && differential && epub && goldens ;;
  *)
    echo "usage: tool/ruby_oracles.sh e2e|differential|epub|goldens|all" >&2
    exit 64
    ;;
esac

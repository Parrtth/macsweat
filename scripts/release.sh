#!/bin/zsh
# Packages a MacSweat release from the version in VERSION.
#
#   scripts/release.sh            build, zip to dist/, and stamp site/install with the version + SHA-256
#   scripts/release.sh --publish  upload that exact zip as a GitHub release, then push main
#
# Between the two steps, commit the stamped site/install. --publish refuses to run on a dirty tree
# or if the zip no longer matches the checksum in site/install.
#
# The website is published by Vercel from the site/ folder on every push to main. So --publish
# uploads the release first and pushes main last: the new installer never goes live before the
# zip it points to exists.
set -eu
cd "${0:A:h}/.."
version=$(<VERSION)
repo=Parrtth/macsweat

if [[ "${1:-}" != "--publish" ]]; then
  ./build.sh
  mkdir -p dist
  rm -f dist/MacSweat.zip
  ditto -c -k --keepParent build/MacSweat.app dist/MacSweat.zip
  sha=$(shasum -a 256 dist/MacSweat.zip | awk '{print $1}')
  print "$sha  MacSweat.zip" > dist/MacSweat.zip.sha256
  sed -i '' -e "s/^VERSION=\".*\"/VERSION=\"$version\"/" -e "s/^SHA256=\".*\"/SHA256=\"$sha\"/" site/install
  print "\nMacSweat $version packaged: dist/MacSweat.zip"
  print "SHA-256 $sha (written to site/install)"
  print "Next: commit site/install, then run scripts/release.sh --publish"
  exit 0
fi

sha=$(shasum -a 256 dist/MacSweat.zip | awk '{print $1}')
grep -q "^SHA256=\"$sha\"" site/install || { print "dist/MacSweat.zip doesn't match site/install — run scripts/release.sh again." >&2; exit 1; }
grep -q "^VERSION=\"$version\"" site/install || { print "site/install isn't stamped with $version." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { print "Commit your changes first (the working tree isn't clean)." >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { print "Switch to main first; the website is published from main." >&2; exit 1; }
# 1. Send the commit up under the release tag only. A tag doesn't trigger a website deploy.
git push origin "HEAD:refs/tags/v$version"
# 2. Create the release on that tag and upload the zip.
gh release create "v$version" dist/MacSweat.zip dist/MacSweat.zip.sha256 --repo $repo \
  --verify-tag --title "MacSweat $version" --generate-notes
# 3. Push main. Vercel publishes site/, and the installer's download is already in place.
git push origin HEAD:main
print "Published MacSweat $version: https://github.com/$repo/releases/tag/v$version"
print "Vercel is publishing the site now. Check https://macsweat.parthh.dev/install in a minute."

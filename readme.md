# Bookmark with Pocket
Add bookmarks to Pocket based on simple rules.


## Firefox bookmarking
There isn't an API for bookmark tags. Have to guess if tags were added. To make
as accurate guess as possible I check tags dateGroupModified field for changes.

Events that I can detect fire only when name(title) or location(url) field of url
is changed. When only tags field is changed there is no event fired.
So when dateGroupModified field is out of "sync" I might detect wrong tag(s).


## Resources
- [Pocket authentication](https://blog.wilgucki.pl/oauth-authentication-without-browser/)


## TODO
- Explore handling of option/result values. [Optional value handling in Nim](https://peterme.net/optional-value-handling-in-nim.html)
  - https://github.com/arnetheduck/nim-result
  - https://github.com/superfunc/maybe
  - https://github.com/PMunch/nim-optionsutils
  - https://github.com/disruptek/badresults
  - https://github.com/superfunc/maybe
  - fusion/matching
- replace tailwindcss with unocss
- Use nim std lib js fetch api (requires nim >= 1.6)
- style options page


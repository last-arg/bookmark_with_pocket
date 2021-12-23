# Bookmark with Pocket
Add bookmarks to Pocket based on simple rules.


## Firefox bookmarking
1) There isn't an API for bookmark tags. Have to guess if tags were added. To make
as accurate guess as possible I check tags dateGroupModified field for changes.

2) Events that I can detect fire only when name(title) or location(url) field of url
is changed. When only tags field is changed there is no event fired.
So when dateGroupModified field is out of "sync" I might detect wrong tag(s).

3) There is no way to modify bookmark tags


## Resources
- [Pocket authentication](https://blog.wilgucki.pl/oauth-authentication-without-browser/)


## TODO
- Explore handling of option/result values.
  - [Optional value handling in Nim](https://peterme.net/optional-value-handling-in-nim.html)
  - [Pattern matching in Nim ](https://nim-lang.org/blog/2021/03/10/fusion-and-pattern-matching.html)
  - https://github.com/arnetheduck/nim-result
  - https://github.com/superfunc/maybe
  - https://github.com/PMunch/nim-optionsutils
  - https://github.com/disruptek/badresults
  - https://github.com/superfunc/maybe
  - fusion/matching
- open/close rule lists
- populate web ext storage with fake data
- options saved (how to update background state machine config?)
  - send event to background state machine. will get and update config
  - send new options to background state machine
- Add remove bookmark rules

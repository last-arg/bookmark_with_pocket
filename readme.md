# Bookmark with Pocket
Add bookmarks to Pocket based on simple tag rules.


## Firefox bookmarking
1) There isn't an API for bookmark tags. Have to guess if tags were added. To make
as accurate guess as possible I check tags dateGroupModified field for changes.

2) Events that I can detect fire only when name(title) or location(url) field of url
is changed. When only tags field is changed there is no event fired.
So when dateGroupModified field is out of "sync" I might detect wrong tag(s).

3) There is no way to modify bookmark tags


## Steps to release web extension
TODO


## Development
```
# Will open firefox browser with web extension
just web-ext
# Watch js and css files
just dev
```

## Resources
- [Pocket authentication](https://blog.wilgucki.pl/oauth-authentication-without-browser/)
- [Optional value handling in Nim](https://peterme.net/optional-value-handling-in-nim.html)
- [Pattern matching in Nim](https://nim-lang.org/blog/2021/03/10/fusion-and-pattern-matching.html)


## TODO
- Rule: remove bookmark

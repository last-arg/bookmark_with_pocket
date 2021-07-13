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

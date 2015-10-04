# Feedistiller [![Build Status](https://travis-ci.org/sdanzan/feedistiller.svg?branch=master)](https://travis-ci.org/sdanzan/feedistiller)


Provides functions to downloads enclosures of rss/atom feeds.

**Work in progress**
  
Features:
- download multiple feeds at once and limit the number of downloads
  occurring at the same (globally or on per feed basis).
- various filtering options:
  - content-type criteria
  - item name criteria
  - item date criteria  
                          
`HTTPoison` must be started to use `Feedistiller`
functions.

**TODO**
- CLI
- More filtering options


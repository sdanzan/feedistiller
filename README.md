# Feedistiller [![Build Status](https://travis-ci.org/sdanzan/feedistiller.svg?branch=master)](https://travis-ci.org/sdanzan/feedistiller) [![Hex pm](http://img.shields.io/hexpm/v/feedistiller.svg?style=flat)](https://hex.pm/packages/feedistiller)

Provides functions to download enclosures of rss/atom feeds. Includes
a small wrapper over the `feeder` feed parsing library.

## Features:

- download multiple feeds at once and limit the number of downloads
  occurring at the same (globally or on per feed basis).
- limited support for authenticated feeds (http basic auth)
- various filtering options:
  - content-type criteria
  - item name criteria
  - item date criteria  
- an elixir wrapper over the `feeder` module (https://github.com/michaelnisi/feeder)
  with complete support of the `file` and `stream` APIs.

## Modules

- `Feedistiller.Feeder`: wrapper over https://github.com/michaelnisi/feeder
- `Feedistiller.CLI`: command line API for Feedistiller features
- `Feedistiller.Http`: Http download of feeds
- `Feedistiller`: feed download functions

## Command line usage

`mix run feedistiller.exs [OPTIONS]`

Example:
> `mix run feedistiller --destination some_directory --max 15 --max-download 5 \
>                        --filter-content-type "audio/mpeg" --feed-url http://some_feed.rss`

See `mix run feedistiller --help` or `Feedistiller.CLI.help` for more informations.

Alternatively you can build the `feedistiller` standalone executable using `mix build.escript`
and run it as `feedistiller [OPTIONS]`.

Feedistiller can be embedded as an application in your projects. Just ensure the 
`feedistiller` application is started. Download functions are located in the
`Feedistiller` module. Reporting is available in the `Feedistiller.Reporter.Reported` Agent.
You can activate console or logger logging via the `Feedistiller.Reporter.log_to_console/log_to_logger`
functions. See the source code for some example.
                          
## TODO

- More filtering options
- More authentication options
- Persistency
- Public tests (currently tests are done in the REPL against a few feeds and are not
  committed in the repo)

## Installation

Add the github repository to your mix dependencies:

  1. Add feedistiller to your list of dependencies in `mix.exs`:

        def deps do
          [{:alambic, git: "https://github.com/sdanzan/feedistiller.git"}]
        end

  2. Ensure feedistiller is started before your application:

        def application do
          [applications: [:feedistiller]]
        end

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add feedistiller to your list of dependencies in `mix.exs`:

        def deps do
          [{:feedistiller, "~> 0.1.0"}]
        end

  2. Ensure alambic is started before your application:

        def application do
          [applications: [:feedistiller]]
        end

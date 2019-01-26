# alerterr

> Pipe any command's errors to Slack

Passes through stdout, stderr, and exit code as if the command was executed
directly. In case of non-zero exit-status, the contents of both output streams
is posted to a Slack webhook. With `--on_ok`, post even upon success.

## Usage

See:

```bash
$ bundle exec ruby main.rb -h
```

Example user-wide executable usable as `alerterr --name=foo uptime`:

```bash
$ cat ~/bin/alerterr
#!/usr/bin/env bash

root=~/code/alerterr
webhook="https://hooks.slack.com/services/XXX/YYY/ZZZ"

export BUNDLE_GEMFILE="$root"/Gemfile

exec bundle exec ruby "$root"/main.rb on_err "$webhook" "$@"
```

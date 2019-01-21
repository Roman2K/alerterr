# alerterr

> Pipe any command's errors to Slack

STDOUT, STDERR and exit code are passed through as if the command was executed
directly. In case of non-zero exit-status, the contents of both output streams
is posted to a Slack webhook. With `--on_ok`, post even upon successful runs.

## Usage

See:

```bash
$ bundle exec ruby main.rb -h
```

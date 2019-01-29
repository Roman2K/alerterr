require 'net/http'
require 'json'
require 'stringio'
require 'shellwords'

module Cmds
  ##
  # Send a Slack notification upon non-zero exit-status.
  #
  # Options:
  #
  #   --name=NAME
  #
  #       Custom name to appear in Slack. Defaults to the executable's filename.
  #   
  #   --on_ok
  #
  #       Notify even upon success.
  #
  #   --on_out=PATTERN
  #
  #       Notify upon success if stdout matches PATTERN.
  #       PATTERN may be either string or a regex in the /.../ format.
  #
  #   --on_err=PATTERN
  #
  #       Notify upon success if stderr matches PATTERN.
  #
  # Add -- before the command to disambiguate on_err options from the command's.
  # Not mandatory but recommended. Example:
  #
  #   alerterr --name=foo -- du --summarize -h
  #
  def self.cmd_on_err(webhook, exe, *args, name: exe,
    on_ok: false, on_out: nil, on_err: nil
  )
    on_out = Match.regexp on_out if on_out
    on_err = Match.regexp on_err if on_err

    runtime, (out, err, st) = time { run exe, *args }

    fields = -> do
      [ { title: "Command",
          value: "`#{Shellwords.join [exe, *args]}`" },
        { title: "Exit code",
          value: "%d" % st.exitstatus,
          short: true },
        { title: "Runtime",
          value: "%.2fs" % runtime,
          short: true },
        { title: "stdout",
          value: fmt_block(out) },
        { title: "stderr",
          value: fmt_block(err) } ]
    end

    attach = if !st.success?
      { fallback: "Command failed: `#{name}`",
        color: "danger",
        pretext: "Command failed",
        author_name: name,
        fields: fields[] }
    elsif on_ok || out =~ on_out || err =~ on_err
      { fallback: "Command OK: `#{name}`",
        color: "good",
        pretext: "Command successful",
        author_name: name,
        fields: fields[] }
    end

    Net::HTTP.
      post(URI(webhook), {attachments: [attach]}.to_json).
      tap { |res|
        res.code == "200" or $stderr.puts \
          "Failed to post to webhook (#{res.code} #{res.msg}):", res.body
      } if attach
      
    exit st.exitstatus
  end

  def self.run(*cmd)
    out, err = Array.new(2) { StringIO.new.set_encoding ENC_BIN }
    tees = {
      out: Tee.new($stdout, out),
      err: Tee.new($stderr, err),
    }
    pid = Bundler.with_clean_env do
      spawn *cmd, {in: $stdin}.update(tees.transform_values &:w)
    end
    _, st = Process.wait2 pid
    tees.each_value { |t| t.w.close }
    tees.each_value { |t| t.thr.join }
    [out.string, err.string, st]
  end

  module Match
    OPTS = {
      i: Regexp::IGNORECASE,
      m: Regexp::MULTILINE,
      x: Regexp::EXTENDED,
    }

    def self.regexp(pat)
      pat =~ %r%\A/(.*)/(.*)\z% or return Regexp.new Regexp.escape pat
      Regexp.new $1, $2.chars.
        map { |c| OPTS[c.to_sym] or raise "unknown option: %s" % c }.
        inject(0) { |opts, opt| opts | opt }
    end
  end

  def self.time
    t0 = Time.now
    res = yield
    [Time.now - t0, res]
  end

  ENC_TEXT = Encoding::UTF_8
  ENC_BIN = Encoding::BINARY

  def self.fmt_block(s)
    unless s.encoding == ENC_TEXT && s.valid_encoding?
      s, enc = s.dup, s.encoding
      s.force_encoding ENC_TEXT
      if !s.valid_encoding?
        s.force_encoding enc
        begin
          s.encode ENC_TEXT
        rescue Encoding::UndefinedConversionError
          return "[binary]"
        end
      end
    end
    s = s.chomp
    s =~ /\S/ or return "[empty]"
    "```\n#{s}\n```"
  end
end

class Tee
  BUFSIZE = 1 * 1024 * 1024

  def initialize(*outs)
    r, @w = IO.pipe
    @thr = Thread.new do
      loop do
        data = begin
          r.readpartial BUFSIZE
        rescue EOFError
          break
        end
        outs.each do |out|
          out.write data
        end
      end
    end
  end

  attr_reader :w
  attr_reader :thr
end

if $0 == __FILE__
  require 'metacli'
  MetaCLI.new(ARGV).run Cmds
end

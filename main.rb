require 'net/http'
require 'json'
require 'stringio'
require 'shellwords'
require 'utils'
require 'gist'

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
    on_ok: false, on_out: nil, on_err: nil, on_log: true
  )
    on_out = Match.regexp on_out if on_out
    on_err = Match.regexp on_err if on_err

    runtime, (out, err, st) = time { run exe, *args }

    on_log = (LogScan::Multi[LogScan.new(out), LogScan.new(err)] if on_log)

    make_attachment = -> do
      { author_name: name,
        text: {"stdout" => out, "stderr" => err}.
          map { |t,s| "*#{t}:*\n#{fmt_block(s) { |t| gist t }}" }.
          join("\n\n"),
        footer: "%s@%s$ %s%s (%s)" % [
          Etc.getlogin, Socket.gethostname,
          [exe, *args].map { |s| s =~ /\s/ ? %("#{s}") : s }.join(" "),
          (" - exit: %d" % st.exitstatus unless st.success?),
          Utils::Fmt.duration(runtime),
        ] }
    end

    attach = if !st.success? || on_log&.error?
      make_attachment[].update \
        fallback: "Command failed: `#{name}`",
        color: "danger",
        pretext: "Command failed"
    elsif on_log&.warn?
      make_attachment[].update \
        fallback: "Command warning: `#{name}`",
        color: "warning",
        pretext: "Command warning"
    elsif on_ok || out =~ on_out || err =~ on_err
      make_attachment[].update \
        fallback: "Command OK: `#{name}`",
        color: "good",
        pretext: "Command successful"
    end

    Net::HTTP.
      post(URI(webhook), {attachments: [attach]}.to_json).
      tap { |res|
        res.code == "200" or $stderr.puts \
          "Failed to post to webhook (#{res.code} #{res.msg}):", res.body
      } if attach
      
    exit st.exitstatus
  end
  
  def self.gist(text)
    url = if text.bytesize >= 7800
      begin
        Gist.gist(text, filename: "alerterr.log",public: false).fetch "html_url"
      rescue => err
        $stderr.puts "alerterr: failed to create gist: #{err.class}: #{err}"
        nil
      end
    end
    if url
      text = [text[0,3500], "…", text[-3500..-1]].join "\n"
    end
    [text, url]
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
    s, bottom = yield s if block_given?
    ["```\n#{s}\n```", bottom].compact.join "\n\n"
  end
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

class LogScan
  def initialize(s)
    @s = s
  end

  def warn?; match? "WARN" or error? end
  def error?; match? "ERROR" or fatal? end
  def fatal?; match? "FATAL" end

  private def match?(level)
    @s =~ /^\s*#{Regexp.escape level}\b/
  end

  class Multi < Array
    def warn?; any? &:warn? end
    def error?; any? &:error? end
    def fatal?; any? &:fatal? end
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

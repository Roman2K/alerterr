require 'net/http'
require 'json'
require 'stringio'
require 'shellwords'
require 'metacli'

module Cmds
  def self.cmd_on_err(webhook, exe, *args, on_ok: false)
    runtime, (out, err, st) = time { run exe, *args }

    fields = [
      { title: "Command",
        value: "`#{Shellwords.join [exe, *args]}`" },
      { title: "Exit code",
        value: "%d" % st.exitstatus,
        short: true },
      { title: "Runtime",
        value: "%.2fs" % runtime,
        short: true },
      { title: "STDOUT",
        value: fmt_block(out) },
      { title: "STDERR",
        value: fmt_block(err) },
    ]
    attach = if st.success?
      { fallback: "Command OK: `#{exe}`",
        color: "good",
        pretext: "Command successful",
        author_name: exe,
        fields: fields } if on_ok
    else
      { fallback: "Command failed: `#{exe}`",
        color: "danger",
        pretext: "Command failed",
        author_name: exe,
        fields: fields }
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
    out, err = StringIO.new, StringIO.new
    tees = {
      out: Tee.new($stdout, out),
      err: Tee.new($stderr, err),
    }
    pid = spawn *cmd, {in: $stdin}.update(tees.transform_values &:w)
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

  def self.fmt_block(s)
    s = s.chomp
    s =~ /\A\s*\z/ and return "None"
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

MetaCLI.new(ARGV).run Cmds

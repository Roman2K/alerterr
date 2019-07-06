require 'minitest/autorun'
require_relative '../main'

class CmdsTest < Minitest::Test
  def test_run
    errcap = out = err = st = nil
    outcap = capture '$stdout' do
      errcap = capture '$stderr' do
        out, err, st = Cmds.run "bash", "-c", "echo someout; echo someerr >&2"
      end
    end
    assert st.success?
    assert_equal Cmds::ENC_BIN, out.encoding
    assert_equal Cmds::ENC_BIN, err.encoding
    assert_equal "someout\n", out
    assert_equal "someout\n", outcap
    assert_equal "someerr\n", err
    assert_equal "someerr\n", errcap

    _, _, st = Cmds.run "bash", "-c", "exit 2"
    assert !st.success?
    assert_equal 2, st.exitstatus
  end

  private def capture(var)
    old = eval var
    io = StringIO.new
    eval "#{var} = io"
    begin
      yield
    ensure
      eval "#{var} = old"
    end
    io.string
  end

  def test_fmt_block
    assert_equal "[empty]",
      Cmds.fmt_block(" ")
    assert_equal "```\nabc\n```",
      Cmds.fmt_block("abc")
    assert_equal "```\nabc\n```",
      Cmds.fmt_block("abc".force_encoding(Cmds::ENC_BIN))

    bin = File.read(__dir__ + "/bin", mode: 'rb')
    assert_equal "[binary]", Cmds.fmt_block(bin)

    bin = File.read(__dir__ + "/textbin", mode: 'rb')
    assert Cmds.fmt_block(bin).include?(bin.dup.force_encoding(Cmds::ENC_TEXT))
  end

  def test_Match
    assert_equal /\./, Match.regexp(".")
    assert_equal /\/\./, Match.regexp("/.")
    assert_equal /./, Match.regexp("/./")
    assert_equal /./i, Match.regexp("/./i")
    assert_equal /./imx, Match.regexp("/./imx")

    err = assert_raises RuntimeError do
      Match.regexp("/./1")
    end
    assert_match /unknown opt/, err.message
  end

  def test_LogScan
    with_none = LogScan.new <<-EOS
 INFO a
DEBUG b
    EOS
    refute with_none.warn?
    refute with_none.error?
    refute with_none.fatal?

    with_warn = LogScan.new <<-EOS
 INFO a
 WARN xxx
DEBUG b
    EOS
    assert with_warn.warn?
    refute with_warn.error?
    refute with_warn.fatal?

    with_error = LogScan.new <<-EOS
 INFO a
ERROR xxx
DEBUG b
    EOS
    assert with_error.warn?
    assert with_error.error?
    refute with_error.fatal?

    multi = LogScan::Multi[]
    refute multi.warn?
    refute multi.error?
    refute multi.fatal?

    multi = LogScan::Multi[with_none]
    refute multi.warn?
    refute multi.error?
    refute multi.fatal?

    multi = LogScan::Multi[with_none, with_error]
    assert multi.warn?
    assert multi.error?
    refute multi.fatal?
  end
end

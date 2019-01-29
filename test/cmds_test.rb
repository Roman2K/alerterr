$:.unshift __dir__ + "/.."

require 'minitest/autorun'
require 'main'

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

  def test_match
    assert_equal /\./, Cmds::Match.regexp(".")
    assert_equal /\/\./, Cmds::Match.regexp("/.")
    assert_equal /./, Cmds::Match.regexp("/./")
    assert_equal /./i, Cmds::Match.regexp("/./i")
    assert_equal /./imx, Cmds::Match.regexp("/./imx")

    err = assert_raises RuntimeError do
      Cmds::Match.regexp("/./1")
    end
    assert_match /unknown opt/, err.message
  end
end

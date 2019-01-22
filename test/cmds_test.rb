$:.unshift __dir__ + "/.."

require 'minitest/autorun'
require 'main'

class CmdsTest < Minitest::Test
  def test_run
    out, err, st = Cmds.run "echo", "ok"
    assert st.success?
    assert_equal Cmds::ENC_BIN, out.encoding
    assert_equal Cmds::ENC_BIN, err.encoding
  end

  def test_fmt_block
    assert_equal "None",
      Cmds.fmt_block(" ")
    assert_equal "```\nabc\n```",
      Cmds.fmt_block("abc")
    assert_equal "```\nabc\n```",
      Cmds.fmt_block("abc".force_encoding(Cmds::ENC_BIN))

    bin = File.read(__dir__ + "/bin", mode: 'rb')
    assert_equal "[Binary]", Cmds.fmt_block(bin)

    bin = File.read(__dir__ + "/textbin", mode: 'rb')
    assert Cmds.fmt_block(bin).include?(bin.dup.force_encoding(Cmds::ENC_TEXT))
  end
end

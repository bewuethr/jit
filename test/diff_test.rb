require "minitest/autorun"

require "diff"

class TestDiff < Minitest::Test
  def test_simple_diff
    a = "ABCABBA".chars
    b = "CBABAC".chars
    edits = Diff.diff(a, b)

    assert_equal(["-A", "-B", " C", "+B", " A", " B", "-B", " A", "+C"], edits.map(&:to_s))
  end
end

require "minitest/autorun"

require "merge/diff3"

class Merge::TestDiff3 < Minitest::Test
  def test_cleanly_merge_two_lists
    merge = Merge::Diff3.merge(%w[a b c], %w[d b c], %w[a b e])
    assert(merge.clean?)
    assert_equal("dbe", merge.to_s)
  end

  def test_cleanly_merge_two_lists_with_same_edit
    merge = Merge::Diff3.merge(%w[a b c], %w[d b c], %w[d b e])
    assert(merge.clean?)
    assert_equal("dbe", merge.to_s)
  end

  def test_uncleanly_merge_two_lists
    merge = Merge::Diff3.merge(%w[a b c], %w[d b c], %w[e b c])
    refute(merge.clean?)

    assert_equal <<~EOF.strip, merge.to_s
      <<<<<<<
      d=======
      e>>>>>>>
      bc
    EOF
  end

  def test_uncleanly_merge_two_lists_against_empty_list
    merge = Merge::Diff3.merge([], %w[d b c], %w[e b c])
    refute(merge.clean?)

    assert_equal <<~EOF, merge.to_s
      <<<<<<<
      dbc=======
      ebc>>>>>>>
    EOF
  end

  def test_uncleanly_merge_two_lists_with_head_names
    merge = Merge::Diff3.merge(%w[a b c], %w[d b c], %w[e b c])
    refute(merge.clean?)

    assert_equal <<~EOF.strip, merge.to_s("left", "right")
      <<<<<<< left
      d=======
      e>>>>>>> right
      bc
    EOF
  end
end

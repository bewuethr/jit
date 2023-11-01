require "minitest/autorun"

require "diff"

class TestDiff < Minitest::Test
  def setup
    @before = %w[the quick brown fox jumps over the lazy dog]
  end

  def hunks(a, b)
    Diff.diff_hunks(a, b).map { |hunk| [hunk.header, hunk.edits.map(&:to_s)] }
  end

  def test_simple_diff
    a = "ABCABBA".chars
    b = "CBABAC".chars
    edits = Diff.diff(a, b)

    assert_equal(["-A", "-B", " C", "+B", " A", " B", "-B", " A", "+C"], edits.map(&:to_s))
  end

  def test_delete_at_start
    after = %w[quick brown fox jumps over the lazy dog]

    assert_equal([
      ["@@ -1,4 +1,3 @@", [
        "-the", " quick", " brown", " fox"
      ]]
    ], hunks(@before, after))
  end

  def test_insert_at_start
    after = %w[so the quick brown fox jumps over the lazy dog]

    assert_equal([
      ["@@ -1,3 +1,4 @@", [
        "+so", " the", " quick", " brown"
      ]]
    ], hunks(@before, after))
  end

  def test_change_in_middle
    after = %w[the quick brown fox leaps right over the lazy dog]

    assert_equal([
      ["@@ -2,7 +2,8 @@", [
        " quick", " brown", " fox", "-jumps", "+leaps", "+right", " over", " the", " lazy"
      ]]
    ], hunks(@before, after))
  end

  def test_combine_nearby_changes_into_single_hunk
    after = %w[the brown fox jumps over the lazy cat]

    assert_equal([
      ["@@ -1,9 +1,8 @@", [
        " the", "-quick", " brown", " fox", " jumps", " over", " the", " lazy", "-dog", "+cat"
      ]]
    ], hunks(@before, after))
  end

  def test_separate_distant_changes_into_two_hunks
    after = %w[a quick brown fox jumps over the lazy cat]

    assert_equal([
      ["@@ -1,4 +1,4 @@", [
        "-the", "+a", " quick", " brown", " fox"
      ]],
      ["@@ -6,4 +6,4 @@", [
        " over", " the", " lazy", "-dog", "+cat"
      ]]
    ], hunks(@before, after))
  end
end

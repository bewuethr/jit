require "minitest/autorun"

require "revision"

class TestRevision < Minitest::Test
  def assert_parse(expression, tree) = assert_equal(tree, Revision.parse(expression))

  def test_parse_head = assert_parse("HEAD", Revision::Ref.new("HEAD"))

  def test_parse_at = assert_parse("@", Revision::Ref.new("HEAD"))

  def test_parse_branch_name = assert_parse("main", Revision::Ref.new("main"))

  def test_parse_object_id
    assert_parse(
      "ad93b522bc1870f43ced7d938b99de65e6f60046",
      Revision::Ref.new("ad93b522bc1870f43ced7d938b99de65e6f60046")
    )
  end

  def test_parse_parent_ref
    assert_parse("HEAD^", Revision::Parent.new(Revision::Ref.new("HEAD"), 1))
  end

  def test_parse_parent_ref_chain
    assert_parse(
      "main^^^",
      Revision::Parent.new(
        Revision::Parent.new(
          Revision::Parent.new(
            Revision::Ref.new("main"),
            1
          ),
          1
        ),
        1
      )
    )
  end

  def test_parse_ancestor_ref
    assert_parse("@~3", Revision::Ancestor.new(Revision::Ref.new("HEAD"), 3))
  end

  def test_parse_parent_and_ancestor_chain
    assert_parse(
      "@~2^^~3",
      Revision::Ancestor.new(
        Revision::Parent.new(
          Revision::Parent.new(
            Revision::Ancestor.new(
              Revision::Ref.new("HEAD"),
              2
            ),
            1
          ),
          1
        ),
        3
      )
    )
  end

  def test_parse_upstream
    assert_parse("main@{uPsTrEaM}", Revision::Upstream.new(Revision::Ref.new("main")))
  end

  def test_parse_shorthand_upstream
    assert_parse("main@{u}", Revision::Upstream.new(Revision::Ref.new("main")))
  end

  def test_parse_upstream_with_no_branch
    assert_parse("@{u}", Revision::Upstream.new(Revision::Ref.new("HEAD")))
  end

  def test_parse_upstream_with_ancestor_operators
    assert_parse(
      "main@{u}^~3",
      Revision::Ancestor.new(
        Revision::Parent.new(
          Revision::Upstream.new(Revision::Ref.new("main")),
          1
        ),
        3
      )
    )
  end
end

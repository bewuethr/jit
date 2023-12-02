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
    assert_parse("HEAD^", Revision::Parent.new(Revision::Ref.new("HEAD")))
  end

  def test_parse_parent_ref_chain
    assert_parse(
      "main^^^",
      Revision::Parent.new(
        Revision::Parent.new(
          Revision::Parent.new(
            Revision::Ref.new("main")
          )
        )
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
            )
          )
        ),
        3
      )
    )
  end
end

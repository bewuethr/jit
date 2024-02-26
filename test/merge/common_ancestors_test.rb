require "minitest/autorun"
require "fileutils"
require "pathname"

require "database"
require "merge/common_ancestors"

class Merge::TestMergeCommonAncestors < Minitest::Test
  def setup = FileUtils.mkdir_p(db_path)

  def teardown = FileUtils.rm_rf(db_path)

  def db_path = Pathname.new(File.expand_path("../test-database", __FILE__))

  def database = @database ||= Database.new(db_path)

  def commit(parent, message)
    @commits ||= {}
    @time ||= Time.now

    parents = [@commits[parent]]
    author = Database::Author.new("A. U. Thor", "author@example.com", @time)
    commit = Database::Commit.new(parents, "0" * 40, author, message)

    database.store(commit)
    @commits[message] = commit.oid
  end

  def chain(names)
    names.each_cons(2) { |parent, message| commit(parent, message) }
  end

  def ancestor(left, right)
    common = Merge::CommonAncestors.new(database, @commits[left], @commits[right])
    database.load(common.find).message
  end
end

class Merge::TestMergeCommonAncestorsLinearHistory < Merge::TestMergeCommonAncestors
  def setup
    super

    #   o---o---o---o
    #   A   B   C   D
    chain([nil] + %w[A B C D])
  end

  def test_find_common_ancestor_of_commit_with_itself
    assert_equal("D", ancestor("D", "D"))
  end

  def test_find_commit_that_is_ancestor_of_the_other
    assert_equal("B", ancestor("B", "D"))
  end

  def test_find_same_commit_with_reversed_arguments
    assert_equal("B", ancestor("D", "B"))
  end

  def test_find_root_commit
    assert_equal("A", ancestor("A", "C"))
  end

  def test_find_intersection_of_root_commit_with_itself
    assert_equal("A", ancestor("A", "A"))
  end
end

class Merge::TestMergeCommonAncestorsForkingHistory < Merge::TestMergeCommonAncestors
  def setup
    super

    #          E   F   G   H
    #          o---o---o---o
    #         /         \
    #        /  C   D    \
    #   o---o---o---o     o---o
    #   A   B    \        J   K
    #             \
    #              o---o---o
    #              L   M   N
    chain([nil] + %w[A B C D])
    chain(%w[B E F G H])
    chain(%w[G J K])
    chain(%w[C L M N])
  end

  def test_find_nearest_fork_point
    assert_equal("G", ancestor("H", "K"))
  end

  def test_find_ancestor_multiple_forks_away
    assert_equal("B", ancestor("D", "K"))
  end

  def test_find_same_fork_point_for_any_point_on_branch
    assert_equal("C", ancestor("D", "L"))
    assert_equal("C", ancestor("M", "D"))
    assert_equal("C", ancestor("D", "N"))
  end

  def test_find_commit_that_is_ancestor_of_the_other
    assert_equal("E", ancestor("K", "E"))
  end

  def test_find_root_commit
    assert_equal("A", ancestor("J", "A"))
  end
end

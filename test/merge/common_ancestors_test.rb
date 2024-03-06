require "minitest/autorun"
require "fileutils"
require "pathname"

require "database"
require "merge/bases"
require "merge/common_ancestors"

class Merge::TestMergeCommonAncestors < Minitest::Test
  def setup = FileUtils.mkdir_p(db_path)

  def teardown = FileUtils.rm_rf(db_path)

  def db_path = Pathname.new(File.expand_path("../test-database", __FILE__))

  def database = @database ||= Database.new(db_path)

  def commit(parents, message)
    @commits ||= {}
    @time ||= Time.now

    parents = parents.map { |oid| @commits[oid] }
    author = Database::Author.new("A. U. Thor", "author@example.com", @time)
    commit = Database::Commit.new(parents, "0" * 40, author, message)

    database.store(commit)
    @commits[message] = commit.oid
  end

  def chain(names)
    names.each_cons(2) { |parent, message| commit([*parent], message) }
  end

  def ancestor(left, right)
    common = Merge::CommonAncestors.new(database, @commits[left], [@commits[right]])
    get_result(common)
  end

  def merge_base(left, right)
    bases = Merge::Bases.new(database, @commits[left], @commits[right])
    get_result(bases)
  end

  def get_result(common)
    commits = common.find.map { |oid| database.load(oid).message }
    (commits.size == 1) ? commits.first : commits
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

class Merge::TestMergeCommonAncestorsHistorywithMerge < Merge::TestMergeCommonAncestors
  def setup
    super

    #   A   B   C   G   H
    #   o---o---o---o---o
    #        \     /
    #         o---o---o
    #         D   E   F
    chain([nil] + %w[A B C])
    chain(%w[B D E F])
    commit(%w[C E], "G")
    chain(%w[G H])
  end

  def test_find_most_recent_common_ancestor
    assert_equal("E", ancestor("H", "F"))
  end

  def test_find_common_ancestor_of_merge_and_its_parent
    assert_equal("C", ancestor("C", "G"))
    assert_equal("E", ancestor("G", "E"))
  end
end

class Merge::TestMergeCommonAncestorsHistorywithMergeFurtherFromOneParent < Merge::TestMergeCommonAncestors
  def setup
    super

    #   A   B   C   G   H   J
    #   o---o---o---o---o---o
    #        \     /
    #         o---o---o
    #         D   E   F
    chain([nil] + %w[A B C])
    chain(%w[B D E F])
    commit(%w[C E], "G")
    chain(%w[G H J])
  end

  def test_find_all_common_ancestors
    assert_equal(%w[E B], ancestor("J", "F"))
  end

  def test_find_best_common_ancestor
    assert_equal("E", merge_base("J", "F"))
  end
end

class Merge::TestMergeCommonAncestorsCommitsBetweenAncestorAndMerge < Merge::TestMergeCommonAncestors
  def setup
    super

    #   A   B   C       H   J
    #   o---o---o-------o---o
    #        \         /
    #         o---o---o G
    #         D  E \
    #               o F
    chain([nil] + %w[A B C])
    chain(%w[B D E F])
    chain(%w[E G])
    commit(%w[C G], "H")
    chain(%w[H J])
  end

  def test_find_all_common_ancestors
    assert_equal(%w[B E], ancestor("J", "F"))
  end

  def test_find_best_common_ancestor
    assert_equal("E", merge_base("J", "F"))
  end
end

class Merge::TestMergeCommonAncestorsEnoughHistoryToFindAllStale < Merge::TestMergeCommonAncestors
  def setup
    super

    #   A   B   C             H   J
    #   o---o---o-------------o---o
    #        \      E        /
    #         o-----o-------o
    #        D \     \     / G
    #           \     o   /
    #            \    F  /
    #             o-----o
    #             P     Q
    chain([nil] + %w[A B C])
    chain(%w[B D E F])
    chain(%w[D P Q])
    commit(%w[E Q], "G")
    commit(%w[C G], "H")
    chain(%w[H J])
  end

  def test_find_best_common_ancestor
    assert_equal("E", ancestor("J", "F"))
    assert_equal("E", ancestor("F", "J"))
  end
end

class Merge::TestMergeCommonAncestorsManyCommonAncestors < Merge::TestMergeCommonAncestors
  def setup
    super

    #         L   M   N   P   Q   R   S   T
    #         o---o---o---o---o---o---o---o
    #        /       /       /       /
    #   o---o---o...o---o...o---o---o---o---o
    #   A   B  C \  D  E \  F  G \  H   J   K
    #             \       \       \
    #              o---o---o---o---o---o
    #              U   V   W   X   Y   Z
    chain([nil] + %w[A B C] + (1..4).map { |n| "pad-1-#{n}" } +
        %w[D E] + (1..4).map { |n| "pad-2-#{n}" } +
        %w[F G] +
        %w[H J K])

    chain(%w[B L M])
    commit(%w[M D], "N")
    chain(%w[N P])
    commit(%w[P F], "Q")
    chain(%w[Q R])
    commit(%w[R H], "S")
    chain(%w[S T])

    chain(%w[C U V])
    commit(%w[V E], "W")
    chain(%w[W X])
    commit(%w[X G], "Y")
    chain(%w[Y Z])
  end

  def test_find_multiple_candidate_common_ancestors
    assert_equal(%w[G D B], ancestor("T", "Z"))
  end

  def test_find_best_common_ancestor
    assert_equal("G", merge_base("T", "Z"))
  end
end

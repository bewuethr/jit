require "minitest/autorun"

require_relative "../command_helper"

class Command::TestMerge < Minitest::Test
  include CommandHelper

  def commit_tree(message, files)
    files.each do |path, contents|
      delete(path) unless contents == :x
      case contents
      when String then write_file(path, contents)
      when :x then make_executable(path)
      when Array
        write_file(path, contents[0])
        make_executable(path)
      end
    end
    delete(".git/index")
    jit_cmd("add", ".")
    commit(message)
  end

  #   A   B   M
  #   o---o---o [main]
  #    \     /
  #     `---o [topic]
  #         C
  #
  def merge3(base, left, right)
    commit_tree("A", base)
    commit_tree("B", left)

    jit_cmd("branch", "topic", "main^")
    jit_cmd("checkout", "topic")
    commit_tree("C", right)

    jit_cmd("checkout", "main")
    set_stdin("M")
    jit_cmd("merge", "topic")
  end

  def assert_clean_merge
    jit_cmd("status", "--porcelain")
    assert_stdout("")

    commit = load_commit("@")
    old_head = load_commit("@^")
    merge_head = load_commit("topic")

    assert_equal("M", commit.message)
    assert_equal([old_head.oid, merge_head.oid], commit.parents)
  end

  def assert_no_merge
    commit = load_commit("@")
    assert_equal("B", commit.message)
    assert_equal(1, commit.parents.size)
  end

  def assert_index(*entries)
    repo.index.load
    actual = repo.index.each_entry.map { |e| [e.path, e.stage] }
    assert_equal(entries, actual)
  end
end

class Command::TestMergeAncestor < Command::TestMerge
  def setup
    super

    commit_tree("A", "f.txt" => "1")
    commit_tree("B", "f.txt" => "2")
    commit_tree("C", "f.txt" => "3")

    jit_cmd("merge", "@^")
  end

  def test_print_up_to_date_message
    assert_stdout("Already up to date.\n")
  end

  def test_does_not_change_repo_state
    commit = load_commit("@")
    assert_equal("C", commit.message)

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end
end

class Command::TestFastForwardMerge < Command::TestMerge
  def setup
    super

    commit_tree("A", "f.txt" => "1")
    commit_tree("B", "f.txt" => "2")
    commit_tree("C", "f.txt" => "3")

    jit_cmd("branch", "topic", "@^^")
    jit_cmd("checkout", "topic")

    set_stdin("M")
    jit_cmd("merge", "main")
  end

  def test_print_fast_forward_message
    a, b = ["main^^", "main"].map { |rev| resolve_revision(rev) }
    assert_stdout <<~EOF
      Updating #{repo.database.short_oid(a)}..#{repo.database.short_oid(b)}
      Fast-forward
    EOF
  end

  def test_update_current_branch_head
    commit = load_commit("@")
    assert_equal("C", commit.message)

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end
end

class Command::TestMergeUnconflictedTwoFiles < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1", "g.txt" => "1"},
      {"f.txt" => "2"},
      {"g.txt" => "2"}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({
      "f.txt" => "2",
      "g.txt" => "2"
    })
  end

  def test_create_clean_merge
    assert_clean_merge
  end

  def test_leave_status_clean
    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end

  def test_write_commit_with_old_head_and_merged_commit_as_parents
    commit = load_commit("@")
    old_head = load_commit("@^")
    merge_head = load_commit("topic")

    assert_equal([old_head.oid, merge_head.oid], commit.parents)
  end
end

class Command::TestMergeUnconflictedWithDeletedFile < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1", "g.txt" => "1"},
      {"f.txt" => "2"},
      {"g.txt" => nil}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({"f.txt" => "2"})
  end

  def test_create_clean_merge
    assert_clean_merge
  end
end

class Command::TestMergeUnconflictedSameAddition < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"g.txt" => "2"},
      {"g.txt" => "2"}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({
      "f.txt" => "1",
      "g.txt" => "2"
    })
  end

  def test_create_clean_merge
    assert_clean_merge
  end
end

class Command::TestMergeUnconflictedSameEdit < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"f.txt" => "2"},
      {"f.txt" => "2"}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({"f.txt" => "2"})
  end

  def test_create_clean_merge
    assert_clean_merge
  end
end

class Command::TestMergeUnconflictedEditAndModeChange < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"f.txt" => "2"},
      {"f.txt" => :x}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({"f.txt" => "2"})
    assert_executable("f.txt")
  end

  def test_create_clean_merge
    assert_clean_merge
  end
end

class Command::TestMergeUnconflictedSameDeletion < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1", "g.txt" => "1"},
      {"g.txt" => nil},
      {"g.txt" => nil}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({"f.txt" => "1"})
  end

  def test_create_clean_merge
    assert_clean_merge
  end
end

class Command::TestMergeUnconflictedDeleteAddParent < Command::TestMerge
  def setup
    super

    merge3(
      {"nest/f.txt" => "1"},
      {"nest/f.txt" => nil},
      {"nest" => "3"}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({"nest" => "3"})
  end

  def test_create_clean_merge
    assert_clean_merge
  end
end

class Command::TestMergeUnconflictedDeleteAddChild < Command::TestMerge
  def setup
    super

    merge3(
      {"nest/f.txt" => "1"},
      {"nest/f.txt" => nil},
      {"nest/f.txt" => nil, "nest/f.txt/g.txt" => "3"}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({"nest/f.txt/g.txt" => "3"})
  end

  def test_create_clean_merge
    assert_clean_merge
  end
end

class Command::TestMergeConflictedAddAdd < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"g.txt" => "2\n"},
      {"g.txt" => "3\n"}
    )
  end

  def test_put_conflicted_file_in_workspace
    assert_workspace({
      "f.txt" => "1",
      "g.txt" => <<~EOF
        <<<<<<<< HEAD
        2
        ========
        3
        >>>>>>>> topic
      EOF
    })
  end

  def test_record_conflict_in_index
    assert_index(
      ["f.txt", 0],
      ["g.txt", 2],
      ["g.txt", 3]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeConflictedAddAddModeConflict < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"g.txt" => "2"},
      {"g.txt" => ["2"]}
    )
  end

  def test_put_conflicted_file_in_workspace
    assert_workspace({
      "f.txt" => "1",
      "g.txt" => "2"
    })
  end

  def test_record_conflict_in_index
    assert_index(
      ["f.txt", 0],
      ["g.txt", 2],
      ["g.txt", 3]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeConflictedFileDirectoryAddition < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"g.txt" => "2"},
      {"g.txt/nested.txt" => "3"}
    )
  end

  def test_put_namespaced_copy_of_conflicted_file_in_workspace
    assert_workspace({
      "f.txt" => "1",
      "g.txt~HEAD" => "2",
      "g.txt/nested.txt" => "3"
    })
  end

  def test_record_conflict_in_index
    assert_index(
      ["f.txt", 0],
      ["g.txt", 2],
      ["g.txt/nested.txt", 0]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeConflictedDirectoryFileAddition < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"g.txt/nested.txt" => "2"},
      {"g.txt" => "3"}
    )
  end

  def test_put_namespaced_copy_of_conflicted_file_in_workspace
    assert_workspace({
      "f.txt" => "1",
      "g.txt~topic" => "3",
      "g.txt/nested.txt" => "2"
    })
  end

  def test_record_conflict_in_index
    assert_index(
      ["f.txt", 0],
      ["g.txt", 3],
      ["g.txt/nested.txt", 0]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeConflictedEditEdit < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1\n"},
      {"f.txt" => "2\n"},
      {"f.txt" => "3\n"}
    )
  end

  def test_put_conflicted_file_in_workspace
    assert_workspace({
      "f.txt" => <<~EOF
        <<<<<<<< HEAD
        2
        ========
        3
        >>>>>>>> topic
      EOF
    })
  end

  def test_record_conflict_in_index
    assert_index(
      ["f.txt", 1],
      ["f.txt", 2],
      ["f.txt", 3]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeConflictedEditDelete < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"f.txt" => "2"},
      {"f.txt" => nil}
    )
  end

  def test_put_left_version_in_workspace
    assert_workspace("f.txt" => "2")
  end

  def test_record_conflict_in_index
    assert_index(
      ["f.txt", 1],
      ["f.txt", 2]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeConflictedDeleteEdit < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1"},
      {"f.txt" => nil},
      {"f.txt" => "3"}
    )
  end

  def test_put_right_version_in_workspace
    assert_workspace("f.txt" => "3")
  end

  def test_record_conflict_in_index
    assert_index(
      ["f.txt", 1],
      ["f.txt", 3]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeConflictedEditAddParent < Command::TestMerge
  def setup
    super

    merge3(
      {"nest/f.txt" => "1"},
      {"nest/f.txt" => "2"},
      {"nest" => "3"}
    )
  end

  def test_put_namespaced_copy_of_conflicted_file_in_workspace
    assert_workspace({
      "nest/f.txt" => "2",
      "nest~topic" => "3"
    })
  end

  def test_record_conflict_in_index
    assert_index(
      ["nest", 3],
      ["nest/f.txt", 1],
      ["nest/f.txt", 2]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeConflictedEditAddChild < Command::TestMerge
  def setup
    super

    merge3(
      {"nest/f.txt" => "1"},
      {"nest/f.txt" => "2"},
      {"nest/f.txt" => nil, "nest/f.txt/g.txt" => "3"}
    )
  end

  def test_put_namespaced_copy_of_conflicted_file_in_workspace
    assert_workspace({
      "nest/f.txt~HEAD" => "2",
      "nest/f.txt/g.txt" => "3"
    })
  end

  def test_record_conflict_in_index
    assert_index(
      ["nest/f.txt", 1],
      ["nest/f.txt", 2],
      ["nest/f.txt/g.txt", 0]
    )
  end

  def test_do_not_write_merge_commit
    assert_no_merge
  end
end

class Command::TestMergeMultipleCommonAncestors < Command::TestMerge
  #   A   B   C       M1  H   M2
  #   o---o---o-------o---o---o
  #        \         /       /
  #         o---o---o G     /
  #         D  E \         /
  #               `-------o
  #                       F
  def setup
    super

    commit_tree("A", "f.txt" => "1")
    commit_tree("B", "f.txt" => "2")
    commit_tree("C", "f.txt" => "3")

    jit_cmd("branch", "topic", "main^")
    jit_cmd("checkout", "topic")
    commit_tree("D", "g.txt" => "1")
    commit_tree("E", "g.txt" => "2")
    commit_tree("F", "g.txt" => "3")

    jit_cmd("branch", "joiner", "topic^")
    jit_cmd("checkout", "joiner")
    commit_tree("G", "h.txt" => "1")

    jit_cmd("checkout", "main")
  end

  def test_perform_first_merge
    set_stdin("merge joiner")
    jit_cmd("merge", "joiner")
    assert_status(0)

    assert_workspace({
      "f.txt" => "3",
      "g.txt" => "2",
      "h.txt" => "1"
    })

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end

  def test_perform_second_merge
    set_stdin("merge joiner")
    jit_cmd("merge", "joiner")

    commit_tree("H", "f.txt" => "4")

    set_stdin("merge topic")
    jit_cmd("merge", "topic")
    assert_status(0)

    assert_workspace({
      "f.txt" => "4",
      "g.txt" => "3",
      "h.txt" => "1"
    })

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end
end

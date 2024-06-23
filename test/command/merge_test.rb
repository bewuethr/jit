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
    jit_cmd("merge", "topic", "-m", "M")
  end

  def assert_clean_merge
    jit_cmd("status", "--porcelain")
    assert_stdout("")

    commit = load_commit("@")
    old_head = load_commit("@^")
    merge_head = load_commit("topic")

    assert_equal("M", commit.message.strip)
    assert_equal([old_head.oid, merge_head.oid], commit.parents)
  end

  def assert_no_merge
    commit = load_commit("@")
    assert_equal("B", commit.message.strip)
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
    assert_equal("C", commit.message.strip)

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

    jit_cmd("merge", "main", "-m", "M")
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
    assert_equal("C", commit.message.strip)

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

class Command::TestMergeUnconflictedInFileMergePossible < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1\n2\n3\n"},
      {"f.txt" => "4\n2\n3\n"},
      {"f.txt" => "1\n2\n5\n"}
    )
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({"f.txt" => "4\n2\n5\n"})
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

  def test_print_merge_conflict
    assert_stdout <<~EOF
      Auto-merging g.txt
      CONFLICT (add/add): Merge conflict in g.txt
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
  end

  def test_put_conflicted_file_in_workspace
    assert_workspace({
      "f.txt" => "1",
      "g.txt" => <<~EOF
        <<<<<<< HEAD
        2
        =======
        3
        >>>>>>> topic
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      AA g.txt
    EOF
  end

  def test_show_combined_diff_against_stages_2_and_3
    jit_cmd("diff")

    assert_stdout <<~EOF
      diff --cc g.txt
      index 0cfbf08,00750ed..2603ab2
      --- a/g.txt
      +++ b/g.txt
      @@@ -1,1 -1,1 +1,5 @@@
      ++<<<<<<< HEAD
       +2
      ++=======
      + 3
      ++>>>>>>> topic
    EOF
  end

  def test_show_diff_against_our_version
    jit_cmd("diff", "--ours")

    assert_stdout <<~EOF
      * Unmerged path g.txt
      diff --git a/g.txt b/g.txt
      index 0cfbf08..2603ab2 100644
      --- a/g.txt
      +++ b/g.txt
      @@ -1,1 +1,5 @@
      +<<<<<<< HEAD
       2
      +=======
      +3
      +>>>>>>> topic
    EOF
  end

  def test_show_diff_against_their_version
    jit_cmd("diff", "--theirs")

    assert_stdout <<~EOF
      * Unmerged path g.txt
      diff --git a/g.txt b/g.txt
      index 00750ed..2603ab2 100644
      --- a/g.txt
      +++ b/g.txt
      @@ -1,1 +1,5 @@
      +<<<<<<< HEAD
      +2
      +=======
       3
      +>>>>>>> topic
    EOF
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

  def test_print_merge_conflict
    assert_stdout <<~EOF
      Auto-merging g.txt
      CONFLICT (add/add): Merge conflict in g.txt
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      AA g.txt
    EOF
  end

  def test_show_combined_diff_against_stages_2_and_3
    jit_cmd("diff")

    assert_stdout <<~EOF
      diff --cc g.txt
      index d8263ee,d8263ee..d8263ee
      mode 100644,100755..100644
      --- a/g.txt
      +++ b/g.txt
    EOF
  end

  def test_report_mode_change_in_appropriate_diff
    jit_cmd("diff", "-2")
    assert_stdout <<~EOF
      * Unmerged path g.txt
    EOF

    jit_cmd("diff", "-3")
    assert_stdout <<~EOF
      * Unmerged path g.txt
      diff --git a/g.txt b/g.txt
      old mode 100755
      new mode 100644
    EOF
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

  def test_print_merge_conflict
    assert_stdout <<~EOF
      Adding g.txt/nested.txt
      CONFLICT (file/directory): There is a directory with name g.txt in topic. Adding g.txt as g.txt~HEAD
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      AU g.txt
      A  g.txt/nested.txt
      ?? g.txt~HEAD
    EOF
  end

  def test_list_file_as_unmerged_in_diff
    jit_cmd("diff")
    assert_stdout "* Unmerged path g.txt\n"
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

  def test_print_merge_conflict
    assert_stdout <<~EOF
      Adding g.txt/nested.txt
      CONFLICT (directory/file): There is a directory with name g.txt in HEAD. Adding g.txt as g.txt~topic
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UA g.txt
      ?? g.txt~topic
    EOF
  end

  def test_list_file_as_unmerged_in_diff
    jit_cmd("diff")
    assert_stdout "* Unmerged path g.txt\n"
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

  def test_print_merge_conflict
    assert_stdout <<~EOF
      Auto-merging f.txt
      CONFLICT (content): Merge conflict in f.txt
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
  end

  def test_put_conflicted_file_in_workspace
    assert_workspace({
      "f.txt" => <<~EOF
        <<<<<<< HEAD
        2
        =======
        3
        >>>>>>> topic
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UU f.txt
    EOF
  end

  def test_show_combined_diff_against_stages_2_and_3
    jit_cmd("diff")

    assert_stdout <<~EOF
      diff --cc f.txt
      index 0cfbf08,00750ed..2603ab2
      --- a/f.txt
      +++ b/f.txt
      @@@ -1,1 -1,1 +1,5 @@@
      ++<<<<<<< HEAD
       +2
      ++=======
      + 3
      ++>>>>>>> topic
    EOF
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

  def test_print_merge_conflict
    assert_stdout <<~EOF
      CONFLICT (modify/delete): f.txt deleted in topic and modified in HEAD. Version HEAD of f.txt left in tree.
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UD f.txt
    EOF
  end

  def test_list_file_as_unmerged_in_diff
    jit_cmd("diff")
    assert_stdout "* Unmerged path f.txt\n"
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

  def test_print_merge_conflict
    assert_stdout <<~EOF
      CONFLICT (modify/delete): f.txt deleted in HEAD and modified in topic. Version topic of f.txt left in tree.
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      DU f.txt
    EOF
  end

  def test_list_file_as_unmerged_in_diff
    jit_cmd("diff")
    assert_stdout "* Unmerged path f.txt\n"
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

  def test_print_merge_conflicts
    assert_stdout <<~EOF
      CONFLICT (modify/delete): nest/f.txt deleted in topic and modified in HEAD. Version HEAD of nest/f.txt left in tree.
      CONFLICT (directory/file): There is a directory with name nest in HEAD. Adding nest as nest~topic
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UA nest
      UD nest/f.txt
      ?? nest~topic
    EOF
  end

  def test_list_file_as_unmerged_in_diff
    jit_cmd("diff")
    assert_stdout <<~EOF
      * Unmerged path nest
      * Unmerged path nest/f.txt
    EOF
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

  def test_print_merge_conflict
    assert_stdout <<~EOF
      Adding nest/f.txt/g.txt
      CONFLICT (modify/delete): nest/f.txt deleted in topic and modified in HEAD. Version HEAD of nest/f.txt left in tree at nest/f.txt~HEAD.
      Automatic merge failed; fix conflicts and then commit the result.
    EOF
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

  def test_report_conflict_in_status
    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UD nest/f.txt
      A  nest/f.txt/g.txt
      ?? nest/f.txt~HEAD
    EOF
  end

  def test_list_file_as_unmerged_in_diff
    jit_cmd("diff")
    assert_stdout "* Unmerged path nest/f.txt\n"
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
    jit_cmd("merge", "joiner", "-m", "merge joiner")
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
    jit_cmd("merge", "joiner", "-m", "merge joiner")

    commit_tree("H", "f.txt" => "4")

    jit_cmd("merge", "topic", "-m", "merge topic")
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

class Command::TestMergeConflictResolution < Command::TestMerge
  def setup
    super

    merge3(
      {"f.txt" => "1\n"},
      {"f.txt" => "2\n"},
      {"f.txt" => "3\n"}
    )
  end

  def test_prevent_commit_with_unmerged_entries
    jit_cmd("commit")

    assert_stderr <<~EOF
      error: Committing is not possible because you have unmerged files.
      hint: Fix them up in the work tree, and then use 'jit add/rm <file>'
      hint: as appropriate to mark resolution and make a commit.
      fatal: Exiting because of an unresolved conflict.
    EOF
    assert_status(128)

    assert_equal("B", load_commit("@").message.strip)
  end

  def test_prevent_merge_continue_with_unmerged_entries
    jit_cmd("merge", "--continue")

    assert_stderr <<~EOF
      error: Committing is not possible because you have unmerged files.
      hint: Fix them up in the work tree, and then use 'jit add/rm <file>'
      hint: as appropriate to mark resolution and make a commit.
      fatal: Exiting because of an unresolved conflict.
    EOF
    assert_status(128)

    assert_equal("B", load_commit("@").message.strip)
  end

  def test_commit_merge_after_resolving_conflicts
    jit_cmd("add", "f.txt")
    jit_cmd("commit")
    assert_status(0)

    commit = load_commit("@")
    assert_equal("M", commit.message.strip)

    parents = commit.parents.map { |oid| load_commit(oid).message.strip }
    assert_equal(["B", "C"], parents)
  end

  def test_allow_merge_continue_after_resolving_conflicts
    jit_cmd("add", "f.txt")
    jit_cmd("merge", "--continue")
    assert_status(0)

    commit = load_commit("@")
    assert_equal("M", commit.message.strip)

    parents = commit.parents.map { |oid| load_commit(oid).message.strip }
    assert_equal(["B", "C"], parents)
  end

  def test_prevent_merge_continue_when_none_is_in_progress
    jit_cmd("add", "f.txt")
    jit_cmd("merge", "--continue")
    jit_cmd("merge", "--continue")

    assert_stderr("fatal: There is no merge in progress (MERGE_HEAD missing).\n")
    assert_status(128)
  end

  def test_abort_merge
    jit_cmd("merge", "--abort")
    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end

  def test_prevent_aborting_when_no_merge_in_progress
    jit_cmd("merge", "--abort")
    jit_cmd("merge", "--abort")

    assert_stderr("fatal: There is no merge to abort (MERGE_HEAD missing).\n")
    assert_status(128)
  end

  def test_prevent_starting_merge_while_one_in_progress
    jit_cmd("merge")

    assert_stderr <<~EOF
      error: Merging is not possible because you have unmerged files.
      hint: Fix them up in the work tree, and then use 'jit add/rm <file>'
      hint: as appropriate to mark resolution and make a commit.
      fatal: Exiting because of an unresolved conflict.
    EOF
    assert_status(128)
  end
end

require "minitest/autorun"

require_relative "../command_helper"

class Command::TestLog < Minitest::Test
  include CommandHelper

  def commit_file(message, time = nil)
    write_file("file.txt", message)
    jit_cmd("add", ".")
    commit(message, time)
  end

  def commit_tree(message, files, time = nil)
    files.each do |path, contents|
      write_file(path, contents)
    end
    jit_cmd("add", ".")
    commit(message, time)
  end
end

class Command::TestLogWithChainOfCommits < Command::TestLog
  #   o---o---o
  #   A   B   C
  def setup
    super

    ["A", "B", "C"].each do |message|
      commit_file(message)
    end

    jit_cmd("branch", "topic", "@^^")

    @commits = ["@", "@^", "@~2"].map { |rev| load_commit(rev) }
  end

  def test_print_log_in_medium_format
    jit_cmd("log")

    assert_stdout <<~EOF
      commit #{@commits[0].oid}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[0].author.readable_time}

          C

      commit #{@commits[1].oid}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[1].author.readable_time}

          B

      commit #{@commits[2].oid}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[2].author.readable_time}

          A
    EOF
  end

  def test_print_medium_format_with_short_commit_ids
    jit_cmd("log", "--abbrev-commit")

    assert_stdout <<~EOF
      commit #{repo.database.short_oid(@commits[0].oid)}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[0].author.readable_time}

          C

      commit #{repo.database.short_oid(@commits[1].oid)}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[1].author.readable_time}

          B

      commit #{repo.database.short_oid(@commits[2].oid)}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[2].author.readable_time}

          A
    EOF
  end

  def test_print_oneline_format
    jit_cmd("log", "--oneline")

    assert_stdout <<~EOF
      #{repo.database.short_oid(@commits[0].oid)} C
      #{repo.database.short_oid(@commits[1].oid)} B
      #{repo.database.short_oid(@commits[2].oid)} A
    EOF
  end

  def test_print_oneline_format_without_short_commit_ids
    jit_cmd("log", "--pretty=oneline")

    assert_stdout <<~EOF
      #{@commits[0].oid} C
      #{@commits[1].oid} B
      #{@commits[2].oid} A
    EOF
  end

  def test_log_from_specified_commit
    jit_cmd("log", "--pretty=oneline", "@^")

    assert_stdout <<~EOF
      #{@commits[1].oid} B
      #{@commits[2].oid} A
    EOF
  end

  def test_print_with_short_decorations
    jit_cmd("log", "--pretty=oneline", "--decorate=short")

    assert_stdout <<~EOF
      #{@commits[0].oid} (HEAD -> main) C
      #{@commits[1].oid} B
      #{@commits[2].oid} (topic) A
    EOF
  end

  def test_print_with_detached_head
    jit_cmd("checkout", "@")
    jit_cmd("log", "--pretty=oneline", "--decorate=short")

    assert_stdout <<~EOF
      #{@commits[0].oid} (HEAD, main) C
      #{@commits[1].oid} B
      #{@commits[2].oid} (topic) A
    EOF
  end

  def test_print_with_full_decorations
    jit_cmd("log", "--pretty=oneline", "--decorate=full")

    assert_stdout <<~EOF
      #{@commits[0].oid} (HEAD -> refs/heads/main) C
      #{@commits[1].oid} B
      #{@commits[2].oid} (refs/heads/topic) A
    EOF
  end

  def test_print_with_patches
    jit_cmd("log", "--pretty=oneline", "--patch")

    assert_stdout <<~EOF
      #{@commits[0].oid} C
      diff --git a/file.txt b/file.txt
      index 7371f47..96d80cd 100644
      --- a/file.txt
      +++ b/file.txt
      @@ -1,1 +1,1 @@
      -B
      +C
      #{@commits[1].oid} B
      diff --git a/file.txt b/file.txt
      index 8c7e5a6..7371f47 100644
      --- a/file.txt
      +++ b/file.txt
      @@ -1,1 +1,1 @@
      -A
      +B
      #{@commits[2].oid} A
      diff --git a/file.txt b/file.txt
      new file mode 100644
      index 0000000..8c7e5a6
      --- /dev/null
      +++ b/file.txt
      @@ -0,0 +1,1 @@
      +A
    EOF
  end
end

class Command::TestLogCommitTree < Command::TestLog
  #  m1  m2  m3
  #   o---o---o [main]
  #        \
  #         o---o---o---o [topic]
  #        t1  t2  t3  t4
  def setup
    super

    (1..3).each { |n| commit_file("main-#{n}") }

    jit_cmd("branch", "topic", "main^")
    jit_cmd("checkout", "topic")

    @branch_time = Time.now + 10
    (1..4).each { |n| commit_file("topic-#{n}", @branch_time) }

    @main = (0..2).map { |n| resolve_revision("main~#{n}") }
    @topic = (0..3).map { |n| resolve_revision("topic~#{n}") }
  end

  def test_log_combined_history_of_multiple_branches
    jit_cmd("log", "--pretty=oneline", "--decorate=short", "main", "topic")

    assert_stdout <<~EOF
      #{@topic[0]} (HEAD -> topic) topic-4
      #{@topic[1]} topic-3
      #{@topic[2]} topic-2
      #{@topic[3]} topic-1
      #{@main[0]} (main) main-3
      #{@main[1]} main-2
      #{@main[2]} main-1
    EOF
  end

  def test_log_difference_from_branch_to_other
    jit_cmd("log", "--pretty=oneline", "main..topic")

    assert_stdout <<~EOF
      #{@topic[0]} topic-4
      #{@topic[1]} topic-3
      #{@topic[2]} topic-2
      #{@topic[3]} topic-1
    EOF

    jit_cmd("log", "--pretty=oneline", "main", "^topic")

    assert_stdout <<~EOF
      #{@main[0]} main-3
    EOF
  end

  def test_exclude_long_branch_with_equal_commit_times
    jit_cmd("branch", "side", "topic^^")
    jit_cmd("checkout", "side")

    (1..10).each { |n| commit_file("side-#{n}", @branch_time) }

    jit_cmd("log", "--pretty=oneline", "side..topic", "^main")

    assert_stdout <<~EOF
      #{@topic[0]} topic-4
      #{@topic[1]} topic-3
    EOF
  end

  def test_log_last_few_commits_on_branch
    jit_cmd("log", "--pretty=oneline", "@~3..")

    assert_stdout <<~EOF
      #{@topic[0]} topic-4
      #{@topic[1]} topic-3
      #{@topic[2]} topic-2
    EOF
  end
end

class Command::TestLogChangingDifferentFiles < Command::TestLog
  def setup
    super

    commit_tree("first", "a/1.txt" => "1", "b/c/2.txt" => "2")
    commit_tree("second", "a/1.txt" => "10", "b/3.txt" => "3")
    commit_tree("third", "b/c/2.txt" => "4")

    @commits = ["@^^", "@^", "@"].map { |rev| load_commit(rev) }
  end

  def test_log_commits_that_change_file
    jit_cmd("log", "--pretty=oneline", "a/1.txt")

    assert_stdout <<~EOF
      #{@commits[1].oid} second
      #{@commits[0].oid} first
    EOF
  end

  def test_log_commits_that_change_directory
    jit_cmd("log", "--pretty=oneline", "b")

    assert_stdout <<~EOF
      #{@commits[2].oid} third
      #{@commits[1].oid} second
      #{@commits[0].oid} first
    EOF
  end

  def test_log_commits_that_change_nested_directory
    jit_cmd("log", "--pretty=oneline", "b/c")

    assert_stdout <<~EOF
      #{@commits[2].oid} third
      #{@commits[0].oid} first
    EOF
  end

  def test_log_commits_with_patches_for_selected_files
    jit_cmd("log", "--pretty=oneline", "--patch", "a/1.txt")

    assert_stdout <<~EOF
      #{@commits[1].oid} second
      diff --git a/a/1.txt b/a/1.txt
      index 56a6051..9a03714 100644
      --- a/a/1.txt
      +++ b/a/1.txt
      @@ -1,1 +1,1 @@
      -1
      +10
      #{@commits[0].oid} first
      diff --git a/a/1.txt b/a/1.txt
      new file mode 100644
      index 0000000..56a6051
      --- /dev/null
      +++ b/a/1.txt
      @@ -0,0 +1,1 @@
      +1
    EOF
  end
end

class Command::TestLogGraphOfCommits < Command::TestLog
  #   A   B   C   D   J   K
  #   o---o---o---o---o---o [master]
  #        \         /
  #         o---o---o---o [topic]
  #         E   F   G   H
  def setup
    super

    time = Time.now

    ("A".."B").each { |n| commit_tree(n, {"f.txt" => n}, time) }
    ("C".."D").each { |n| commit_tree(n, {"f.txt" => n}, time + 1) }

    jit_cmd("branch", "topic", "main~2")
    jit_cmd("checkout", "topic")

    ("E".."H").each { |n| commit_tree(n, {"g.txt" => n}, time + 2) }

    jit_cmd("checkout", "main")
    set_stdin("J")
    jit_cmd("merge", "topic^")

    commit_tree("K", {"f.txt" => "K"}, time + 3)

    @main = (0..5).map { |n| resolve_revision("main~#{n}") }
    @topic = (0..3).map { |n| resolve_revision("topic~#{n}") }
  end

  def test_log_concurrent_branches_leading_to_merge
    jit_cmd("log", "--pretty=oneline")

    assert_stdout <<~EOF
      #{@main[0]} K
      #{@main[1]} J
      #{@topic[1]} G
      #{@topic[2]} F
      #{@topic[3]} E
      #{@main[2]} D
      #{@main[3]} C
      #{@main[4]} B
      #{@main[5]} A
    EOF
  end

  def test_no_patches_for_merge_commits
    jit_cmd("log", "--pretty=oneline", "--patch", "topic..main", "^main^^^")

    assert_stdout <<~EOF
      #{@main[0]} K
      diff --git a/f.txt b/f.txt
      index 02358d2..449e49e 100644
      --- a/f.txt
      +++ b/f.txt
      @@ -1,1 +1,1 @@
      -D
      +K
      #{@main[1]} J
      #{@main[2]} D
      diff --git a/f.txt b/f.txt
      index 96d80cd..02358d2 100644
      --- a/f.txt
      +++ b/f.txt
      @@ -1,1 +1,1 @@
      -C
      +D
    EOF
  end

  def test_do_not_list_merges_with_treesame_parents_for_prune_paths
    jit_cmd("log", "--pretty=oneline", "g.txt")

    assert_stdout <<~EOF
      #{@topic[1]} G
      #{@topic[2]} F
      #{@topic[3]} E
    EOF
  end
end

require "minitest/autorun"

require_relative "../command_helper"

class Command::TestLog < Minitest::Test
  include CommandHelper

  def commit_file(message)
    write_file("file.txt", message)
    jit_cmd("add", ".")
    commit(message)
  end

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

class Command::TestLogCommitTree < Minitest::Test
  include CommandHelper

  def commit_file(message, time = nil)
    write_file("file.txt", message)
    jit_cmd("add", ".")
    commit(message, time)
  end

  def setup
    super

    #  m1  m2  m3
    #   o---o---o [main]
    #        \
    #         o---o---o---o [topic]
    #        t1  t2  t3  t4
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

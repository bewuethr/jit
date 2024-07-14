require_relative "base"
require_relative "shared/write_commit"
require_relative "../merge/inputs"
require_relative "../merge/resolve"
require_relative "../repository/sequencer"
require_relative "../rev_list"

module Command
  class CherryPick < Base
    include WriteCommit

    CONFLICT_NOTES = <<~EOF
      after resolving the conflicts, mark the corrected paths
      with 'jit add <paths>' or 'jit rm <paths>'
      and commit the result with 'jit commit'
    EOF

    def define_options
      @options[:mode] = :run

      @parser.on("--continue") { @options[:mode] = :continue }
      @parser.on("--abort") { @options[:mode] = :abort }
      @parser.on("--quit") { @options[:mode] = :quit }
    end

    def run
      case @options[:mode]
      when :continue then handle_continue
      when :abort then handle_abort
      when :quit then handle_quit
      end

      sequencer.start
      store_commit_sequence
      resume_sequencer
    end

    private def handle_continue
      repo.index.load
      write_cherry_pick_commit if pending_commit.in_progress?

      sequencer.load
      sequencer.drop_command
      resume_sequencer
    rescue Repository::PendingCommit::Error => error
      @stderr.puts "fatal: #{error.message}"
      exit 128
    end

    private def handle_abort
      pending_commit.clear(merge_type) if pending_commit.in_progress?
      repo.index.load_for_update

      begin
        sequencer.abort
      rescue => error
        @stderr.puts "warning: #{error.message}"
      end

      repo.index.write_updates
      exit 0
    end

    private def handle_quit
      pending_commit.clear(merge_type) if pending_commit.in_progress?
      sequencer.quit
      exit 0
    end

    private def sequencer = @sequencer ||= Repository::Sequencer.new(repo)

    private def store_commit_sequence
      commits = RevList.new(repo, @args.reverse, walk: false)
      commits.reverse_each { sequencer.pick(_1) }
    end

    private def resume_sequencer
      loop do
        break unless (commit = sequencer.next_command)
        pick(commit)
        sequencer.drop_command
      end

      sequencer.quit
      exit 0
    end

    private def pick(commit)
      inputs = pick_merge_inputs(commit)
      resolve_merge(inputs)
      fail_on_conflict(inputs, commit.message) if repo.index.conflict?

      picked = Database::Commit.new([inputs.left_oid], write_tree.oid,
        commit.author, current_author, commit.message)

      finish_commit(picked)
    end

    private def pick_merge_inputs(commit)
      short = repo.database.short_oid(commit.oid)

      left_name = Refs::HEAD
      left_oid = repo.refs.read_head
      right_name = "#{short}... #{commit.title_line.strip}"
      right_oid = commit.oid

      ::Merge::CherryPick.new(left_name, right_name,
        left_oid, right_oid, [commit.parent])
    end

    private def resolve_merge(inputs)
      repo.index.load_for_update
      ::Merge::Resolve.new(repo, inputs).execute
      repo.index.write_updates
    end

    private def fail_on_conflict(inputs, message)
      sequencer.dump

      pending_commit.start(inputs.right_oid, merge_type)

      edit_file(pending_commit.message_path) do |editor|
        editor.puts(message)
        editor.puts("")
        editor.note("Conflicts:")
        repo.index.conflict_paths.each { editor.note("\t#{_1}") }
        editor.close
      end

      @stderr.puts "error: could not apply #{inputs.right_name}"
      CONFLICT_NOTES.each_line { @stderr.puts "hint: #{_1}" }
      exit 1
    end

    private def merge_type = :cherry_pick

    private def finish_commit(commit)
      repo.database.store(commit)
      repo.refs.update_head(commit.oid)
      print_commit(commit)
    end
  end
end

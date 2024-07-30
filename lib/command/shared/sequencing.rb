require_relative "../../merge/resolve"
require_relative "../../repository/sequencer"

module Command
  module Sequencing
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

    private def sequencer = @sequencer ||= Repository::Sequencer.new(repo)

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

    private def finish_commit(commit)
      repo.database.store(commit)
      repo.refs.update_head(commit.oid)
      print_commit(commit)
    end

    private def handle_continue
      repo.index.load

      case pending_commit.merge_type
      when :cherry_pick then write_cherry_pick_commit
      when :revert then write_revert_commit
      end

      sequencer.load
      sequencer.drop_command
      resume_sequencer
    rescue Repository::PendingCommit::Error => error
      @stderr.puts "fatal: #{error.message}"
      exit 128
    end

    private def resume_sequencer
      loop do
        action, commit = sequencer.next_command
        break unless commit

        case action
        when :pick then pick(commit)
        when :revert then revert(commit)
        end
        sequencer.drop_command
      end

      sequencer.quit
      exit 0
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
  end
end

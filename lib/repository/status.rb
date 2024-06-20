require "sorted_set"

require_relative "inspector"
require_relative "../sorted_hash"

class Repository
  class Status
    attr_reader :changed, :index_changes, :conflicts, :workspace_changes,
      :untracked, :stats, :head_tree

    def initialize(repository)
      @repo = repository
      @stats = {}

      @inspector = Inspector.new(@repo)

      @changed = SortedSet.new
      @index_changes = SortedHash.new
      @conflicts = SortedHash.new
      @workspace_changes = SortedHash.new
      @untracked = SortedSet.new

      @head_tree = @repo.database.load_tree_list(@repo.refs.read_head)

      scan_workspace
      check_index_entries
      collect_deleted_head_files
    end

    private def record_change(path, set, type)
      @changed.add(path)
      set[path] = type
    end

    private def scan_workspace(prefix = nil)
      @repo.workspace.list_dir(prefix).each do |path, stat|
        if @repo.index.tracked?(path)
          @stats[path] = stat if stat.file?
          scan_workspace(path) if stat.directory?
        elsif @inspector.trackable_file?(path, stat)
          path += File::SEPARATOR if stat.directory?
          @untracked.add(path)
        end
      end
    end

    private def check_index_entries
      @repo.index.each_entry do |entry|
        if entry.stage == 0
          check_index_against_workspace(entry)
          check_index_against_head_tree(entry)
        else
          @changed.add(entry.path)
          @conflicts[entry.path] ||= []
          @conflicts[entry.path].push(entry.stage)
        end
      end
    end

    private def check_index_against_workspace(entry)
      stat = @stats[entry.path]
      status = @inspector.compare_index_to_workspace(entry, stat)

      if status
        record_change(entry.path, @workspace_changes, status)
      else
        @repo.index.update_entry_stat(entry, stat)
      end
    end

    private def check_index_against_head_tree(entry)
      item = @head_tree[entry.path]
      status = @inspector.compare_tree_to_index(item, entry)

      if status
        record_change(entry.path, @index_changes, status)
      end
    end

    private def collect_deleted_head_files
      @head_tree.each_key do |path|
        unless @repo.index.tracked_file?(path)
          record_change(path, @index_changes, :deleted)
        end
      end
    end
  end
end

require "sorted_set"

require_relative "base"

module Command
  class Status < Base
    SHORT_STATUS = {
      added: "A",
      deleted: "D",
      modified: "M"
    }

    def run
      @stats = {}
      @changed = SortedSet.new
      @index_changes = {}
      @workspace_changes = {}
      @untracked = SortedSet.new

      repo.index.load_for_update

      scan_workspace
      load_head_tree
      check_index_entries
      collect_deleted_head_files

      repo.index.write_updates

      print_results

      exit 0
    end

    def scan_workspace(prefix = nil)
      repo.workspace.list_dir(prefix).each do |path, stat|
        if repo.index.tracked?(path)
          @stats[path] = stat if stat.file?
          scan_workspace(path) if stat.directory?
        elsif trackable_file?(path, stat)
          path += File::SEPARATOR if stat.directory?
          @untracked.add(path)
        end
      end
    end

    def trackable_file?(path, stat)
      return false unless stat

      return !repo.index.tracked?(path) if stat.file?
      return false unless stat.directory?

      items = repo.workspace.list_dir(path)
      files = items.select { |_, item_stat| item_stat.file? }
      dirs = items.select { |_, item_stat| item_stat.directory? }

      [files, dirs].any? do |list|
        list.any? { |item_path, item_stat| trackable_file?(item_path, item_stat) }
      end
    end

    def load_head_tree
      @head_tree = {}

      head_oid = repo.refs.read_head
      return unless head_oid

      commit = repo.database.load(head_oid)
      read_tree(commit.tree)
    end

    def read_tree(tree_oid, pathname = Pathname.new(""))
      tree = repo.database.load(tree_oid)

      tree.entries.each do |name, entry|
        path = pathname.join(name)
        if entry.tree?
          read_tree(entry.oid, path)
        else
          @head_tree[path.to_s] = entry
        end
      end
    end

    def check_index_entries
      repo.index.each_entry do |entry|
        check_index_against_workspace(entry)
        check_index_against_head_tree(entry)
      end
    end

    def check_index_against_workspace(entry)
      stat = @stats[entry.path]

      unless stat
        return record_change(entry.path, @workspace_changes, :deleted)
      end

      unless entry.stat_match?(stat)
        return record_change(entry.path, @workspace_changes, :modified)
      end

      return if entry.times_match?(stat)

      data = repo.workspace.read_file(entry.path)
      blob = Database::Blob.new(data)
      oid = repo.database.hash_object(blob)

      if entry.oid == oid
        repo.index.update_entry_stat(entry, stat)
      else
        record_change(entry.path, @workspace_changes, :modified)
      end
    end

    def check_index_against_head_tree(entry)
      item = @head_tree[entry.path]

      if item
        unless entry.mode == item.mode && entry.oid == item.oid
          record_change(entry.path, @index_changes, :modified)
        end
      else
        record_change(entry.path, @index_changes, :added)
      end
    end

    def collect_deleted_head_files
      @head_tree.each_key do |path|
        unless repo.index.tracked_file?(path)
          record_change(path, @index_changes, :deleted)
        end
      end
    end

    def record_change(path, set, type)
      @changed.add(path)
      set[path] = type
    end

    def print_results
      @changed.each do |path|
        status = status_for(path)
        puts "#{status} #{path}"
      end

      @untracked.each do |path|
        puts "?? #{path}"
      end
    end

    def status_for(path)
      left = SHORT_STATUS.fetch(@index_changes[path], " ")
      right = SHORT_STATUS.fetch(@workspace_changes[path], " ")

      left + right
    end
  end
end

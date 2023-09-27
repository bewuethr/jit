require "pathname"
require_relative "../repository"

module Command
  class Add
    def run
      root_path = Pathname.new(Dir.getwd)
      repo = Repository.new(root_path.join(".git"))

      begin
        repo.index.load_for_update
      rescue Lockfile::LockDenied => error
        warn <<~EOF
          fatal: #{error.message}

          Another jit process seems to be running in this repository.
          Please make sure all processes are terminated, then try again.
          If it still fails, a jit process may have crashed in this
          repository earlier: remove the file manually to continue.
        EOF
        exit 128
      end

      begin
        paths = ARGV.flat_map do |path|
          path = Pathname.new(File.expand_path(path))
          repo.workspace.list_files(path)
        end
      rescue Workspace::MissingFile => error
        warn "fatal: #{error.message}"
        repo.index.release_lock
        exit 128
      end

      begin
        paths.each do |path|
          data = repo.workspace.read_file(path)
          stat = repo.workspace.stat_file(path)

          blob = Database::Blob.new(data)
          repo.database.store(blob)
          repo.index.add(path, blob.oid, stat)
        end
      rescue Workspace::NoPermission => error
        warn "error: #{error.message}"
        warn "fatal: adding files failed"
        repo.index.release_lock
        exit 128
      end

      repo.index.write_updates
      exit 0
    end
  end
end

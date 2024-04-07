require "fileutils"
require "pathname"

require "command"
require "repository"

module CommandHelper
  def setup = jit_cmd("init", repo_path.to_s)

  def teardown = FileUtils.rm_rf(repo_path)

  def repo_path = Pathname.new(File.expand_path("../test-repo", __FILE__))

  def repo
    @repository ||= Repository.new(repo_path.join(".git"))
  end

  def short_index_oid_for(path)
    index = Index.new(repo_path.join(".git", "index"))
    index.load
    entry = index.each_entry.find { |e| e.path == path }

    entry.oid[..6]
  end

  def short_workspace_oid_for(path)
    db = Database.new(repo_path.join(".git", "objects"))
    blob = Database::Blob.new(File.read(repo_path.join(path)))

    db.hash_object(blob)[..6]
  end

  def short_head_oid_for(path)
    entry = repo.status.head_tree.fetch(path)

    entry.oid[..6]
  end

  def write_file(name, contents)
    path = repo_path.join(name)
    FileUtils.mkdir_p(path.dirname)

    flags = File::RDWR | File::CREAT | File::TRUNC
    File.open(path, flags) { |file| file.write(contents) }
  end

  def make_executable(name) = File.chmod(0o755, repo_path.join(name))

  def make_unreadable(name) = File.chmod(0o200, repo_path.join(name))

  def mkdir(name) = FileUtils.mkdir_p(repo_path.join(name))

  def touch(name) = FileUtils.touch(repo_path.join(name))

  def delete(name) = FileUtils.rm_rf(repo_path.join(name))

  def set_env(key, value)
    @env ||= {}
    @env[key] = value
  end

  def set_stdin(string)
    @stdin = StringIO.new(string)
  end

  def jit_cmd(*argv)
    @env ||= {}
    @stdin ||= StringIO.new
    @stdout = StringIO.new
    @stderr = StringIO.new

    @cmd = Command.execute(repo_path.to_s, @env, argv, @stdin, @stdout, @stderr)
  end

  def commit(message, time = nil)
    set_env("GIT_AUTHOR_NAME", "A. U. Thor")
    set_env("GIT_AUTHOR_EMAIL", "author@example.com")
    set_stdin(message)
    Time.stub(:now, time || Time.now) { jit_cmd("commit") }
  end

  def assert_status(status) = assert_equal(status, @cmd.status)

  def assert_stdout(message) = assert_output(@stdout, message)

  def assert_stderr(message) = assert_output(@stderr, message)

  def assert_output(stream, message)
    stream.rewind
    assert_equal(message, stream.read)
  end

  def resolve_revision(expression) = Revision.new(repo, expression).resolve

  def assert_workspace(contents)
    files = {}

    repo.workspace.list_files.sort.each do |pathname|
      files[pathname.to_s] = repo.workspace.read_file(pathname)
    end

    assert_equal(contents, files)
  end

  def assert_noent(filename) = refute File.exist?(repo_path.join(filename))

  def load_commit(expression) = repo.database.load(resolve_revision(expression))

  def assert_executable(filename)
    assert(File.executable?(repo_path.join(filename)))
  end
end

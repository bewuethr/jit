require_relative "base"
require_relative "shared/fast_forward"
require_relative "shared/receive_objects"
require_relative "shared/remote_client"
require_relative "../remotes"
require_relative "../rev_list"

module Command
  class Fetch < Base
    include FastForward
    include ReceiveObjects
    include RemoteClient

    CAPABILITIES = ["ofs-delta"]
    UPLOAD_PACK = "git-upload-pack"

    def define_options
      @parser.on("-f", "--force") { @options[:force] = true }
      @parser.on("--upload-pack=<upload-pack>") { @options[:uploader] = _1 }
    end

    def run
      configure
      start_agent("fetch", @uploader, @fetch_url, CAPABILITIES)

      recv_references
      send_want_list
      send_have_list
      recv_objects
      update_remote_refs

      exit(@errors.empty? ? 0 : 1)
    end

    private def configure
      current_branch = repo.refs.current_ref.short_name
      branch_remote = repo.config.get(["branch", current_branch, "remote"])

      name = @args.fetch(0, branch_remote || Remotes::DEFAULT_REMOTE)
      remote = repo.remotes.get(name)

      @fetch_url = remote&.fetch_url || @args[0]
      @uploader = @options[:uploader] || remote&.uploader || UPLOAD_PACK
      @fetch_specs = (@args.size > 1) ? @args.drop(1) : remote&.fetch_specs
    end

    private def send_want_list
      @targets = Remotes::Refspec.expand(@fetch_specs, @remote_refs.keys)
      wanted = Set.new

      @local_refs = {}

      @targets.each do |target, (source, _)|
        local_oid = repo.refs.read_ref(target)
        remote_oid = @remote_refs[source]

        next if local_oid == remote_oid

        @local_refs[target] = local_oid
        wanted.add(remote_oid)
      end

      wanted.each { @conn.send_packet("want #{_1}") }
      @conn.send_packet(nil)

      exit 0 if wanted.empty?
    end

    private def send_have_list
      options = {all: true, missing: true}
      rev_list = ::RevList.new(repo, [], options)

      rev_list.each { @conn.send_packet("have #{_1.oid}") }
      @conn.send_packet("done")

      @conn.recv_until(Pack::SIGNATURE) {}
    end

    private def recv_objects
      unpack_limit = repo.config.get(["fetch", "unpackLimit"])
      recv_packed_objects(unpack_limit, Pack::SIGNATURE)
    end

    private def update_remote_refs
      @stderr.puts "From #{@fetch_url}"

      @errors = {}
      @local_refs.each { |target, oid| attempt_ref_update(target, oid) }
    end

    private def attempt_ref_update(target, old_oid)
      source, forced = @targets[target]

      new_oid = @remote_refs[source]
      ref_names = [source, target]
      ff_error = fast_forward_error(old_oid, new_oid)

      if @options[:force] || forced || ff_error.nil?
        repo.refs.update_ref(target, new_oid)
      else
        error = @errors[target] = ff_error
      end

      report_ref_update(ref_names, error, old_oid, new_oid, ff_error.nil?)
    end
  end
end

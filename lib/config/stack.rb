require "pathname"
require_relative "../config"

class Config
  class Stack
    GLOBAL_CONFIG = File.expand_path("~/.gitconfig")
    GLOBAL_CONFIG_XDG = File.expand_path("git/config",
      ENV["XDG_CONFIG_HOME"] || File.expand_path("~/.config"))
    SYSTEM_CONFIG = "/etc/gitconfig"

    def initialize(git_path)
      global_path = GLOBAL_CONFIG

      if File.exist?(GLOBAL_CONFIG_XDG) && !File.exist?(GLOBAL_CONFIG)
        global_path = GLOBAL_CONFIG_XDG
      end

      @configs = {
        local: Config.new(git_path.join("config")),
        global: Config.new(Pathname.new(global_path)),
        system: Config.new(Pathname.new(SYSTEM_CONFIG))
      }
    end

    def open = @configs.each_value(&:open)

    def get(key) = get_all(key).last

    def get_all(key)
      %i[system global local].flat_map do |name|
        @configs[name].open
        @configs[name].get_all(key)
      end
    end

    def file(name)
      if @configs.has_key?(name)
        @configs[name]
      else
        Config.new(Pathname.new(name))
      end
    end
  end
end

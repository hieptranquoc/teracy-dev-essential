require 'teracy-dev/config/configurator'
require 'teracy-dev/plugin'

module TeracyDevEssential
  module Config
    class HostManager < TeracyDev::Config::Configurator
      PLUGIN_NAME = "vagrant-hostmanager"

      def configure_common(settings, config)
        @plugins = settings['vagrant']['plugins'] ||= []

        # get all eth networks or enp0s in some system version
        # then get the latest ip
        # TODO(hoatle):
        # - don't use hard-code interface names: https://github.com/teracyhq-incubator/teracy-dev-essential/issues/21
        # - select explictly by users or implictly by public > private > internal: https://github.com/teracyhq-incubator/teracy-dev-essential/issues/20
        @host_ip_command = "ip addr | grep -e eth -e enp | grep inet | cut -d/ -f1 | tail -1 | sed -e 's/^[ \t]*//' | cut -d' ' -f2"

        configure_ip_display(config, settings)

        configure_hostmanager(config) if can_proceed?(@plugins, PLUGIN_NAME)
      end

      def configure_node(settings, config)
        return if !can_proceed?(@plugins, PLUGIN_NAME)
        # guest hosts fixer
        hostname = settings['vm']['hostname']
        return if hostname.nil? || hostname.empty?
        fix_hosts_command = "sed -i \"s/\\(127.0.1.1\\)\\(.*\\)#{hostname}\\(.*\\)/\\1\\3/\" /etc/hosts"
        @logger.debug("fix_hosts_command: #{fix_hosts_command}")

        options = {
          "inline" => fix_hosts_command
        }

        config.vm.provision "guest-hosts-fixer", type: "shell" do |provision|
          provision.set_options(options)
        end

      end

      private

      def configure_ip_display(config, settings)
        extension_lookup_path = TeracyDev::Util.extension_lookup_path(settings, 'teracy-dev-essential')

        config.vm.provision "shell",
          run: "always",
          args: [@host_ip_command],
          path: "#{extension_lookup_path}/teracy-dev-essential/provisioners/shell/ip_display.sh",
          name: "Display IP"
      end

      # check if plugin is installed and enabled to proceed
      def can_proceed?(plugins, plugin_name)
          plugins = plugins.select do |plugin|
            plugin['name'] == plugin_name
          end

          return false if plugins.length != 1
          plugin = plugins[0]

          if !TeracyDev::Plugin.installed?(plugin_name)
            @logger.debug("#{plugin_name} is not installed")
            return false
          end

          if plugin['enabled'] != true
            @logger.debug("#{plugin_name} is installed but not enabled so its settings is ignored")
            return false
          end
          return true
      end


      def configure_hostmanager(config)
        # conflict potential
        if TeracyDev::Plugin.installed?('vagrant-hostsupdater')
          @logger.warn('conflict potential, recommended: $ vagrant plugin uninstall vagrant-hostsupdater')
        end

        config.hostmanager.ip_resolver = proc do |vm, resolving_vm|
          read_ip_address(vm)
        end
      end

      def read_ip_address(machine)

        result  = ""

        @logger.debug("machine.name: #{machine.name}... ")

        begin
          # sudo is needed for ifconfig
          machine.communicate.sudo(@host_ip_command) do |type, data|
            result << data if type == :stdout
          end
          @logger.debug("machine.name: #{machine.name}... success")
        rescue
          result = "# NOT-UP"
          @logger.warn("machine.name: #{machine.name}... not running")
        end

        result.strip
      end
    end
  end
end

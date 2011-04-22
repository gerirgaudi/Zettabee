require 'rubygems'
require 'optparse'
require 'ostruct'
require 'date'
require 'yaml'

module ZettaBee

  class CLI

    ME = "zettabee"

    attr_reader :options

    def initialize(arguments)
      @arguments = arguments
      @options = OpenStruct.new

      # defaults
      @options.cfgfile = "/local/etc/zettabee/zettabee.cfg"
      @options.debug = false
      @options.nagios = false
      @options.verbose = false
      @action = nil
      @destination = nil
      @zfsrs = {}
    end

    def run
      if parsed_options? && arguments_valid?
        process_arguments
        process_command
      else
        output_usage(127)
      end
    end

    protected

      def parsed_options?
        opts = OptionParser.new
        opts.on('-V', '--version')                                                          { output_version ; exit 0 }
        opts.on('-h', '--help')                                                             { output_help }
        opts.on('-d', '--debug', "Debug mode" )                                             { @options.debug = true }
        opts.on('-v', '--verbose', "Verbose Mode")                                          { @options.verbose = true }
        opts.on('-n', '--nagios NAGIOSHOST', String, "Nagios Host for NSCA")                { |nagioshost| @options.nagios = nagioshost }
        opts.on('-c', '--config CONFIG', String, "Configuration file location")             { |cfgfile| @options.cfgfile = cfgfile }

        opts.parse!(@arguments) rescue return false

        process_options
        true

      end

      def arguments_valid?
        if @arguments.length < 1 or @arguments.length > 2
          $stderr.puts "Invalid number of arguments: #{@arguments}"
          return false
        end
        true
      end

      def process_options
        ZettaBee.nagios = @options.nagios if @options.nagios
        ZettaBee.debug = @options.debug if @options.debug
        ZettaBee.verbose = @options.verbose if @options.verbose
        ZettaBee.cfgfile = @options.cfgfile if @options.cfgfile
      end

      def process_arguments
        case @arguments.length
          when 2 then
            @action = @arguments[0]
            @destination = @arguments[1].split(':')[-1]
          when 1 then
            @action = @arguments[0]
            @destination = nil
          else
            return false
        end

        # verify action is valid
      end

      def process_command

        @zfsrs = ZettaBee.readconfig()

        if @destination then
          zfsr = nil
          if @destination.split('/').length > 1
            zfsr = @zfsrs[@destination]
          elsif @destination.split('/').length == 1
            @zfsrs.each_key do |key|
              if key.split('/')[-1] == @destination
                zfsr = @zfsrs[key]
              end
            end
          end
          if zfsr.nil?
            abort "error: invalid destination: #{@destination}"
          else
            zfsr.execute(@action.to_sym)
            Utilities.send_nsca(zfsr.dhost,"#{ME}:#{zfsr.port}",0,"#{zfsr.shost}:#{zfsr.szfs} #{@action.to_s.upcase} #{zfsr.dhost}:#{zfsr.dzfs}",@options.nagios) if @options.nagios
          end
        else
          @zfsrs.each_value do |zfsr|
            zfsr.execute(@action.to_sym)
            Utilities.send_nsca(zfsr.dhost,"#{ME}:#{zfsr.port}",0,"#{zfsr.shost}:#{zfsr.szfs} #{@action.to_s.upcase} #{zfsr.dhost}:#{zfsr.dzfs}",@options.nagios) if @options.nagios
          end
        end
      end

      def output_usage(exit_status)

        puts "Options:\n"

        @options.marshal_dump.each do |name, val|
          puts "  #{name} = #{val}"
        end
        exit exit_status
      end
  end

  class Utilities
    def Utilities.send_nsca(hostname,svc_descr,rt,svc_output,nagioshost="nagios",send_nsca_cfg="/usr/local/etc/nsca/send_nsca.cfg")
      pstatus = popen4("/usr/local/bin/send_nsca -H #{nagioshost} -c #{send_nsca_cfg}") do |pid, pstdin, pstdout, pstderr|
        pstdin.write("#{hostname}\t#{svc_descr}\t#{rt}\t#{svc_output}\n")
        pstdin.close
      end
    end
  end
end
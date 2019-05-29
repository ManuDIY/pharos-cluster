# frozen_string_literal: true

require 'pry' if Gem.loaded_specs.key?('pry')
require 'sentry-raven'

Raven.configure do |config|
  config.logger.level = Logger::FATAL
  config.dsn = 'https://82e24db6400645f8b07262ba356d05c5:03d7c6502a48493c9354a0820f0546f0@sentry.io/1470318'
end

module Pharos
  class Command < Clamp::Command
    include Pharos::Logging

    # @param [Array<Symbol>] a list of CommandOption module names in snake_case, for example :filtered_hosts
    def self.options(*option_names)
      option_names.each do |option_name|
        module_name = option_name.to_s.gsub(/\?$/, '').extend(Pharos::CoreExt::StringCasing).camelcase.to_sym
        send(:include, Pharos::CommandOptions.const_get(module_name))
      end
    end

    def parse(*_arguments)
      result = super
      Pharos::CoreExt::Colorize.disable! unless color?
      Pharos::Logging.debug! if debug?
      result
    end

    def run(*_args)
      super
    rescue Clamp::HelpWanted, Clamp::ExecutionError, Clamp::UsageError
      raise
    rescue Errno::EPIPE => e
      raise if debug?

      warn "ERROR: #{e.class.name} : #{e.message}" if $stdout.tty?
      exit 141
    rescue Pharos::ConfigError => e
      warn "==> #{e}"
      exit 11
    rescue StandardError => e
      Raven.capture_exception(e)
      raise if Pharos::Logging.debug?

      signal_error "#{e.class.name} : #{e.message}"
    end

    option '--[no-]color', :flag, "colorize output", default: $stdout.tty?

    option ['-v', '--version'], :flag, "print #{File.basename($PROGRAM_NAME)} version" do
      puts "#{File.basename($PROGRAM_NAME)} #{Pharos.version}"
      exit 0
    end

    option ['-d', '--debug'], :flag, "enable debug output", environment_variable: "DEBUG"

    if Object.const_defined?(:Pry)
      # rubocop:disable Lint/Debugger
      module Console
        def execute
          binding.pry
        end
      end
      # rubocop:enable Lint/Debugger

      option ['--console'], :flag, "start console instead of execute", hidden: true do
        extend(Console)
      end
    end

    def prompt
      @prompt ||= TTY::Prompt.new(enable_color: color?)
    end

    def rouge
      @rouge ||= Rouge::Formatters::Terminal256.new(Rouge::Themes::Github.new)
    end

    def tty?
      $stdin.tty?
    end

    def stdin_eof?
      $stdin.eof?
    end

    # @param secs [Integer]
    # @return [String]
    def humanize_duration(secs)
      [[60, :second], [60, :minute], [24, :hour], [1000, :day]].map{ |count, name|
        next unless secs.positive?

        secs, n = secs.divmod(count).map(&:to_i)
        next if n.zero?

        "#{n} #{name}#{'s' unless n == 1}"
      }.compact.reverse.join(' ')
    end
  end
end

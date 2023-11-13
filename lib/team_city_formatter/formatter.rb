require_relative 'logger'

require 'cucumber/formatter/ast_lookup'
require 'cucumber/formatter/backtrace_filter'
require 'cucumber/formatter/console_counts'

module TeamCityFormatter
  class Formatter
    attr_reader :config, :options
    private :config, :options
    attr_reader :current_feature_uri, :current_feature_name, :previous_test_case, :retry_attempt, :retry_count, :errors
    private :current_feature_uri, :current_feature_name, :previous_test_case, :retry_attempt, :retry_count, :errors

    def initialize(config)
      @config = config
      @options = config.to_hash
      @logger = Logger.new(config.out_stream)
      @retry_count = config.retry_attempts

      @counts = Cucumber::Formatter::ConsoleCounts.new(config)

      @errors = []
      @current_feature_uri = nil
      @current_feature_name = nil
      @previous_test_case = nil
      @retryAttempt = 0

      bind_events(config)

      @ast_lookup = Cucumber::Formatter::AstLookup.new(config)
    end

    def bind_events(config)
      config.on_event :test_case_started, &method(:on_test_case_started)
      config.on_event :test_case_finished, &method(:on_test_case_finished)
      config.on_event :test_step_finished, &method(:on_test_step_finished)
      config.on_event :test_run_finished, &method(:on_test_run_finished)
    end

    def on_test_case_started(event)
      if !same_feature_as_previous_test_case?(event.test_case.location)
        @logger.test_suite_finished(@current_feature_name) if @current_feature_name
        @current_feature_uri = event.test_case.location.file
        @current_feature_name = gherkin_document.feature.name
        @logger.test_suite_started(@current_feature_name)
      end
      @logger.test_started(event.test_case.name)
    end

    def on_test_case_finished(event)
      if event.test_case != @previous_test_case
        @previous_test_case = event.test_case
        @retry_attempt = 0
        @errors = []
      else
        @retry_attempt = retry_attempt + 1
      end

      exception_to_be_printed = find_exception_to_be_printed(event.result)

      @errors << exception_to_be_printed if exception_to_be_printed

      @logger.test_failed_with_exceptions(event.test_case.name, errors) if exception_to_be_printed && retry_attempt >= retry_count

      @logger.test_finished(event.test_case.name)
    end

    def on_test_step_finished(event)
      @logger.render_output("#{event.result.to_s} #{event.test_step}") unless event.result.is_a? Cucumber::Core::Test::Result::Skipped
    end

    def on_test_run_finished(event)
      @logger.test_suite_finished(@current_feature_name) if @current_feature_name
      @logger.render_output(@counts.to_s)
    end

    private

    def same_feature_as_previous_test_case?(location)
      location.file == current_feature_uri
    end

    def find_exception_to_be_printed(result)
      return nil if result.ok?(options[:strict])
      result = result.with_filtered_backtrace(Cucumber::Formatter::BacktraceFilter)
      exception = result.failed? ? result.exception : result
      exception
    end

    def gherkin_document
      @ast_lookup.gherkin_document(current_feature_uri)
    end
  end
end

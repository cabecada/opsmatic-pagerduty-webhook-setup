#!/usr/bin/env ruby
#
# PagerDutySetup -- a script to quickly check and setup Opsmatic webhooks on your PagerDuty Services
#
# You will need the following information:
#
# Opsmatic Organization Integration Token (Found in the Opsmatic dashboard under Org Settings | Team)
# PagerDuty Subdomain (your custom URL subdomain for PagerDuty)
# PagerDuty API Access Key (Found in PagerDuty dashboard, under the API Access menu)
#
# Run an initial report with:
# ruby pager_duty_setup.rb -s my-pagerduty-subdomain --pdkey my-pagerduty-api-key --okey my-opsmatic-token
#
# To add your Opsmatic webhook to all of your services, run:
# ruby pager_duty_setup.rb -s my-pagerduty-subdomain --pdkey my-pagerduty-api-key --okey my-opsmatic-token --addhooks
#
# Tested with all supported Rubies: 1.9.3, 2.0.0, 2.1.x

require 'net/http'
require 'uri'
require 'ostruct'
require 'optparse'
require 'json'

class PagerDutySetup
  PAGER_DUTY_API_BASE_URL           = "https://SUBDOMAIN.pagerduty.com/api/v1".freeze
  PAGER_DUTY_SERVICES_API_ENDPOINT  = "services"
  PAGER_DUTY_WEBHOOKS_API_ENDPOINT  = "webhooks"
  PAGER_DUTY_WEB_SERVICE_TYPE       = "service"
  OPSMATIC_WEBHOOK_BASE_URL         = "https://api.opsmatic.com/webhooks/events/pagerduty?token=".freeze
  OPSMATIC_WEBHOOK_BASE_URL_REGEXP  = /^\s*https:\/\/api.opsmatic.com\/webhooks\/events\/pagerduty\?token\=/i
  TIMEOUT_SECONDS                   = 30 # don't run too long on HTTP requests
  PAGER_DUTY_MAX_PAGE_SIZE          = 100 # documented max page size for PagerDuty

  @@options = OpenStruct.new

  attr_accessor :subdomain, :limit, :pdkey, :okey

  def initialize(run_time)
    @run_time = run_time
    @timeout = @@options.timeout || TIMEOUT_SECONDS
    @subdomain = @@options.subdomain
    @pdkey= @@options.pdkey
    @okey= @@options.okey
    @limit = PAGER_DUTY_MAX_PAGE_SIZE
  end

  def self.warn(p)
    log p, true
  end

  def self.log(p, force = false)
    if (@@options && @@options.verbose) || force
      $stdout.print p.to_s + "\n"
      $stdout.flush
    end
  end

  def warn(p)
    PagerDutySetup.warn(p)
  end

  def log(p, force = false)
    PagerDutySetup.log(p,force)
  end

  def query_string(params)
    params.is_a?(Array) ? params.flatten.compact.join('&') : nil
  end

  def pager_duty_pagination_parameters(page)
    page ? ["offset=#{page * limit}", "limit=#{limit}"] : []
  end

  def pagerduty_endpoint_url(endpoint, params = {})
    base_url = [PAGER_DUTY_API_BASE_URL.gsub(/SUBDOMAIN/, subdomain), endpoint].join('/')
    pagerduty_params = []
    pagerduty_params << pager_duty_pagination_parameters(params[:page])
    [base_url, query_string(pagerduty_params)].compact.join('?')
  end

  def restful_pager_duty_resource(url, data=nil, method=:get)
    uri           = URI.parse(url)
    http          = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl  = true

    case method
    when :get
      request = Net::HTTP::Get.new(uri.request_uri)
    when :post
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = JSON.generate(data) if data
    else
      raise "Unsupported HTTP method"
    end

    request['Content-type']   = 'application/json'
    request['Authorization']  = "Token token=#{pdkey}"

    response = http.request(request)
    response.value
    response.body
  end

  def pager_duty_resources(url)
    parsed_results = nil
    Timeout::timeout(@timeout) do
      if raw_result = restful_pager_duty_resource(url)
        parsed_results = JSON.parse(raw_result)
      end
    end
    parsed_results
  end

  def pager_duty_resource(url, data, method)
    parsed_results = nil
    Timeout::timeout(@timeout) do
      if raw_result = restful_pager_duty_resource(url, data, method)
        parsed_results = JSON.parse(raw_result)
      end
    end
    parsed_results
  end

  def get_resources(endpoint, key=nil)
    elements  = []
    total     = nil
    page      = 0
    key       ||= endpoint
    begin
      if page_of_elements = pager_duty_resources(pagerduty_endpoint_url(endpoint, :page => page))
        total ||= page_of_elements['total']
        elements += page_of_elements[key]
        page += 1
      else
        break
      end
    end while elements.length < total
    elements
  end

  def create_resource(endpoint, data)
    pager_duty_resource(pagerduty_endpoint_url(endpoint), data, :post)
  end

  # Create a simple hash with service info we need for rest of operation
  def combine_services_and_webhooks(services, webhooks)
    combined = []
    services.each do |service|
      fields = {  :id           => service['id'],
                  :name         => service['name'],
                  :service_url  => service['service_url']
                }
      fields[:webhooks] = webhooks.select do |webhook|
        webhook_object = webhook['webhook_object']
        (( webhook_object['id'] == service['id']) &&
          webhook_object['type'] == PAGER_DUTY_WEB_SERVICE_TYPE &&
          webhook['url'] =~ OPSMATIC_WEBHOOK_BASE_URL_REGEXP)
      end
      combined << fields
    end
    combined
  end

  def webhook_installed?(service)
    service[:webhooks] && !service[:webhooks].empty?
  end

  def webhook_status(service)
    webhook_installed?(service) ? 'installed' : 'not installed'
  end

  def report_service_web_hook_status(services)
    log "Status of PagerDuty Services", true
    services.each do |service|
      log "#{service[:id]}\t#{service[:name]}\t#{webhook_status(service)}", true
    end
  end

  def webhook_object(service_id)
    { 'name'            =>  'Opsmatic Webhook',
      'url'             =>  "#{OPSMATIC_WEBHOOK_BASE_URL}#{okey}",
      'webhook_object'  =>  { 'type'  => PAGER_DUTY_WEB_SERVICE_TYPE,
                              'id'    => service_id
                            }
    }
  end

  def add_webhook_to_services(services)
    log "Adding webhooks"
    count = 0
    services.each do |service|
      unless webhook_installed?(service)
        webhook = webhook_object(service[:id])
        results = create_resource(PAGER_DUTY_WEBHOOKS_API_ENDPOINT, webhook)
        count += 1
      end
    end
    warn "Created #{count} webhook(s)" if count > 0
    warn "No webhooks created" if count == 0
  end

  def process
    log "Starting Service Scan"

    services = get_resources(PAGER_DUTY_SERVICES_API_ENDPOINT)
    log "Found #{services.length} services"

    webhooks = get_resources(PAGER_DUTY_WEBHOOKS_API_ENDPOINT)
    log "Found #{webhooks.length} webhooks"

    combined_services = combine_services_and_webhooks(services, webhooks)
    report_service_web_hook_status(combined_services)
    add_webhook_to_services(combined_services) if @@options.addhooks
  end

  def self.main
    @@options.verbose   = false
    @@options.addhooks  = false
    @@options.pdkey     = nil
    @@options.okey      = nil
    @@options.domain    = nil
    @@options.timeout   = TIMEOUT_SECONDS

    # parse command-line options
    optsparse = OptionParser.new do |opts|
      opts.on('-v', '--verbose') { @@options.verbose = true }
      opts.on('-a', '--addhooks') { @@options.addhooks = true }
      opts.on('-s', '--subdomain SUBDOMAIN') {|subdomain| @@options.subdomain = subdomain}
      opts.on('-p', '--pdkey PAGERDUTY_API_KEY') {|key| @@options.pdkey = key}
      opts.on('-o', '--okey OPSMATIC_API_KEY') {|key| @@options.okey = key }
      opts.on('-t', '--timeout [timeout]') {|timeout| @@options.timeout = timeout.to_i }
      opts.on('-h', '--help') do
          puts opts
          exit
      end
    end
    begin
      optsparse.parse!(ARGV)
      required_options = [:subdomain, :pdkey, :okey]
      missing_options = required_options.select{ |param| @@options.send(param).nil? }
      unless missing_options.empty?
        puts "Missing options: #{missing_options.join(', ')}"
        puts optsparse
        exit
      end
    rescue OptionParser::InvalidOption, OptionParser::MissingArgument
      puts $!.to_s
      puts optparse
      exit
    end

    begin
      run_time = Time.now
      log "Starting PagerDutySetup at #{run_time}"
      PagerDutySetup.new( run_time ).process
      log "Stopping PagerDutySetup at #{Time.now}"
    rescue Exception => e
      warn "ERROR: #{e.inspect + e.backtrace.to_s}"
    end
  end
end

PagerDutySetup.main

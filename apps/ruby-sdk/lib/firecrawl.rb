# frozen_string_literal: true

require 'httparty'
require 'json'
require 'websocket-client-simple'

module Firecrawl
  class Error < StandardError; end

  class SearchParams
    attr_accessor :query, :limit, :tbs, :filter, :lang, :country, :location, :origin, :timeout, :scrapeOptions

    def initialize(query:, limit: 5, tbs: nil, filter: nil, lang: "en", country: "us", location: nil, origin: "api", timeout: 60000, scrapeOptions: nil)
      @query = query
      @limit = limit
      @tbs = tbs
      @filter = filter
      @lang = lang
      @country = country
      @location = location
      @origin = origin
      @timeout = timeout
      @scrapeOptions = scrapeOptions
    end
  end

  class FirecrawlApp
    class SearchResponse
      attr_accessor :success, :data, :warning, :error

      def initialize(success:, data:, warning: nil, error: nil)
        @success = success
        @data = data
        @warning = warning
        @error = error
      end
    end

    class ExtractParams
      attr_accessor :prompt, :schema, :system_prompt, :allow_external_links, :enable_web_search, :enableWebSearch

      def initialize(prompt: nil, schema: nil, system_prompt: nil, allow_external_links: false, enable_web_search: false, enableWebSearch: false)
        @prompt = prompt
        @schema = schema
        @system_prompt = system_prompt
        @allow_external_links = allow_external_links
        @enable_web_search = enable_web_search
        @enableWebSearch = enableWebSearch
      end
    end

    class ExtractResponse
      attr_accessor :success, :data, :error

      def initialize(success:, data: nil, error: nil)
        @success = success
        @data = data
        @error = error
      end
    end

    def initialize(api_key: nil, api_url: nil)
      @api_key = api_key || ENV['FIRECRAWL_API_KEY']
      @api_url = api_url || ENV['FIRECRAWL_API_URL'] || 'https://api.firecrawl.dev'

      if @api_url.include?('api.firecrawl.dev') && @api_key.nil?
        warn "No API key provided for cloud service"
        raise ArgumentError, 'No API key provided'
      end

      puts "Initialized FirecrawlApp with API URL: #{@api_url}"
    end

    def scrape_url(url, params: nil)
      headers = prepare_headers
      scrape_params = {'url' => url}

      if params
        extract = params[:extract]
        if extract
          if extract[:schema] && extract[:schema].respond_to?(:schema)
            extract[:schema] = extract[:schema].schema()
          end
          scrape_params['extract'] = extract
        end

        params.each do |key, value|
          scrape_params[key] = value unless key == :extract
        end

        json = params[:jsonOptions]
        if json
          if json[:schema] && json[:schema].respond_to?(:schema)
            json[:schema] = json[:schema].schema()
          end
          scrape_params['jsonOptions'] = json
        end

        params.each do |key, value|
          scrape_params[key] = value unless key == :jsonOptions
        end
      end

      endpoint = '/v1/scrape'

      response = HTTParty.post(
        "#{@api_url}#{endpoint}",
        headers: headers,
        body: scrape_params.to_json
      )

      if response.code == 200
        begin
          response_body = JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end

        if response_body['success'] && response_body['data']
          return response_body['data']
        elsif response_body['error']
          raise Error, "Failed to scrape URL. Error: #{response_body['error']}"
        else
          raise Error, "Failed to scrape URL. Error: #{response_body}"
        end
      else
        handle_error(response, 'scrape URL')
      end
    end

    def search(query, params: nil)
      if params.nil?
        params = {}
      end

      search_params = SearchParams.new(query: query, **params)

      response = HTTParty.post(
        "#{@api_url}/v1/search",
        headers: {"Authorization" => "Bearer #{@api_key}"},
        body: search_params.instance_variables.each_with_object({}) { |var, hash| hash[var.to_s.delete("@")] = search_params.instance_variable_get(var) }.to_json
      )

      if response.code != 200
        raise Error, "Request failed with status code #{response.code}"
      end

      begin
        return JSON.parse(response.body)
      rescue JSON::ParserError
        raise Error, 'Failed to parse Firecrawl response as JSON.'
      end
    end

    def crawl_url(url, params: nil, poll_interval: 2, idempotency_key: nil)
      endpoint = '/v1/crawl'
      headers = prepare_headers(idempotency_key: idempotency_key)
      json_data = {'url' => url}
      if params
        json_data.merge!(params)
      end
      response = post_request(
        "#{@api_url}#{endpoint}",
        json_data,
        headers
      )
      if response.code == 200
        begin
          id = JSON.parse(response.body).fetch('id')
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
        return monitor_job_status(id, headers, poll_interval)
      else
        handle_error(response, 'start crawl job')
      end
    end

    def async_crawl_url(url, params: nil, idempotency_key: nil)
      endpoint = '/v1/crawl'
      headers = prepare_headers(idempotency_key: idempotency_key)
      json_data = {'url' => url}
      if params
        json_data.merge!(params)
      end
      response = post_request(
        "#{@api_url}#{endpoint}",
        json_data,
        headers
      )
      if response.code == 200
        begin
          return JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
      else
        handle_error(response, 'start crawl job')
      end
    end

    def check_crawl_status(id)
      endpoint = "/v1/crawl/#{id}"

      headers = prepare_headers
      response = get_request("#{@api_url}#{endpoint}", headers)
      if response.code == 200
        begin
          status_data = JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
        if status_data['status'] == 'completed'
          if status_data['data']
            data = status_data['data']
            while status_data['next']
              if data.length == 0
                break
              end
              next_url = status_data['next']
              if !next_url
                warn "Expected 'next' URL is missing."
                break
              end
              begin
                status_response = get_request(next_url, headers)
                if status_response.code != 200
                  puts "Failed to fetch next page: #{status_response.code}"
                  break
                end
                next_data = JSON.parse(status_response.body)
              rescue JSON::ParserError
                raise Error, 'Failed to parse Firecrawl response as JSON.'
              end
              data.concat(next_data['data'] || [])
              status_data = next_data
            end
            status_data['data'] = data
          end
        end

        response = {
          'status' => status_data['status'],
          'total' => status_data['total'],
          'completed' => status_data['completed'],
          'creditsUsed' => status_data['creditsUsed'],
          'expiresAt' => status_data['expiresAt'],
          'data' => status_data['data']
        }

        if status_data['error']
          response['error'] = status_data['error']
        end

        if status_data['next']
          response['next'] = status_data['next']
        end

        return {
          'success' => status_data['error'] ? false : true,
          **response
        }
      else
        handle_error(response, 'check crawl status')
      end
    end

    def check_crawl_errors(id)
      headers = prepare_headers
      response = get_request("#{@api_url}/v1/crawl/#{id}/errors", headers)
      if response.code == 200
        begin
          return JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
      else
        handle_error(response, "check crawl errors")
      end
    end

    def cancel_crawl(id)
      headers = prepare_headers
      response = delete_request("#{@api_url}/v1/crawl/#{id}", headers)
      if response.code == 200
        begin
          return JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
      else
        handle_error(response, "cancel crawl job")
      end
    end

    def crawl_url_and_watch(url, params: nil, idempotency_key: nil)
      crawl_response = async_crawl_url(url, params: params, idempotency_key: idempotency_key)
      if crawl_response['success'] && crawl_response['id']
        return CrawlWatcher.new(crawl_response['id'], self)
      else
        raise Error, "Crawl job failed to start"
      end
    end

    def map_url(url, params: nil)
      endpoint = '/v1/map'
      headers = prepare_headers

      json_data = {'url' => url}
      if params
        json_data.merge!(params)
      end

      response = HTTParty.post(
        "#{@api_url}#{endpoint}",
        headers: headers,
        body: json_data.to_json
      )
      if response.code == 200
        begin
          response_body = JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
        if response_body['success'] && response_body['links']
          return response_body
        elsif response_body['error']
          raise Error, "Failed to map URL. Error: #{response_body['error']}"
        else
          raise Error, "Failed to map URL. Error: #{response_body}"
        end
      else
        handle_error(response, 'map')
      end
    end

    def batch_scrape_urls(urls, params: nil, poll_interval: 2, idempotency_key: nil)
      endpoint = f'/v1/batch/scrape'
      headers = prepare_headers(idempotency_key: idempotency_key)
      json_data = {'urls' => urls}
      if params
        json_data.merge!(params)
      end
      response = post_request(
        "#{@api_url}#{endpoint}",
        json_data,
        headers
      )
      if response.code == 200
        begin
          id = JSON.parse(response.body).fetch('id')
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
        return monitor_job_status(id, headers, poll_interval)

      else
        handle_error(response, 'start batch scrape job')
      end
    end

    def async_batch_scrape_urls(urls, params: nil, idempotency_key: nil)
      endpoint = '/v1/batch/scrape'
      headers = prepare_headers(idempotency_key: idempotency_key)
      json_data = {'urls' => urls}
      if params
        json_data.merge!(params)
      end
      response = post_request(
        "#{@api_url}#{endpoint}",
        json_data,
        headers
      )
      if response.code == 200
        begin
          return JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
      else
        handle_error(response, 'start batch scrape job')
      end
    end

    def batch_scrape_urls_and_watch(urls, params: nil, idempotency_key: nil)
      crawl_response = async_batch_scrape_urls(urls, params: params, idempotency_key: idempotency_key)
      if crawl_response['success'] && crawl_response['id']
        return CrawlWatcher.new(crawl_response['id'], self)
      else
        raise Error, "Batch scrape job failed to start"
      end
    end

    def check_batch_scrape_status(id)
      endpoint = f'/v1/batch/scrape/{id}'

      headers = prepare_headers
      response = get_request("#{@api_url}#{endpoint}", headers)
      if response.code == 200
        begin
          status_data = JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
        if status_data['status'] == 'completed'
          if status_data['data']
            data = status_data['data']
            while status_data['next']
              if data.length == 0
                break
              end
              next_url = status_data['next']
              if !next_url
                warn "Expected 'next' URL is missing."
                break
              end
              begin
                status_response = get_request(next_url, headers)
                if status_response.code != 200
                  puts "Failed to fetch next page: #{status_response.code}"
                  break
                end
                next_data = JSON.parse(status_response.body)
              rescue JSON::ParserError
                raise Error, 'Failed to parse Firecrawl response as JSON.'
              end
              data.concat(next_data['data'] || [])
              status_data = next_data
            end
            status_data['data'] = data
          end
        end

        response = {
          'status' => status_data['status'],
          'total' => status_data['total'],
          'completed' => status_data['completed'],
          'creditsUsed' => status_data['creditsUsed'],
          'expiresAt' => status_data['expiresAt'],
          'data' => status_data['data']
        }

        if status_data['error']
          response['error'] = status_data['error']
        end

        if status_data['next']
          response['next'] = status_data['next']
        end

        return {
          'success' => status_data['error'] ? false : true,
          **response
        }
      else
        handle_error(response, 'check batch scrape status')
      end
    end

    def check_batch_scrape_errors(id)
      headers = prepare_headers
      response = get_request("#{@api_url}/v1/batch/scrape/#{id}/errors", headers)
      if response.code == 200
        begin
          return JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, 'Failed to parse Firecrawl response as JSON.'
        end
      else
        handle_error(response, "check batch scrape errors")
      end
    end

    def extract(params)
      headers = prepare_headers

      if params.nil? || (params[:prompt].nil? && params[:schema].nil?)
        raise ArgumentError, "Either prompt or schema is required"
      end

      urls = params[:urls]

      schema = params[:schema]
      if schema
        if schema.respond_to?(:model_json_schema)
          schema = schema.model_json_schema()
        end
      end

      request_data = {
        **params,
        'allowExternalLinks' => params[:allow_external_links] || params[:allowExternalLinks] || false,
        'enableWebSearch' => params[:enable_web_search] || params[:enableWebSearch] || false,
        'schema' => schema,
        'origin' => 'api-sdk',
        'urls' => urls
      }

      begin
        response = post_request(
          "#{@api_url}/v1/extract",
          request_data,
          headers
        )
        if response.code == 200
          begin
            data = JSON.parse(response.body)
          rescue JSON::ParserError
            raise Error, 'Failed to parse Firecrawl response as JSON.'
          end
          if data['success']
            job_id = data['id']
            if job_id.nil?
              raise Error, 'Job ID not returned from extract request.'
            end

            while true
              status_response = get_request(
                "#{@api_url}/v1/extract/#{job_id}",
                headers
              )
              if status_response.code == 200
                begin
                  status_data = JSON.parse(status_response.body)
                rescue JSON::ParserError
                  raise Error, 'Failed to parse Firecrawl response as JSON.'
                end
                if status_data['status'] == 'completed'
                  if status_data['success']
                    return status_data
                  else
                    raise Error, "Failed to extract. Error: #{status_data['error']}"
                  end
                elsif ['failed', 'cancelled'].include?(status_data['status'])
                  raise Error, "Extract job #{status_data['status']}. Error: #{status_data['error']}"
                end
              else
                handle_error(status_response, "extract-status")
              end

              sleep(2)  # Polling interval
            end
          else
            raise Error, "Failed to extract. Error: #{data['error']}"
          end
        else
          handle_error(response, "extract")
        end
      rescue Error => e
        raise e
      rescue => e
        raise Error, "#{e.message}", 500
      end

      return {'success' => false, 'error' => "Internal server error."}
    end

    def get_extract_status(job_id)
      headers = prepare_headers
      begin
        response = get_request("#{@api_url}/v1/extract/#{job_id}", headers)
        if response.code == 200
          begin
            return JSON.parse(response.body)
          rescue JSON::ParserError
            raise Error, 'Failed to parse Firecrawl response as JSON.'
          end
        else
          handle_error(response, "get extract status")
        end
      rescue => e
        raise Error, "#{e.message}", 500
      end
    end

    def async_extract(params, idempotency_key: nil)
      headers = prepare_headers(idempotency_key: idempotency_key)

      if params.nil? || (params[:prompt].nil? && params[:schema].nil?)
        raise ArgumentError, "Either prompt or schema is required"
      end

      urls = params[:urls]

      schema = params[:schema]
      if schema
        if schema.respond_to?(:model_json_schema)
          schema = schema.model_json_schema()
        end
      end

      request_data = {
        **params,
        'allowExternalLinks' => params[:allow_external_links] || params[:allowExternalLinks] || false,
        'enableWebSearch' => params[:enable_web_search] || params[:enableWebSearch] || false,
        'schema' => schema,
        'origin' => 'api-sdk',
        'urls' => urls
      }

      begin
        response = post_request(
          "#{@api_url}/v1/extract",
          request_data,
          headers
        )
        if response.code == 200
          begin
            return JSON.parse(response.body)
          rescue JSON::ParserError
            raise Error, 'Failed to parse Firecrawl response as JSON.'
          end
        else
          handle_error(response, "async extract")
        end
      rescue => e
        raise Error, "#{e.message}", 500
      end
    end

    private

    def prepare_headers(idempotency_key: nil)
      headers = {'Content-Type' => 'application/json', 'Authorization' => "Bearer #{@api_key}"}
      headers['x-idempotency-key'] = idempotency_key if idempotency_key
      headers
    end

    def post_request(url, data, headers, retries: 3, backoff_factor: 0.5)
      attempt = 0
      begin
        attempt += 1
        response = HTTParty.post(url, headers: headers, body: data.to_json)
        if response.code >= 500
          raise Error, "Server error: #{response.code}"
        end
        response
      rescue Error => e
        if attempt < retries
          sleep(backoff_factor * (2 ** attempt))
          retry
        else
          raise e, "Request failed after multiple retries: #{e.message}"
        end
      rescue => e
        raise Error, "Request failed: #{e.message}"
      end
    end

    def get_request(url, headers, retries: 3, backoff_factor: 0.5)
      attempt = 0
      begin
        attempt += 1
        response = HTTParty.get(url, headers: headers)
        if response.code >= 500
          raise Error, "Server error: #{response.code}"
        end
        response
      rescue Error => e
        if attempt < retries
          sleep(backoff_factor * (2 ** attempt))
          retry
        else
          raise e, "Request failed after multiple retries: #{e.message}"
        end
      rescue => e
        raise Error, "Request failed: #{e.message}"
      end
    end

    def delete_request(url, headers, retries: 3, backoff_factor: 0.5)
      attempt = 0
      begin
        attempt += 1
        response = HTTParty.delete(url, headers: headers)
        if response.code >= 500
          raise Error, "Server error: #{response.code}"
        end
        response
      rescue Error => e
        if attempt < retries
          sleep(backoff_factor * (2 ** attempt))
          retry
        else
          raise e, "Request failed after multiple retries: #{e.message}"
        end
      rescue => e
        raise Error, "Request failed: #{e.message}"
      end
    end

    def monitor_job_status(id, headers, poll_interval)
      while true
        response = get_request("#{@api_url}/v1/crawl/#{id}", headers)
        if response.code == 200
          begin
            status_data = JSON.parse(response.body)
          rescue JSON::ParserError
            raise Error, 'Failed to parse Firecrawl response as JSON.'
          end
          if status_data['status'] == 'completed'
            return status_data
          elsif ['failed', 'cancelled'].include?(status_data['status'])
            raise Error, "Crawl job #{status_data['status']}. Error: #{status_data['error']}"
          end
        else
          handle_error(response, "crawl-status")
        end

        sleep(poll_interval)
      end
    end

    def handle_error(response, action)
      begin
        error_body = JSON.parse(response.body)
        message = error_body['error'] || "Unknown error"
      rescue JSON::ParserError
        message = response.body
      end
      raise Error, "Failed to #{action}. Status: #{response.code}, Message: #{message}"
    end
  end

  class CrawlWatcher
    def initialize(id, app)
      @id = id
      @app = app
      @data = []
      @status = "scraping"
      @ws_url = app.api_url.gsub('http', 'ws') + "/v1/crawl/#{@id}"
      @event_handlers = {
        'done' => [],
        'error' => [],
        'document' => []
      }
    end

    def connect
      ws = WebSocket::Client::Simple.connect @ws_url

      ws.on :message do |msg|
        handle_message(msg.data)
      end

      ws.on :open do
        puts "Connected to #{@ws_url}"
      end

      ws.on :close do |e|
        puts "Connection closed: #{e.inspect}"
      end

      ws.on :error do |e|
        puts "Error: #{e.inspect}"
        dispatch_event('error', e)
      end

      @ws = ws
    end

    def add_event_listener(event_type, handler)
      if @event_handlers.key?(event_type)
        @event_handlers[event_type] << handler
      end
    end

    def dispatch_event(event_type, detail)
      if @event_handlers.key?(event_type)
        @event_handlers[event_type].each { |handler| handler.call(detail) }
      end
    end

    private

    def handle_message(msg)
      begin
        message = JSON.parse(msg)
        type = message['type']
        data = message['data']

        case type
        when 'document'
          @data << data
          dispatch_event('document', data)
        when 'done'
          @status = 'done'
          dispatch_event('done', @data)
          @ws.close
        when 'error'
          @status = 'error'
          dispatch_event('error', data)
          @ws.close
        else
          puts "Unknown message type: #{type}"
        end
      rescue JSON::ParserError => e
        puts "Error parsing JSON: #{e.message}"
      rescue => e
        puts "Error handling message: #{e.message}"
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'firecrawl'

# Get API key from environment variable
api_key = ENV['FIRECRAWL_API_KEY']

if api_key.nil?
  puts "Please set FIRECRAWL_API_KEY environment variable"
  exit 1
end

# Initialize the Firecrawl app
firecrawl = Firecrawl::FirecrawlApp.new(api_key: api_key)

# Get the URL from the command line arguments, or use a default if none is provided
url = ARGV[0] || 'https://www.example.com'

# Example usage of scrape_url
begin
  data = firecrawl.scrape_url(url)
  puts "Scrape data: #{data}"
rescue Firecrawl::Error => e
  puts "Error scraping URL: #{e.message}"
end

# Example usage of search
begin
  search_results = firecrawl.search('test')
  puts "Search results: #{search_results}"
rescue Firecrawl::Error => e
  puts "Error searching: #{e.message}"
end

# Example usage of crawl_url
begin
  crawl_result = firecrawl.crawl_url(url)
  puts "Crawl result: #{crawl_result}"
rescue Firecrawl::Error => e
  puts "Error crawling URL: #{e.message}"
end

# Example usage of async_crawl_url
begin
  async_crawl_result = firecrawl.async_crawl_url(url)
  puts "Async crawl result: #{async_crawl_result}"
rescue Firecrawl::Error => e
  puts "Error async crawling URL: #{e.message}"
end

# Example usage of check_crawl_status
begin
  # Replace with a valid crawl ID
  crawl_id = 'your_crawl_id'
  crawl_status = firecrawl.check_crawl_status(crawl_id)
  puts "Crawl status: #{crawl_status}"
rescue Firecrawl::Error => e
  puts "Error checking crawl status: #{e.message}"
end

# Example usage of check_crawl_errors
begin
  # Replace with a valid crawl ID
  crawl_id = 'your_crawl_id'
  crawl_errors = firecrawl.check_crawl_errors(crawl_id)
  puts "Crawl errors: #{crawl_errors}"
rescue Firecrawl::Error => e
  puts "Error checking crawl errors: #{e.message}"
end

# Example usage of cancel_crawl
begin
  # Replace with a valid crawl ID
  crawl_id = 'your_crawl_id'
  cancel_result = firecrawl.cancel_crawl(crawl_id)
  puts "Cancel result: #{cancel_result}"
rescue Firecrawl::Error => e
  puts "Error cancelling crawl: #{e.message}"
end

# Example usage of map_url
begin
  map_result = firecrawl.map_url(url)
  puts "Map result: #{map_result}"
rescue Firecrawl::Error => e
  puts "Error mapping URL: #{e.message}"
end

# Example usage of extract
begin
  # Replace with a valid URL and schema
  params = {
    urls: [url],
    prompt: "Extract the title and main content of the page."
  }
  extract_result = firecrawl.extract(params)
  puts "Extract result: #{extract_result.inspect}"
rescue Firecrawl::Error => e
  puts "Error extracting: #{e.message}"
end

# Example usage of async_extract
begin
  # Replace with a valid URL and schema
  params = {
    urls: [url],
    prompt: "Extract the title and main content of the page."
  }
  async_extract_result = firecrawl.async_extract(params)
  puts "Async extract result: #{async_extract_result.inspect}"
rescue Firecrawl::Error => e
  puts "Error async extracting: #{e.message}"
end

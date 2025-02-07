# Firecrawl Ruby SDK

This SDK provides a Ruby interface for interacting with the Firecrawl API.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'firecrawl'
```

And then execute:
```bash
bundle install
```

Or install it yourself as:
```bash
gem install firecrawl
```

## Usage

```ruby
require 'firecrawl'

# Initialize the Firecrawl app
firecrawl = Firecrawl::FirecrawlApp.new(api_key: 'YOUR_API_KEY')

# Example usage of scrape_url
data = firecrawl.scrape_url('https://www.example.com')
puts data

# Example usage of search
search_results = firecrawl.search('test')
puts search_results
```

## Methods

*   `scrape_url(url, params: nil)`
*   `search(query, params: nil)`
*   `crawl_url(url, params: nil, poll_interval: 2, idempotency_key: nil)`
*   `async_crawl_url(url, params: nil, idempotency_key: nil)`
*   `check_crawl_status(id)`
*   `check_crawl_errors(id)`
*   `cancel_crawl(id)`
*   `crawl_url_and_watch(url, params: nil, idempotency_key: nil)`
*   `map_url(url, params: nil)`
*   `batch_scrape_urls(urls, params: nil, poll_interval: 2, idempotency_key: nil)`
*   `async_batch_scrape_urls(urls, params: nil, idempotency_key: nil)`
*   `batch_scrape_urls_and_watch(urls, params: nil, idempotency_key: nil)`
*   `check_batch_scrape_status(id)`
*   `check_batch_scrape_errors(id)`
*   `extract(urls, params: nil)`
*   `get_extract_status(job_id)`
*   `async_extract(urls, params: nil, idempotency_key: nil)`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/firecrawl/firecrawl.

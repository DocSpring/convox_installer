# Convox Installer

A Ruby gem that makes it easier to build a Convox installation script. The main purpose of this gem is to make it easier to set up on-premise installations of your app for enterprise users.

This gem provides a DSL so that you can write a script that walks your users through setting up Convox and getting your app and running, setting up S3 buckets, etc.

## Requirements

- MacOS
- Convox v3 CLI

_Please let us know if you need to run this script on Linux. Linux support should not be too difficult to implement, but unfortunately we probably won't be able to support Windows._

### Requires Convox >= 3

This version of `convox_installer` is only designed to work with Convox 3 and later. You can run `convox version` to check your version. Please install the Convox v3 CLI by following the instructions here: https://docs.convox.com/getting-started/introduction/

_If you want to set up a Convox v2 rack (deprecated), the last version of `convox_installer` that supports the v2 CLI is `1.0.9`. (Take a look at [the `convox2` branch](https://github.com/DocSpring/convox_installer/tree/convox2).)_

## USE AT YOUR OWN RISK! THIS CODE IS PROVIDED WITHOUT ANY WARRANTIES OR GUARANTEES

We have successfully set up a number of test and production deployments using this gem. Everything seems to work very well. The library also facilitates idempotency and crash-resistance, so you can easily re-run your installation script if something goes wrong. However, if anything goes wrong, then you can end up with a large AWS bill if you're not careful. If anything crashes then make sure you double-check everything in your AWS account and shut down any leftover resources. **USE THIS SOFTWARE AT YOUR OWN RISK.**

## Features

- Idempotent. If this script crashes, you can restart it and it will pick up
  where it left off. Every step looks up the existing state, and only makes a change
  if things are not yet set up (or out of sync).
- Ensures that the `convox` and `terraform` CLI tools are installed
- Wraps the `convox` CLI and parses JSON output from API calls
- Add a Docker Repository (e.g. ECR registry)
- Set up an S3 bucket with an optional CORS policy
- Set up an RDS database (Postgres)
- Set up an Elasticache cluster (Redis)

## Introduction

[Convox](https://convox.com/) is an awesome open source PaaS, which is like Heroku for your own AWS account. [`convox/rack`](https://github.com/convox/rack) is completely open source and free to use, but you can also sign up for a free or paid account to use the hosted service on convox.com.

`convox_installer` is a Ruby gem that makes it much easier to build an installation script for `convox/rack` (the open source PaaS). The Convox CLI is awesome, but it's missing a nice way to script a full deployment. I originally wrote a bash script that made API calls and used [`jq`](https://stedolan.github.io/jq/) and `sed`, but this was very error-prone and it did not have good cross-platform support.

I've written this installation script in Ruby, which provides very good cross-platform support, and also allows me to write tests.

## Usage

Create a new Ruby file (e.g. `install.rb`), and use `bundler/inline` to install and require the `convox_installer` gem. Your install script should start like this:

```ruby
#!/usr/bin/env ruby
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'convox_installer', '3.0.0'
end

require "convox_installer"
include ConvoxInstaller
```

Including the `include ConvoxInstaller` gives you some Ruby methods that you can call to construct an installation workflow. See the "`ConvoxInstaller` DSL" section below.

You should create a new git repo for your own installation script, and then use the provided classes and methods to build your own installation workflow. You must also include a `convox.yml` (or a `convox.example.yml`).

You can see a complete example in [`examples/full_installation.rb`](./examples/full_installation.rb).

## Config

Config is loaded from ENV vars, or from saved JSON data at
`./.installer_config.json`. The script will save all of the user's responses into `./.installer_config.json` (in the current directory).

## Customize the Config Prompts

You can set your own config prompts in your own installation script, by setting a `@prompts` instance variable. You can extend the default config prompts like this:

```ruby
@prompts = ConvoxInstaller::Config::DEFAULT_PROMPTS + [
  {
    section: "Docker Authentication",
    info: "You should have received authentication details for the Docker Registry\n" \
    "via email. If not, please contact support@example.com",
  },
  {
    key: :docker_registry_url,
    title: "Docker Registry URL",
    value: "1234567890.dkr.ecr.us-east-1.amazonaws.com",
  },
  {
    key: :docker_registry_username,
    title: "Docker Registry Username",
  },
  {
    key: :docker_registry_password,
    title: "Docker Registry Password",
  }
]
```

## Prompt API:

The `@prompts` variable must be an array of hashes. There are two kinds of hashes:

#### Section Heading

Shows a heading and optional details.

```ruby
{
  section: "The heading for this config section",
  info: "Description about this config section"
}
```

#### Config Prompt

- A config prompt with a default value:

```ruby
{
  key: :config_key_name,
  title: "Title to show in the user prompt / config summary",
  prompt: "Question to show the user",
  default: "default value",
}
```

- Set a value from a `Proc`, and don't prompt the user:

```ruby
  {
    key: :config_key_name,
    title: "Title to show in the config summary",
    value: -> () { "string-with-random-suffix-#{SecureRandom.hex(4)}" },
  }
```

- Set a value, and hide this setting from the user (even in the summary):

```ruby
  {
    key: :config_key_name,
    value: "Config Value",
    hidden: true,
  },
```

## `ConvoxInstaller` DSL

#### `ensure_requirements!`

Makes sure that the `convox` and `terraform` CLI tools are installed on this system. If not, shows installation instructions and exits.

#### `prompt_for_config`

Loads config from ENV vars, or from saved config at `./.installer_config.json`.
If any config settings are missing, it prompts the user for input. Finally, it shows a summary of the config, and asks the user if they want to proceed with the installation. If the user enters `y` (or `yes`), the `prompt_for_config` method completes. If they enter `n` (or `no`), we loop over every setting and let them press "enter" to keep the current value, or provide a new value to correct any mistakes.

#### `install_convox`

- **Required Config:** `aws_region`, `aws_access_key_id`, `aws_secret_access_key`,
  `stack_name`, `instance_type`

Runs `convox rack install ...`. Has some validations to ensure that all required settings are present.

#### `validate_convox_rack_and_write_current!`

Ensures that the local machine contains a directory for the rack's terraform config, and sets the current rack for Convox CLI commands.

#### `validate_convox_rack_api!`

Makes an API request (`convox api get /system`) to get the rack details, and makes sure that everything is correct.

#### `convox_rack_data`

Returns a Ruby hash with all convox rack data.

#### `create_convox_app!`

- **Required Config:** `convox_app_name`

Checks if the app already exists. If not, calls `convox apps create ... --wait` to create a new app. Then waits for the app to be ready. (Avoids an occasional race condition.)

#### `set_default_app_for_directory!`

Writes the app name into `./.convox/app` (in the current directory.) The `convox` CLI reads this file, so you don't need to specify the `--app` flag for future commands.

#### `add_s3_bucket`

Adds an S3 bucket to your Terraform config.

- **Required Config:** `s3_bucket_name`

NOTE: This method just writes a new Terraform configuration file. You must run `apply_terraform_update!` to apply the changes and create the S3 bucket.

Creates an S3 bucket from the `:s3_bucket_name` config setting. This is not a default setting, so you can add something like this to your custom `@prompts`:

```ruby
  {
    key: :s3_bucket_name,
    title: "S3 Bucket for uploads",
    value: -> () { "yourapp-uploads-#{SecureRandom.hex(4)}" },
  }
```

The `:value` `Proc` will generate a bucket name with a random suffix. (Avoids conflicts when you are setting up multiple deployments for your app.)

You can also set a CORS policy for your S3 bucket. (`:s3_bucket_name`)
We set the `cors_rule` option for the `aws_s3_bucket` resource in the Terraform configuration. Example:

```
   cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["https://s3-website-test.hashicorp.com"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
```

See: https://registry.terraform.io/providers/hashicorp/aws/3.33.0/docs/resources/s3_bucket#using-cors

_Note: If the `:s3_bucket_cors_rule` setting is not provided, then it is skipped._

Here's how we set up a CORS policy in our own `install.rb` script:

```ruby
xxxxc = <<-TERRAFORM
  cors_rule {
    allowed_headers = ["Authorization", "cache-control", "x-requested-with"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
TERRAFORM

@prompts = [
  {
    key: :s3_bucket_cors_rule,
    value: S3_BUCKET_CORS_RULE,
    hidden: true,
  }
]
```

#### `add_rds_database`

Adds an RDS database to your Terraform config.

- **Required Config:**
  - `database_username`
  - `database_password`
- **Optional Config:**
  - `database_allocated_storage` _(default: 30)_
  - `database_engine` _(default: 'postgres')_
  - `database_engine_version` _(default: '14.8')_
  - `database_instance_class` _(default: 'db.t3.small')_
  - `database_multi_az` _(default: true)_

#### `add_elasticache_cluster`

Adds an Elasticache cluster to your Terraform config.

- **Optional Config:**
  - `engine` _(default: 'redis')_
  - `engine_version` _(default: '6.x')_
  - `node_type` _(default: 'cache.t3.medium')_
  - `num_cache_nodes` _(default: 1)_
  - `port` _(default: 6379)_

#### `apply_terraform_update!`

Runs `terraform apply -auto-approve` to apply any changes to your Terraform configuration (add new resources, etc.)

#### `rds_details`

Returns information about the created RDS database resource.

```ruby
{
  postgres_url: "Full URL for the RDS database (including auth)",
}
```

#### `elasticache_details`

Returns information about the created RDS database resource.

```ruby
{
  redis_url: "Full URL for the Redis cluster",
}
```

#### `s3_bucket_details`

- **Required Config:** `s3_bucket_name`

Get the S3 bucket details for `s3_bucket_name`. Parses the URL and returns a hash:

```ruby
{
  access_key_id: "AWS Access Key ID",
  secret_access_key: "AWS Secret Access Key",
  name: "Full S3 Bucket Name (includes the rack/app)",
}
```

I use these S3 bucket details to set env variables for my app. (`convox env set ...`)

#### `add_docker_registry!`

- **Required Config:** `docker_registry_url`, `docker_registry_username`, `docker_registry_password`

Checks the list of registries to see if `docker_registry_url` has already been added. If not, runs `convox registries add ...` to add a new Docker registry (e.g. Docker Hub, ECR).

#### `default_service_domain_name`

- **Required Config:** `convox_app_name`
- **Optional Config:** `default_service`

Finds the default `*.convox.cloud` URL for the web service. (You can visit this URL in the browser to access your app.)

Example: `web.docspring.dc6bae48c2e36366.convox.cloud`

You can override the default service name in your config (e.g. `web`):

```ruby
@prompts = [
  # ...
  {
    key: :default_service,
    title: "Default Convox Service (for domain)",
    value: "web",
    hidden: true,
  }
]
```

> (This hidden setting isn't visible to the user.)

#### `run_convox_command!(cmd)`

Runs a `convox` CLI command, and shows all output in the terminal. Crashes the script with an error if the `convox` command has a non-zero exit code.

If you want to run `convox env set MYVAR=value`, then you would call:

```ruby
run_convox_command! 'env set MYVAR=value'
```

## License

[MIT](./LICENSE)

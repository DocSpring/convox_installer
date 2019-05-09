# Convox Installer

A Ruby gem that makes it easier to build a Convox installation script. This is like Chef/Ansible/Terraform for your initial Convox setup.

## WARNING: This is alpha software, and still rough around the edges.

I put this together in a few days, so it doesn't have great test coverage. However, I've set up a number of test and production deployments using my installation script, and everything seems to work quite well.

## Features

* Idempotent. If this script crashes, you can restart it and it will pick up
  where it left off. Every step looks up the existing state, and only makes a change
  if things are not yet set up (or out of sync).
* Ensures that the `convox` and `aws` CLI tools are installed
* Wraps the `convox` CLI and parses JSON output from API calls
* Add an Docker Repository (e.g. ECR registry)
* Set up an S3 bucket with a CORS policy

## Introduction

[Convox](https://convox.com/) is an awesome open source PaaS, which is like Heroku for your own AWS account. [`convox/rack`](https://github.com/convox/rack) is completely open source and free to use, but you can also sign up for a free or paid account to use the hosted service on convox.com.

`convox_installer` is a Ruby gem that makes it much easier to build an installation script for `convox/rack` (the open source PaaS). The Convox CLI is awesome, but it's missing a nice way to script a full deployment. I originally wrote a bash script that made API calls and used [`jq`](https://stedolan.github.io/jq/) and `sed`, but this was very error-prone and it did not have good cross-platform support.

I've rewritten this installation script in Ruby, which provides very good cross-platform support, and also allows me to write tests.

## Usage

Create a new Ruby file (e.g. `install.rb`), and use `bundler/inline` to install and require the `convox_installer` gem. Your install script should start like this:

```ruby
#!/usr/bin/env ruby
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'convox_installer'
end

require "convox_installer"
include ConvoxInstaller
```

Including the `include ConvoxInstaller` gives you some Ruby methods that you can call to construct an installation workflow. See the "`ConvoxInstaller` DSL" section below.

You should create a new git repo for your own installation script, and then use the provided classes and methods to build your own installation workflow. You must also include a `convox.yml` (or a `convox.example.yml`).

You can see a complete example in [`examples/full_installation.rb`](./examples/full_installation.rb).


## Config

Config is loaded from ENV vars, or from saved JSON data at
`~/.convox/installer_config`. The script will save all of the user's responses into `~/.convox/installer_config`.

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

* A config prompt with a default value:

```ruby
{
  key: :config_key_name,
  title: "Title to show in the user prompt / config summary",
  prompt: "Question to show the user",
  default: "default value",
}
```

* Set a value from a `Proc`, and don't prompt the user:

```ruby
  {
    key: :config_key_name,
    title: "Title to show in the config summary",
    value: -> () { "string-with-random-suffix-#{SecureRandom.hex(4)}" },
  }
```

* Set a value, and hide this setting from the user (even in the summary):

```ruby
  {
    key: :config_key_name,
    value: "Config Value",
    hidden: true,
  },
```


## `ConvoxInstaller` DSL

#### `ensure_requirements!`

Makes sure that the `convox` and `aws` CLI tools are installed on this system. If not, shows installation instructions and exits.

#### `prompt_for_config`

Loads config from ENV vars, or from saved config at `~/.convox/installer_config`.
If any config settings are missing, it prompts the user for input. Finally, it shows a summary of the config, and asks the user if they want to proceed with the installation. If the user enters `y` (or `yes`), the `prompt_for_config` method completes. If they enter `n` (or `no`), we loop over every setting and let them press "enter" to keep the current value, or provide a new value to correct any mistakes.

#### `backup_convox_host_and_rack`

If there are any existing files at `~/.convox/host` or `~/.convox/rack`, this method moves these to `~/.convox/host.bak` and `~/.convox/rack.bak`.

#### `install_convox`

* **Required Config:** `aws_region`, `aws_access_key_id`, `aws_secret_access_key`,
  `stack_name`, `instance_type`

Runs `convox rack install ...`. Has some validations to ensure that all required settings are present.

#### `validate_convox_auth_and_set_host!`

After running `install_convox`, call this method to ensure that the the `~/.convox/auth` file has been updated with the correct details (checks the rack name and AWS region.) Then it sets the rack host in `~/.convox/host` (if not already set.)

#### `validate_convox_rack!`

Calls `convox api get /system` to get the Rack details, then makes sure that everything is correct.

#### `convox_rack_data`

Returns a Ruby hash with all convox rack data.

#### `create_convox_app!`

* **Required Config:** `convox_app_name`

Checks if the app already exists. If not, calls `convox apps create ... --wait` to create a new app. Then waits for the app to be ready. (Avoids an occasional race condition.)


#### `set_default_app_for_directory!`

Writes the app name into `./.convox/app` (in the current directory.) The `convox` CLI reads this file, so you don't need to specify the `--app` flag for future commands.


#### `create_s3_bucket!`

* **Required Config:** `s3_bucket_name`

Creates an S3 bucket from the `:s3_bucket_name` config setting. This is not a default setting, so you can add something like this to your custom `@prompts`:

```ruby
  {
    key: :s3_bucket_name,
    title: "S3 Bucket for uploads",
    value: -> () { "yourapp-uploads-#{SecureRandom.hex(4)}" },
  }
```

The `:value` `Proc` will generate a bucket name with a random suffix. (Avoids conflicts when you are setting up multiple deployments for your app.)

`create_s3_bucket!` will also call `set_s3_bucket_cors_policy` automatically, so you don't need to call this manually.

#### `set_s3_bucket_cors_policy`

* **Required Config:** `s3_bucket_name`

Set up a CORS policy for your S3 bucket. (`:s3_bucket_name`)

*Note: If the `:s3_bucket_cors_policy` setting is not provided, then this method does nothing.*

You should set `:s3_bucket_cors_policy` to a JSON string. Here's how I set this up in my own `install.rb` script:

```ruby
S3_BUCKET_CORS_POLICY = <<-JSON
{
  "CORSRules": [
    {
      "AllowedOrigins": ["*"],
      "AllowedHeaders": ["Authorization", "cache-control", "x-requested-with"],
      "AllowedMethods": ["PUT", "POST", "GET"],
      "MaxAgeSeconds": 3000
    }
  ]
}
JSON

@prompts = [
  {
    key: :s3_bucket_cors_policy,
    value: S3_BUCKET_CORS_POLICY,
    hidden: true,
  }
]
```


#### `s3_bucket_details`

* **Required Config:** `s3_bucket_name`

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

* **Required Config:** `docker_registry_url`, `docker_registry_username`, `docker_registry_password`

Checks the list of registries to see if `docker_registry_url` has already been added. If not, runs `convox registries add ...` to add a new Docker registry (e.g. Docker Hub, ECR).

#### `default_service_domain_name`

* **Required Config:** `convox_app_name`, `default_service`

Parses the rack router ELB name and region, and returns the default `convox.site` domain for your default service. (You can visit this URL in the browser to access your app.)

Example: `myapp-web.rackname-Route-ABCDFE123456-123456789.us-west-2.convox.site`

Set a default service in your config prompts (e.g. `web`):

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

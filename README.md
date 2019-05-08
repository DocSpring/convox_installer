# Convox Installer

[Convox](https://convox.com/) is an awesome open source PaaS, which is like Heroku for your own AWS account. [`convox/rack`](https://github.com/convox/rack) is completely open source and free to use, but you can also sign up for a free or paid account to use the hosted service on convox.com.

`convox_installer` is a Ruby gem that makes it much easier to build an installation script for `convox/rack` (the open source PaaS). The Convox CLI is awesome, but it's missing a nice way to script a full deployment. I originally wrote a bash script that made API calls and used [`jq`](https://stedolan.github.io/jq/) and `sed`, but this was very error-prone and it did not have good cross-platform support.

I've rewritten this installation script in Ruby, which provides very good cross-platform support, and also allows me to write tests.

# Usage

You should create a new git repo for your own installation script, and then use the provided classes and methods to build your own installation workflow. You must also include a `convox.yml`.

You can see an example in [`examples/full_installation.rb`](./examples/full_installation.rb).
(This Ruby file uses `bundler/inline`, so it will download and install the `convox_installer` gem before running the script.)

# Config

Config is loaded from ENV vars, or from saved JSON data at
`~/.convox/installer_config`.

### License

[MIT](./LICENSE)

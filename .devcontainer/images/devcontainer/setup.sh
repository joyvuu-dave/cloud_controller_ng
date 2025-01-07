#!/bin/bash
set -Eeuo pipefail
# shellcheck disable=SC2064
trap "pkill -P $$" EXIT

setupAptPackages () {
  # CF CLI is not available for aarch64 :(
  if [[ $(uname -m) == aarch64 ]]; then
    PACKAGES="postgresql-client postgresql-client-common mariadb-client ruby-dev"
  else
    PACKAGES="cf8-cli postgresql-client postgresql-client-common mariadb-client ruby-dev"
  fi

  wget -q -O - https://packages.cloudfoundry.org/debian/cli.cloudfoundry.org.key | sudo apt-key add -
  echo "deb https://packages.cloudfoundry.org/debian stable main" | sudo tee /etc/apt/sources.list.d/cloudfoundry-cli.list
  sudo apt-get update
  export DEBIAN_FRONTEND="noninteractive" && echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections
  sudo apt-get install -o Dpkg::Options::="--force-overwrite" $PACKAGES -y
}

setupRuby () {
  rbenv install $(cat /tmp/.ruby-version)
  rbenv global $(cat /tmp/.ruby-version)
}

setupRubyGems () {
  gem install cf-uaac
}

setupCredhubCli () {
  set -x
  wget "https://github.com/cloudfoundry/credhub-cli/releases/download/2.9.41/credhub-linux-amd64-2.9.41.tg" -O /tmp/credhub.tar.gz
  cd /tmp
  sudo tar -xzf /tmp/credhub.tar.gz && sudo rm -f /tmp/credhub.tar.gz && sudo mv /tmp/credhub /usr/bin
}

setupYqCli () {
  sudo wget "https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_linux_amd64" -O /usr/bin/yq
  sudo chmod +x /usr/bin/yq
}

echo """
export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1
""" > ~/.bashrc

setupAptPackages
setupRuby
setupRubyGems
setupCredhubCli
setupYqCli

# Setup User Permissions
sudo groupadd docker
sudo usermod -aG docker "vscode"

trap "" EXIT

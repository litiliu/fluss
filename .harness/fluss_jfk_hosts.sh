#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Shared host lists for the jfk Fluss cluster operational harness.

set -euo pipefail

JFK_COORDINATOR_HOSTS=(
  udjf2srb010.webex.com
  udjf2srb016.webex.com
)

JFK_TABLET_HOSTS=(
  udjf2srb023.webex.com
  udjf2srb056.webex.com
  udjf2srb043.webex.com
  udjf2srb052.webex.com
  udjf2srb036.webex.com
)

fluss_jfk_each_host() {
  local host

  for host in "${JFK_COORDINATOR_HOSTS[@]}"; do
    printf 'coordinator %s\n' "${host}"
  done

  for host in "${JFK_TABLET_HOSTS[@]}"; do
    printf 'tablet %s\n' "${host}"
  done
}

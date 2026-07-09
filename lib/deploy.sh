#!/usr/bin/env bash
# Maintainer deployer for proveo CLI

deploy_target() {
  local target="$1"
  local tag="$2"
  local publish_image
  publish_image="$(reg_image "$target"):$tag"

  ensure_image_available "$publish_image" "$target"
  print_info "Pushing $publish_image"
  docker push "$publish_image"
  print_success "Deployed $publish_image"
}

#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

@test "bun and pnpm release-age exclusion lists are identical" {
  repo_root="$BATS_TEST_DIRNAME/.."
  bun_list="$BATS_TEST_TMPDIR/bun"
  pnpm_list="$BATS_TEST_TMPDIR/pnpm"

  yq -p toml -o yaml '.install.minimumReleaseAgeExcludes[]' "$repo_root/dot_config/dot_bunfig.toml" | sort >"$bun_list"
  yq '.minimumReleaseAgeExclude[]' "$repo_root/dot_config/pnpm/config.yaml" | sort >"$pnpm_list"

  [[ -s "$bun_list" ]]
  run diff -u --label bunfig.toml --label pnpm/config.yaml "$bun_list" "$pnpm_list"
  [[ "$status" -eq 0 ]] || {
    printf '%s\n' "$output"
    false
  }
}

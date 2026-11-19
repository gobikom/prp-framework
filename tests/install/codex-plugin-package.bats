#!/usr/bin/env bats

setup() {
    framework=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
    market_root="$BATS_TEST_TMPDIR/marketplace"
    packager="$framework/scripts/package-codex-plugin.py"
    manifest="$framework/adapters/claude-code-plugin/plugins/prp-core/.codex-plugin/plugin.json"
    version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$manifest")
    plugin="$market_root/.agents/plugins/packages/prp-core/$version"
    catalog="$market_root/.agents/plugins/marketplace.json"
}

@test "Codex marketplace has a native catalog and byte-identical regular skills" {
    run python3 "$packager" --output "$market_root"
    [ "$status" -eq 0 ]
    [ -f "$catalog" ]
    cmp "$manifest" "$plugin/.codex-plugin/plugin.json"
    python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); p=data["plugins"][0]; assert data["name"] == "prp-marketplace" and p["name"] == "prp-core" and p["source"] == {"source":"local", "path":sys.argv[2]}' "$catalog" "./.agents/plugins/packages/prp-core/$version"
    [ -z "$(find "$plugin" -type l -print)" ]
    for skill in "$framework/adapters/codex"/prp-*/SKILL.md; do
        skill_dir=$(basename "$(dirname "$skill")")
        cmp "$skill" "$plugin/skills/$skill_dir/SKILL.md"
    done
    grep -q -- '--l2-comments' "$plugin/skills/prp-review-agents/SKILL.md"
    run python3 "$packager" --output "$market_root"
    [ "$status" -eq 0 ]
}

@test "same-version collision leaves the existing package and catalog intact" {
    python3 "$packager" --output "$market_root"
    cp "$catalog" "$BATS_TEST_TMPDIR/initial-catalog"
    changed="$plugin/skills/prp-review-agents/SKILL.md"
    printf 'existing package\n' > "$changed"
    run python3 "$packager" --output "$market_root"
    [ "$status" -ne 0 ]
    [[ "$output" == *'bump the plugin version'* ]]
    grep -qx 'existing package' "$changed"
    cmp "$catalog" "$BATS_TEST_TMPDIR/initial-catalog"
}

@test "foreign marketplace catalog is preserved without publishing the package" {
    mkdir -p "$(dirname "$catalog")"
    printf '%s\n' '{"name":"foreign-marketplace","plugins":[{"source":{"path":"./existing/1.0.0"}}]}' > "$catalog"
    cp "$catalog" "$BATS_TEST_TMPDIR/initial-catalog"
    run python3 "$packager" --output "$market_root"
    [ "$status" -ne 0 ]
    [[ "$output" == *'unmanaged catalog'* ]]
    cmp "$catalog" "$BATS_TEST_TMPDIR/initial-catalog"
    [ ! -e "$plugin" ]
}

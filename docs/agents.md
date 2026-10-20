# Use the Docker environment skill

The canonical source is [`skills/yii2-docker-environment/SKILL.md`](../skills/yii2-docker-environment/SKILL.md).
It guides image selection, application setup, isolated validation and cleanup. Its helper tests a dependency-free
PHP fixture; validating an actual Yii application remains a separate step.

## Install and activate

### Composer installation

This bundle is not a Composer package. After the [one-time plugin setup](https://yii2-framework.github.io/docs/project/ai-agents/#composer-installation),
set `auto-sync` to `true` in `skills.json` and register its Git source once. Subsequent Composer install/update
operations synchronize it automatically while `auto-sync` is enabled:

```bash
composer skills:add yii2-extensions/docker-images --ref=main --skill=yii2-docker-environment
composer skills:show
```

If `auto-sync` is `false`, run `composer skills:update` after dependency installation or updates.

### Optional npx installation

From the application root, use a local checkout until public listing confirms the skill exists on the default
branch:

```bash
npx skills@1.7.2 add /absolute/path/to/docker-images --list
npx skills@1.7.2 add /absolute/path/to/docker-images \
  --skill yii2-docker-environment --agent claude-code codex opencode
```

For published sources, first run `npx skills@1.7.2 add yii2-extensions/docker-images --list`, then use that source
instead of the local path. Installation remains project-scoped. Keep the complete skill directory, including its
`scripts/`; installing the skill does not install Docker or pull an image.

The pinned installer uses `.agents/skills/` for Codex and OpenCode and `.claude/skills/` for Claude Code. This source
checkout provides aliases in those two locations to the single canonical `skills/` source. Verify discovery in a
fresh client session, then explicitly invoke `$yii2-docker-environment` in Codex, `/yii2-docker-environment` in
Claude Code, or ask OpenCode to load it using its skill tool.

An installer listing, a manual `SKILL.md` read, native discovery, native activation and a successful container test
are separate evidence. Do not claim native client activation from a helper test. The documentation site distributes
unchanged skill bundles with provenance and checksums; it does not own another editable copy.

## Verify the environment

Run the [isolated helper](testing.md#run-an-isolated-image-check), then run the application's own checks with its
actual dependencies and test configuration. Record the image ID, relevant assertions and missing prerequisites.
A successful helper run proves its stack checks; native skill discovery and activation require separate client
evidence and are not established by reading the skill manually.

[Back to documentation](../README.md#documentation)

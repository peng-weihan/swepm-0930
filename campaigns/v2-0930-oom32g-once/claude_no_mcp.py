"""Campaign-local Claude Code adapter; leaves the installed Harbor untouched."""

import shlex

from harbor.agents.installed.claude_code import ClaudeCode


class ClaudeCodeNoMCP(ClaudeCode):
    def build_cli_flags(self) -> str:
        return (
            super().build_cli_flags()
            + " --strict-mcp-config --mcp-config "
            + shlex.quote('{"mcpServers":{}}')
            + " --disallowedTools 'mcp__*'"
        )

    async def install(self, environment) -> None:
        # Native binary is downloaded once, checksum-verified, and mounted read-only.
        # Claude's native distribution does not require a Node/npm installation.
        result = await self.exec_as_agent(
            environment,
            command=(
                'set -eu; test -x /opt/swepm-claude/claude; '
                'mkdir -p "$HOME/.local/bin"; '
                'ln -sfn /opt/swepm-claude/claude "$HOME/.local/bin/claude"; '
                '/opt/swepm-claude/claude --version'
            ),
        )
        if result.return_code != 0:
            raise RuntimeError("Mounted Claude Code binary failed its version check")


"""Account-authenticated Codex using the pinned native CLI, without package installs."""
from pathlib import PurePosixPath
from harbor.agents.installed.codex import Codex

class CodexAccount(Codex):
    _REMOTE_CODEX_HOME = PurePosixPath('/opt/swepm-runtime/home')
    _REMOTE_CODEX_SECRETS_DIR = PurePosixPath('/opt/swepm-runtime/secrets')

    async def install(self, environment):
        result = await self.exec_as_agent(environment, command='test -x /usr/local/bin/codex-code-mode-host && codex --version')
        if result.return_code != 0 or '0.159.0' not in (result.stdout or ''):
            raise RuntimeError('Pinned native Codex version check failed')

    def _build_effective_config(self, openai_base_url=None):
        if self.mcp_servers or openai_base_url:
            raise ValueError('This campaign requires account authentication and no MCP')
        config = super()._build_effective_config(None)
        config['mcp_servers'] = {}
        return config

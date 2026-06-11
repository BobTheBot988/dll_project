# Docker compose spec

We need to make a docker-compose which automatically starts a synthesis of test2
using the preferred model of the user.
The docker-compose should work in the following manner:

1. The hooks should be installed inside of the main container described inside of the Dockerfile
2. The git-diff-checker should be installed as well inside of the main container.
3. The main docker should install claude with this command: `bash curl -fsSL <https://claude.ai/install.sh> | bash`
4. The mcp-synthesizer should be installed as well and taken out of its container, the redis instance should be started as well.
5. The mcp-synthesizer should be pointed to the test2 directory found from the root of this git directory.

The user shall provide the api-key and URL this shall be made in such a way
that the mcp-synthesizer tool shall automatically pick up on that.
To do so the model must be compatible with claude so we should add this to the
README.md inside of which we should explain and provide example
commands formatted in such a manner.

```bash
docker compose  run -d --env ANTHROPIC_BASE_URL= "https://api.xxx/anthropic" \
ANTHROPIC_AUTH_TOKEN = "sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
```

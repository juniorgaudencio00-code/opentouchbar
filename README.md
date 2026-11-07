# ⚡️ OpentouchBar

Alternativa **open-source** ao BetterTouchTool para macOS: motor de ações + **servidor MCP nativo**
+ Touch Bar (hardware e virtual na tela). Feito para a era dos agentes: **a barra é configurável
por arquivo — e qualquer agente MCP pode editá-la e apertar seus botões.**

## Por quê

O BetterTouchTool é fechado, pago, e trata agentes como_feature de IA colada no lado. O
OpentouchBar nasce ao contrário: **MCP é cidadão de primeira classe**, a config é declarativa e
versionável em git, e a barra funciona em **qualquer Mac** — a barra virtual na tela replica a
Touch Bar onde o hardware não existe (ou morreu).

- 🖥️ **Barra virtual** flutuante, arrastável, customizável — funciona em todo Mac
- 🎛️ **Touch Bar de hardware** nativa (NSTouchBar) onde existir
- 🤖 **Servidor MCP embutido** (HTTP + bearer) — 12 tools: shell, AppleScript, JS, variáveis,
  clipboard, arquivos, log de execução, `press_button`
- 📝 **Config TOML declarativa** com hot-reload — botão novo = bloco novo
- 🔓 MIT, zero dependências externas no núcleo

## Rodando

```bash
brew install xcodegen          # gera o .xcodeproj a partir do project.yml
xcodegen generate
xcodebuild -scheme OpentouchBar -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/OpentouchBar-*/Build/Products/Debug/OpentouchBar.app
```

O app cria `~/.config/opentouchbar/config.toml` com exemplos e um token gerado na 1ª execução,
e sobe o servidor MCP em `127.0.0.1:64833`.

## Config (a API da barra)

```toml
[server]
port = 64833
token = "seu-token"     # bearer do servidor MCP

[[buttons]]
label = "Deploy"
emoji = "🚀"
[buttons.action]
type = "shell"          # shell | applescript | js | url
command = "./deploy.sh"

[[triggers]]
hotkey = "cmd+shift+o"
[triggers.action]
type = "applescript"
source = 'display notification "oi"'
```

Salvar o arquivo atualiza a barra na hora. Variáveis persistidas: `{{nome}}` dentro de actions
resolve pelo store (`set_variable`/`get_variable` via MCP).

## Servidor MCP

```bash
TOKEN=$(grep '^token' ~/.config/opentouchbar/config.toml | cut -d'"' -f2)
curl -X POST http://127.0.0.1:64833/mcp \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Aponte seu cliente MCP (Claude, Codex, ZCode…) para `http://127.0.0.1:64833/mcp` com o bearer.
Tools: `run_shell`, `run_applescript`, `run_js`, `get_variable`, `set_variable`, `get_clipboard`,
`set_clipboard`, `list_directory`, `create_file`, `get_execution_log`, `list_buttons`,
`press_button`.

## Arquitetura

```
config.toml ──hot-reload──▶ ConfigStore ──▶ VirtualBarWindow (NSPanel)
                                 │       ├─▶ HardwareTB (NSTouchBar)
                                 └─▶ ActionEngine ──▶ ActionRunner (Process/JavaScriptCore)
                                          │              ├── /bin/bash -c
                                          │              ├── osascript -e
                                          │              ├── JavaScriptCore
                                          │              └── NSWorkspace.open
                                 └─▶ MCPServer (NWListener :64833, bearer)
                                          └─▶ ToolRegistry (12 tools)
```

`press_button` (MCP) e o clique humano seguem **o mesmo caminho** (`ButtonDispatcher` → engine →
log) — o agente aperta botões de verdade.

## Roadmap

- **v0.2 ✅**: hotkeys globais (Carbon), menu com triggers/launch-at-login/editar config
- **v0.3 ✅**: editor visual (SwiftUI) escrevendo o mesmo TOML, TOMLWriter com round-trip testado
- **v0.4**: helpers fora de processo para scripts longos (modelo XPC), widgets, hooks de foco de app
- **fase 2**: sync entre máquinas, plugin SDK, gestos de trackpad

## Licença

MIT — veja [LICENSE](LICENSE).

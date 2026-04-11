#!/usr/bin/env bash
# didio-menu.sh — menu interativo de terminal pro framework claude-didio-config
#
# Usage: didio menu   (ou apenas: didio)
#
# Lista as ações mais comuns: criar feature, rodar bug fix, revisar
# branch, abrir dashboard, ver docs, retro. Não faz orquestração
# complexa aqui — delega pros outros bin/didio-* ou imprime o comando
# Claude Code que o usuário deve usar.

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
VERSION="$(cat "$DIDIO_HOME/VERSION" 2>/dev/null || echo dev)"
PROJECT_ROOT="$(pwd)"

print_header() {
  cat <<EOF

  ╔══════════════════════════════════════════════════════════╗
  ║               claude-didio-config · $VERSION
  ║               Didio Agents Dash — menu principal
  ╚══════════════════════════════════════════════════════════╝

  Projeto atual: $PROJECT_ROOT

EOF
}

print_menu() {
  cat <<'EOF'
  O que você quer fazer?

    1) 🆕 Criar nova feature         (Architect → Waves → TechLead → QA)
    2) 🐛 Corrigir um bug            (feature curta, 1 Wave)
    3) 🔍 Revisar código             (só TechLead sobre a branch atual)
    4) 📊 Status da execução         (lê logs/agents/state.json)
    5) 🖥️  Abrir dashboard            (didio dashboard)
    6) 📚 Ver docs                   (docs/ ADRs / PRDs / diagramas)
    7) 🎓 Retrospectiva manual       (consolida learnings por role)
    8) ❓ Prompts prontos            (mostra o README cheat-sheet)
    0) Sair

  Dica: antes de começar uma nova feature, rode /clear no Claude Code
  pra limpar o contexto. Contexto contaminado gera decisões ruins.

EOF
}

action_create_feature() {
  cat <<'EOF'

  Pra criar uma nova feature, abra o Claude Code neste diretório e
  cole um dos prompts abaixo:

    /create-feature F0X <descrição curta da feature>

  OU (equivalente em linguagem natural):

    Claude, leia CLAUDE.md e crie a feature F0X: <descrição>.
    Use o workflow didio: Architect → Waves → TechLead → QA.
    Ao terminar, atualize o README.md com o que foi entregue.

  Lembre de rodar /clear antes.

EOF
}

action_fix_bug() {
  cat <<'EOF'

  Pra corrigir um bug, cole no Claude Code:

    Claude, temos um bug: <descrição + passos pra reproduzir>.
    Crie uma feature curta com 1 Wave. Rode Developer, TechLead e QA.

EOF
}

action_review_branch() {
  cat <<'EOF'

  Pra rodar só o TechLead sobre os commits atuais, cole no Claude Code:

    Claude, rode apenas o agente TechLead sobre os commits desta branch
    e me dê um verdict com issues BLOCKING / IMPORTANT / MINOR.

EOF
}

action_status() {
  local state="$PROJECT_ROOT/logs/agents/state.json"
  if [[ ! -f "$state" ]]; then
    echo
    echo "  Nenhum state.json encontrado em $state."
    echo "  Rode 'didio log-watcher' em paralelo à execução dos agentes."
    echo
    return
  fi
  python3 - "$state" <<'PY' 2>/dev/null || echo "  [didio-menu] não consegui ler state.json"
import json, sys
with open(sys.argv[1]) as f:
    s = json.load(f)
agents = s.get("agents", [])
running = [a for a in agents if a.get("status") == "running"]
recent = sorted(agents, key=lambda a: a.get("started_at", ""), reverse=True)[:5]
print()
print(f"  Total de runs: {len(agents)}   |   Rodando agora: {len(running)}")
print(f"  Última atualização: {s.get('generated_at', '?')}")
print()
if running:
    print("  Rodando agora:")
    for a in running:
        print(f"    - {a.get('role', '?')}/{a.get('task', '?')} (pid {a.get('pid', '?')})")
    print()
print("  Últimos 5 runs:")
for a in recent:
    status = a.get("status", "?")
    role = a.get("role", "?")
    task = a.get("task", "?")
    exit_c = a.get("exit_code", "-")
    phrase = a.get("phrase") or a.get("easter_egg") or ""
    print(f"    - [{status:9}] {role:10} {task:20} exit={exit_c}  {phrase[:60]}")
print()
PY
}

action_dashboard() {
  echo
  echo "  Abrindo o Didio Agents Dash em background..."
  echo
  if command -v didio >/dev/null 2>&1; then
    didio dashboard &
  else
    "$DIDIO_HOME/bin/didio-dashboard.sh" &
  fi
  disown || true
  echo "  Servidor iniciado. Abra http://localhost:7777 se não abrir automaticamente."
  echo
}

action_docs() {
  if [[ -d "$PROJECT_ROOT/docs" ]]; then
    echo
    echo "  docs/"
    find "$PROJECT_ROOT/docs" -maxdepth 2 -type f \( -name "*.md" -o -name "*.mmd" \) \
      | sed "s|$PROJECT_ROOT/||" | sort | sed 's|^|    |'
    echo
  else
    echo
    echo "  Este projeto não tem docs/. Rode /install-claude-didio-framework primeiro."
    echo
  fi
}

action_retro() {
  read -r -p "  Qual feature? (ex: F01): " F
  if [[ -z "$F" ]]; then
    echo "  Feature id vazio. Cancelado."; return
  fi
  cat <<EOF

  Pra rodar a retrospectiva manual, cole no Claude Code:

    Claude, rode cerimônia de retrospectiva da feature $F.
    Leia os logs em logs/agents/ e os reviews em tasks/features/$F*/.
    Consolide learnings por role em memory/agent-learnings/<role>.md
    (append, não sobrescreva) e escreva tasks/features/$F*/retrospective.md.

EOF
}

action_prompts() {
  cat <<'EOF'

  Prompts prontos (copie e cole no Claude Code):

  — Criar feature:
    Claude, leia CLAUDE.md e crie a feature F0X: <descrição>.
    Use o workflow didio: Architect → Waves → TechLead → QA.

  — Corrigir bug:
    Claude, temos um bug: <descrição + repro>.
    Crie uma feature curta com 1 Wave. Rode Developer, TechLead e QA.

  — Revisar branch:
    Claude, rode apenas o agente TechLead sobre os commits desta branch
    e me dê um verdict com issues BLOCKING / IMPORTANT / MINOR.

  — Plan mode:
    Claude, entre em plan mode e explore <área>. Quero contexto,
    arquivos críticos, passos numerados, verificação e2e e riscos.

  — Retrospectiva:
    Claude, rode cerimônia de retrospectiva da feature F0X.
    Consolide learnings em memory/agent-learnings/<role>.md.

  ⚠️ Antes de começar algo novo, rode /clear no Claude Code.

EOF
}

main() {
  while true; do
    print_header
    print_menu
    read -r -p "  > " choice
    case "$choice" in
      1) action_create_feature ;;
      2) action_fix_bug ;;
      3) action_review_branch ;;
      4) action_status ;;
      5) action_dashboard ;;
      6) action_docs ;;
      7) action_retro ;;
      8) action_prompts ;;
      0|q|Q|exit|quit) echo; echo "  Bye 👋"; exit 0 ;;
      *) echo "  Opção inválida: $choice" ;;
    esac
    echo
    read -r -p "  [enter] pra voltar ao menu, q pra sair: " cont
    [[ "$cont" == "q" || "$cont" == "Q" ]] && exit 0
  done
}

main

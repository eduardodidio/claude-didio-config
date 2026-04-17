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
  # Load config lib for mode badges
  source "${DIDIO_HOME}/bin/didio-config-lib.sh"

  cat <<EOF

  ╔══════════════════════════════════════════════════════════╗
  ║               claude-didio-config · $VERSION
  ║               Didio Agents Dash — menu principal
  ╚══════════════════════════════════════════════════════════╝

  Projeto atual: $PROJECT_ROOT

EOF
  didio_config_summary
  echo
}

print_menu() {
  # Show turbo/economy state in toggle labels
  local turbo_label="OFF" economy_label="OFF"
  local max_p
  max_p=$(didio_read_config max_parallel)
  [[ "$(didio_is_turbo)" == "true" ]] && turbo_label="ON"
  [[ "$(didio_is_economy)" == "true" ]] && economy_label="ON"
  [[ -z "$max_p" || "$max_p" == "0" ]] && max_p="ilimitado"

  cat <<EOF
  O que você quer fazer?

    1) 🆕 Criar nova feature         (Architect -> Waves -> TechLead -> QA)
    2) 🐛 Corrigir um bug            (feature curta, 1 Wave)
    3) 🔍 Revisar código             (só TechLead sobre a branch atual)
    4) 📊 Status da execução         (lê logs/agents/state.json)
    5) 🖥️  Abrir dashboard            (didio dashboard)
    6) 📚 Ver docs                   (docs/ ADRs / PRDs / diagramas)
    7) 🎓 Retrospectiva manual       (consolida learnings por role)
    8) ❓ Prompts prontos            (mostra o README cheat-sheet)
   14) 🗓️  Planejar feature           (Architect only, tasks BMad)
   15) 📋 Listar features planejadas (Status=planned)
   ──────────────────────────────────────────────────────────
    9) ⚡ Turbo Mode                  [$turbo_label]
   10) 💰 Economy Mode               [$economy_label]
   11) 🔀 Max paralelismo            [$max_p]
   12) 🤖 Configurar modelos         (modelo por agente)
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

action_turbo() {
  local current
  current="$(didio_is_turbo)"
  if [[ "$current" == "true" ]]; then
    didio_write_config turbo false
    echo
    echo "  Turbo Mode DESATIVADO."
    echo
  else
    echo
    echo "  ⚠️  Turbo Mode ativa paralelismo maximo (sem limite de agentes"
    echo "  simultaneos). Use com cuidado em projetos grandes."
    echo
    read -r -p "  Ativar Turbo Mode? [y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      didio_write_config turbo true
      echo "  Turbo Mode ATIVADO."
    else
      echo "  Cancelado."
    fi
    echo
  fi
}

action_economy() {
  local current
  current="$(didio_is_economy)"
  if [[ "$current" == "true" ]]; then
    didio_write_config economy false
    echo
    echo "  Economy Mode DESATIVADO. Modelos voltaram ao padrao:"
    echo "    Architect = Opus | Developer/TechLead/QA = Sonnet"
    echo
  else
    echo
    echo "  Economy Mode troca os modelos para versoes mais baratas:"
    echo "    Architect = Sonnet (em vez de Opus)"
    echo "    Developer/TechLead/QA = Haiku (em vez de Sonnet)"
    echo
    echo "  Menor qualidade, custo significativamente menor."
    echo
    read -r -p "  Ativar Economy Mode? [y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      didio_write_config economy true
      echo "  Economy Mode ATIVADO."
    else
      echo "  Cancelado."
    fi
    echo
  fi
}

action_max_parallel() {
  local current architect_model
  current=$(didio_read_config max_parallel)
  [[ -z "$current" || "$current" == "0" ]] && current="0 (ilimitado)"

  # Get architect model to determine recommendation tier
  architect_model=$(didio_model_for_role architect)

  echo
  echo "  Paralelismo maximo atual: $current"
  echo
  echo "  Recomendacoes por modelo (baseado no Architect: $architect_model):"
  echo "    Opus:   $(didio_recommend_parallel opus)"
  echo "    Sonnet: $(didio_recommend_parallel sonnet)"
  echo "    Haiku:  $(didio_recommend_parallel haiku)"
  echo
  echo "  Use 0 para ilimitado (todas as tasks da Wave em paralelo)."
  echo
  read -r -p "  Novo valor [0-20]: " new_val
  if [[ "$new_val" =~ ^[0-9]+$ ]] && [[ "$new_val" -le 20 ]]; then
    didio_write_config max_parallel "$new_val"
    [[ "$new_val" == "0" ]] && new_val="ilimitado"
    echo "  Max paralelismo atualizado para: $new_val"
  else
    echo "  Valor invalido. Cancelado."
  fi
  echo
}

action_models() {
  echo
  echo "  Configuracao atual de modelos:"
  didio_config_summary
  echo
  echo "  Opcoes:"
  echo "    1) Padrao      (Architect=Opus, demais=Sonnet)"
  echo "    2) Economy     (Architect=Sonnet, demais=Haiku)"
  echo "    3) Tudo Opus   (todos os agentes usam Opus)"
  echo "    4) Tudo Sonnet (todos os agentes usam Sonnet)"
  echo "    5) Cancelar"
  echo
  read -r -p "  Escolha [1-5]: " choice
  case "$choice" in
    1)
      didio_write_config economy false
      echo "  Modelos definidos para padrao (Opus/Sonnet)."
      ;;
    2)
      didio_write_config economy true
      echo "  Modelos definidos para economy (Sonnet/Haiku)."
      ;;
    3)
      local config="$PROJECT_ROOT/didio.config.json"
      python3 -c "
import json
with open('$config') as f: c = json.load(f)
for role in ['architect','developer','techlead','qa']:
    c['models'][role] = {'model': 'opus', 'fallback': 'sonnet'}
c['economy'] = False
with open('$config', 'w') as f: json.dump(c, f, indent=2); f.write('\n')
" 2>/dev/null
      echo "  Todos os agentes usando Opus (fallback: Sonnet)."
      ;;
    4)
      local config="$PROJECT_ROOT/didio.config.json"
      python3 -c "
import json
with open('$config') as f: c = json.load(f)
for role in ['architect','developer','techlead','qa']:
    c['models'][role] = {'model': 'sonnet', 'fallback': 'haiku'}
c['economy'] = False
with open('$config', 'w') as f: json.dump(c, f, indent=2); f.write('\n')
" 2>/dev/null
      echo "  Todos os agentes usando Sonnet (fallback: Haiku)."
      ;;
    *) echo "  Cancelado." ;;
  esac
  echo
}

action_plan_feature() {
  cat <<'EOF'

  Pra planejar uma nova feature (sem executar), cole um dos prompts:

    /plan-feature F0X <descrição curta da feature>

  OU (linguagem natural):

    Claude, leia CLAUDE.md e PLANEJE a feature F0X: <descrição>.
    Rode apenas o Architect em modo PLAN_ONLY. Quero tasks em padrão
    BMad (User Story, Dev Notes, Testing) com Status=planned.
    Não execute Waves, TechLead ou QA.

  Depois de revisar o plano, use a opção 1 ou /create-feature F0X
  pra executar.

EOF
}

action_list_planned() {
  local features_dir="$PROJECT_ROOT/tasks/features"
  if [[ ! -d "$features_dir" ]]; then
    echo
    echo "  Nenhum diretório tasks/features/ encontrado em $PROJECT_ROOT."
    echo
    return
  fi
  python3 - "$features_dir" <<'PY' 2>/dev/null || echo "  [didio-menu] erro ao listar features"
import os, re, sys, glob
features_dir = sys.argv[1]
rows = []
for d in sorted(glob.glob(os.path.join(features_dir, "*/"))):
    name = os.path.basename(d.rstrip("/"))
    if name.startswith("FXX") or name.startswith("_"):
        continue
    readmes = glob.glob(os.path.join(d, "*-README.md"))
    if not readmes:
        continue
    readme = readmes[0]
    try:
        with open(readme) as f:
            content = f.read()
    except Exception:
        continue
    status_match = re.search(r"\*\*Status:\*\*\s*([^\s|]+)", content)
    status = status_match.group(1).strip() if status_match else "?"
    if status != "planned":
        continue
    title_match = re.search(r"^#\s+(.+)$", content, re.MULTILINE)
    title = title_match.group(1).strip() if title_match else os.path.basename(d.rstrip("/"))
    fid_match = re.match(r"(F\d+)", os.path.basename(d.rstrip("/")))
    fid = fid_match.group(1) if fid_match else "?"
    task_files = glob.glob(os.path.join(d, f"{fid}-T*.md"))
    rel = os.path.relpath(d.rstrip("/"), os.path.dirname(features_dir))
    rows.append((fid, title, len(task_files), rel))

print()
if not rows:
    print("  Nenhuma feature com Status=planned encontrada.")
    print("  Use a opção 14 (Planejar feature) pra criar uma.")
    print()
    sys.exit(0)

print(f"  Features planejadas ({len(rows)}):")
print()
print(f"    {'ID':<6} {'#tasks':<7} {'Título':<45} Path")
print(f"    {'-'*6} {'-'*7} {'-'*45} {'-'*30}")
for fid, title, ntasks, rel in rows:
    t = title[:43] + ".." if len(title) > 45 else title
    print(f"    {fid:<6} {ntasks:<7} {t:<45} {rel}")
print()
print("  Pra executar uma feature planejada, use /create-feature <FXX>")
print("  ou a opção 1 do menu.")
print()
PY
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
      9) action_turbo ;;
      10) action_economy ;;
      11) action_max_parallel ;;
      12) action_models ;;
      14) action_plan_feature ;;
      15) action_list_planned ;;
      0|q|Q|exit|quit) echo; echo "  Bye 👋"; exit 0 ;;
      *) echo "  Opção inválida: $choice" ;;
    esac
    echo
    read -r -p "  [enter] pra voltar ao menu, q pra sair: " cont
    [[ "$cont" == "q" || "$cont" == "Q" ]] && exit 0
  done
}

main

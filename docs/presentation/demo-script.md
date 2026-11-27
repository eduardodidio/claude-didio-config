# Leadership Forum — Live Demo Script

**Duration:** ~5 minutes
**Prerequisites:** Terminal open in a didio-managed project, dashboard running (optional)

---

## 1. Show the Framework (30s)

```bash
# Show project structure
ls CLAUDE.md README.md docs/ tasks/ agents/ memory/

# Show the agent learnings
ls memory/agent-learnings/

# Show the config
cat didio.config.json | python3 -m json.tool | head -30
```

**Talking point:** "This is what a didio-managed project looks like. CLAUDE.md has the guardrails, agents/ has the prompts, memory/ has the learnings from every feature shipped."

---

## 2. War Room: Add a Card (30s)

```bash
# Add a card to the War Room
didio warroom add "Refactor auth module for SSO support" \
  --body "Session handling needs rework for SAML integration" \
  --priority high \
  --tags "auth,refactor,sso"

# Show the card
didio warroom list
```

**Talking point:** "Anyone can add a card — operator, agent, or external system. Cards sit in the War Room until Black Hawk Alpha triages them."

---

## 3. Triage (dry-run) (30s)

```bash
# Show what triage would do (without spawning the agent)
didio blackhawk triage --dry-run
```

**Talking point:** "Alpha reads all ADRs, learnings, and existing features before making a recommendation. The dry-run shows what would happen without consuming tokens."

---

## 4. Promote a Card (30s)

```bash
# Promote a card (use an existing promoted card as example)
didio warroom list --status promoted

# Show the created feature directory
ls tasks/features/F36-*/
cat tasks/features/F36-*/F36-README.md
```

**Talking point:** "Promotion creates the exact directory structure the Architect expects. The pipeline can now execute this feature automatically."

---

## 5. Bravo Intelligence Scanner (45s)

```bash
# Run Bravo in dry-run mode
didio bravo monitor --dry-run

# Show the report
ls logs/agents/bravo-report-*.json
cat logs/agents/bravo-report-*.json | python3 -m json.tool | head -30
```

**Talking point:** "Bravo scans pipeline health, flags, token budget, and governance decisions every 15 minutes. It raises War Room cards for anomalies — Alpha triages those too. This is the intelligence loop."

---

## 6. Knowledge Mesh (45s)

```bash
# Register this project
didio mesh register .

# Show the mesh
didio mesh list

# Query across all projects
didio mesh query "pipeline" --limit 5

# Clean up
didio mesh unregister "$(basename $PWD)"
```

**Talking point:** "The Knowledge Mesh lets agents on Project A learn from Project B's mistakes. No MCP required — it reads files directly. This is the foundation for corporate-wide intelligence."

---

## 7. DOB Benchmark (30s)

```bash
# Show benchmark results
ls logs/dob-results/

# Run the scorer
didio dob-score logs/dob-results/example/*/summary.json 2>/dev/null | head -20
```

**Talking point:** "DOB is how we measure ourselves. 12 dimensions, K=3 runs. The regression gate blocks any change that makes agents worse."

---

## 8. Wrap Up (30s)

```bash
# Show total features shipped
ls tasks/features/ | wc -l

# Show the agent learnings accumulated
wc -l memory/agent-learnings/*.md

# Show the guardrails
grep -c "NUNCA" CLAUDE.md
```

**Talking point:** "37 features shipped, each with TechLead review and QA validation. The agents have accumulated hundreds of learnings. The guardrails ensure safety. This is an orchestration framework that improves with every feature."

---

## Contingency: If Something Fails

- If `didio warroom add` fails: show an existing card JSON directly
  ```bash
  cat logs/warroom/cards/WR-20261126-001.json | python3 -m json.tool
  ```
- If `didio bravo monitor` fails: show a pre-generated report
  ```bash
  cat logs/agents/bravo-report-*.json | python3 -m json.tool
  ```
- If `didio mesh` fails: explain the concept with the architecture diagram
  ```bash
  cat docs/diagrams/F37-architecture.mmd
  ```

**Golden rule:** Never let a live demo failure become awkward silence. Have the fallback ready.
